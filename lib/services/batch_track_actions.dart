import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/unified_library_item.dart';
import 'package:spotiflac_android/providers/download_history_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/conversion_library_service.dart';
import 'package:spotiflac_android/services/ffmpeg_service.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/services/replaygain_service.dart';
import 'package:spotiflac_android/utils/audio_conversion_utils.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/int_utils.dart';
import 'package:spotiflac_android/utils/lyrics_metadata_helper.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/widgets/batch_convert_sheet.dart';
import 'package:spotiflac_android/widgets/batch_progress_dialog.dart';

final _batchActionsLog = AppLogger('BatchActions');

class _BatchConversionFailure implements Exception {
  final String stage;
  final String message;

  const _BatchConversionFailure(this.stage, this.message);

  @override
  String toString() => '$stage: $message';
}

/// Shows the batch format-conversion sheet for [selectedItems] and runs the
/// conversion when confirmed. Handles both history-backed and local-backed
/// items, including SAF-hosted files.
///
/// [onSheetOpen] / [onSheetClosed] let the caller hide and restore any
/// selection UI around the sheet; [onSheetClosed] receives whether a
/// conversion was started.
Future<void> showBatchConvertSheet(
  BuildContext context,
  WidgetRef ref,
  List<UnifiedLibraryItem> selectedItems, {
  required VoidCallback onExitSelectionMode,
  VoidCallback? onSheetOpen,
  Future<void> Function(bool didStartConversion)? onSheetClosed,
}) async {
  final sourceFormats = <String>{};
  final sourceBitDepths = <int?>[];
  final sourceSampleRates = <int?>[];
  for (final item in selectedItems) {
    final sourceFormat = convertibleAudioSourceFormat(
      storedFormat: item.localItem?.format ?? item.historyItem?.format,
      filePath: item.filePath,
      fileName: item.historyItem?.safFileName,
    );
    if (sourceFormat != null) sourceFormats.add(sourceFormat);
    sourceBitDepths.add(item.historyItem?.bitDepth ?? item.localItem?.bitDepth);
    sourceSampleRates.add(
      item.historyItem?.sampleRate ?? item.localItem?.sampleRate,
    );
  }

  final formats = audioConversionTargetFormats
      .where(
        (target) => sourceFormats.any(
          (source) =>
              canConvertAudioFormat(sourceFormat: source, targetFormat: target),
        ),
      )
      .toList();

  if (formats.isEmpty) return;

  var didStartConversion = false;

  // The queue launches this action from a temporary OverlayEntry. Its
  // onSheetOpen callback removes that entry, which deactivates [context]. Keep
  // the root Navigator's context before doing so; it remains mounted for the
  // sheet, the confirmation dialog, progress updates, and the final snackbar.
  final modalContext = Navigator.of(context, rootNavigator: true).context;

  // Resolve localized strings up front; the builder must not look up
  // Localizations via a possibly deactivated context.
  final sheetTitle = modalContext.l10n.selectionBatchConvertConfirmTitle;
  final sheetConfirmLabel = modalContext.l10n.selectionConvertCount(
    selectedItems.length,
  );

  onSheetOpen?.call();

  await showModalBottomSheet<void>(
    context: modalContext,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) => BatchConvertSheet(
      formats: formats,
      title: sheetTitle,
      confirmLabel: sheetConfirmLabel,
      sourceBitDepth: lowestKnownPositiveInt(sourceBitDepths),
      sourceSampleRate: lowestKnownPositiveInt(sourceSampleRates),
      onConvert:
          (format, bitrate, losslessQuality, losslessProcessing, keepOriginal) {
            didStartConversion = true;
            Navigator.pop(sheetContext);
            _performBatchConversion(
              modalContext,
              ref,
              selectedItems: selectedItems,
              targetFormat: format,
              bitrate: bitrate,
              losslessQuality: losslessQuality,
              losslessProcessing: losslessProcessing,
              keepOriginal: keepOriginal,
              onExitSelectionMode: onExitSelectionMode,
            );
          },
    ),
  );

  await onSheetClosed?.call(didStartConversion);
}

Future<void> _performBatchConversion(
  BuildContext context,
  WidgetRef ref, {
  required List<UnifiedLibraryItem> selectedItems,
  required String targetFormat,
  required String bitrate,
  LosslessConversionQuality losslessQuality = const LosslessConversionQuality(),
  LosslessConversionProcessing losslessProcessing =
      const LosslessConversionProcessing(),
  bool keepOriginal = false,
  required VoidCallback onExitSelectionMode,
}) async {
  final convertibleItems = <UnifiedLibraryItem>[];
  for (final item in selectedItems) {
    final sourceFormat = convertibleAudioSourceFormat(
      storedFormat: item.localItem?.format ?? item.historyItem?.format,
      filePath: item.filePath,
      fileName: item.historyItem?.safFileName,
    );
    if (sourceFormat == null ||
        !canConvertAudioFormat(
          sourceFormat: sourceFormat,
          targetFormat: targetFormat,
        )) {
      continue;
    }
    convertibleItems.add(item);
  }

  if (convertibleItems.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.selectionConvertNoConvertible)),
      );
    }
    return;
  }

  final isLossless = isLosslessConversionTarget(targetFormat);
  final losslessLabels = context.l10n.losslessConversionLabels;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.selectionBatchConvertConfirmTitle),
      content: Text(
        keepOriginal
            ? context.l10n.selectionBatchConvertConfirmKeepOriginal(
                convertibleItems.length,
                targetFormat,
              )
            : isLossless && losslessQuality.hasCaps
            ? context.l10n.selectionBatchConvertConfirmMessageLosslessCapped(
                convertibleItems.length,
                targetFormat,
                losslessQualityLabel(
                  losslessQuality,
                  originalLabel: losslessLabels.original,
                  originalQualityLabel: losslessLabels.originalQuality,
                ),
              )
            : isLossless
            ? context.l10n.selectionBatchConvertConfirmMessageLossless(
                convertibleItems.length,
                targetFormat,
              )
            : context.l10n.selectionBatchConvertConfirmMessage(
                convertibleItems.length,
                targetFormat,
                bitrate,
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.l10n.dialogCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(context.l10n.trackConvertFormat),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  int successCount = 0;
  final failures = <String>[];
  final total = convertibleItems.length;
  final settings = ref.read(settingsProvider);
  final shouldEmbedLyrics =
      settings.embedLyrics && settings.lyricsMode != 'external';

  var cancelled = false;
  BatchProgressDialog.show(
    context: context,
    title: context.l10n.trackConvertConverting,
    total: total,
    icon: Icons.transform,
    onCancel: () {
      cancelled = true;
      BatchProgressDialog.dismiss(context);
    },
  );

  for (int i = 0; i < total; i++) {
    if (!context.mounted || cancelled) break;
    final item = convertibleItems[i];

    BatchProgressDialog.update(current: i + 1, detail: item.trackName);

    String failureStage = 'metadata';
    String? coverPath;
    String? safTempPath;
    String? convertedSafTempPath;
    try {
      final metadata = <String, String>{
        'TITLE': item.trackName,
        'ARTIST': item.artistName,
        'ALBUM': item.albumName,
      };
      try {
        final result = await PlatformBridge.readFileMetadata(item.filePath);
        if (result['error'] == null) {
          mergePlatformMetadataForTagEmbed(target: metadata, source: result);
        }
      } catch (_) {}
      await ensureLyricsMetadataForConversion(
        metadata: metadata,
        sourcePath: item.filePath,
        shouldEmbedLyrics: shouldEmbedLyrics,
        trackName: item.trackName,
        artistName: item.artistName,
        spotifyId: item.historyItem?.spotifyId ?? '',
        durationMs:
            ((item.historyItem?.duration ?? item.localItem?.duration) ?? 0) *
            1000,
      );

      try {
        final tempDir = await getTemporaryDirectory();
        final coverOutput =
            '${tempDir.path}${Platform.pathSeparator}batch_cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final coverResult = await PlatformBridge.extractCoverToFile(
          item.filePath,
          coverOutput,
        );
        if (coverResult['error'] == null) {
          coverPath = coverOutput;
        }
      } catch (_) {}

      String workingPath = item.filePath;
      final isSaf = isContentUri(item.filePath);

      if (isSaf) {
        failureStage = 'read SAF source';
        safTempPath = await ConversionLibraryService.copySafSourceToTemp(
          item.filePath,
        );
        if (safTempPath == null || safTempPath.isEmpty) {
          throw const _BatchConversionFailure(
            'read SAF source',
            'temporary copy was not created',
          );
        }
        workingPath = safTempPath;
      }

      failureStage = 'FFmpeg conversion';
      final newPath = await FFmpegService.convertAudioFormat(
        inputPath: workingPath,
        targetFormat: targetFormat.toLowerCase(),
        bitrate: bitrate,
        metadata: metadata,
        coverPath: coverPath,
        artistTagMode: settings.artistTagMode,
        deleteOriginal: !isSaf && !keepOriginal,
        sourceBitDepth: item.historyItem?.bitDepth ?? item.localItem?.bitDepth,
        losslessQuality: losslessQuality,
        losslessProcessing: losslessProcessing,
      );

      if (newPath == null) {
        throw const _BatchConversionFailure(
          'FFmpeg conversion',
          'converter returned no output',
        );
      }
      if (isSaf) convertedSafTempPath = newPath;

      final sourceBitDepth =
          item.historyItem?.bitDepth ?? item.localItem?.bitDepth;
      final sourceSampleRate =
          item.historyItem?.sampleRate ?? item.localItem?.sampleRate;
      final isLosslessOutput = isLosslessConversionTarget(targetFormat);
      int? convertedBitDepth;
      int? convertedSampleRate;
      if (isLosslessOutput) {
        try {
          final convertedMetadata = await PlatformBridge.readFileMetadata(
            newPath,
          );
          if (convertedMetadata['error'] == null) {
            convertedBitDepth = readPositiveInt(convertedMetadata['bit_depth']);
            convertedSampleRate = readPositiveInt(
              convertedMetadata['sample_rate'],
            );
          }
        } catch (_) {}
        convertedBitDepth ??= losslessQuality.effectiveBitDepth(sourceBitDepth);
        convertedSampleRate ??= losslessQuality.effectiveSampleRate(
          sourceSampleRate,
        );
      }
      final newQuality = convertedAudioQualityLabel(
        targetFormat: targetFormat,
        bitrate: bitrate,
        labels: losslessLabels,
        losslessQuality: losslessQuality,
        actualBitDepth: convertedBitDepth,
        actualSampleRate: convertedSampleRate,
      );

      if (isSaf && item.historyItem != null) {
        failureStage = 'publish SAF output';
        final hi = item.historyItem!;
        final treeUri = hi.downloadTreeUri;
        final relativeDir = hi.safRelativeDir ?? '';
        if (treeUri != null && treeUri.isNotEmpty) {
          final oldFileName = hi.safFileName ?? '';
          final published = await ConversionLibraryService.publishSafConversion(
            treeUri: treeUri,
            relativeDir: relativeDir,
            originalFileName: oldFileName,
            targetFormat: targetFormat,
            sourcePath: newPath,
            keepOriginal: keepOriginal,
          );
          final safUri = published?.uri;

          if (safUri == null || safUri.isEmpty) {
            throw const _BatchConversionFailure(
              'publish SAF output',
              'destination file was not created',
            );
          }

          if (!keepOriginal && !isSameContentUri(item.filePath, safUri)) {
            try {
              await PlatformBridge.safDelete(item.filePath);
            } catch (_) {}
          }

          await ConversionLibraryService.persistHistoryConversion(
            source: hi,
            newFilePath: safUri,
            newQuality: newQuality,
            targetFormat: targetFormat,
            bitrate: bitrate,
            bitDepth: convertedBitDepth,
            sampleRate: convertedSampleRate,
            keepOriginal: keepOriginal,
            newSafFileName: published!.fileName,
          );
        } else {
          throw const _BatchConversionFailure(
            'publish SAF output',
            'download folder permission is unavailable',
          );
        }
        try {
          await File(newPath).delete();
        } catch (_) {}
        if (safTempPath != null) {
          try {
            await File(safTempPath).delete();
          } catch (_) {}
        }
      } else if (isSaf && item.localItem != null) {
        failureStage = 'publish SAF output';
        final uri = Uri.parse(item.filePath);
        final pathSegments = uri.pathSegments;

        String? treeUri;
        String relativeDir = '';
        String oldFileName = '';

        final treeIdx = pathSegments.indexOf('tree');
        final docIdx = pathSegments.indexOf('document');
        if (treeIdx >= 0 && treeIdx + 1 < pathSegments.length) {
          final treeId = pathSegments[treeIdx + 1];
          treeUri =
              'content://${uri.authority}/tree/${Uri.encodeComponent(treeId)}';
        }
        if (docIdx >= 0 && docIdx + 1 < pathSegments.length) {
          final docPath = Uri.decodeFull(pathSegments[docIdx + 1]);
          final slashIdx = docPath.lastIndexOf('/');
          if (slashIdx >= 0) {
            oldFileName = docPath.substring(slashIdx + 1);
            final treeId = treeIdx >= 0 && treeIdx + 1 < pathSegments.length
                ? Uri.decodeFull(pathSegments[treeIdx + 1])
                : '';
            if (treeId.isNotEmpty && docPath.startsWith(treeId)) {
              final afterTree = docPath.substring(treeId.length);
              final trimmed = afterTree.startsWith('/')
                  ? afterTree.substring(1)
                  : afterTree;
              final lastSlash = trimmed.lastIndexOf('/');
              relativeDir = lastSlash >= 0
                  ? trimmed.substring(0, lastSlash)
                  : '';
            }
          } else {
            oldFileName = docPath;
          }
        }

        if (treeUri != null && oldFileName.isNotEmpty) {
          final published = await ConversionLibraryService.publishSafConversion(
            treeUri: treeUri,
            relativeDir: relativeDir,
            originalFileName: oldFileName,
            targetFormat: targetFormat,
            sourcePath: newPath,
            keepOriginal: keepOriginal,
          );
          final safUri = published?.uri;

          if (safUri == null || safUri.isEmpty) {
            throw const _BatchConversionFailure(
              'publish SAF output',
              'destination file was not created',
            );
          }

          if (!keepOriginal && !isSameContentUri(item.filePath, safUri)) {
            try {
              await PlatformBridge.safDelete(item.filePath);
            } catch (_) {}
          }
          await LibraryDatabase.instance.replaceWithConvertedItem(
            item: item.localItem!,
            newFilePath: safUri,
            targetFormat: targetFormat,
            bitrate: bitrate,
            bitDepth: convertedBitDepth,
            sampleRate: convertedSampleRate,
            keepOriginal: keepOriginal,
          );
        } else {
          throw const _BatchConversionFailure(
            'publish SAF output',
            'source document location could not be resolved',
          );
        }

        try {
          await File(newPath).delete();
        } catch (_) {}
        if (safTempPath != null) {
          try {
            await File(safTempPath).delete();
          } catch (_) {}
        }
      } else if (item.historyItem != null) {
        await ConversionLibraryService.persistHistoryConversion(
          source: item.historyItem!,
          newFilePath: newPath,
          newQuality: newQuality,
          targetFormat: targetFormat,
          bitrate: bitrate,
          bitDepth: convertedBitDepth,
          sampleRate: convertedSampleRate,
          keepOriginal: keepOriginal,
        );
      } else if (item.localItem != null) {
        await LibraryDatabase.instance.replaceWithConvertedItem(
          item: item.localItem!,
          newFilePath: newPath,
          targetFormat: targetFormat,
          bitrate: bitrate,
          bitDepth: convertedBitDepth,
          sampleRate: convertedSampleRate,
          keepOriginal: keepOriginal,
        );
      }

      successCount++;
    } catch (error, stackTrace) {
      final detail = error is _BatchConversionFailure
          ? error.toString()
          : '$failureStage: $error';
      failures.add('${item.trackName} — $detail');
      _batchActionsLog.e(
        'Batch conversion failed for ${item.trackName} at $failureStage',
        error,
        stackTrace,
      );
    } finally {
      for (final path in <String?>[
        coverPath,
        safTempPath,
        convertedSafTempPath,
      ]) {
        if (path == null || path.isEmpty) continue;
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (error) {
          _batchActionsLog.w('Failed to clean temporary file $path: $error');
        }
      }
    }
  }

  await ref.read(downloadHistoryProvider.notifier).reloadFromStorage();
  await ref.read(localLibraryProvider.notifier).reloadFromStorage();

  onExitSelectionMode();

  if (context.mounted) {
    if (!cancelled) {
      BatchProgressDialog.dismiss(context);
    }
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${context.l10n.selectionBatchConvertSuccess(successCount, total, targetFormat)}'
          '${failures.isEmpty ? '' : ' • ${context.l10n.trackConvertFailed}: ${failures.length} (${failures.first})'}',
        ),
      ),
    );
  }
}

/// Batch-scans loudness and writes ReplayGain tags to [selectedItems].
///
/// [onConfirmOpen] / [onConfirmClosed] let the caller hide and restore any
/// selection UI around the confirmation dialog; [onConfirmClosed] receives
/// whether the user confirmed.
Future<void> runBatchReplayGain(
  BuildContext context,
  List<UnifiedLibraryItem> selectedItems, {
  required VoidCallback onExitSelectionMode,
  VoidCallback? onConfirmOpen,
  Future<void> Function(bool confirmed)? onConfirmClosed,
}) async {
  if (selectedItems.isEmpty) return;

  onConfirmOpen?.call();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.replayGainBatchConfirmTitle),
      content: Text(
        ctx.l10n.replayGainBatchConfirmMessage(selectedItems.length),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.l10n.dialogCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.l10n.replayGainBatchConfirmTitle),
        ),
      ],
    ),
  );

  await onConfirmClosed?.call(confirmed == true);

  if (confirmed != true || !context.mounted) return;

  var cancelled = false;
  int successCount = 0;
  final total = selectedItems.length;

  BatchProgressDialog.show(
    context: context,
    title: context.l10n.replayGainBatchAnalyzing,
    total: total,
    icon: Icons.graphic_eq,
    onCancel: () {
      cancelled = true;
      BatchProgressDialog.dismiss(context);
    },
  );

  for (int i = 0; i < total; i++) {
    if (!context.mounted || cancelled) break;
    final item = selectedItems[i];
    BatchProgressDialog.update(current: i + 1, detail: item.trackName);
    try {
      final ok = await ReplayGainService.applyToFile(item.filePath);
      if (ok) successCount++;
    } catch (_) {}
  }

  onExitSelectionMode();

  if (!context.mounted) return;
  if (!cancelled) {
    BatchProgressDialog.dismiss(context);
  }
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(context.l10n.replayGainBatchSuccess(successCount, total)),
    ),
  );
}

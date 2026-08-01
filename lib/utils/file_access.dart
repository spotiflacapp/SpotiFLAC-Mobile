import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/services/music_player_service.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/mime_utils.dart';

/// Regular expression to detect iOS app container paths.
/// Matches paths like /var/mobile/Containers/Data/Application/{UUID}
/// or /private/var/mobile/Containers/Data/Application/{UUID}
final _iosContainerRootPattern = RegExp(
  r'^(/private)?/var/mobile/Containers/Data/Application/[A-F0-9\-]+/?$',
  caseSensitive: false,
);
final _iosContainerPathWithoutLeadingSlashPattern = RegExp(
  r'^(private/)?var/mobile/Containers/Data/Application/[A-F0-9\-]+/.+',
  caseSensitive: false,
);
final _iosLegacyRelativeDocumentsPattern = RegExp(
  r'^Data/Application/[A-F0-9\-]+/Documents(?:/(.*))?$',
  caseSensitive: false,
);
final _iosNestedLegacyDocumentsPattern = RegExp(
  r'/Documents/Data/Application/[A-F0-9\-]+/Documents(?:/(.*))?$',
  caseSensitive: false,
);

String _normalizeRecoveredIosSuffix(String suffix) {
  final trimmed = suffix.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
}

String _joinRecoveredIosPath(String documentsPath, String suffix) {
  final normalizedSuffix = _normalizeRecoveredIosSuffix(suffix);
  if (normalizedSuffix.isEmpty) return documentsPath;
  return '$documentsPath/$normalizedSuffix';
}

/// Checks if a path is a valid writable directory on iOS.
/// Returns false if:
/// - The path is the app container root (not writable)
/// - The path is an iCloud Drive path (not accessible by Go backend)
/// - The path is outside the app sandbox
bool isValidIosWritablePath(String path) {
  if (!Platform.isIOS) return true;
  if (path.isEmpty) return false;
  if (!path.startsWith('/')) return false;

  if (_iosContainerRootPattern.hasMatch(path)) {
    return false;
  }

  if (path.contains('Mobile Documents') ||
      path.contains('CloudDocs') ||
      path.contains('com~apple~CloudDocs')) {
    return false;
  }

  if (_iosNestedLegacyDocumentsPattern.hasMatch(path)) {
    return false;
  }

  final containerPattern = RegExp(
    r'/var/mobile/Containers/Data/Application/[A-F0-9\-]+',
    caseSensitive: false,
  );
  final match = containerPattern.firstMatch(path);
  if (match != null) {
    final remainingPath = path.substring(match.end);
    if (remainingPath.isEmpty || remainingPath == '/') {
      return false;
    }
  }

  return true;
}

/// Validates and potentially corrects an iOS path.
/// Returns a valid Documents subdirectory path if the input is invalid.
Future<String> validateOrFixIosPath(
  String path, {
  String subfolder = 'SpotiFLAC',
}) async {
  if (!Platform.isIOS) return path;

  final trimmed = path.trim();
  final docDir = await getApplicationDocumentsDirectory();

  final nestedLegacyMatch = _iosNestedLegacyDocumentsPattern.firstMatch(
    trimmed,
  );
  if (nestedLegacyMatch != null) {
    return _joinRecoveredIosPath(docDir.path, nestedLegacyMatch.group(1) ?? '');
  }

  if (isValidIosWritablePath(trimmed)) {
    return trimmed;
  }

  final candidates = <String>[];

  if (trimmed.isNotEmpty) {
    candidates.add(trimmed);
  }

  if (_iosContainerPathWithoutLeadingSlashPattern.hasMatch(trimmed)) {
    candidates.add('/$trimmed');
  }

  final legacyRelativeMatch = _iosLegacyRelativeDocumentsPattern.firstMatch(
    trimmed,
  );
  if (legacyRelativeMatch != null) {
    candidates.add(
      _joinRecoveredIosPath(docDir.path, legacyRelativeMatch.group(1) ?? ''),
    );
  }

  if (!trimmed.startsWith('/')) {
    final documentsMarker = 'Documents/';
    final index = trimmed.indexOf(documentsMarker);
    if (index >= 0) {
      final suffix = trimmed.substring(index + documentsMarker.length).trim();
      candidates.add(_joinRecoveredIosPath(docDir.path, suffix));
    }
  }

  for (final candidate in candidates) {
    if (isValidIosWritablePath(candidate)) {
      return candidate;
    }
  }

  final musicDir = Directory('${docDir.path}/$subfolder');
  if (!await musicDir.exists()) {
    await musicDir.create(recursive: true);
  }
  return musicDir.path;
}

/// Detailed result for iOS path validation
class IosPathValidationResult {
  final bool isValid;
  final String? correctedPath;
  final String? errorReason;

  const IosPathValidationResult({
    required this.isValid,
    this.correctedPath,
    this.errorReason,
  });
}

/// Validates an iOS path and returns detailed information about the result.
IosPathValidationResult validateIosPath(String path) {
  if (!Platform.isIOS) {
    return const IosPathValidationResult(isValid: true);
  }

  if (path.isEmpty) {
    return const IosPathValidationResult(
      isValid: false,
      errorReason: 'Path is empty',
    );
  }

  if (!path.startsWith('/')) {
    return const IosPathValidationResult(
      isValid: false,
      errorReason:
          'Invalid path format. Please choose a local folder from Files.',
    );
  }

  if (_iosContainerRootPattern.hasMatch(path)) {
    return const IosPathValidationResult(
      isValid: false,
      errorReason:
          'Cannot write to app container root. Please choose a subfolder like Documents.',
    );
  }

  if (path.contains('Mobile Documents') ||
      path.contains('CloudDocs') ||
      path.contains('com~apple~CloudDocs')) {
    return const IosPathValidationResult(
      isValid: false,
      errorReason:
          'iCloud Drive is not supported. Please choose a local folder.',
    );
  }

  if (_iosNestedLegacyDocumentsPattern.hasMatch(path)) {
    return const IosPathValidationResult(
      isValid: false,
      errorReason:
          'Invalid iOS app folder path. Please choose App Documents or another local folder.',
    );
  }

  final containerPattern = RegExp(
    r'/var/mobile/Containers/Data/Application/[A-F0-9\-]+',
    caseSensitive: false,
  );
  final match = containerPattern.firstMatch(path);
  if (match != null) {
    final remainingPath = path.substring(match.end);
    if (remainingPath.isEmpty || remainingPath == '/') {
      return const IosPathValidationResult(
        isValid: false,
        errorReason:
            'Cannot write to app container root. Please use the default folder or choose a different location.',
      );
    }
  }

  return const IosPathValidationResult(isValid: true);
}

class FileAccessStat {
  final int? size;
  final DateTime? modified;

  const FileAccessStat({this.size, this.modified});
}

bool isContentUri(String? path) {
  return path != null && path.startsWith('content://');
}

bool isSameContentUri(String? first, String? second) {
  if (first == null || second == null) return false;
  if (first == second) return true;
  if (!isContentUri(first) || !isContentUri(second)) return false;

  String decode(String value) {
    try {
      return Uri.decodeFull(value);
    } catch (_) {
      return value;
    }
  }

  return decode(first) == decode(second);
}

/// Pattern matching CUE virtual path suffixes like #track01, #track12, etc.
final _cueTrackSuffix = RegExp(r'#track\d+$');

const cueVirtualTrackRequiresSplitMessage =
    'This CUE track is virtual. Use Split into Tracks first.';

/// Whether the path is a CUE virtual path (contains #trackNN suffix).
bool isCueVirtualPath(String? path) {
  return path != null && _cueTrackSuffix.hasMatch(path);
}

/// Strip the #trackNN suffix from a CUE virtual path to get the base .cue path.
/// Returns the path unchanged if it's not a CUE virtual path.
String stripCueTrackSuffix(String path) {
  return path.replaceFirst(_cueTrackSuffix, '');
}

Future<bool> fileExists(String? path) async {
  if (path == null || path.isEmpty) return false;
  final realPath = isCueVirtualPath(path) ? stripCueTrackSuffix(path) : path;
  if (isContentUri(realPath)) {
    return PlatformBridge.safExists(realPath);
  }
  return File(realPath).exists();
}

/// Deletes [path] and reports whether the file is confirmed absent afterward.
///
/// SAF providers are allowed to reject a delete request by returning `false`.
/// Callers that also remove a Library row must only do so when this returns
/// `true`, otherwise the app would hide a file that still exists on storage.
Future<bool> deleteFile(String? path) async {
  if (path == null || path.isEmpty) return false;
  // CUE virtual paths should NOT be deleted through this function —
  // deleting album.cue would remove ALL tracks. Callers should handle
  // CUE deletion specially (e.g. only delete when all tracks are removed).
  if (isCueVirtualPath(path)) return false;
  if (isContentUri(path)) {
    try {
      final deleted = await PlatformBridge.safDelete(path);
      final confirmedAbsent = deleted || !await PlatformBridge.safExists(path);
      if (confirmedAbsent) {
        await musicPlayerHandler?.onSourceDeleted(path);
      }
      return confirmedAbsent;
    } catch (_) {
      return false;
    }
  }

  final file = File(path);
  try {
    if (await file.exists()) {
      await file.delete();
    }
    final confirmedAbsent = !await file.exists();
    if (confirmedAbsent) {
      await musicPlayerHandler?.onSourceDeleted(path);
    }
    return confirmedAbsent;
  } catch (_) {
    return false;
  }
}

Future<FileAccessStat?> fileStat(String? path) async {
  if (path == null || path.isEmpty) return null;
  final realPath = isCueVirtualPath(path) ? stripCueTrackSuffix(path) : path;
  if (isContentUri(realPath)) {
    final stat = await PlatformBridge.safStat(realPath);
    final exists = stat['exists'] as bool? ?? true;
    if (!exists) return null;
    return FileAccessStat(
      size: stat['size'] as int?,
      modified: stat['modified'] != null
          ? DateTime.fromMillisecondsSinceEpoch(stat['modified'] as int)
          : null,
    );
  }

  final stat = await FileStat.stat(realPath);
  if (stat.type == FileSystemEntityType.notFound) return null;
  return FileAccessStat(size: stat.size, modified: stat.modified);
}

Future<void> openFile(String path) async {
  if (isCueVirtualPath(path)) {
    throw Exception(cueVirtualTrackRequiresSplitMessage);
  }

  final realPath = path;
  if (isContentUri(realPath)) {
    await PlatformBridge.openContentUri(realPath, mimeType: '');
    return;
  }
  final mimeType = audioMimeTypeForPath(realPath);
  final result = await OpenFilex.open(realPath, type: mimeType);
  if (result.type != ResultType.done) {
    throw Exception(result.message);
  }
}

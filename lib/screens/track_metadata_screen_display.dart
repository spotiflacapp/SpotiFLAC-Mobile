// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of 'track_metadata_screen.dart';

// Display helpers: quality/bitrate labels, service track-id formatting,
// snackbars, and path formatting.
extension _TrackMetadataDisplay on _TrackMetadataScreenState {
  bool _isBitrateFormatValue(String? value) {
    return const {
      'aac',
      'eac3',
      'ac3',
      'ac4',
      'mp3',
      'opus',
      'm4a',
    }.contains(normalizeAudioFormatValue(value));
  }

  String? _usableStoredQuality(String? quality) {
    final normalized = normalizeOptionalString(quality);
    if (normalized == null || isPlaceholderQualityLabel(normalized)) {
      return null;
    }
    final bitrateMatch = RegExp(
      r'\b(\d+)\s*kbps\b',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (bitrateMatch != null) {
      final bitrate = int.tryParse(bitrateMatch.group(1) ?? '');
      if (bitrate != null && bitrate < 16) return null;
    }
    return normalized;
  }

  String? _displayQualityForValues({
    required String? format,
    int? bitDepth,
    int? sampleRate,
    int? bitrateKbps,
    String? storedQuality,
  }) {
    final normalizedFormat = normalizeAudioFormatValue(format);
    final formatLabel = normalizedFormat == null
        ? normalizeOptionalString(format)?.toUpperCase()
        : _formatLabelForRaw(normalizedFormat);
    if (_isBitrateFormatValue(normalizedFormat)) {
      return buildDisplayAudioQuality(
            bitrateKbps: bitrateKbps,
            format: formatLabel,
          ) ??
          _usableStoredQuality(storedQuality) ??
          formatLabel;
    }
    return buildDisplayAudioQuality(
      bitDepth: bitDepth,
      sampleRate: sampleRate,
      storedQuality: _usableStoredQuality(storedQuality),
    );
  }

  String _displayServiceTrackId(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return raw;
    final spotifyTrackIdPattern = RegExp(r'^[A-Za-z0-9]{22}$');

    if (raw.startsWith('deezer:')) return raw.substring('deezer:'.length);
    if (raw.startsWith('tidal:')) return raw.substring('tidal:'.length);
    if (raw.startsWith('qobuz:')) return raw.substring('qobuz:'.length);
    if (spotifyTrackIdPattern.hasMatch(raw)) return raw;

    if (raw.startsWith('spotify:')) {
      final last = raw.split(':').last.trim();
      if (spotifyTrackIdPattern.hasMatch(last)) return last;
      return raw;
    }

    final uri = Uri.tryParse(raw);
    if (uri != null &&
        uri.host.contains('spotify.com') &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'track') {
      final candidate = uri.pathSegments[1].trim();
      if (spotifyTrackIdPattern.hasMatch(candidate)) {
        return candidate;
      }
    }

    return raw;
  }

  String _serviceForTrackId(String value, {required String fallbackService}) {
    final raw = value.trim();
    if (raw.isEmpty) return fallbackService;
    final spotifyTrackIdPattern = RegExp(r'^[A-Za-z0-9]{22}$');

    if (raw.startsWith('deezer:')) return MusicServices.deezer;
    if (raw.startsWith('tidal:')) return MusicServices.tidal;
    if (raw.startsWith('qobuz:')) return MusicServices.qobuz;
    if (raw.startsWith('spotify:')) return MusicServices.spotify;
    if (spotifyTrackIdPattern.hasMatch(raw)) return MusicServices.spotify;

    final uri = Uri.tryParse(raw);
    if (uri != null) {
      final host = uri.host.toLowerCase();
      if (host.contains('spotify.com')) return MusicServices.spotify;
      if (host.contains('deezer.com')) return MusicServices.deezer;
      if (host.contains('tidal.com')) return MusicServices.tidal;
      if (host.contains('qobuz.com')) return MusicServices.qobuz;
    }

    return fallbackService;
  }

  String? get _displayAudioQuality {
    final fileName = _extractFileNameFromPathOrUri(cleanFilePath);
    final fileExt = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : null;

    return _displayQualityForValues(
      format: _storedAudioFormat ?? fileExt,
      bitDepth: bitDepth,
      sampleRate: sampleRate,
      bitrateKbps: _audioBitrate,
      storedQuality: _quality,
    );
  }

  /// The raw file path, with EXISTS: prefix stripped but #trackNN preserved.
  /// Use this when you need the full virtual path (e.g. for display or DB lookups).
  String get rawFilePath {
    final path = _filePath;
    return path.startsWith('EXISTS:') ? path.substring(7) : path;
  }

  /// The clean file path with both EXISTS: prefix and #trackNN suffix stripped.
  /// Use this for actual filesystem/SAF operations.
  String get cleanFilePath {
    var path = _filePath;
    if (path.startsWith('EXISTS:')) path = path.substring(7);
    if (isCueVirtualPath(path)) path = stripCueTrackSuffix(path);
    return path;
  }

  bool get _isCueVirtualTrack => isCueVirtualPath(rawFilePath);

  String _cueVirtualTrackGuidance(BuildContext context) {
    return 'This CUE track is virtual. Use ${context.l10n.cueSplitButton} first.';
  }

  void _showCueVirtualTrackSnackBar(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_cueVirtualTrackGuidance(context))));
  }

  void _hideCurrentSnackBar() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  String get _l10nCueSplitFailed => context.l10n.cueSplitFailed;
  String get _l10nCueSplitNoAudioFile => context.l10n.cueSplitNoAudioFile;

  String _l10nCueSplitSplitting(int current, int total) {
    return context.l10n.cueSplitSplitting(current, total);
  }

  String _l10nCueSplitSuccess(int count) {
    return context.l10n.cueSplitSuccess(count);
  }

  void _showSnackBarMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showLongSnackBarMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 60)),
    );
  }

  String _formatPathForDisplay(String pathOrUri) {
    if (pathOrUri.isEmpty || !pathOrUri.startsWith('content://')) {
      return pathOrUri;
    }

    try {
      final uri = Uri.parse(pathOrUri);
      final segments = uri.pathSegments;
      String? documentId;

      final documentIndex = segments.indexOf('document');
      if (documentIndex != -1 && documentIndex + 1 < segments.length) {
        documentId = Uri.decodeComponent(segments[documentIndex + 1]);
      }

      if (documentId == null || documentId.isEmpty) {
        final treeIndex = segments.indexOf('tree');
        if (treeIndex != -1 && treeIndex + 1 < segments.length) {
          documentId = Uri.decodeComponent(segments[treeIndex + 1]);
        }
      }

      if (documentId == null || documentId.isEmpty) return pathOrUri;

      final separatorIndex = documentId.indexOf(':');
      if (separatorIndex <= 0) return documentId;

      final volumeId = documentId.substring(0, separatorIndex);
      final relativePath = documentId
          .substring(separatorIndex + 1)
          .replaceAll('\\', '/');

      if (volumeId.toLowerCase() == 'primary') {
        if (relativePath.isEmpty) return '/storage/emulated/0';
        return '/storage/emulated/0/$relativePath';
      }

      if (relativePath.isEmpty) return volumeId;
      return 'SD Card/$relativePath';
    } catch (_) {
      return pathOrUri;
    }
  }
}

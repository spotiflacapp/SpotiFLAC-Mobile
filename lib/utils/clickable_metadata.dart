import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/screens/artist_screen.dart';
import 'package:spotiflac_android/screens/album_screen.dart';
import 'package:spotiflac_android/screens/home_tab.dart'
    show ExtensionArtistScreen, ExtensionAlbumScreen;
import 'package:spotiflac_android/services/shell_navigation_service.dart';
import 'package:spotiflac_android/utils/artist_utils.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('ClickableMetadata');

class _MetadataSearchResult {
  final String providerId;
  final List<Map<String, dynamic>> items;

  const _MetadataSearchResult({required this.providerId, required this.items});
}

Future<_MetadataSearchResult?> _searchMetadataProviders(
  BuildContext context,
  String query, {
  required String filter,
  int limit = 5,
  String? sourceProviderId,
}) async {
  final providerIds = _metadataSearchProviderCandidates(
    context,
    sourceProviderId: sourceProviderId,
  );

  for (final providerId in providerIds) {
    try {
      final items = await _searchMetadataProvider(
        providerId,
        query,
        filter: filter,
        limit: limit,
      );
      if (items.isNotEmpty) {
        return _MetadataSearchResult(providerId: providerId, items: items);
      }
    } catch (e) {
      _log.w(
        'Metadata lookup failed for provider "$providerId", filter=$filter: $e',
      );
    }
  }

  return null;
}

Future<List<Map<String, dynamic>>> _searchMetadataProvider(
  String providerId,
  String query, {
  required String filter,
  required int limit,
}) async {
  return PlatformBridge.customSearchWithExtension(
    providerId,
    query,
    options: {'filter': filter, 'limit': limit},
  );
}

List<String> _metadataSearchProviderCandidates(
  BuildContext context, {
  String? sourceProviderId,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final extensionState = container.read(extensionProvider);
  final settings = container.read(settingsProvider);
  final extensionNotifier = container.read(extensionProvider.notifier);
  final candidates = <String>[];

  void addProvider(String? providerId) {
    final normalized = providerId?.trim();
    if (normalized == null ||
        normalized.isEmpty ||
        candidates.contains(normalized) ||
        !_canSearchMetadataProvider(normalized, extensionState)) {
      return;
    }
    candidates.add(normalized);
  }

  addProvider(sourceProviderId);
  addProvider(settings.searchProvider);

  for (final providerId in extensionState.metadataProviderPriority) {
    addProvider(providerId);
  }
  for (final providerId in extensionNotifier.getAllMetadataProviders()) {
    addProvider(providerId);
  }

  final searchExtensions = extensionState.extensions
      .where((ext) => ext.enabled && ext.hasCustomSearch)
      .toList(growable: false);
  for (final extension in searchExtensions.where(
    (ext) => ext.searchBehavior?.primary == true,
  )) {
    addProvider(extension.id);
  }
  for (final extension in searchExtensions.where(
    (ext) => ext.searchBehavior?.primary != true,
  )) {
    addProvider(extension.id);
  }

  return candidates;
}

bool _canSearchMetadataProvider(
  String providerId,
  ExtensionState extensionState,
) {
  return extensionState.extensions.any(
    (ext) => ext.enabled && ext.hasCustomSearch && ext.id == providerId,
  );
}

Future<void> navigateToArtist(
  BuildContext context, {
  required String artistName,
  String? artistId,
  String? coverUrl,
  String? extensionId,
}) async {
  if (artistName.isEmpty) return;

  final normalizedArtistId = _normalizeArtistId(artistId);

  if (normalizedArtistId != null &&
      _canNavigateArtistDirectly(
        artistId: normalizedArtistId,
        extensionId: extensionId,
      )) {
    _pushArtistScreen(
      context,
      artistId: normalizedArtistId,
      artistName: artistName,
      coverUrl: coverUrl,
      extensionId: extensionId,
    );
    return;
  }

  _showLoadingSnackBar(context, context.l10n.clickableLookingUpArtist);
  try {
    final searchResult = await _searchMetadataProviders(
      context,
      artistName,
      filter: 'artist',
      limit: 3,
      sourceProviderId: extensionId,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final artistList = searchResult?.items ?? const <Map<String, dynamic>>[];
    if (artistList.isEmpty) {
      _showUnavailable(context, context.l10n.trackArtist);
      return;
    }

    Map<String, dynamic>? bestMatch;
    final lowerName = artistName.toLowerCase().trim();
    for (final a in artistList) {
      final name = (a['name'] as String? ?? '').toLowerCase().trim();
      if (name == lowerName) {
        bestMatch = a;
        break;
      }
    }
    bestMatch ??= artistList.first;

    final resolvedId = bestMatch['id'] as String? ?? '';
    final resolvedName = bestMatch['name'] as String? ?? artistName;
    final resolvedImage = bestMatch['images'] as String?;
    final resolvedProviderId = _resolveResultProviderId(
      bestMatch,
      searchResult?.providerId,
    );

    if (resolvedId.isEmpty) {
      _showUnavailable(context, context.l10n.trackArtist);
      return;
    }

    if (!context.mounted) return;
    _pushArtistScreen(
      context,
      artistId: resolvedId,
      artistName: resolvedName,
      coverUrl: resolvedImage ?? coverUrl,
      extensionId: resolvedProviderId,
    );
  } catch (e) {
    _log.e('Failed to look up artist "$artistName": $e', e);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    _showUnavailable(context, context.l10n.trackArtist);
  }
}

Future<void> navigateToAlbum(
  BuildContext context, {
  required String albumName,
  String? albumId,
  String? artistName,
  String? coverUrl,
  String? extensionId,
}) async {
  if (albumName.isEmpty) return;

  if (albumId != null && albumId.isNotEmpty && !_isUnknownResourceId(albumId)) {
    _pushAlbumScreen(
      context,
      albumId: albumId,
      albumName: albumName,
      coverUrl: coverUrl,
      extensionId: extensionId,
    );
    return;
  }

  _showLoadingSnackBar(context, context.l10n.clickableLookingUpAlbum);
  try {
    final query = artistName != null && artistName.isNotEmpty
        ? '$albumName $artistName'
        : albumName;

    final searchResult = await _searchMetadataProviders(
      context,
      query,
      filter: 'album',
      limit: 5,
      sourceProviderId: extensionId,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final albumList = searchResult?.items ?? const <Map<String, dynamic>>[];
    if (albumList.isEmpty) {
      _showUnavailable(context, context.l10n.trackAlbum);
      return;
    }

    Map<String, dynamic>? bestMatch;
    final lowerName = albumName.toLowerCase().trim();
    for (final a in albumList) {
      final name = (a['name'] as String? ?? '').toLowerCase().trim();
      if (name == lowerName) {
        bestMatch = a;
        break;
      }
    }
    bestMatch ??= albumList.first;

    final resolvedId = bestMatch['id'] as String? ?? '';
    final resolvedName = bestMatch['name'] as String? ?? albumName;
    final resolvedImage = bestMatch['images'] as String?;
    final resolvedProviderId = _resolveResultProviderId(
      bestMatch,
      searchResult?.providerId,
    );

    if (resolvedId.isEmpty) {
      _showUnavailable(context, context.l10n.trackAlbum);
      return;
    }

    if (!context.mounted) return;
    _pushAlbumScreen(
      context,
      albumId: resolvedId,
      albumName: resolvedName,
      coverUrl: resolvedImage ?? coverUrl,
      extensionId: resolvedProviderId,
    );
  } catch (e) {
    _log.e('Failed to look up album "$albumName": $e', e);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    _showUnavailable(context, context.l10n.trackAlbum);
  }
}

void _pushArtistScreen(
  BuildContext context, {
  required String artistId,
  required String artistName,
  String? coverUrl,
  String? extensionId,
}) {
  final isExtension = extensionId != null;
  final resolvedProviderId = extensionId;

  _pushViaPreferredNavigator(
    context,
    (context) => isExtension && resolvedProviderId != null
        ? ExtensionArtistScreen(
            extensionId: resolvedProviderId,
            artistId: artistId,
            artistName: artistName,
            coverUrl: coverUrl,
          )
        : ArtistScreen(
            artistId: artistId,
            artistName: artistName,
            coverUrl: coverUrl,
            extensionId: resolvedProviderId,
          ),
  );
}

void _pushAlbumScreen(
  BuildContext context, {
  required String albumId,
  required String albumName,
  String? coverUrl,
  String? extensionId,
}) {
  final isExtension = extensionId != null;
  final resolvedExtensionId = extensionId;

  _pushViaPreferredNavigator(
    context,
    (context) => isExtension && resolvedExtensionId != null
        ? ExtensionAlbumScreen(
            extensionId: resolvedExtensionId,
            albumId: albumId,
            albumName: albumName,
            coverUrl: coverUrl,
          )
        : AlbumScreen(
            albumId: albumId,
            albumName: albumName,
            coverUrl: coverUrl,
            extensionId: resolvedExtensionId,
            tracks: const [],
          ),
  );
}

void _pushViaPreferredNavigator(BuildContext context, WidgetBuilder builder) {
  final currentNavigator = Navigator.of(context);
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  final activeTabNavigator = ShellNavigationService.activeTabNavigator();

  final shouldRouteToTabNavigator =
      identical(currentNavigator, rootNavigator) && activeTabNavigator != null;

  if (!shouldRouteToTabNavigator) {
    currentNavigator.push(MaterialPageRoute<void>(builder: builder));
    return;
  }

  final currentRoute = ModalRoute.of(context);
  final shouldPopCurrentRoute =
      currentRoute != null && currentRoute.isFirst == false;

  if (shouldPopCurrentRoute && currentNavigator.canPop()) {
    currentNavigator.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!activeTabNavigator.mounted) return;
      activeTabNavigator.push(MaterialPageRoute<void>(builder: builder));
    });
    return;
  }

  activeTabNavigator.push(MaterialPageRoute<void>(builder: builder));
}

void _showLoadingSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(message),
        ],
      ),
      duration: const Duration(seconds: 10),
    ),
  );
}

void _showUnavailable(BuildContext context, String type) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(context.l10n.clickableInformationUnavailable(type))),
  );
}

class ClickableArtistName extends StatefulWidget {
  final String artistName;
  final String? artistId;
  final String? coverUrl;
  final String? extensionId;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const ClickableArtistName({
    super.key,
    required this.artistName,
    this.artistId,
    this.coverUrl,
    this.extensionId,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  State<ClickableArtistName> createState() => _ClickableArtistNameState();
}

class _ClickableArtistNameState extends State<ClickableArtistName> {
  List<_ArtistTapTarget> _artistTargets = const [];
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _rebuildArtistTargets();
  }

  @override
  void didUpdateWidget(covariant ClickableArtistName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artistName != widget.artistName ||
        oldWidget.artistId != widget.artistId ||
        oldWidget.coverUrl != widget.coverUrl ||
        oldWidget.extensionId != widget.extensionId) {
      _rebuildArtistTargets();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _rebuildArtistTargets() {
    _disposeRecognizers();
    _artistTargets = _buildArtistTapTargets(widget.artistName, widget.artistId);
    if (_artistTargets.length <= 1) return;

    for (final target in _artistTargets) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () => navigateToArtist(
          context,
          artistName: target.name,
          artistId: target.artistId,
          coverUrl: widget.coverUrl,
          extensionId: _extensionIdForTarget(target),
        );
      _recognizers.add(recognizer);
    }
  }

  String? _extensionIdForTarget(_ArtistTapTarget target) {
    if (widget.extensionId == null) return null;
    if (_artistTargets.length == 1) return widget.extensionId;
    return target.artistId != null ? widget.extensionId : null;
  }

  List<InlineSpan> _buildMultiArtistSpans() {
    final spans = <InlineSpan>[];
    for (var i = 0; i < _artistTargets.length; i++) {
      final target = _artistTargets[i];
      spans.add(
        TextSpan(
          text: target.name,
          style: widget.style,
          recognizer: _recognizers[i],
        ),
      );
      if (i < _artistTargets.length - 1) {
        spans.add(TextSpan(text: ', ', style: widget.style));
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    if (_artistTargets.isEmpty) {
      return Text(
        widget.artistName,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        textAlign: widget.textAlign,
      );
    }

    if (_artistTargets.length == 1) {
      final target = _artistTargets.first;
      return GestureDetector(
        onTap: () => navigateToArtist(
          context,
          artistName: target.name,
          artistId: target.artistId,
          coverUrl: widget.coverUrl,
          extensionId: _extensionIdForTarget(target),
        ),
        child: Text(
          target.name,
          style: widget.style,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
          textAlign: widget.textAlign,
        ),
      );
    }

    return Text.rich(
      TextSpan(style: widget.style, children: _buildMultiArtistSpans()),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
      textAlign: widget.textAlign ?? TextAlign.start,
    );
  }
}

class _ArtistTapTarget {
  final String name;
  final String? artistId;

  const _ArtistTapTarget({required this.name, this.artistId});
}

List<_ArtistTapTarget> _buildArtistTapTargets(
  String rawArtistNames,
  String? rawArtistIds,
) {
  final parsedNames = splitArtistNames(rawArtistNames);
  if (parsedNames.isEmpty) return const [];

  final uniqueNames = <String>[];
  final seen = <String>{};
  for (final parsed in parsedNames) {
    final key = parsed.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (key.isEmpty || !seen.add(key)) continue;
    uniqueNames.add(parsed);
  }
  if (uniqueNames.isEmpty) return const [];

  if (uniqueNames.length == 1) {
    return [
      _ArtistTapTarget(
        name: uniqueNames.first,
        artistId: _normalizeArtistId(rawArtistIds),
      ),
    ];
  }

  final parsedIds = _parseArtistIds(rawArtistIds);
  if (parsedIds.length == uniqueNames.length) {
    return List<_ArtistTapTarget>.generate(
      uniqueNames.length,
      (index) => _ArtistTapTarget(
        name: uniqueNames[index],
        artistId: parsedIds[index],
      ),
      growable: false,
    );
  }

  return uniqueNames
      .map((name) => _ArtistTapTarget(name: name))
      .toList(growable: false);
}

List<String> _parseArtistIds(String? rawArtistIds) {
  final raw = rawArtistIds?.trim();
  if (raw == null || raw.isEmpty) return const [];

  final parsed = <String>[];
  for (final part in raw.split(RegExp(r'\s*,\s*'))) {
    final normalized = _normalizeArtistId(part);
    if (normalized != null) {
      parsed.add(normalized);
    }
  }
  return parsed;
}

String? _normalizeArtistId(String? artistId) {
  final id = artistId?.trim();
  if (id == null || _isUnknownResourceId(id)) {
    return null;
  }
  return id;
}

bool _isUnknownResourceId(String id) {
  final normalized = id.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'unknown' ||
      normalized.endsWith(':unknown');
}

String? _resolveResultProviderId(
  Map<String, dynamic> result,
  String? fallbackProviderId,
) {
  final providerId = result['provider_id']?.toString().trim();
  if (providerId != null && providerId.isNotEmpty) return providerId;
  final source = result['source']?.toString().trim();
  if (source != null && source.isNotEmpty) return source;
  final fallback = fallbackProviderId?.trim();
  return fallback != null && fallback.isNotEmpty ? fallback : null;
}

bool _canNavigateArtistDirectly({
  required String artistId,
  required String? extensionId,
}) {
  if (extensionId != null) return true;
  return _spotifyArtistIdPattern.hasMatch(artistId);
}

final RegExp _spotifyArtistIdPattern = RegExp(r'^[A-Za-z0-9]{22}$');

class ClickableAlbumName extends StatelessWidget {
  final String albumName;
  final String? albumId;
  final String? artistName;
  final String? coverUrl;
  final String? extensionId;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const ClickableAlbumName({
    super.key,
    required this.albumName,
    this.albumId,
    this.artistName,
    this.coverUrl,
    this.extensionId,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => navigateToAlbum(
        context,
        albumName: albumName,
        albumId: albumId,
        artistName: artistName,
        coverUrl: coverUrl,
        extensionId: extensionId,
      ),
      child: Text(
        albumName,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';

/// Colour scheme derived from cover art, used to theme detail-screen headers.
///
/// The headers used to hardcode `Colors.white` text over a `Colors.black`
/// scrim, so they looked identical in light and dark mode and ignored dynamic
/// colour entirely — and white-on-pale-cover was hard to read. Deriving a
/// scheme from the artwork keeps the header tinted by the album while still
/// following the app's brightness, and guarantees the on-colours contrast with
/// whatever surface ends up behind them.
class CoverPalette {
  const CoverPalette._();

  /// Quantizing an image is not cheap, so results are memoized per
  /// URL+brightness. Bounded because a long library-browsing session would
  /// otherwise keep every visited album's scheme alive.
  static final Map<String, ColorScheme> _cache = <String, ColorScheme>{};
  static final List<String> _cacheOrder = <String>[];
  static const int _maxEntries = 32;

  static bool _isNetworkSource(String source) =>
      source.startsWith('http://') || source.startsWith('https://');

  /// Includes the local file version so replacing artwork at the same path
  /// cannot reuse a palette derived from the previous image.
  static String cacheKeyFor(String source, Brightness brightness) {
    var versionedSource = source;
    if (!_isNetworkSource(source)) {
      try {
        final stat = File(source).statSync();
        if (stat.type != FileSystemEntityType.notFound) {
          versionedSource =
              '$source|${stat.modified.microsecondsSinceEpoch}|${stat.size}';
        }
      } catch (_) {
        // Resolution below will return null for inaccessible local files.
      }
    }
    return '$versionedSource|${brightness.name}';
  }

  /// Cached scheme for [source], or null when it has not been resolved yet.
  static ColorScheme? peek(String source, Brightness brightness) =>
      _cache[cacheKeyFor(source, brightness)];

  static ColorScheme? _peekByKey(String key) => _cache[key];

  /// Resolves the scheme for [source] (a network URL or a local file path).
  /// Returns null when the image cannot be decoded.
  static Future<ColorScheme?> resolve(
    String source,
    Brightness brightness, {
    String? cacheKey,
  }) async {
    final key = cacheKey ?? cacheKeyFor(source, brightness);
    final cached = _cache[key];
    if (cached != null) return cached;

    final ImageProvider provider;
    if (_isNetworkSource(source)) {
      provider = cachedCoverImageProvider(source);
    } else {
      final file = File(source);
      if (!file.existsSync()) return null;
      provider = FileImage(file);
    }

    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: provider,
        brightness: brightness,
      );
      _cache[key] = scheme;
      _cacheOrder.add(key);
      while (_cacheOrder.length > _maxEntries) {
        _cache.remove(_cacheOrder.removeAt(0));
      }
      return scheme;
    } catch (_) {
      // Unreachable URL, unsupported format, decode failure: callers fall back
      // to the app scheme.
      return null;
    }
  }
}

/// Exposes the header's effective [ColorScheme] to descendants.
///
/// Header sub-widgets (meta rows, circle buttons, play actions) live in the
/// screens' own build methods, so they cannot be handed the palette directly;
/// they read it from here and fall back to the app scheme when absent.
class HeaderPalette extends InheritedWidget {
  const HeaderPalette({super.key, required this.scheme, required super.child});

  final ColorScheme scheme;

  static ColorScheme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HeaderPalette>()?.scheme ??
      Theme.of(context).colorScheme;

  @override
  bool updateShouldNotify(HeaderPalette oldWidget) =>
      scheme != oldWidget.scheme;
}

/// Resolves [imageSource] into a [ColorScheme] and rebuilds when it arrives.
class CoverPaletteBuilder extends StatefulWidget {
  const CoverPaletteBuilder({
    super.key,
    required this.imageSource,
    required this.builder,
  });

  /// Cover URL or local path. Null disables palette extraction.
  final String? imageSource;

  final Widget Function(BuildContext context, ColorScheme scheme) builder;

  @override
  State<CoverPaletteBuilder> createState() => _CoverPaletteBuilderState();
}

class _CoverPaletteBuilderState extends State<CoverPaletteBuilder> {
  ColorScheme? _scheme;
  String? _resolvedKey;
  int _resolveGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeResolve();
  }

  @override
  void didUpdateWidget(CoverPaletteBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check local file identity even when its path did not change. Metadata
    // editing can replace cover bytes in place.
    _maybeResolve();
  }

  void _maybeResolve() {
    final source = widget.imageSource;
    final brightness = Theme.of(context).brightness;
    if (source == null || source.isEmpty) {
      _resolveGeneration++;
      _resolvedKey = null;
      _scheme = null;
      return;
    }
    final key = CoverPalette.cacheKeyFor(source, brightness);
    if (_resolvedKey == key) return;

    final requestGeneration = ++_resolveGeneration;
    _resolvedKey = key;

    final cached = CoverPalette._peekByKey(key);
    if (cached != null) {
      _scheme = cached;
      return;
    }
    _scheme = null;

    CoverPalette.resolve(source, brightness, cacheKey: key).then((scheme) {
      if (!mounted) return;
      if (_resolveGeneration != requestGeneration || _resolvedKey != key) {
        return;
      }
      setState(() => _scheme = scheme);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = _scheme ?? Theme.of(context).colorScheme;
    return HeaderPalette(
      scheme: scheme,
      child: widget.builder(context, scheme),
    );
  }
}

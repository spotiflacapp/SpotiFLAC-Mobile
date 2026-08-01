import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';

class CachedCoverImage extends StatelessWidget {
  static const int _defaultMinCacheExtent = 64;
  static const int _defaultMaxCacheExtent = 512;

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final Widget Function(BuildContext, String)? placeholder;
  final BorderRadius? borderRadius;
  final bool resizeDiskCache;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;

  const CachedCoverImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.memCacheWidth,
    this.memCacheHeight,
    this.errorWidget,
    this.placeholder,
    this.borderRadius,
    this.resizeDiskCache = false,
    this.fadeInDuration = Duration.zero,
    this.fadeOutDuration = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final autoMemCacheWidth =
        memCacheWidth ?? _cacheExtentForLogicalSize(context, width);
    final autoMemCacheHeight =
        memCacheHeight ?? _cacheExtentForLogicalSize(context, height);
    final diskCacheWidth = resizeDiskCache ? autoMemCacheWidth : null;
    final diskCacheHeight = resizeDiskCache ? autoMemCacheHeight : null;
    final image = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      memCacheWidth: autoMemCacheWidth,
      memCacheHeight: autoMemCacheHeight,
      maxWidthDiskCache: diskCacheWidth,
      maxHeightDiskCache: diskCacheHeight,
      cacheManager: CoverCacheManager.instance,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: fadeOutDuration,
      useOldImageOnUrlChange: true,
      filterQuality: FilterQuality.low,
      errorWidget: errorWidget,
      placeholder: placeholder,
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return image;
  }

  static int? _cacheExtentForLogicalSize(BuildContext context, double? size) {
    if (size == null || !size.isFinite || size <= 0) return null;
    final dpr = MediaQuery.devicePixelRatioOf(
      context,
    ).clamp(1.0, 3.0).toDouble();
    return (size * dpr)
        .round()
        .clamp(_defaultMinCacheExtent, _defaultMaxCacheExtent)
        .toInt();
  }
}

/// Renders [url] as a local file (when it's not an http/https URL) or as a
/// cached network image otherwise, with a shared [placeholder] used for the
/// local error state, the local not-ready frame, and the network
/// placeholder/error states alike.
class LocalOrNetworkCoverImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? localCacheWidth;
  final int? networkCacheWidth;
  final Duration? fadeInDuration;
  final Duration fadeOutDuration;
  final String Function(String)? urlTransform;
  final Widget Function(BuildContext) placeholder;

  const LocalOrNetworkCoverImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.localCacheWidth,
    this.networkCacheWidth,
    this.fadeInDuration,
    this.fadeOutDuration = Duration.zero,
    this.urlTransform,
    required this.placeholder,
  });

  bool get _isLocal =>
      !url.startsWith('http://') && !url.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    if (_isLocal) {
      final image = Image.file(
        File(url),
        width: width,
        height: height,
        fit: fit,
        cacheWidth: localCacheWidth,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        frameBuilder: fadeInDuration == null
            ? null
            : (context, child, frame, wasSynchronouslyLoaded) {
                final ready = wasSynchronouslyLoaded || frame != null;
                if (fadeInDuration == Duration.zero) {
                  return ready ? child : placeholder(context);
                }
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    placeholder(context),
                    AnimatedOpacity(
                      opacity: ready ? 1.0 : 0.0,
                      duration: fadeInDuration!,
                      curve: Curves.easeOutCubic,
                      child: child,
                    ),
                  ],
                );
              },
        errorBuilder: (_, _, _) => placeholder(context),
      );
      return borderRadius == null
          ? image
          : ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return CachedCoverImage(
      imageUrl: urlTransform?.call(url) ?? url,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: networkCacheWidth,
      borderRadius: borderRadius,
      fadeInDuration: fadeInDuration ?? Duration.zero,
      fadeOutDuration: fadeOutDuration,
      placeholder: (_, _) => placeholder(context),
      errorWidget: (_, _, _) => placeholder(context),
    );
  }
}

CachedNetworkImageProvider cachedCoverImageProvider(String url) {
  return CachedNetworkImageProvider(
    url,
    cacheManager: CoverCacheManager.instance,
  );
}

/// Pre-warms the cover cache at the metadata-screen display size so the hero
/// transition doesn't pop in a low-res frame. Http(s) URLs only.
void precacheCoverImage(BuildContext context, String? url) {
  if (url == null || url.isEmpty) return;
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return;
  }
  final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0).toDouble();
  final targetSize = (360 * dpr).round().clamp(512, 1024).toInt();
  precacheImage(
    ResizeImage(
      cachedCoverImageProvider(url),
      width: targetSize,
      height: targetSize,
    ),
    context,
  );
}

int coverImageCacheExtent(
  BuildContext context,
  double logicalSize, {
  int min = 64,
  int max = 512,
}) {
  final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0).toDouble();
  return (logicalSize * dpr).round().clamp(min, max).toInt();
}

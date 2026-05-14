// lib/services/cross_extension_share_service.dart

import 'dart:convert';
import 'package:flutter/services.dart';

/// Result from one extension's search attempt.
class CrossExtensionShareResult {
  final String extensionId;
  final String displayName;
  final bool found;
  final String? itemId;
  final String? itemName;
  final String? itemArtists;
  final String? error;

  const CrossExtensionShareResult({
    required this.extensionId,
    required this.displayName,
    required this.found,
    this.itemId,
    this.itemName,
    this.itemArtists,
    this.error,
  });

  factory CrossExtensionShareResult.fromJson(Map<String, dynamic> json) {
    return CrossExtensionShareResult(
      extensionId: json['extension_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      found: json['found'] as bool? ?? false,
      itemId: json['item_id'] as String?,
      itemName: json['item_name'] as String?,
      itemArtists: json['item_artists'] as String?,
      error: json['error'] as String?,
    );
  }
}

class CrossExtensionShareService {
  static const _channel = MethodChannel('com.zarz.spotiflac/backend');

  /// Searches for [name] (album/artist/playlist) across all extensions
  /// except [sourceExtensionId].
  ///
  /// [type] must be "album", "artist", or "playlist".
  static Future<List<CrossExtensionShareResult>> findAcrossExtensions({
    required String name,
    required String artists,
    required String type,
    required String sourceExtensionId,
  }) async {
    final requestJson = jsonEncode({
      'name': name,
      'artists': artists,
      'type': type,
      'source_extension_id': sourceExtensionId,
    });

    final String? responseJson = await _channel.invokeMethod(
      'findCollectionAcrossExtensions',
      requestJson,
    );

    if (responseJson == null || responseJson.isEmpty) return [];

    final List<dynamic> decoded = jsonDecode(responseJson) as List<dynamic>;
    return decoded
        .map((e) => CrossExtensionShareResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

import 'package:spotiflac_android/constants/music_services.dart';

/// Maps a legacy prefixed resource id (e.g. "deezer:123") to its provider id,
/// or null when the value carries no known provider prefix.
String? legacyProviderIdFromResourceId(String value) {
  if (value.startsWith('deezer:')) return MusicServices.deezer;
  if (value.startsWith('qobuz:')) return MusicServices.qobuz;
  if (value.startsWith('tidal:')) return MusicServices.tidal;
  if (value.startsWith('spotify:')) return MusicServices.spotify;
  return null;
}

/// Strips a leading "provider:" prefix from a resource id, if present.
String stripPrefixedResourceId(String value) {
  final colonIndex = value.indexOf(':');
  if (colonIndex <= 0 || colonIndex == value.length - 1) {
    return value;
  }
  return value.substring(colonIndex + 1);
}

/// Resolves the metadata provider id to fetch a resource from, preferring a
/// caller-supplied [knownProviderId] (e.g. from a recent-access entry that
/// already recorded its source) over guessing from [resourceId]'s shape.
///
/// [legacyProviderIdFromResourceId] only recognizes legacy-prefixed ids
/// ("deezer:...", "spotify:...", etc.); anything else - including a plain,
/// unprefixed id from a provider that never used that scheme - resolves to
/// null unless the caller already knows the provider.
String? resolvePreferredMetadataProviderId(
  String? knownProviderId,
  String resourceId,
) {
  final known = knownProviderId?.trim();
  if (known != null && known.isNotEmpty) return known;
  return legacyProviderIdFromResourceId(resourceId);
}

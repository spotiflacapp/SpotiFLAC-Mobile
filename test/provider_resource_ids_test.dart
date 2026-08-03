import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/constants/music_services.dart';
import 'package:spotiflac_android/utils/provider_resource_ids.dart';

void main() {
  group('legacyProviderIdFromResourceId', () {
    test('maps known legacy prefixes to their provider id', () {
      expect(
        legacyProviderIdFromResourceId('deezer:123'),
        MusicServices.deezer,
      );
      expect(legacyProviderIdFromResourceId('qobuz:123'), MusicServices.qobuz);
      expect(legacyProviderIdFromResourceId('tidal:123'), MusicServices.tidal);
      expect(
        legacyProviderIdFromResourceId('spotify:123'),
        MusicServices.spotify,
      );
    });

    test('returns null for an id with no known prefix', () {
      expect(legacyProviderIdFromResourceId('37i9dQZF1DXcBWIGoYBM5M'), isNull);
      expect(legacyProviderIdFromResourceId(''), isNull);
    });
  });

  group('stripPrefixedResourceId', () {
    test('strips a leading provider prefix', () {
      expect(stripPrefixedResourceId('deezer:123'), '123');
    });

    test('leaves an id without a prefix unchanged', () {
      expect(
        stripPrefixedResourceId('37i9dQZF1DXcBWIGoYBM5M'),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
    });

    test('leaves a bare colon or trailing colon unchanged', () {
      expect(stripPrefixedResourceId(':123'), ':123');
      expect(stripPrefixedResourceId('deezer:'), 'deezer:');
    });
  });

  group('resolvePreferredMetadataProviderId', () {
    test('prefers a known provider id over guessing from the resource id', () {
      expect(
        resolvePreferredMetadataProviderId(
          'apple-music-ext',
          '37i9dQZF1DXcBWIGoYBM5M',
        ),
        'apple-music-ext',
      );
    });

    test('falls back to the legacy prefix guess when nothing is known', () {
      expect(
        resolvePreferredMetadataProviderId(null, 'deezer:123'),
        MusicServices.deezer,
      );
    });

    test('treats a blank known provider id as unknown', () {
      expect(
        resolvePreferredMetadataProviderId('   ', 'deezer:123'),
        MusicServices.deezer,
      );
    });

    test(
      'returns null for an unprefixed id with no known provider (the #368 case)',
      () {
        expect(
          resolvePreferredMetadataProviderId(null, '37i9dQZF1DXcBWIGoYBM5M'),
          isNull,
        );
      },
    );
  });
}

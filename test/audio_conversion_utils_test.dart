import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/utils/audio_conversion_utils.dart';

void main() {
  group('same-format lossless conversion', () {
    test('allows FLAC re-encoding for quality processing', () {
      expect(
        canConvertAudioFormat(sourceFormat: 'FLAC', targetFormat: 'FLAC'),
        isTrue,
      );
      expect(
        canConvertAudioFormat(sourceFormat: 'flac', targetFormat: ' flac '),
        isTrue,
      );
    });

    test('keeps same-format lossy conversion disabled', () {
      expect(
        canConvertAudioFormat(sourceFormat: 'MP3', targetFormat: 'MP3'),
        isFalse,
      );
      expect(
        canConvertAudioFormat(sourceFormat: 'Opus', targetFormat: 'Opus'),
        isFalse,
      );
    });
  });

  group('lossless processing options', () {
    test('preserves both resamplers and both dither methods', () {
      const soxrTpdf = LosslessConversionProcessing(
        dither: 'triangular',
        resampler: 'soxr',
      );
      const swrHighPass = LosslessConversionProcessing(
        dither: 'triangular_hp',
        resampler: 'swr',
      );

      expect(soxrTpdf.normalizedResampler, 'soxr');
      expect(soxrTpdf.normalizedDither, 'triangular');
      expect(soxrTpdf.hasDither, isTrue);
      expect(swrHighPass.normalizedResampler, 'swr');
      expect(swrHighPass.normalizedDither, 'triangular_hp');
      expect(swrHighPass.hasDither, isTrue);
    });

    test('uses VHQ and a 95 percent passband only for SoXR', () {
      const soxr = LosslessConversionProcessing(resampler: 'soxr');
      const swr = LosslessConversionProcessing(resampler: 'swr');

      expect(losslessResamplerFilterOptions(soxr), [
        'resampler=soxr',
        'precision=28',
        'cutoff=0.95',
      ]);
      expect(losslessResamplerFilterOptions(swr), ['resampler=swr']);
    });
  });

  group('kept conversion output identity', () {
    test('keeps the original base name and only changes the extension', () {
      expect(
        convertedOutputFileName(
          originalFileName: 'Track.flac',
          targetFormat: 'FLAC',
        ),
        'Track.flac',
      );
      expect(
        convertedOutputFileName(
          originalFileName: 'Track.flac',
          targetFormat: 'MP3',
        ),
        'Track.mp3',
      );
    });

    test('derives stable but path-specific converted item IDs', () {
      final first = convertedLibraryItemId('source', '/music/Track.flac');
      final repeated = convertedLibraryItemId('source', '/music/Track.flac');
      final other = convertedLibraryItemId('source', '/music/Track.m4a');

      expect(first, repeated);
      expect(first, isNot(other));
    });
  });
}

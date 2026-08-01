import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/utils/audio_quality_badge_policy.dart';

void main() {
  group('Library audio quality badge color', () {
    test('keeps legacy 24-bit labels highlighted', () {
      expect(shouldHighlightAudioQualityBadge('24-bit/96kHz'), isTrue);
      expect(shouldHighlightAudioQualityBadge('FLAC 24bit-48kHz'), isTrue);
      expect(shouldHighlightAudioQualityBadge('24/192kHz'), isTrue);
    });

    test('highlights only measured bitrates above 900 kbps', () {
      expect(shouldHighlightAudioQualityBadge('900kbps'), isFalse);
      expect(shouldHighlightAudioQualityBadge('901kbps'), isTrue);
      expect(shouldHighlightAudioQualityBadge('FLAC 1760 kbps'), isTrue);
      expect(shouldHighlightAudioQualityBadge('1.76 Mbps'), isTrue);
    });

    test('leaves normal lossy bitrate labels neutral', () {
      expect(shouldHighlightAudioQualityBadge('AAC 320kbps'), isFalse);
      expect(shouldHighlightAudioQualityBadge('OPUS 256k'), isFalse);
      expect(shouldHighlightAudioQualityBadge('16-bit/44.1kHz'), isFalse);
    });
  });

  group('Library audio quality label mode', () {
    test('uses measured bitrate by default', () {
      expect(
        buildLibraryAudioQualityLabel(
          mode: AppSettings.libraryQualityLabelBitrate,
          format: 'flac',
          bitrateKbps: 1760,
          bitDepth: 24,
          sampleRate: 48000,
        ),
        'FLAC 1760kbps',
      );
      expect(
        normalizeLibraryQualityLabelMode('unsupported'),
        AppSettings.libraryQualityLabelBitrate,
      );
    });

    test('restores legacy bit depth and sample rate labels', () {
      expect(
        buildLibraryAudioQualityLabel(
          mode: AppSettings.libraryQualityLabelBitDepth,
          format: 'flac',
          bitrateKbps: 1760,
          bitDepth: 24,
          sampleRate: 48000,
        ),
        '24-bit/48kHz',
      );
    });

    test('keeps bitrate meaningful for lossy formats', () {
      expect(
        buildLibraryAudioQualityLabel(
          mode: AppSettings.libraryQualityLabelBitDepth,
          format: 'mp3',
          bitrateKbps: 320,
          bitDepth: 16,
          sampleRate: 44100,
        ),
        'MP3 320kbps',
      );
    });

    test('falls back when the preferred metadata is unavailable', () {
      expect(
        buildLibraryAudioQualityLabel(
          mode: AppSettings.libraryQualityLabelBitDepth,
          format: 'flac',
          bitrateKbps: 950,
          storedQuality: 'LOSSLESS',
        ),
        'FLAC 950kbps',
      );
      expect(
        buildLibraryAudioQualityLabel(
          mode: AppSettings.libraryQualityLabelBitrate,
          storedQuality: '24-bit/96kHz',
        ),
        '24-bit/96kHz',
      );
    });
  });
}

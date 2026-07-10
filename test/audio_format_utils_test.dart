import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/utils/audio_format_utils.dart';

void main() {
  group('readPositiveBitrateKbps', () {
    test('passes through plausible kbps values', () {
      expect(readPositiveBitrateKbps(320), 320);
    });

    test('converts bps to kbps for large values', () {
      expect(readPositiveBitrateKbps(320000), 320);
    });

    test('rejects implausibly low values', () {
      expect(readPositiveBitrateKbps(8), isNull);
    });

    test('rejects non-numeric input', () {
      expect(readPositiveBitrateKbps('not a number'), isNull);
      expect(readPositiveBitrateKbps(null), isNull);
    });
  });

  group('audioFormatForPath', () {
    test('detects known extensions case-insensitively', () {
      expect(audioFormatForPath('/music/song.OPUS'), 'OPUS');
      expect(audioFormatForPath('/music/song.ogg'), 'OPUS');
      expect(audioFormatForPath('/music/song.mp3'), 'MP3');
      expect(audioFormatForPath('/music/song.aac'), 'AAC');
      expect(audioFormatForPath('/music/song.m4a'), 'M4A');
      expect(audioFormatForPath('/music/song.mp4'), 'M4A');
    });

    test('falls back to fileName when filePath does not match', () {
      expect(
        audioFormatForPath(null, fileName: 'track.mp3'),
        'MP3',
      );
    });

    test('returns null for unknown or missing extensions', () {
      expect(audioFormatForPath('/music/song.flac'), isNull);
      expect(audioFormatForPath(null), isNull);
    });
  });

  group('nonPlaceholderQuality', () {
    test('returns null for placeholder or empty quality', () {
      expect(nonPlaceholderQuality(null), isNull);
      expect(nonPlaceholderQuality('lossless'), isNull);
    });

    test('returns null for implausibly low bitrate labels', () {
      expect(nonPlaceholderQuality('8 kbps'), isNull);
    });

    test('returns null for requested-lossless placeholder labels', () {
      expect(nonPlaceholderQuality('Hi-Res Lossless'), isNull);
      expect(nonPlaceholderQuality('HIRES'), isNull);
    });

    test('returns a real quality label unchanged', () {
      expect(nonPlaceholderQuality('FLAC 1411kbps'), 'FLAC 1411kbps');
    });
  });

  group('normalizeAudioFormatValue / isLossyAudioFormat', () {
    test('normalizes known aliases to canonical keys', () {
      expect(normalizeAudioFormatValue('MP4A'), 'aac');
      expect(normalizeAudioFormatValue('EC-3'), 'eac3');
      expect(normalizeAudioFormatValue('ogg'), 'opus');
      expect(normalizeAudioFormatValue('mp4'), 'm4a');
      expect(normalizeAudioFormatValue('unknown'), isNull);
    });

    test('classifies lossy vs lossless formats', () {
      expect(isLossyAudioFormat('mp3'), isTrue);
      expect(isLossyAudioFormat('m4a'), isTrue);
      expect(isLossyAudioFormat('flac'), isFalse);
      expect(isLossyAudioFormat('alac'), isFalse);
      expect(isLossyAudioFormat(null), isFalse);
    });
  });

  group('lossy format helpers', () {
    test('lossyFormatForSetting maps free-form settings to canonical keys', () {
      expect(lossyFormatForSetting('OPUS 256kbps'), 'opus');
      expect(lossyFormatForSetting('AAC 256kbps'), 'aac');
      expect(lossyFormatForSetting('M4A'), 'aac');
      expect(lossyFormatForSetting('anything else'), 'mp3');
    });

    test('lossyExtensionForFormat returns the matching extension', () {
      expect(lossyExtensionForFormat('opus'), '.opus');
      expect(lossyExtensionForFormat('aac'), '.m4a');
      expect(lossyExtensionForFormat('mp3'), '.mp3');
    });

    test('metadataFormatForLossyFormat renames aac to m4a for tagging', () {
      expect(metadataFormatForLossyFormat('aac'), 'm4a');
      expect(metadataFormatForLossyFormat('opus'), 'opus');
    });

    test('displayFormatForLossyFormat renders a user-facing label', () {
      expect(displayFormatForLossyFormat('aac'), 'AAC');
      expect(displayFormatForLossyFormat('opus'), 'OPUS');
    });
  });

  group('displayFormatForCodec', () {
    test('maps known codecs to display labels', () {
      expect(displayFormatForCodec('flac'), 'FLAC');
      expect(displayFormatForCodec('EC-3'), 'EAC3');
      expect(displayFormatForCodec('unknown'), isNull);
    });
  });

  group('resolveDisplayQuality', () {
    test('prefers a bitrate label for lossy formats', () {
      expect(
        resolveDisplayQuality(
          filePath: '/music/song.mp3',
          bitrateKbps: 320,
        ),
        'MP3 320kbps',
      );
    });

    test('falls back to the stored quality when bitrate is unavailable', () {
      expect(
        resolveDisplayQuality(
          filePath: '/music/song.mp3',
          storedQuality: 'MP3 CBR',
        ),
        'MP3 CBR',
      );
    });

    test('falls back to bit depth/sample rate for hi-res containers', () {
      expect(
        resolveDisplayQuality(
          filePath: '/music/song.flac',
          detectedFormat: 'flac',
          bitDepth: 24,
          sampleRate: 96000,
        ),
        '24-bit/96kHz',
      );
    });

    test('treats M4A with a real bit depth as a hi-res container, not lossy', () {
      expect(
        resolveDisplayQuality(
          filePath: '/music/song.m4a',
          bitDepth: 24,
          sampleRate: 48000,
        ),
        '24-bit/48kHz',
      );
    });
  });
}

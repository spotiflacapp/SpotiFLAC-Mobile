import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/widgets/audio_analysis_widget.dart';

void main() {
  group('audio analysis codec support', () {
    test('rejects AC-4 aliases unsupported by the bundled decoder', () {
      expect(isAudioAnalysisCodecSupported('ac4'), isFalse);
      expect(isAudioAnalysisCodecSupported('AC-4'), isFalse);
      expect(isAudioAnalysisCodecSupported('Dolby Atmos (AC_4)'), isFalse);
      expect(unsupportedAudioAnalysisCodecLabel('AC-4'), 'AC-4');
    });

    test('keeps supported codecs inside MP4 analyzable', () {
      expect(isAudioAnalysisCodecSupported('aac'), isTrue);
      expect(isAudioAnalysisCodecSupported('alac'), isTrue);
      expect(isAudioAnalysisCodecSupported('eac3'), isTrue);
      expect(isAudioAnalysisCodecSupported('E-AC-3'), isTrue);
      expect(isAudioAnalysisCodecSupported('flac'), isTrue);
      expect(isAudioAnalysisCodecSupported(null), isTrue);
    });
  });

  group('audio level analysis', () {
    test('reads peak and RMS from the final astats overall summary', () {
      const logs = '''
[Parsed_astats_0] Channel: 1
[Parsed_astats_0] Peak level dB: -0.847144
[Parsed_astats_0] RMS level dB: -12.935500
[Parsed_astats_0] Channel: 2
[Parsed_astats_0] Peak level dB: -0.861847
[Parsed_astats_0] RMS level dB: -12.752564
[Parsed_astats_0] Overall
[Parsed_astats_0] Peak level dB: -0.847144
[Parsed_astats_0] RMS level dB: -12.843069
''';

      final summary = parseAudioAstatsSummary(logs);

      expect(summary, isNotNull);
      expect(summary!.peakDb, closeTo(-0.847144, 0.000001));
      expect(summary.rmsDb, closeTo(-12.843069, 0.000001));
    });

    test('rejects logs delivered without the final RMS metric', () {
      const incompleteLogs = '''
[Parsed_astats_0] Overall
[Parsed_astats_0] Peak level dB: -0.847144
''';

      expect(parseAudioAstatsSummary(incompleteLogs), isNull);
    });

    test('reads per-session metadata without depending on FFmpeg logs', () {
      const metadata = '''
lavfi.astats.1.Peak_level=-0.847144
lavfi.astats.1.RMS_level=-12.935500
lavfi.astats.1.Peak_count=2.000000
lavfi.astats.2.Peak_level=-0.861847
lavfi.astats.2.RMS_level=-12.752564
lavfi.astats.2.Peak_count=2.000000
lavfi.astats.Overall.Peak_level=-0.847144
lavfi.astats.Overall.RMS_level=-12.843069
lavfi.r128.I=-9.708
lavfi.r128.true_peak=0.907
''';

      final summary = parseAudioAnalysisMetadata(metadata);

      expect(summary, isNotNull);
      expect(summary!.peakDb, closeTo(-0.847144, 0.000001));
      expect(summary.rmsDb, closeTo(-12.843069, 0.000001));
      expect(summary.integratedLufs, closeTo(-9.708, 0.000001));
      expect(summary.truePeakDb, closeTo(-0.8476, 0.001));
      expect(summary.channelStats, hasLength(2));
      expect(summary.channelStats.first.channel, 1);
      expect(summary.channelStats.first.peakCount, 2);
    });

    test('keeps the analyzer independent from process-global log level', () {
      final arguments = buildAudioMetricsArguments(
        inputPath: 'source.flac',
        metadataPath: '/tmp/metrics.txt',
        durationSeconds: 203.94,
      );

      expect(arguments, isNot(contains('-v')));
      expect(arguments, isNot(contains('-loglevel')));
      expect(arguments.join(' '), contains('ametadata=print'));
      expect(arguments.join(' '), contains("aselect='gte(t,201.940)'"));
    });

    test('rejects incomplete per-session metadata instead of using zero', () {
      const metadata = 'lavfi.astats.Overall.Peak_level=-0.8';

      expect(parseAudioAnalysisMetadata(metadata), isNull);
    });
  });

  group('audio spectrogram filter', () {
    test('keeps source rate and uses a full-range float pipeline', () {
      final filter = buildAudioSpectrogramFilter();

      expect(filter, contains('[0:a:0]aformat=sample_fmts=fltp'));
      expect(filter, contains('s=1600x800'));
      expect(filter, contains('scale=log'));
      expect(filter, contains('fscale=lin'));
      expect(filter, contains('win_func=hann'));
      expect(filter, contains('drange=120'));
      expect(filter, contains('limit=0'));
      expect(filter, isNot(contains('pan=')));
      expect(filter, isNot(contains('aresample')));
    });

    test('can render one source channel without app-specific branching', () {
      final filter = buildAudioSpectrogramFilter(channel: 1);

      expect(filter, contains('[0:a:0]pan=mono|c0=c1,'));
      expect(filter, contains('aformat=sample_fmts=fltp'));
    });

    test('processes the complete source without resampling or downmixing', () {
      final arguments = buildAudioSpectrogramArguments(
        inputPath: 'source.flac',
        outputPath: 'spectrum.rgba',
      );

      expect(arguments, containsAllInOrder(['-i', 'source.flac']));
      expect(arguments, containsAllInOrder(['-frames:v', '1']));
      expect(arguments, containsAllInOrder(['-pix_fmt', 'rgba']));
      expect(arguments, isNot(contains('-t')));
      expect(arguments, isNot(contains('-ss')));
      expect(arguments, isNot(contains('-ar')));
      expect(arguments, isNot(contains('-ac')));
      expect(arguments, isNot(contains('-loglevel')));
    });

    test('renders a monotonic cutoff plane beside the display image', () {
      final arguments = buildAudioSpectrogramArguments(
        inputPath: 'source.flac',
        outputPath: 'spectrum.rgba',
        cutoffOutputPath: 'cutoff.gray',
      );
      final filter = arguments[arguments.indexOf('-filter_complex') + 1];

      expect(filter, contains('asplit=2'));
      expect(filter, contains('color=intensity'));
      expect(filter, contains('s=400x800'));
      expect(filter, contains('color=green'));
      expect(filter, contains('format=gray[cutoff]'));
      expect(
        arguments,
        containsAllInOrder(['-map', '[cutoff]', '-frames:v', '1']),
      );
      expect(
        arguments,
        containsAllInOrder(['-pix_fmt', 'gray', 'cutoff.gray']),
      );
    });
  });

  group('effective spectral cutoff', () {
    const width = 200;
    const height = 800;
    const nyquist = 96000.0;

    test('ignores a narrow ultrasonic pilot above a 22 kHz music band', () {
      final intensity = _blankIntensity(width, height, value: 12);
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
        lowHz: 0,
        highHz: 22000,
        intensity: 220,
      );
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
        lowHz: 53880,
        highHz: 54120,
        intensity: 255,
      );

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
      );

      expect(cutoff, isNotNull);
      expect(cutoff!, inInclusiveRange(21000, 23500));
    });

    test('rejects a low noise floor above a 15.8 kHz bandwidth edge', () {
      const cdNyquist = 22050.0;
      final intensity = _blankIntensity(width, height, value: 42);
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: cdNyquist,
        lowHz: 0,
        highHz: 15800,
        intensity: 100,
      );
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: cdNyquist,
        lowHz: 15800,
        highHz: cdNyquist,
        intensity: 85,
        startColumn: 0,
        endColumn: 10,
      );

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: cdNyquist,
      );

      expect(cutoff, isNotNull);
      expect(cutoff!, inInclusiveRange(15300, 16300));
    });

    test('retains genuine broadband ultrasonic content', () {
      final intensity = _blankIntensity(width, height, value: 10);
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
        lowHz: 0,
        highHz: 48000,
        intensity: 180,
      );

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
      );

      expect(cutoff, isNotNull);
      expect(cutoff!, inInclusiveRange(47000, 49500));
    });

    test('reports Nyquist for full-bandwidth content', () {
      final intensity = _blankIntensity(width, height, value: 180);

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
      );

      expect(cutoff, nyquist);
    });

    test(
      'reports Nyquist for full-band music with a natural spectral tilt',
      () {
        const cdNyquist = 22050.0;
        final intensity = _blankIntensity(width, height);
        _paintNaturalSpectralTilt(
          intensity,
          width: width,
          height: height,
          lowFrequencyIntensity: 140,
          nyquistIntensity: 26,
        );

        final cutoff = estimateEffectiveSpectralCutoffHz(
          intensity: intensity,
          width: width,
          height: height,
          maxFrequencyHz: cdNyquist,
        );

        expect(cutoff, cdNyquist);
      },
    );

    test('does not report an isolated line as a broadband cutoff', () {
      final intensity = _blankIntensity(width, height);
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
        lowHz: 53880,
        highHz: 54120,
        intensity: 255,
      );

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
      );

      expect(cutoff, isNull);
    });

    test('rejects invalid or incomplete images', () {
      expect(
        estimateEffectiveSpectralCutoffHz(
          intensity: Uint8List(0),
          width: 1,
          height: 1,
          maxFrequencyHz: nyquist,
        ),
        isNull,
      );
    });
  });
}

Uint8List _blankIntensity(int width, int height, {int value = 0}) {
  final intensity = Uint8List(width * height);
  if (value > 0) intensity.fillRange(0, intensity.length, value);
  return intensity;
}

void _paintFrequencyBand(
  Uint8List values, {
  required int width,
  required int height,
  required double maxFrequencyHz,
  required double lowHz,
  required double highHz,
  required int intensity,
  int startColumn = 0,
  int? endColumn,
}) {
  final columnEnd = endColumn ?? width;
  for (var y = 0; y < height; y++) {
    final frequency = (height - y - 0.5) / height * maxFrequencyHz;
    if (frequency < lowHz || frequency > highHz) continue;
    for (var x = startColumn; x < columnEnd; x++) {
      values[y * width + x] = intensity;
    }
  }
}

void _paintNaturalSpectralTilt(
  Uint8List values, {
  required int width,
  required int height,
  required int lowFrequencyIntensity,
  required int nyquistIntensity,
}) {
  final span = lowFrequencyIntensity - nyquistIntensity;
  for (var y = 0; y < height; y++) {
    final normalizedFrequency = (height - y - 0.5) / height;
    final intensity =
        (lowFrequencyIntensity -
                span * normalizedFrequency * normalizedFrequency)
            .round()
            .clamp(0, 255);
    for (var x = 0; x < width; x++) {
      values[y * width + x] = intensity;
    }
  }
}

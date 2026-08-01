import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/widgets/audio_analysis_widget.dart';

void main() {
  group('spectral cutoff formatting', () {
    test('formats a detected cutoff frequency', () {
      expect(
        formatAudioAnalysisSpectralCutoff(
          22605,
          notDetectedLabel: 'Not detected',
        ),
        '22.6 kHz',
      );
    });

    test('keeps the metric visible when no cutoff is detected', () {
      expect(
        formatAudioAnalysisSpectralCutoff(
          null,
          notDetectedLabel: 'Not detected',
        ),
        'Not detected',
      );
    });
  });
}

part of 'audio_analysis_widget.dart';

// Spectrogram rendering: interactive view, axis painter, palette.

class _SpectrogramView extends StatelessWidget {
  final ui.Image image;
  final int sampleRate;
  final double maxFreq;
  final double duration;
  final int channels;
  final int selectedChannel;
  final bool channelLoading;
  final ValueChanged<int> onChannelChanged;

  const _SpectrogramView({
    required this.image,
    required this.sampleRate,
    required this.maxFreq,
    required this.duration,
    required this.channels,
    required this.selectedChannel,
    required this.channelLoading,
    required this.onChannelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const labelColor = Color(0xFFB5B5B5);

    return Card(
      color: Colors.black,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (channels > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text(context.l10n.audioAnalysisChannels),
                      selected: selectedChannel < 0,
                      onSelected: (_) => onChannelChanged(-1),
                      visualDensity: VisualDensity.compact,
                    ),
                    for (var channel = 0; channel < channels; channel++) ...[
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: Text('Ch ${channel + 1}'),
                        selected: selectedChannel == channel,
                        onSelected: (_) => onChannelChanged(channel),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (channelLoading)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 10, 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const leftGutter = 34.0;
                const bottomGutter = 18.0;
                final plotWidth = constraints.maxWidth - leftGutter;
                final plotHeight = plotWidth / 2.0;
                final totalHeight = plotHeight + bottomGutter;
                return SizedBox(
                  width: constraints.maxWidth,
                  height: totalHeight,
                  child: CustomPaint(
                    painter: _SpectrogramPainter(
                      image: image,
                      maxFreqHz: maxFreq,
                      durationSec: duration,
                      labelColor: labelColor,
                      gridColor: Colors.white.withValues(alpha: 0.10),
                    ),
                    size: Size(constraints.maxWidth, totalHeight),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 10, 8),
            child: Row(
              children: [
                const Text(
                  '-120 dBFS',
                  style: TextStyle(color: labelColor, fontSize: 10),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: LinearGradient(colors: _legendColors()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '0 dBFS',
                  style: TextStyle(color: labelColor, fontSize: 10),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${context.l10n.audioAnalysisSampleRate}: $sampleRate Hz',
                  style: const TextStyle(color: labelColor, fontSize: 11),
                ),
                const Spacer(),
                Text(
                  '${context.l10n.audioAnalysisNyquist}: ${(maxFreq / 1000).toStringAsFixed(1)} kHz',
                  style: const TextStyle(color: labelColor, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<Color> _legendColors() {
    return List.generate(20, (i) {
      final c = _spekColorRGB(i / 19.0);
      return Color.fromARGB(255, c[0], c[1], c[2]);
    });
  }
}

class _SpectrogramPainter extends CustomPainter {
  final ui.Image image;
  final double maxFreqHz;
  final double durationSec;
  final Color labelColor;
  final Color gridColor;

  static const double leftGutter = 34;
  static const double bottomGutter = 18;

  _SpectrogramPainter({
    required this.image,
    required this.maxFreqHz,
    required this.durationSec,
    required this.labelColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(
      leftGutter,
      0,
      size.width - leftGutter,
      size.height - bottomGutter,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      plot,
      Paint()..filterQuality = FilterQuality.medium,
    );

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // Frequency axis (Y): 0 Hz at the bottom, maxFreq at the top.
    final maxKHz = maxFreqHz / 1000.0;
    if (maxKHz > 0) {
      final stepKHz = _niceStepKHz(maxKHz);
      for (double fk = 0; fk <= maxKHz + 0.001; fk += stepKHz) {
        final ratio = (fk * 1000) / maxFreqHz;
        final y = plot.bottom - ratio * plot.height;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
        _drawText(
          canvas,
          fk == 0 ? '0' : '${fk.toStringAsFixed(0)}k',
          Offset(plot.left - 5, y),
          align: _TextAlignV.rightCenter,
        );
      }
    }

    if (durationSec > 0) {
      final stepSec = _niceStepSec(durationSec);
      for (double ts = 0; ts <= durationSec + 0.001; ts += stepSec) {
        final ratio = ts / durationSec;
        final x = plot.left + ratio * plot.width;
        canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
        _drawText(
          canvas,
          formatClock(ts),
          Offset(x, plot.bottom + 3),
          align: _TextAlignV.topCenter,
        );
      }
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset anchor, {
    required _TextAlignV align,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    double dx = anchor.dx;
    double dy = anchor.dy;
    switch (align) {
      case _TextAlignV.rightCenter:
        dx = anchor.dx - tp.width;
        dy = anchor.dy - tp.height / 2;
        break;
      case _TextAlignV.topCenter:
        dx = anchor.dx - tp.width / 2;
        dy = anchor.dy;
        break;
    }
    tp.paint(canvas, Offset(dx, dy));
  }

  static double _niceStepKHz(double maxKHz) {
    const candidates = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0];
    for (final c in candidates) {
      if (maxKHz / c <= 6) return c;
    }
    return 100.0;
  }

  static double _niceStepSec(double dur) {
    const candidates = [5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0, 600.0];
    for (final c in candidates) {
      if (dur / c <= 6) return c;
    }
    return 1200.0;
  }

  @override
  bool shouldRepaint(covariant _SpectrogramPainter old) =>
      old.image != image ||
      old.maxFreqHz != maxFreqHz ||
      old.durationSec != durationSec;
}

enum _TextAlignV { rightCenter, topCenter }

List<int> _spekColorRGB(double intensity) {
  int r, g, b;
  if (intensity < 0.08) {
    final t = intensity / 0.08;
    r = 0;
    g = 0;
    b = (t * 80).floor();
  } else if (intensity < 0.18) {
    final t = (intensity - 0.08) / 0.10;
    r = (t * 50).floor();
    g = (t * 30).floor();
    b = (80 + t * 175).floor();
  } else if (intensity < 0.28) {
    final t = (intensity - 0.18) / 0.10;
    r = (50 + t * 150).floor();
    g = (30 - t * 30).floor();
    b = (255 - t * 55).floor();
  } else if (intensity < 0.40) {
    final t = (intensity - 0.28) / 0.12;
    r = (200 + t * 55).floor();
    g = 0;
    b = (200 - t * 200).floor();
  } else if (intensity < 0.52) {
    final t = (intensity - 0.40) / 0.12;
    r = 255;
    g = (t * 100).floor();
    b = 0;
  } else if (intensity < 0.65) {
    final t = (intensity - 0.52) / 0.13;
    r = 255;
    g = (100 + t * 80).floor();
    b = 0;
  } else if (intensity < 0.78) {
    final t = (intensity - 0.65) / 0.13;
    r = 255;
    g = (180 + t * 55).floor();
    b = (t * 30).floor();
  } else if (intensity < 0.90) {
    final t = (intensity - 0.78) / 0.12;
    r = 255;
    g = (235 + t * 20).floor();
    b = (30 + t * 100).floor();
  } else {
    final t = (intensity - 0.90) / 0.10;
    r = 255;
    g = 255;
    b = (130 + t * 125).floor();
  }
  return [r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255)];
}

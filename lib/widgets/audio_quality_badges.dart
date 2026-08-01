import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';

class AudioQualityBadge extends StatelessWidget {
  final String label;
  final ColorScheme colorScheme;

  const AudioQualityBadge({
    super.key,
    required this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: context.tokens.borderRadiusBadge,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: context.tokens.badgeFontSize,
          fontWeight: FontWeight.w600,
          color: colorScheme.onPrimaryContainer,
          height: 1.3,
        ),
      ),
    );
  }
}

class ExplicitBadge extends StatelessWidget {
  final ColorScheme colorScheme;

  const ExplicitBadge({super.key, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Explicit',
      child: Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
          borderRadius: context.tokens.borderRadiusBadge,
        ),
        child: Text(
          'E',
          style: TextStyle(
            fontSize: context.tokens.badgeFontSize,
            fontWeight: FontWeight.w700,
            color: colorScheme.surface,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class DolbyAtmosBadge extends StatelessWidget {
  final ColorScheme colorScheme;

  const DolbyAtmosBadge({super.key, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.6),
        borderRadius: context.tokens.borderRadiusBadge,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(14, 10),
            painter: DolbyLogoPainter(color: colorScheme.onTertiaryContainer),
          ),
          const SizedBox(width: 3),
          Text(
            'Atmos',
            style: TextStyle(
              fontSize: context.tokens.badgeFontSize,
              fontWeight: FontWeight.w600,
              color: colorScheme.onTertiaryContainer,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class DolbyLogoPainter extends CustomPainter {
  final Color color;

  DolbyLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final h = size.height;
    final w = size.width;
    final cy = h / 2;

    final leftPath = Path()
      ..moveTo(w * 0.08, 0)
      ..lineTo(w * 0.08, h)
      ..lineTo(w * 0.20, h)
      ..arcToPoint(
        Offset(w * 0.20, 0),
        radius: Radius.elliptical(w * 0.25, cy),
        clockwise: false,
      )
      ..close();
    canvas.drawPath(leftPath, paint);

    final rightPath = Path()
      ..moveTo(w * 0.92, 0)
      ..lineTo(w * 0.92, h)
      ..lineTo(w * 0.80, h)
      ..arcToPoint(
        Offset(w * 0.80, 0),
        radius: Radius.elliptical(w * 0.25, cy),
        clockwise: true,
      )
      ..close();
    canvas.drawPath(rightPath, paint);
  }

  @override
  bool shouldRepaint(DolbyLogoPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// Convenience builder: returns a list of quality badge widgets for a track.
/// Pass the result into a Row using spread operator.
List<Widget> buildQualityBadges({
  required String? audioQuality,
  required String? audioModes,
  required ColorScheme colorScheme,
  bool explicit = false,
}) {
  final badges = <Widget>[];
  if (explicit) {
    badges.add(const SizedBox(width: 6));
    badges.add(ExplicitBadge(colorScheme: colorScheme));
  }
  if (audioQuality != null && audioQuality.isNotEmpty) {
    badges.add(const SizedBox(width: 6));
    badges.add(
      AudioQualityBadge(label: audioQuality, colorScheme: colorScheme),
    );
  }
  if (audioModes != null && audioModes.contains('DOLBY_ATMOS')) {
    badges.add(const SizedBox(width: 4));
    badges.add(DolbyAtmosBadge(colorScheme: colorScheme));
  }
  return badges;
}

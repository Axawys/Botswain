import 'dart:math';

import 'package:flutter/material.dart';

/// Полукруглый индикатор загруженности (Circular half progress bar).
///
/// Рисует верхнюю полуокружность: серая подложка + дуга значения. В центре —
/// крупное значение, снизу — подпись.
class HalfCircleGauge extends StatelessWidget {
  const HalfCircleGauge({
    super.key,
    required this.value,
    required this.centerText,
    required this.caption,
    this.color,
  });

  /// Доля заполнения 0..1.
  final double value;
  final String centerText;
  final String caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 132,
          height: 74,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              CustomPaint(
                size: const Size(132, 74),
                painter: _GaugePainter(
                  value: value.clamp(0, 1),
                  color: fg,
                  background: scheme.surfaceContainerHighest,
                  stroke: 11,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  centerText,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(caption, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.color,
    required this.background,
    required this.stroke,
  });

  final double value;
  final Color color;
  final Color background;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - stroke / 2;
    // Центр внизу — тогда верхняя полуокружность занимает всю высоту виджета.
    final center = Offset(size.width / 2, size.height - stroke / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final base = Paint()
      ..color = background
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // Верхняя полуокружность: от 180° по часовой на 180°.
    canvas.drawArc(rect, pi, pi, false, base);
    canvas.drawArc(rect, pi, pi * value, false, arc);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color || old.background != background;
}

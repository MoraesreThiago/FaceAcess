import 'package:flutter/material.dart';

class ScanFramePainter extends CustomPainter {
  ScanFramePainter({
    required this.pulseValue,
    required this.active,
  });

  final double pulseValue;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final frameWidth = size.width * 0.45;
    final frameHeight = size.height * 0.65;
    const cornerLength = 30.0;

    final color = Color.lerp(Colors.white54, Colors.cyanAccent, pulseValue)!;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final left = centerX - frameWidth / 2;
    final top = centerY - frameHeight / 2;
    final right = centerX + frameWidth / 2;
    final bottom = centerY + frameHeight / 2;

    canvas.drawLine(Offset(left, top + cornerLength), Offset(left, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left + cornerLength, top), paint);
    canvas.drawLine(
        Offset(right - cornerLength, top), Offset(right, top), paint);
    canvas.drawLine(
        Offset(right, top), Offset(right, top + cornerLength), paint);
    canvas.drawLine(
      Offset(left, bottom - cornerLength),
      Offset(left, bottom),
      paint,
    );
    canvas.drawLine(
      Offset(left, bottom),
      Offset(left + cornerLength, bottom),
      paint,
    );
    canvas.drawLine(
      Offset(right - cornerLength, bottom),
      Offset(right, bottom),
      paint,
    );
    canvas.drawLine(
      Offset(right, bottom),
      Offset(right, bottom - cornerLength),
      paint,
    );

    final scanY = top + (bottom - top) * pulseValue;
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Colors.cyanAccent.withValues(alpha: 0.6),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(left, scanY - 1, frameWidth, 2))
      ..strokeWidth = 2;
    canvas.drawLine(Offset(left, scanY), Offset(right, scanY), scanPaint);
  }

  @override
  bool shouldRepaint(ScanFramePainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue || oldDelegate.active != active;
  }
}

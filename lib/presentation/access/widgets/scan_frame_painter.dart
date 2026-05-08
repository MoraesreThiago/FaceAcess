import 'dart:math';

import 'package:flutter/material.dart';

/// Estado visual do overlay de detecção.
enum ScanState {
  /// Aguardando rosto — oval branco/acinzentado com pulso suave.
  idle,

  /// Rosto detectado, analisando — oval cyan com glow e linha de scan.
  faceDetected,
}

/// Pintor do enquadramento oval de reconhecimento facial.
///
/// Desenha:
///   1. Scrim escuro semi-transparente cobrindo toda a tela, com um recorte
///      oval no centro para destacar o rosto.
///   2. Borda oval colorida conforme [scanState].
///   3. Glow suave (blur) quando [scanState] == [ScanState.faceDetected].
///   4. Linha de scan animada dentro do oval.
class ScanFramePainter extends CustomPainter {
  const ScanFramePainter({
    required this.pulseValue,
    required this.scanState,
  });

  final double pulseValue;
  final ScanState scanState;

  // Proporções do oval em relação ao tamanho da tela.
  static const double _ovalCenterYFraction = 0.44;
  static const double _ovalWidthFraction  = 0.60;
  static const double _ovalHeightFraction = 0.58;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * _ovalCenterYFraction;
    final a  = size.width  * _ovalWidthFraction  / 2; // semi-eixo horizontal
    final b  = size.height * _ovalHeightFraction / 2; // semi-eixo vertical

    final ovalRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width:  a * 2,
      height: b * 2,
    );

    // ── 1. Scrim com recorte oval ─────────────────────────────────────
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );
    // BlendMode.clear "apaga" a área do oval, criando o recorte transparente.
    canvas.drawOval(ovalRect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    // ── 2. Glow externo (só quando rosto detectado) ───────────────────
    if (scanState == ScanState.faceDetected) {
      final intensity = 0.45 + 0.55 * pulseValue;
      canvas.drawOval(
        ovalRect,
        Paint()
          ..color = Colors.cyanAccent.withValues(alpha: 0.22 * intensity)
          ..strokeWidth = 20
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawOval(
        ovalRect,
        Paint()
          ..color = Colors.cyanAccent.withValues(alpha: 0.10 * intensity)
          ..strokeWidth = 36
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }

    // ── 3. Borda oval principal ───────────────────────────────────────
    final borderColor = scanState == ScanState.idle
        ? Color.lerp(
            Colors.white.withValues(alpha: 0.30),
            Colors.white.withValues(alpha: 0.55),
            pulseValue,
          )!
        : Color.lerp(
            Colors.cyanAccent.withValues(alpha: 0.75),
            Colors.cyanAccent,
            pulseValue,
          )!;

    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = borderColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    // Arcos reforçados nos 4 extremos do oval (sensação de "mira").
    _drawCornerArcs(canvas, ovalRect, borderColor);

    // ── 4. Linha de scan animada dentro do oval ───────────────────────
    final scanY = ovalRect.top + ovalRect.height * pulseValue;
    final dy    = scanY - cy;
    if (dy.abs() < b) {
      final halfW = a * sqrt(1.0 - (dy / b) * (dy / b));
      final scanAlpha =
          scanState == ScanState.faceDetected ? 0.65 : 0.20;
      final scanColor = scanState == ScanState.faceDetected
          ? Colors.cyanAccent.withValues(alpha: scanAlpha)
          : Colors.white.withValues(alpha: scanAlpha);

      canvas.drawLine(
        Offset(cx - halfW, scanY),
        Offset(cx + halfW, scanY),
        Paint()
          ..shader = LinearGradient(colors: [
            Colors.transparent,
            scanColor,
            Colors.transparent,
          ]).createShader(
            Rect.fromLTWH(cx - halfW, scanY - 1, halfW * 2, 2),
          )
          ..strokeWidth = 1.5,
      );
    }
  }

  /// Arcos curtos nos 4 extremos do oval (topo, baixo, esquerda, direita).
  void _drawCornerArcs(Canvas canvas, Rect oval, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: (color.a * 1.4).clamp(0.0, 1.0))
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const sweep = 0.38; // ~22 graus em radianos

    canvas.drawArc(oval, -pi / 2 - sweep / 2, sweep, false, paint); // topo
    canvas.drawArc(oval,  pi / 2 - sweep / 2, sweep, false, paint); // baixo
    canvas.drawArc(oval,  pi     - sweep / 2, sweep, false, paint); // esquerda
    canvas.drawArc(oval, -sweep / 2,           sweep, false, paint); // direita
  }

  @override
  bool shouldRepaint(ScanFramePainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
        oldDelegate.scanState != scanState;
  }
}

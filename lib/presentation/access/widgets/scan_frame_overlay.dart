import 'package:flutter/material.dart';

import 'scan_frame_painter.dart';

/// Overlay de enquadramento facial para a tela de acesso.
///
/// Quando [active] é false (resultado exibido), some completamente.
/// Quando [faceDetected] muda, o oval e o texto de status reagem
/// em tempo real sem necessidade de interação do usuário.
class ScanFrameOverlay extends StatefulWidget {
  const ScanFrameOverlay({
    super.key,
    required this.active,
    required this.faceDetected,
  });

  /// false quando o [AccessFeedbackOverlay] está visível (resultado na tela).
  final bool active;

  /// true enquanto o ML Kit detecta pelo menos um rosto no frame atual.
  final bool faceDetected;

  @override
  State<ScanFrameOverlay> createState() => _ScanFrameOverlayState();
}

class _ScanFrameOverlayState extends State<ScanFrameOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.expand();

    final scanState = widget.faceDetected
        ? ScanState.faceDetected
        : ScanState.idle;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Oval + scrim + linha de scan.
            CustomPaint(
              painter: ScanFramePainter(
                pulseValue: _pulseController.value,
                scanState: scanState,
              ),
            ),

            // Texto de status abaixo do oval.
            _StatusLabel(faceDetected: widget.faceDetected),
          ],
        );
      },
    );
  }
}

/// Label de instrução/estado posicionada logo abaixo do oval de rosto.
class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.faceDetected});

  final bool faceDetected;

  // Deve bater com ScanFramePainter._ovalCenterYFraction +
  // ScanFramePainter._ovalHeightFraction / 2.
  static const double _ovalBottomFraction = 0.44 + 0.58 / 2; // ≈ 0.73

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final topOffset = screenH * (_ovalBottomFraction + 0.04);

    return Positioned(
      top: topOffset,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.3),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            faceDetected ? 'Identificando...' : 'Posicione seu rosto',
            key: ValueKey(faceDetected),
            style: TextStyle(
              color: faceDetected
                  ? Colors.cyanAccent.withValues(alpha: 0.90)
                  : Colors.white.withValues(alpha: 0.45),
              fontSize: 14,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w400,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
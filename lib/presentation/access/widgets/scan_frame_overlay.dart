import 'package:flutter/material.dart';

import 'scan_frame_painter.dart';

class ScanFrameOverlay extends StatefulWidget {
  const ScanFrameOverlay({
    super.key,
    required this.active,
  });

  final bool active;

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
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        return CustomPaint(
          painter: ScanFramePainter(
            pulseValue: _pulseController.value,
            active: widget.active,
          ),
        );
      },
    );
  }
}

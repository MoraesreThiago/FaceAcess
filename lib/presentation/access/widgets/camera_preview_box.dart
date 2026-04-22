import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraPreviewBox extends StatelessWidget {
  const CameraPreviewBox({
    super.key,
    required this.controller,
  });

  final CameraController? controller;

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Iniciando câmera…',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return CameraPreview(controller!);
  }
}

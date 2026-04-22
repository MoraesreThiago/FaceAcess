import 'dart:typed_data';

import 'package:camera/camera.dart';

class CameraFramePayload {
  const CameraFramePayload({
    required this.width,
    required this.height,
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.yBytesPerRow,
    required this.uBytesPerRow,
    required this.vBytesPerRow,
    required this.uBytesPerPixel,
    required this.vBytesPerPixel,
  });

  factory CameraFramePayload.fromCameraImage(CameraImage image) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    return CameraFramePayload(
      width: image.width,
      height: image.height,
      yBytes: Uint8List.fromList(yPlane.bytes),
      uBytes: Uint8List.fromList(uPlane.bytes),
      vBytes: Uint8List.fromList(vPlane.bytes),
      yBytesPerRow: yPlane.bytesPerRow,
      uBytesPerRow: uPlane.bytesPerRow,
      vBytesPerRow: vPlane.bytesPerRow,
      uBytesPerPixel: uPlane.bytesPerPixel ?? 1,
      vBytesPerPixel: vPlane.bytesPerPixel ?? 1,
    );
  }

  final int width;
  final int height;
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int yBytesPerRow;
  final int uBytesPerRow;
  final int vBytesPerRow;
  final int uBytesPerPixel;
  final int vBytesPerPixel;

  Map<String, Object> toMessage() {
    return <String, Object>{
      'width': width,
      'height': height,
      'yBytes': yBytes,
      'uBytes': uBytes,
      'vBytes': vBytes,
      'yBytesPerRow': yBytesPerRow,
      'uBytesPerRow': uBytesPerRow,
      'vBytesPerRow': vBytesPerRow,
      'uBytesPerPixel': uBytesPerPixel,
      'vBytesPerPixel': vBytesPerPixel,
    };
  }

  static CameraFramePayload fromMessage(Map<Object?, Object?> message) {
    return CameraFramePayload(
      width: message['width']! as int,
      height: message['height']! as int,
      yBytes: message['yBytes']! as Uint8List,
      uBytes: message['uBytes']! as Uint8List,
      vBytes: message['vBytes']! as Uint8List,
      yBytesPerRow: message['yBytesPerRow']! as int,
      uBytesPerRow: message['uBytesPerRow']! as int,
      vBytesPerRow: message['vBytesPerRow']! as int,
      uBytesPerPixel: message['uBytesPerPixel']! as int,
      vBytesPerPixel: message['vBytesPerPixel']! as int,
    );
  }
}

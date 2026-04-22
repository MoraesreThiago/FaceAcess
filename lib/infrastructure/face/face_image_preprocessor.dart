import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'camera_frame_payload.dart';

class FaceCropRect {
  const FaceCropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  Map<String, Object> toMessage() {
    return <String, Object>{
      'left': left,
      'top': top,
      'width': width,
      'height': height,
    };
  }

  static FaceCropRect fromMessage(Map<Object?, Object?> message) {
    return FaceCropRect(
      left: message['left']! as double,
      top: message['top']! as double,
      width: message['width']! as double,
      height: message['height']! as double,
    );
  }
}

enum FaceCropStrategy {
  rotateThenCrop,
  cropThenRotate,
}

class FacePreprocessingRequest {
  const FacePreprocessingRequest({
    required this.frame,
    required this.cropRect,
    required this.rotationDegrees,
    required this.cropStrategy,
    required this.targetSize,
  });

  final CameraFramePayload frame;
  final FaceCropRect cropRect;
  final int rotationDegrees;
  final FaceCropStrategy cropStrategy;
  final int targetSize;

  Map<String, Object> toMessage() {
    return <String, Object>{
      'frame': frame.toMessage(),
      'cropRect': cropRect.toMessage(),
      'rotationDegrees': rotationDegrees,
      'cropStrategy': cropStrategy.name,
      'targetSize': targetSize,
    };
  }

  static FacePreprocessingRequest fromMessage(Map<Object?, Object?> message) {
    return FacePreprocessingRequest(
      frame: CameraFramePayload.fromMessage(
        message['frame']! as Map<Object?, Object?>,
      ),
      cropRect: FaceCropRect.fromMessage(
        message['cropRect']! as Map<Object?, Object?>,
      ),
      rotationDegrees: message['rotationDegrees']! as int,
      cropStrategy: FaceCropStrategy.values.byName(
        message['cropStrategy']! as String,
      ),
      targetSize: message['targetSize']! as int,
    );
  }
}

Future<Float32List?> preprocessFaceTensorOnIsolate(
  FacePreprocessingRequest request,
) {
  return compute(_preprocessFaceTensorMessage, request.toMessage());
}

Float32List? _preprocessFaceTensorMessage(Map<Object?, Object?> message) {
  final request = FacePreprocessingRequest.fromMessage(message);
  return preprocessFaceTensorSync(request);
}

Float32List? preprocessFaceTensorSync(FacePreprocessingRequest request) {
  final rawImage = _yuv420ToImage(request.frame);
  final prepared = _prepareFaceImage(request, rawImage);
  if (prepared == null) return null;

  final resized = img.copyResize(
    prepared,
    width: request.targetSize,
    height: request.targetSize,
  );

  final inputData = Float32List(request.targetSize * request.targetSize * 3);
  int idx = 0;
  for (int y = 0; y < request.targetSize; y++) {
    for (int x = 0; x < request.targetSize; x++) {
      final pixel = resized.getPixel(x, y);
      inputData[idx++] = (pixel.r.toDouble() - 127.5) / 128.0;
      inputData[idx++] = (pixel.g.toDouble() - 127.5) / 128.0;
      inputData[idx++] = (pixel.b.toDouble() - 127.5) / 128.0;
    }
  }

  return inputData;
}

Uint8List buildNv21Bytes(CameraFramePayload frame, {Uint8List? buffer}) {
  final expectedLength =
      frame.width * frame.height + frame.width * frame.height ~/ 2;
  final nv21 = buffer != null && buffer.length == expectedLength
      ? buffer
      : Uint8List(expectedLength);

  for (int row = 0; row < frame.height; row++) {
    nv21.setRange(
      row * frame.width,
      row * frame.width + frame.width,
      frame.yBytes,
      row * frame.yBytesPerRow,
    );
  }

  int uvOffset = frame.width * frame.height;
  for (int row = 0; row < frame.height ~/ 2; row++) {
    for (int col = 0; col < frame.width ~/ 2; col++) {
      final uIndex = row * frame.uBytesPerRow + col * frame.uBytesPerPixel;
      final vIndex = row * frame.vBytesPerRow + col * frame.vBytesPerPixel;
      nv21[uvOffset++] = frame.vBytes[vIndex];
      nv21[uvOffset++] = frame.uBytes[uIndex];
    }
  }

  return nv21;
}

img.Image? _prepareFaceImage(
  FacePreprocessingRequest request,
  img.Image rawImage,
) {
  switch (request.cropStrategy) {
    case FaceCropStrategy.rotateThenCrop:
      final oriented = _rotateImage(rawImage, request.rotationDegrees);
      return _cropFace(oriented, request.cropRect);
    case FaceCropStrategy.cropThenRotate:
      final cropped = _cropFace(rawImage, request.cropRect);
      if (cropped == null) return null;
      return _rotateImage(cropped, request.rotationDegrees);
  }
}

img.Image _rotateImage(img.Image source, int degrees) {
  if (degrees == 0) return source;
  return img.copyRotate(source, angle: degrees);
}

img.Image? _cropFace(img.Image source, FaceCropRect rect) {
  final x = rect.left.toInt().clamp(0, source.width - 1);
  final y = rect.top.toInt().clamp(0, source.height - 1);
  final width = rect.width.toInt().clamp(1, source.width - x);
  final height = rect.height.toInt().clamp(1, source.height - y);
  if (width <= 0 || height <= 0) return null;

  return img.copyCrop(source, x: x, y: y, width: width, height: height);
}

img.Image _yuv420ToImage(CameraFramePayload frame) {
  final output = img.Image(width: frame.width, height: frame.height);

  for (int y = 0; y < frame.height; y++) {
    for (int x = 0; x < frame.width; x++) {
      final yVal = frame.yBytes[y * frame.yBytesPerRow + x];
      final uIndex =
          (y ~/ 2) * frame.uBytesPerRow + (x ~/ 2) * frame.uBytesPerPixel;
      final vIndex =
          (y ~/ 2) * frame.vBytesPerRow + (x ~/ 2) * frame.vBytesPerPixel;
      final uVal = frame.uBytes[uIndex] - 128;
      final vVal = frame.vBytes[vIndex] - 128;

      final r = (yVal + 1.402 * vVal).round().clamp(0, 255);
      final g =
          (yVal - 0.344136 * uVal - 0.714136 * vVal).round().clamp(0, 255);
      final b = (yVal + 1.772 * uVal).round().clamp(0, 255);

      output.setPixelRgb(x, y, r, g, b);
    }
  }

  return output;
}

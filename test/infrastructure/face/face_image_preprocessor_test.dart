import 'dart:typed_data';

import 'package:faceaccess/infrastructure/face/camera_frame_payload.dart';
import 'package:faceaccess/infrastructure/face/face_image_preprocessor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildNv21Bytes', () {
    test('interleaves Y and UV planes into nv21 layout and reuses buffer', () {
      final frame = _testFrame();
      final reusable = Uint8List(24);

      final nv21 = buildNv21Bytes(frame, buffer: reusable);

      expect(identical(nv21, reusable), isTrue);
      expect(nv21.length, 24);
      expect(nv21.sublist(0, 16), equals(frame.yBytes));
      expect(nv21.sublist(16), equals(List<int>.filled(8, 128)));
    });
  });

  group('preprocessFaceTensorSync', () {
    test('returns normalized tensor for rotate-then-crop flow', () {
      final tensor = preprocessFaceTensorSync(
        FacePreprocessingRequest(
          frame: _testFrame(),
          cropRect: const FaceCropRect(
            left: 0,
            top: 0,
            width: 4,
            height: 4,
          ),
          rotationDegrees: 0,
          cropStrategy: FaceCropStrategy.rotateThenCrop,
          targetSize: 2,
        ),
      );

      expect(tensor, isNotNull);
      expect(tensor!.length, 12);
      expect(tensor.every((value) => value >= -1.0 && value <= 1.0), isTrue);
      expect(
        tensor[0],
        lessThan(tensor[9]),
        reason: 'o gradiente do frame deve sobreviver ao resize/crop',
      );
    });

    test('supports crop-then-rotate flow kept for the legacy stream path', () {
      final tensor = preprocessFaceTensorSync(
        FacePreprocessingRequest(
          frame: _testFrame(),
          cropRect: const FaceCropRect(
            left: 0,
            top: 0,
            width: 2,
            height: 2,
          ),
          rotationDegrees: 90,
          cropStrategy: FaceCropStrategy.cropThenRotate,
          targetSize: 2,
        ),
      );

      expect(tensor, isNotNull);
      expect(tensor!.length, 12);
      expect(tensor[0], isNot(equals(tensor[9])));
    });
  });
}

CameraFramePayload _testFrame() {
  return CameraFramePayload(
    width: 4,
    height: 4,
    yBytes: Uint8List.fromList(<int>[
      0,
      16,
      32,
      48,
      64,
      80,
      96,
      112,
      128,
      144,
      160,
      176,
      192,
      208,
      224,
      240,
    ]),
    uBytes: Uint8List.fromList(<int>[128, 128, 128, 128]),
    vBytes: Uint8List.fromList(<int>[128, 128, 128, 128]),
    yBytesPerRow: 4,
    uBytesPerRow: 2,
    vBytesPerRow: 2,
    uBytesPerPixel: 1,
    vBytesPerPixel: 1,
  );
}

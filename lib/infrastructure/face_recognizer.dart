import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceRecognizer {
  Interpreter? _interpreter;
  int _embeddingSize = 512;

  static const int _inputSize = 160;

  Future<void> initialize() async {
    final options = InterpreterOptions()..threads = 2;
    _interpreter = await Interpreter.fromAsset(
      'assets/models/facenet.tflite',
      options: options,
    );
    _interpreter!.allocateTensors();
    // Read actual embedding size from the model's output tensor shape [1, N]
    final outShape = _interpreter!.getOutputTensor(0).shape;
    if (outShape.length >= 2) _embeddingSize = outShape[1];
  }

  /// Returns a L2-normalised embedding, or null on failure.
  Future<List<double>?> getEmbedding(img.Image faceImage) async {
    if (_interpreter == null) return null;

    final resized =
        img.copyResize(faceImage, width: _inputSize, height: _inputSize);

    // Build flat Float32List input [1 * 160 * 160 * 3], normalised to [-1, 1]
    final inputData = Float32List(1 * _inputSize * _inputSize * 3);
    int idx = 0;
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        inputData[idx++] = (pixel.r.toDouble() - 127.5) / 128.0;
        inputData[idx++] = (pixel.g.toDouble() - 127.5) / 128.0;
        inputData[idx++] = (pixel.b.toDouble() - 127.5) / 128.0;
      }
    }

    final outputData = Float32List(_embeddingSize);

    _interpreter!.getInputTensor(0).setTo(inputData);
    _interpreter!.invoke();
    final raw = _interpreter!.getOutputTensor(0).data.buffer.asFloat32List();
    outputData.setAll(0, raw.take(_embeddingSize));

    return _l2Normalize(outputData.map((v) => v.toDouble()).toList());
  }

  List<double> _l2Normalize(List<double> v) {
    double norm = 0;
    for (final x in v) norm += x * x;
    norm = sqrt(norm);
    if (norm == 0) return v;
    return v.map((x) => x / norm).toList();
  }

  void dispose() => _interpreter?.close();
}

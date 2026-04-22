import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../application/use_cases/evaluate_access_use_case.dart';
import '../../domain/entities/access_decision.dart';
import '../../domain/entities/user_role.dart';
import '../../infrastructure/access_log_service.dart';
import '../../infrastructure/face/camera_frame_payload.dart';
import '../../infrastructure/face/face_image_preprocessor.dart';
import '../../infrastructure/face_recognizer.dart';
import '../../infrastructure/mqtt_door_controller.dart';
import '../../infrastructure/tts_service.dart';

@immutable
class AccessControllerConfig {
  const AccessControllerConfig({
    required this.cameras,
    required this.faceRecognizer,
    required this.evaluateAccess,
    required this.doorController,
    required this.ttsService,
    required this.accessLogService,
  });

  final List<CameraDescription> cameras;
  final FaceRecognizer faceRecognizer;
  final EvaluateAccessUseCase evaluateAccess;
  final MqttDoorController doorController;
  final TtsService ttsService;
  final AccessLogService accessLogService;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is AccessControllerConfig &&
            listEquals(other.cameras, cameras) &&
            other.faceRecognizer == faceRecognizer &&
            other.evaluateAccess == evaluateAccess &&
            other.doorController == doorController &&
            other.ttsService == ttsService &&
            other.accessLogService == accessLogService);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(cameras),
        faceRecognizer,
        evaluateAccess,
        doorController,
        ttsService,
        accessLogService,
      );
}

@immutable
class AccessViewState {
  const AccessViewState({
    this.cameraController,
    this.isRecognizing = false,
    this.lastDecision,
    this.overlayVisible = false,
  });

  static const Object _sentinel = Object();

  final CameraController? cameraController;
  final bool isRecognizing;
  final AccessDecision? lastDecision;
  final bool overlayVisible;

  bool get isCameraReady => cameraController?.value.isInitialized == true;

  AccessViewState copyWith({
    Object? cameraController = _sentinel,
    bool? isRecognizing,
    Object? lastDecision = _sentinel,
    bool? overlayVisible,
  }) {
    return AccessViewState(
      cameraController: cameraController == _sentinel
          ? this.cameraController
          : cameraController as CameraController?,
      isRecognizing: isRecognizing ?? this.isRecognizing,
      lastDecision: lastDecision == _sentinel
          ? this.lastDecision
          : lastDecision as AccessDecision?,
      overlayVisible: overlayVisible ?? this.overlayVisible,
    );
  }
}

final accessControllerProvider = ChangeNotifierProvider.autoDispose
    .family<AccessController, AccessControllerConfig>((ref, config) {
  final controller = AccessController(
    cameras: config.cameras,
    faceRecognizer: config.faceRecognizer,
    evaluateAccess: config.evaluateAccess,
    doorController: config.doorController,
    ttsService: config.ttsService,
    accessLogService: config.accessLogService,
  );
  unawaited(controller.initialize());
  return controller;
});

class AccessController extends ChangeNotifier {
  AccessController({
    required this.cameras,
    required this.faceRecognizer,
    required this.evaluateAccess,
    required this.doorController,
    required this.ttsService,
    required this.accessLogService,
    DateTime Function()? clock,
  }) : _clock = clock ?? _defaultClock;

  static DateTime _defaultClock() => DateTime.now();

  final List<CameraDescription> cameras;
  final FaceRecognizer faceRecognizer;
  final EvaluateAccessUseCase evaluateAccess;
  final MqttDoorController doorController;
  final TtsService ttsService;
  final AccessLogService accessLogService;
  final DateTime Function() _clock;

  static const int _windowSize = 3;
  static const Duration _overlayFadeDuration = Duration(milliseconds: 400);

  AccessViewState _state = const AccessViewState();
  AccessViewState get state => _state;

  CameraImage? _latestFrame;
  FaceDetector? _faceDetector;
  bool _initialized = false;
  bool _disposed = false;

  final List<String?> _recentMatches = <String?>[];
  int _graceCyclesWithoutFace = 0;
  DateTime? _lastExitTime;
  final Map<String, DateTime> _doorCooldown = <String, DateTime>{};
  DateTime _lastOverlayAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastOverlayKey;
  Timer? _overlayHideTimer;
  Timer? _overlayClearTimer;
  Uint8List? _nv21Buffer;

  static String greetingFor(DateTime time) {
    final hour = time.hour;
    if (hour >= 6 && hour < 12) return 'Bom dia';
    if (hour >= 12 && hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  String get currentGreeting => greetingFor(_clock());

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    unawaited(doorController.connect());
    await _initCamera();
  }

  Future<void> pauseCamera() async {
    try {
      if (_state.cameraController?.value.isStreamingImages == true) {
        await _state.cameraController!.stopImageStream();
      }
    } catch (_) {}
  }

  Future<void> resumeCamera({bool fullReinit = false}) async {
    final currentController = _state.cameraController;

    if (!fullReinit) {
      try {
        if (currentController != null &&
            currentController.value.isInitialized &&
            !currentController.value.isStreamingImages) {
          await currentController.startImageStream(_onCameraFrame);
          _updateState(_state.copyWith(cameraController: currentController));
          return;
        }
      } catch (_) {}
    }

    if (currentController != null) {
      await _disposeCameraController(currentController);
    }
    _updateState(_state.copyWith(cameraController: null));
    await Future.delayed(const Duration(milliseconds: 400));
    await _initCamera();
  }

  Future<String?> recognizeNow() async {
    final frame = _latestFrame;
    if (frame == null || _state.isRecognizing) return null;

    _updateState(_state.copyWith(isRecognizing: true));
    try {
      final decision = await _evaluateManualFrame(frame);

      _lastOverlayKey = null;
      _displayOverlay(decision, const Duration(seconds: 5));

      if (decision.isAuthorized && decision.personName != null) {
        final now = _clock();
        final personName = decision.personName!;
        final lastDoor = _doorCooldown[personName];
        if (lastDoor == null || now.difference(lastDoor).inSeconds >= 5) {
          _doorCooldown[personName] = now;
          unawaited(doorController.openDoor());
        }
        unawaited(ttsService.announceGreeting(currentGreeting, personName));
      }

      return null;
    } catch (e) {
      return 'Erro: $e';
    } finally {
      if (!_disposed) {
        _updateState(_state.copyWith(isRecognizing: false));
      }
    }
  }

  Future<void> processFrame(CameraImage image) async {
    final controller = _state.cameraController;
    if (controller == null) return;

    final framePayload = CameraFramePayload.fromCameraImage(image);
    final inputImage = _toInputImage(framePayload, controller);
    final faces = await _detector.processImage(inputImage);

    if (faces.isEmpty) {
      handleNoFaceDetected();
      return;
    }
    _graceCyclesWithoutFace = 0;

    if (_lastExitTime != null) {
      if (_clock().difference(_lastExitTime!).inSeconds < 3) return;
      _lastExitTime = null;
    }

    final face = faces.reduce(
      (a, b) => a.boundingBox.width > b.boundingBox.width ? a : b,
    );

    final embedding = await _extractEmbedding(
      frame: framePayload,
      face: face,
      rotationDegrees: controller.description.sensorOrientation,
      cropStrategy: FaceCropStrategy.cropThenRotate,
    );
    if (embedding == null) return;

    final decision = await evaluateAccess.execute(embedding);
    registerDecision(decision);
  }

  @visibleForTesting
  void registerDecision(AccessDecision decision) {
    final key = decision.isAuthorized ? decision.personName : null;
    _recentMatches.add(key);
    if (_recentMatches.length > _windowSize) {
      _recentMatches.removeAt(0);
    }
    if (_recentMatches.length < 2) return;

    final counts = <String?, int>{};
    for (final match in _recentMatches) {
      counts[match] = (counts[match] ?? 0) + 1;
    }
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);

    if (best.value < 2) return;

    if (best.key != null) {
      final matched = decision.personName == best.key
          ? decision
          : AccessDecision.authorized(
              personName: best.key!,
              role: decision.role ?? UserRole.operador,
              confidence: decision.confidence ?? 0.5,
            );
      _showAuthorized(matched);
      return;
    }

    _showDenied();
  }

  @visibleForTesting
  void handleNoFaceDetected() {
    _graceCyclesWithoutFace++;
    if (_graceCyclesWithoutFace < 3) return;

    if (_recentMatches.isNotEmpty) {
      _lastExitTime = _clock();
    }
    _recentMatches.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _overlayHideTimer?.cancel();
    _overlayClearTimer?.cancel();

    final controller = _state.cameraController;
    if (controller != null) {
      unawaited(_disposeCameraController(controller));
    }
    _faceDetector?.close();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await controller.initialize();
    if (_disposed) {
      await _disposeCameraController(controller);
      return;
    }

    await controller.startImageStream(_onCameraFrame);
    _updateState(_state.copyWith(cameraController: controller));
  }

  Future<AccessDecision> _evaluateManualFrame(CameraImage frame) async {
    final controller = _state.cameraController;
    if (controller == null) return AccessDecision.denied();

    final framePayload = CameraFramePayload.fromCameraImage(frame);
    final inputImage = _toInputImage(framePayload, controller);
    final faces = await _detector.processImage(inputImage);

    if (faces.isEmpty) {
      return AccessDecision.denied();
    }

    final face = faces.reduce(
      (a, b) => a.boundingBox.width > b.boundingBox.width ? a : b,
    );

    final embedding = await _extractEmbedding(
      frame: framePayload,
      face: face,
      rotationDegrees: _computeRotationDeg(controller),
      cropStrategy: FaceCropStrategy.rotateThenCrop,
    );
    if (embedding == null) {
      return AccessDecision.denied();
    }

    return evaluateAccess.execute(embedding);
  }

  void _showAuthorized(AccessDecision decision) {
    final personName = decision.personName!;
    final now = _clock();

    if (_lastOverlayKey == 'auth:$personName' &&
        now.difference(_lastOverlayAt).inSeconds < 3) {
      return;
    }
    _lastOverlayKey = 'auth:$personName';
    _lastOverlayAt = now;

    final lastDoor = _doorCooldown[personName];
    if (lastDoor == null || now.difference(lastDoor).inSeconds >= 5) {
      _doorCooldown[personName] = now;
      unawaited(doorController.openDoor());
    }

    unawaited(ttsService.announceAuthorized(personName));
    unawaited(
      accessLogService.log(
        personName: personName,
        authorized: true,
        role: decision.role?.key,
      ),
    );
    _displayOverlay(decision, const Duration(seconds: 4));
  }

  void _showDenied() {
    final now = _clock();
    if (_lastOverlayKey == 'denied' &&
        now.difference(_lastOverlayAt).inSeconds < 4) {
      return;
    }
    _lastOverlayKey = 'denied';
    _lastOverlayAt = now;

    unawaited(ttsService.announceDenied());
    unawaited(
      accessLogService.log(
        personName: 'Desconhecido',
        authorized: false,
      ),
    );
    _displayOverlay(AccessDecision.denied(), const Duration(seconds: 3));
  }

  void _displayOverlay(AccessDecision decision, Duration visibleFor) {
    _overlayHideTimer?.cancel();
    _overlayClearTimer?.cancel();

    _updateState(
      _state.copyWith(
        lastDecision: decision,
        overlayVisible: true,
      ),
    );

    _overlayHideTimer = Timer(visibleFor, () {
      if (_disposed) return;

      _updateState(_state.copyWith(overlayVisible: false));
      _overlayClearTimer = Timer(_overlayFadeDuration, () {
        if (_disposed || _state.overlayVisible) return;
        _updateState(_state.copyWith(lastDecision: null));
      });
    });
  }

  void _onCameraFrame(CameraImage image) {
    _latestFrame = image;
  }

  void _updateState(AccessViewState newState) {
    if (_disposed) return;
    _state = newState;
    notifyListeners();
  }

  FaceDetector get _detector => _faceDetector ??= FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableLandmarks: false,
          enableClassification: false,
          minFaceSize: 0.15,
        ),
      );

  int _deviceOrientationToDeg(DeviceOrientation orientation) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        return 0;
      case DeviceOrientation.landscapeLeft:
        return 90;
      case DeviceOrientation.portraitDown:
        return 180;
      case DeviceOrientation.landscapeRight:
        return 270;
    }
  }

  int _computeRotationDeg(CameraController controller) {
    final camera = controller.description;
    final sensorDeg = camera.sensorOrientation;
    final deviceDeg = _deviceOrientationToDeg(
      controller.value.deviceOrientation,
    );
    final isFront = camera.lensDirection == CameraLensDirection.front;
    return isFront
        ? (sensorDeg + deviceDeg) % 360
        : (sensorDeg - deviceDeg + 360) % 360;
  }

  Future<List<double>?> _extractEmbedding({
    required CameraFramePayload frame,
    required Face face,
    required int rotationDegrees,
    required FaceCropStrategy cropStrategy,
  }) async {
    final inputTensor = await preprocessFaceTensorOnIsolate(
      FacePreprocessingRequest(
        frame: frame,
        cropRect: FaceCropRect(
          left: face.boundingBox.left,
          top: face.boundingBox.top,
          width: face.boundingBox.width,
          height: face.boundingBox.height,
        ),
        rotationDegrees: rotationDegrees,
        cropStrategy: cropStrategy,
        targetSize: FaceRecognizer.inputSize,
      ),
    );
    if (inputTensor == null) return null;
    return faceRecognizer.getEmbeddingFromInputTensor(inputTensor);
  }

  InputImage _toInputImage(
    CameraFramePayload frame,
    CameraController controller,
  ) {
    final rotDeg = _computeRotationDeg(controller);
    final rotation = InputImageRotationValue.fromRawValue(rotDeg) ??
        InputImageRotation.rotation0deg;
    _nv21Buffer = buildNv21Bytes(frame, buffer: _nv21Buffer);

    return InputImage.fromBytes(
      bytes: _nv21Buffer!,
      metadata: InputImageMetadata(
        size: ui.Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: frame.width,
      ),
    );
  }

  Future<void> _disposeCameraController(CameraController controller) async {
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}

    try {
      await controller.dispose();
    } catch (_) {}
  }
}

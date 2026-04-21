import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../application/use_cases/evaluate_access_use_case.dart';
import '../domain/entities/access_decision.dart';
import '../domain/entities/operator_role.dart';
import '../domain/entities/user_role.dart';
import '../domain/entities/tablet_assignment.dart';
import '../domain/entities/tablet_identity.dart';
import '../infrastructure/access_log_service.dart';
import '../infrastructure/face_database.dart';
import '../infrastructure/face_recognizer.dart';
import '../infrastructure/firebase_database.dart';
import '../infrastructure/mqtt_door_controller.dart';
import '../infrastructure/tts_service.dart';
import 'people_list_screen.dart';
import 'register_screen.dart';

class AccessScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final FaceRecognizer faceRecognizer;
  final EvaluateAccessUseCase evaluateAccess;
  final MqttDoorController doorController;
  final TtsService ttsService;
  final FaceDatabase faceDatabase;
  final FirebaseDatabase firebaseDatabase;
  final TabletIdentity tabletIdentity;
  final TabletAssignment? tabletAssignment;
  final AccessLogService accessLogService;
  final OperatorRole profile;

  const AccessScreen({
    super.key,
    required this.cameras,
    required this.faceRecognizer,
    required this.evaluateAccess,
    required this.doorController,
    required this.ttsService,
    required this.faceDatabase,
    required this.firebaseDatabase,
    required this.tabletIdentity,
    required this.tabletAssignment,
    required this.accessLogService,
    required this.profile,
  });

  @override
  State<AccessScreen> createState() => _AccessScreenState();
}

class _AccessScreenState extends State<AccessScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;

  // ── Frame processing ────────────────────────────────────────────────────────
  CameraImage? _latestFrame;
  bool _isRecognizing = false;

  // ── Recognition history (sliding window) ───────────────────────────────────
  // Stores the last N decisions to smooth out flicker.
  static const int _windowSize = 3;
  final List<String?> _recentMatches = []; // name or null (denied)
  int _graceCyclesWithoutFace = 0;
  DateTime? _lastExitTime;

  // ── Cooldowns ───────────────────────────────────────────────────────────────
  // Door-open cooldown: ESP32 trigger only once per 5 s per person.
  final Map<String, DateTime> _doorCooldown = {};
  // Overlay cooldown: don't re-show same message within 3 s.
  DateTime _lastOverlayAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastOverlayKey;

  // ── UI state ────────────────────────────────────────────────────────────────
  AccessDecision? _lastDecision;
  bool _overlayVisible = false;
  Timer? _overlayHideTimer;

  // ── Animations ──────────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late AnimationController _overlayController;
  late Animation<double> _overlayFade;

  // ── Clock ───────────────────────────────────────────────────────────────────
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  String get _greeting {
    final h = _now.hour;
    if (h >= 6 && h < 12) return 'Bom dia';
    if (h >= 12 && h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _overlayFade = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeInOut,
    );

    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );

    _initDetector();
    _initCamera();
    widget.doorController.connect();
  }

  void _initDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: false,
        enableClassification: false,
        minFaceSize: 0.15,
      ),
    );
  }

  Future<void> _initCamera() async {
    final frontCamera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();
    if (!mounted) return;
    await _cameraController!.startImageStream(_onCameraFrame);
    setState(() {});
  }

  Future<void> _pauseCamera() async {
    try {
      if (_cameraController?.value.isStreamingImages == true) {
        await _cameraController!.stopImageStream();
      }
    } catch (_) {}
  }

  Future<void> _resumeCamera({bool fullReinit = false}) async {
    if (!fullReinit) {
      try {
        if (_cameraController != null &&
            _cameraController!.value.isInitialized &&
            !_cameraController!.value.isStreamingImages) {
          await _cameraController!.startImageStream(_onCameraFrame);
          setState(() {});
          return;
        }
      } catch (_) {}
    }
    try {
      await _cameraController?.stopImageStream();
    } catch (_) {}
    try {
      await _cameraController?.dispose();
    } catch (_) {}
    _cameraController = null;
    setState(() {});
    await Future.delayed(const Duration(milliseconds: 400));
    await _initCamera();
  }

  // ── Frame pipeline ──────────────────────────────────────────────────────────

  void _onCameraFrame(CameraImage image) {
    _latestFrame = image; // cache for manual recognition button
  }

  Future<void> _processFrame(CameraImage image) async {
    final inputImage = _toInputImage(image);
    final faces = await _faceDetector.processImage(inputImage);

    if (faces.isEmpty) {
      _handleNoFace();
      return;
    }
    _graceCyclesWithoutFace = 0;

    // Don't re-evaluate if someone just left (3s block)
    if (_lastExitTime != null) {
      if (DateTime.now().difference(_lastExitTime!).inSeconds < 3) return;
      _lastExitTime = null;
    }

    final face = faces.reduce(
      (a, b) => a.boundingBox.width > b.boundingBox.width ? a : b,
    );

    // Crop face from raw sensor image, then rotate small crop for FaceNet.
    final rawImage = _yuv420ToImage(image);
    final sensorCrop = _cropFace(rawImage, face.boundingBox);
    if (sensorCrop == null) return;

    final sensorOrientation =
        _cameraController!.description.sensorOrientation;
    final faceImage = _rotateForDisplay(sensorCrop, sensorOrientation);

    final embedding = await widget.faceRecognizer.getEmbedding(faceImage);
    if (embedding == null) return;

    final decision = await widget.evaluateAccess.execute(embedding);
    _pushDecision(decision);
  }

  /// Sliding-window smoothing: a verdict is only emitted when the last
  /// [_windowSize] frames agree (same person, or all denied).
  void _pushDecision(AccessDecision decision) {
    final key = decision.isAuthorized ? decision.personName : null;
    _recentMatches.add(key);
    if (_recentMatches.length > _windowSize) _recentMatches.removeAt(0);
    if (_recentMatches.length < 2) return;

    // Count occurrences of each candidate in the window
    final counts = <String?, int>{};
    for (final k in _recentMatches) {
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);

    // Need at least 2 matching frames in the window to commit
    if (best.value < 2) return;

    if (best.key != null) {
      // Find the AccessDecision object for the best key — use the most recent
      // one (the one we just pushed) if it matches.
      final matched = decision.personName == best.key
          ? decision
          : AccessDecision.authorized(
              personName: best.key!,
              role: decision.role ?? UserRole.operador,
              confidence: decision.confidence ?? 0.5,
            );
      _showAuthorized(matched);
    } else {
      _showDenied();
    }
  }

  void _showAuthorized(AccessDecision decision) {
    final name = decision.personName!;
    final now = DateTime.now();

    // Throttle overlay: don't re-show same person within 3 s
    if (_lastOverlayKey == 'auth:$name' &&
        now.difference(_lastOverlayAt).inSeconds < 3) {
      return;
    }
    _lastOverlayKey = 'auth:$name';
    _lastOverlayAt = now;

    // Open door only once per door-cooldown window (5 s)
    final lastDoor = _doorCooldown[name];
    if (lastDoor == null || now.difference(lastDoor).inSeconds >= 5) {
      _doorCooldown[name] = now;
      widget.doorController.openDoor();
    }

    widget.ttsService.announceAuthorized(name);
    widget.accessLogService.log(
      personName: name,
      authorized: true,
      role: decision.role?.key,
    );
    _displayOverlay(decision, const Duration(seconds: 4));
  }

  void _showDenied() {
    final now = DateTime.now();
    if (_lastOverlayKey == 'denied' &&
        now.difference(_lastOverlayAt).inSeconds < 4) {
      return;
    }
    _lastOverlayKey = 'denied';
    _lastOverlayAt = now;

    widget.ttsService.announceDenied();
    widget.accessLogService.log(
      personName: 'Desconhecido',
      authorized: false,
    );
    _displayOverlay(AccessDecision.denied(), const Duration(seconds: 3));
  }

  void _displayOverlay(AccessDecision decision, Duration visibleFor) {
    if (!mounted) return;
    _overlayHideTimer?.cancel();
    setState(() {
      _lastDecision = decision;
      _overlayVisible = true;
    });
    _overlayController.forward(from: 0);
    _overlayHideTimer = Timer(visibleFor, () {
      if (!mounted) return;
      _overlayController.reverse();
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) setState(() => _overlayVisible = false);
      });
    });
  }

  void _handleNoFace() {
    _graceCyclesWithoutFace++;
    if (_graceCyclesWithoutFace >= 3) {
      if (_recentMatches.isNotEmpty) _lastExitTime = DateTime.now();
      _recentMatches.clear();
      if (mounted && _overlayVisible && _overlayHideTimer?.isActive != true) {
        // Timer already scheduled hide — don't interfere
      }
    }
  }

  // ── Manual recognition ──────────────────────────────────────────────────────

  Future<void> _recognizeNow() async {
    final frame = _latestFrame;
    if (frame == null || _isRecognizing) return;
    setState(() => _isRecognizing = true);
    try {
      AccessDecision decision;

      final inputImage = _toInputImage(frame);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        decision = AccessDecision.denied();
      } else {
        final face = faces.reduce(
          (a, b) => a.boundingBox.width > b.boundingBox.width ? a : b,
        );
        // Rotate full image first so bounding box coordinates match
        final rawImage = _yuv420ToImage(frame);
        final orientedImage = _rotateForDisplay(rawImage, _computeRotationDeg());
        final faceImage = _cropFace(orientedImage, face.boundingBox);
        if (faceImage == null) {
          decision = AccessDecision.denied();
        } else {
          final embedding =
              await widget.faceRecognizer.getEmbedding(faceImage);
          decision = embedding == null
              ? AccessDecision.denied()
              : await widget.evaluateAccess.execute(embedding);
        }
      }

      // Manual trigger always shows result — bypass cooldown
      _lastOverlayKey = null;
      _displayOverlay(decision, const Duration(seconds: 5));

      if (decision.isAuthorized && decision.personName != null) {
        final now = DateTime.now();
        final last = _doorCooldown[decision.personName!];
        if (last == null || now.difference(last).inSeconds >= 5) {
          _doorCooldown[decision.personName!] = now;
          widget.doorController.openDoor();
        }
        widget.ttsService.announceGreeting(_greeting, decision.personName!);
      }
      // Denied: no audio, overlay already displayed
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red[800],
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRecognizing = false);
    }
  }

  // ── Image utilities ─────────────────────────────────────────────────────────

  int _deviceOrientationToDeg(DeviceOrientation o) {
    switch (o) {
      case DeviceOrientation.portraitUp:    return 0;
      case DeviceOrientation.landscapeLeft: return 90;
      case DeviceOrientation.portraitDown:  return 180;
      case DeviceOrientation.landscapeRight: return 270;
    }
  }

  /// Returns the degrees to rotate the raw sensor image so faces are upright.
  /// Accounts for both sensor orientation and current device orientation.
  int _computeRotationDeg() {
    final camera = _cameraController!.description;
    final sensorDeg = camera.sensorOrientation;
    final deviceDeg = _deviceOrientationToDeg(
      _cameraController!.value.deviceOrientation,
    );
    final isFront = camera.lensDirection == CameraLensDirection.front;
    return isFront
        ? (sensorDeg + deviceDeg) % 360
        : (sensorDeg - deviceDeg + 360) % 360;
  }

  InputImage _toInputImage(CameraImage image) {
    final rotDeg = _computeRotationDeg();
    final rotation = InputImageRotationValue.fromRawValue(rotDeg) ??
        InputImageRotation.rotation0deg;

    // Convert YUV420 → NV21 (VU interleaved), which ML Kit expects on Android
    final int w = image.width;
    final int h = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final nv21 = Uint8List(w * h + w * h ~/ 2);

    // Y plane — copy row by row to strip padding
    for (int row = 0; row < h; row++) {
      nv21.setRange(
        row * w,
        row * w + w,
        yPlane.bytes,
        row * yPlane.bytesPerRow,
      );
    }

    // UV plane — interleave V then U (NV21 order)
    int uvOffset = w * h;
    for (int row = 0; row < h ~/ 2; row++) {
      for (int col = 0; col < w ~/ 2; col++) {
        final idx = row * uvRowStride + col * uvPixelStride;
        nv21[uvOffset++] = vPlane.bytes[idx];
        nv21[uvOffset++] = uPlane.bytes[idx];
      }
    }

    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: ui.Size(w.toDouble(), h.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: w,
      ),
    );
  }

  img.Image _rotateForDisplay(img.Image source, int degrees) {
    if (degrees == 0) return source;
    return img.copyRotate(source, angle: degrees);
  }

  img.Image? _cropFace(img.Image source, Rect box) {
    final x = box.left.toInt().clamp(0, source.width - 1);
    final y = box.top.toInt().clamp(0, source.height - 1);
    final w = box.width.toInt().clamp(1, source.width - x);
    final h = box.height.toInt().clamp(1, source.height - y);
    if (w <= 0 || h <= 0) return null;
    return img.copyCrop(source, x: x, y: y, width: w, height: h);
  }

  img.Image _yuv420ToImage(CameraImage cameraImage) {
    final int width = cameraImage.width;
    final int height = cameraImage.height;

    final yPlane = cameraImage.planes[0];
    final uPlane = cameraImage.planes[1];
    final vPlane = cameraImage.planes[2];

    final Uint8List yBuf = yPlane.bytes;
    final Uint8List uBuf = uPlane.bytes;
    final Uint8List vBuf = vPlane.bytes;

    final int yRowStride = yPlane.bytesPerRow;
    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final output = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yVal = yBuf[y * yRowStride + x];
        final int uvIdx = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
        final int uVal = uBuf[uvIdx] - 128;
        final int vVal = vBuf[uvIdx] - 128;

        final int r = (yVal + 1.402 * vVal).round().clamp(0, 255);
        final int g =
            (yVal - 0.344136 * uVal - 0.714136 * vVal).round().clamp(0, 255);
        final int b = (yVal + 1.772 * uVal).round().clamp(0, 255);

        output.setPixelRgb(x, y, r, g, b);
      }
    }
    return output;
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraPreview(),
          _buildScanOverlay(),
          _buildBottomButtons(),
          if (_overlayVisible && _lastDecision != null)
            _buildAccessOverlay(_lastDecision!),
          _buildTopBar(),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
    final isAdmin = widget.profile == OperatorRole.admin;

    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Cadastros — apenas Admin
            if (isAdmin) ...[
              ElevatedButton.icon(
                onPressed: () async {
                  await _pauseCamera();
                  if (!mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PeopleListScreen(
                        faceDatabase: widget.faceDatabase,
                        firebaseDatabase: widget.firebaseDatabase,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  await _resumeCamera(fullReinit: false);
                },
                icon: const Icon(Icons.people, size: 18),
                label: const Text('Cadastros'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
              const SizedBox(width: 16),

              // Cadastrar — apenas Admin
              ElevatedButton.icon(
                onPressed: () async {
                  await _pauseCamera();
                  if (!mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RegisterScreen(
                        cameras: widget.cameras,
                        faceRecognizer: widget.faceRecognizer,
                        faceDatabase: widget.faceDatabase,
                        firebaseDatabase: widget.firebaseDatabase,
                        locationId: widget.tabletAssignment?.locationId,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  await _resumeCamera(fullReinit: true);
                },
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Cadastrar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
              const SizedBox(width: 16),
            ],

            // Reconhecer
            GestureDetector(
              onTap: _isRecognizing ? null : _recognizeNow,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  color: _isRecognizing
                      ? Colors.white12
                      : Colors.cyanAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isRecognizing ? Colors.white24 : Colors.cyanAccent,
                    width: 2,
                  ),
                  boxShadow: _isRecognizing
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.cyanAccent.withOpacity(0.25),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                ),
                child: _isRecognizing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white54,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.face_retouching_natural,
                              color: Colors.cyanAccent, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Reconhecer',
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Iniciando câmera…',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    return CameraPreview(_cameraController!);
  }

  Widget _buildScanOverlay() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        return CustomPaint(
          painter: _ScanFramePainter(
            pulseValue: _pulseController.value,
            active: !_overlayVisible,
          ),
        );
      },
    );
  }

  Widget _buildAccessOverlay(AccessDecision decision) {
    final authorized = decision.isAuthorized;
    final role = decision.role;
    final Color baseColor =
        authorized ? (role?.color ?? Colors.green) : Colors.red;

    return FadeTransition(
      opacity: _overlayFade,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              baseColor.withOpacity(0.95),
              baseColor.withOpacity(0.75),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.15),
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Icon(
                authorized
                    ? (role?.icon ?? Icons.check_circle_outline)
                    : Icons.block,
                size: 70,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            if (authorized && decision.personName != null) ...[
              Text(
                '$_greeting,',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w300,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                decision.personName!,
                style: const TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              if (role != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white54, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(role.icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        role.label.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
            ] else ...[
              const Text(
                'NÃO AUTORIZADO',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final weekdays = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    final months = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];
    final dateStr = '${weekdays[_now.weekday - 1]}, ${_now.day} ${months[_now.month - 1]} ${_now.year}';
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Transform.translate(
          offset: const Offset(0, -30),
          child: Container(
          padding: EdgeInsets.only(
            left: 0,
            right: isPortrait ? 12 : 20,
            top: isPortrait ? 8 : 10,
            bottom: isPortrait ? 8 : 10,
          ),
          child: isPortrait
              // ── Portrait: coluna compacta no topo ──────────────────────────
              ? Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: const Offset(-8, 0),
                          child: Image.asset(
                            'assets/logo_bembrasil.png',
                            height: 90,
                            fit: BoxFit.contain,
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Transform.translate(
                              offset: const Offset(-20, 0),
                              child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shield, color: Colors.white, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'FACE ACCESS',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(dateStr,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 10)),
                            Text('$h:$m',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w300,
                                  letterSpacing: 2,
                                  fontFeatures: [ui.FontFeature.tabularFigures()],
                                )),
                          ],
                        ),
                      ],
                    ),
                  ],
                )
              // ── Landscape: layout original ─────────────────────────────────
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Logo
                    Transform.translate(
                      offset: const Offset(-8, -21),
                      child: Image.asset(
                        'assets/logo_bembrasil.png',
                        height: 115,
                        fit: BoxFit.contain,
                      ),
                    ),
                    // FACE ACCESS
                    Expanded(
                      child: Transform.translate(
                        offset: const Offset(-29, -25),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.shield, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'FACE ACCESS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Data e hora
                    Transform.translate(
                      offset: const Offset(0, -20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(dateStr,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          Text('$h:$m',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w300,
                                letterSpacing: 2,
                                fontFeatures: [ui.FontFeature.tabularFigures()],
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _overlayHideTimer?.cancel();
    _clockTimer.cancel();
    _pulseController.dispose();
    _overlayController.dispose();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }
}

/// Corner brackets + scan line
class _ScanFramePainter extends CustomPainter {
  final double pulseValue;
  final bool active;

  _ScanFramePainter({required this.pulseValue, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final frameW = size.width * 0.45;
    final frameH = size.height * 0.65;
    final cornerLen = 30.0;

    final color = Color.lerp(Colors.white54, Colors.cyanAccent, pulseValue)!;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final left = cx - frameW / 2;
    final top = cy - frameH / 2;
    final right = cx + frameW / 2;
    final bottom = cy + frameH / 2;

    canvas.drawLine(Offset(left, top + cornerLen), Offset(left, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left + cornerLen, top), paint);
    canvas.drawLine(Offset(right - cornerLen, top), Offset(right, top), paint);
    canvas.drawLine(Offset(right, top), Offset(right, top + cornerLen), paint);
    canvas.drawLine(
        Offset(left, bottom - cornerLen), Offset(left, bottom), paint);
    canvas.drawLine(
        Offset(left, bottom), Offset(left + cornerLen, bottom), paint);
    canvas.drawLine(
        Offset(right - cornerLen, bottom), Offset(right, bottom), paint);
    canvas.drawLine(
        Offset(right, bottom), Offset(right, bottom - cornerLen), paint);

    final scanY = top + (bottom - top) * pulseValue;
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Colors.cyanAccent.withOpacity(0.6),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(left, scanY - 1, frameW, 2))
      ..strokeWidth = 2;
    canvas.drawLine(Offset(left, scanY), Offset(right, scanY), scanPaint);
  }

  @override
  bool shouldRepaint(_ScanFramePainter old) =>
      old.pulseValue != pulseValue || old.active != active;
}

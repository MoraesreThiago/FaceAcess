import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../domain/entities/user_role.dart';
import '../infrastructure/face_database.dart';
import '../infrastructure/face_recognizer.dart';
import '../infrastructure/firebase_database.dart';

class RegisterScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final FaceRecognizer faceRecognizer;
  final FaceDatabase faceDatabase;
  final FirebaseDatabase firebaseDatabase;

  /// Unidade em que a pessoa está sendo cadastrada. `null` significa
  /// "sem restrição de unidade" — comportamento idêntico ao legado
  /// quando o tablet ainda não tinha setup completo.
  final String? locationId;

  const RegisterScreen({
    super.key,
    required this.cameras,
    required this.faceRecognizer,
    required this.faceDatabase,
    required this.firebaseDatabase,
    required this.locationId,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;

  final TextEditingController _nameController = TextEditingController();
  final List<List<double>> _capturedEmbeddings = [];

  UserRole _selectedRole = UserRole.operador;

  static const int _minPhotos = 10;
  static const int _maxPhotos = 30;

  bool _isCapturing = false;
  bool _isSaving = false;
  Timer? _autoCaptureTimer;
  String _statusMessage = 'Posicione o rosto centralizado e bem iluminado';
  bool _faceDetected = false;

  late AnimationController _captureAnim;

  @override
  void initState() {
    super.initState();
    _captureAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.25,
      ),
    );
    _initCamera();
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
    );

    await _cameraController!.initialize();
    if (mounted) setState(() {});
  }

  void _startAutoCapture() {
    if (_capturedEmbeddings.length >= _maxPhotos) return;
    _capturePhoto();
    _autoCaptureTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) {
        if (_capturedEmbeddings.length >= _maxPhotos) {
          _stopAutoCapture();
        } else {
          _capturePhoto();
        }
      },
    );
  }

  void _stopAutoCapture() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;
    if (_capturedEmbeddings.length >= _maxPhotos) return;
    if (_isCapturing) return;

    setState(() {
      _isCapturing = true;
      _statusMessage = 'Processando…';
    });

    _captureAnim.forward().then((_) => _captureAnim.reverse());

    try {
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('Imagem inválida');

      // Apply EXIF orientation so the image matches what ML Kit sees
      final rawImage = img.bakeOrientation(decoded);

      final inputImage = InputImage.fromFilePath(xFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        setState(() {
          _statusMessage = '⚠️ Nenhum rosto detectado — tente novamente';
          _faceDetected = false;
        });
        return;
      }

      final face = faces.reduce(
        (a, b) => a.boundingBox.width > b.boundingBox.width ? a : b,
      );

      final x = face.boundingBox.left.toInt().clamp(0, rawImage.width - 1);
      final y = face.boundingBox.top.toInt().clamp(0, rawImage.height - 1);
      final w = face.boundingBox.width.toInt().clamp(1, rawImage.width - x);
      final h = face.boundingBox.height.toInt().clamp(1, rawImage.height - y);

      final cropped = img.copyCrop(rawImage, x: x, y: y, width: w, height: h);
      final embedding = await widget.faceRecognizer.getEmbedding(cropped);

      if (embedding == null) throw Exception('Falha ao gerar embedding');

      setState(() {
        _faceDetected = true;
        _capturedEmbeddings.add(embedding);
        final remaining = _minPhotos - _capturedEmbeddings.length;
        if (remaining > 0) {
          _statusMessage =
              'Foto ${_capturedEmbeddings.length}/$_maxPhotos capturada — '
              'faltam $remaining para liberar o salvar';
        } else {
          _statusMessage =
              '✅ ${_capturedEmbeddings.length}/$_maxPhotos fotos — pode salvar!';
        }
      });

      await File(xFile.path).delete().catchError((_) {});
    } catch (e) {
      setState(() => _statusMessage = '❌ Erro: $e');
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _savePerson() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Digite o nome da pessoa');
      return;
    }
    if (_capturedEmbeddings.length < _minPhotos) {
      _showSnack('Capture no mínimo $_minPhotos fotos');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Salva local (Hive) para reconhecimento rápido offline
      await widget.faceDatabase.savePerson(
        name,
        _capturedEmbeddings,
        role: _selectedRole,
      );

      // Salva no Firebase para sincronizar com outros tablets
      await widget.firebaseDatabase.savePerson(
        name,
        _capturedEmbeddings,
        role: _selectedRole,
        allowedUnits:
            (widget.locationId != null && widget.locationId!.isNotEmpty)
                ? [widget.locationId!]
                : const <String>[],
      );

      if (mounted) {
        _showSnack('✅ $name (${_selectedRole.label}) cadastrado com sucesso!');
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      _showSnack('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final canSave = _capturedEmbeddings.length >= _minPhotos &&
        _nameController.text.trim().isNotEmpty &&
        !_isSaving;
    final progress = _capturedEmbeddings.length / _maxPhotos;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.person_add, size: 22),
            SizedBox(width: 8),
            Text('Cadastrar Pessoa',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(
              _capturedEmbeddings.length >= _minPhotos
                  ? Colors.greenAccent
                  : _selectedRole.color,
            ),
          ),
        ),
      ),
      body: Builder(
        builder: (context) {
          // Usa tamanho físico da tela (ignora teclado) para detectar orientação
          final view = View.of(context);
          final physicalSize = view.physicalSize / view.devicePixelRatio;
          final isPortrait = physicalSize.height >= physicalSize.width;
          final cameraWidget = Stack(
            fit: StackFit.expand,
            children: [
              _cameraController?.value.isInitialized == true
                  ? CameraPreview(_cameraController!)
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white)),
              CustomPaint(
                painter: _FaceFramePainter(
                  color: _faceDetected ? _selectedRole.color : Colors.white38,
                ),
              ),
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: _ProgressRing(
                    progress: progress,
                    count: _capturedEmbeddings.length,
                    max: _maxPhotos,
                    min: _minPhotos,
                    color: _selectedRole.color,
                  ),
                ),
              ),
            ],
          );

          final formWidget = Container(
            color: const Color(0xFF111111),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: isPortrait ? MainAxisSize.min : MainAxisSize.max,
              children: [
                // Status message
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12, height: 1.4),
                  ),
                ),
                const SizedBox(height: 12),

                // Name field
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nome completo',
                    labelStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.person, color: Colors.white38),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _selectedRole.color, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),

                // Role selector
                const Text(
                  'CARGO / FUNÇÃO',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: UserRole.values.map((role) {
                    final selected = _selectedRole == role;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedRole = role),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? role.color.withOpacity(0.25)
                              : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? role.color : Colors.white12,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(role.icon,
                                size: 14,
                                color: selected ? role.color : Colors.white38),
                            const SizedBox(width: 6),
                            Text(
                              role.label,
                              style: TextStyle(
                                color: selected ? role.color : Colors.white54,
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (!isPortrait) const Spacer(),
                const SizedBox(height: 12),

                // Capture button — segure para captura contínua a cada 500ms
                ScaleTransition(
                  scale: Tween(begin: 1.0, end: 0.93).animate(_captureAnim),
                  child: GestureDetector(
                    onTapDown: (_) {
                      if (!_isCapturing && _capturedEmbeddings.length < _maxPhotos) {
                        _startAutoCapture();
                      }
                    },
                    onTapUp: (_) => _stopAutoCapture(),
                    onTapCancel: _stopAutoCapture,
                    child: ElevatedButton.icon(
                      onPressed: _capturedEmbeddings.length >= _maxPhotos ? null : () {},
                      icon: _isCapturing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.camera_alt),
                      label: Text(_isCapturing
                          ? 'Capturando…'
                          : 'Segurar para capturar (${_capturedEmbeddings.length}/$_maxPhotos)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedRole.color.withOpacity(0.8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Save button
                ElevatedButton.icon(
                  onPressed: canSave ? _savePerson : null,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Salvando…' : 'Salvar cadastro'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white10,
                    disabledForegroundColor: Colors.white30,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          );

          if (isPortrait) {
            // Portrait: câmera altura fixa + formulário scrollável (teclado não cobre)
            final cameraHeight = physicalSize.height * 0.42;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              child: Column(
                children: [
                  SizedBox(height: cameraHeight, child: cameraWidget),
                  formWidget,
                ],
              ),
            );
          } else {
            // Landscape: câmera à esquerda, formulário à direita
            return Row(
              children: [
                Expanded(flex: 3, child: cameraWidget),
                SizedBox(width: 320, child: formWidget),
              ],
            );
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _captureAnim.dispose();
    _cameraController?.dispose();
    _faceDetector.close();
    _nameController.dispose();
    super.dispose();
  }
}

/// Oval guide frame drawn on the camera
class _FaceFramePainter extends CustomPainter {
  final Color color;
  _FaceFramePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 - 30;
    final rx = size.width * 0.28;
    final ry = size.height * 0.38;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawOval(Rect.fromCenter(
        center: Offset(cx, cy), width: rx * 2, height: ry * 2), paint);
  }

  @override
  bool shouldRepaint(_FaceFramePainter old) => old.color != color;
}

/// Circular progress indicator with count
class _ProgressRing extends StatelessWidget {
  final double progress;
  final int count;
  final int max;
  final int min;
  final Color color;

  const _ProgressRing({
    required this.progress,
    required this.count,
    required this.max,
    required this.min,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(80, 80),
            painter: _RingPainter(
              progress: progress,
              color: count >= min ? Colors.greenAccent : color,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'de $max',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    canvas.drawCircle(
        center, radius, Paint()..color = Colors.white12..strokeWidth = 5..style = PaintingStyle.stroke);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = color
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

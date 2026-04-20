import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/use_cases/evaluate_access_use_case.dart';
import 'domain/entities/user_profile.dart';
import 'firebase_options.dart';
import 'infrastructure/access_log_service.dart';
import 'infrastructure/auth_service.dart';
import 'infrastructure/face_database.dart';
import 'infrastructure/face_recognizer.dart';
import 'infrastructure/firebase_database.dart';
import 'infrastructure/mqtt_door_controller.dart';
import 'infrastructure/tablet_config.dart';
import 'infrastructure/tts_service.dart';
import 'presentation/access_screen.dart';
import 'presentation/login_screen.dart';
import 'presentation/tablet_setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Hide navigation bar and status bar (immersive kiosk mode)
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  // Tablet identity
  final tabletConfig = TabletConfig();
  await tabletConfig.initialize();

  // Autenticação
  final authService = AuthService();
  await authService.initialize();

  // Câmeras
  final cameras = await availableCameras();

  // Infraestrutura
  final faceDatabase = FaceDatabase();
  await faceDatabase.initialize();

  final firebaseDatabase = FirebaseDatabase();

  // Sincroniza Firestore → Hive na inicialização (somente pessoas da unidade)
  _syncFirestoreToHive(
    firebaseDatabase: firebaseDatabase,
    faceDatabase: faceDatabase,
    unit: tabletConfig.unit,
  );

  final faceRecognizer = FaceRecognizer();
  await faceRecognizer.initialize();

  final doorController = MqttDoorController();
  final evaluateAccess = EvaluateAccessUseCase(faceDatabase: faceDatabase);
  final ttsService = TtsService();
  await ttsService.initialize();

  runApp(ProviderScope(
    child: FaceAccessApp(
      cameras: cameras,
      faceRecognizer: faceRecognizer,
      evaluateAccess: evaluateAccess,
      doorController: doorController,
      ttsService: ttsService,
      faceDatabase: faceDatabase,
      firebaseDatabase: firebaseDatabase,
      tabletConfig: tabletConfig,
      authService: authService,
    ),
  ));
}

/// Baixa as pessoas do Firestore e salva no Hive local.
/// Roda em background — erros são silenciosos.
Future<void> _syncFirestoreToHive({
  required FirebaseDatabase firebaseDatabase,
  required FaceDatabase faceDatabase,
  required String unit,
}) async {
  try {
    final people = await firebaseDatabase.loadAll(
      unit: unit.isNotEmpty ? unit : null,
    );
    for (final entry in people.entries) {
      await faceDatabase.savePerson(
        entry.key,
        entry.value.embeddings,
        role: entry.value.role,
      );
    }
  } catch (_) {
    // Sem conexão — usa cache local do Hive
  }
}

class FaceAccessApp extends StatefulWidget {
  final List<CameraDescription> cameras;
  final FaceRecognizer faceRecognizer;
  final EvaluateAccessUseCase evaluateAccess;
  final MqttDoorController doorController;
  final TtsService ttsService;
  final FaceDatabase faceDatabase;
  final FirebaseDatabase firebaseDatabase;
  final TabletConfig tabletConfig;
  final AuthService authService;

  const FaceAccessApp({
    super.key,
    required this.cameras,
    required this.faceRecognizer,
    required this.evaluateAccess,
    required this.doorController,
    required this.ttsService,
    required this.faceDatabase,
    required this.firebaseDatabase,
    required this.tabletConfig,
    required this.authService,
  });

  @override
  State<FaceAccessApp> createState() => _FaceAccessAppState();
}

class _FaceAccessAppState extends State<FaceAccessApp> {
  UserProfile? _loggedProfile;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _configured = widget.tabletConfig.isConfigured;
  }

  void _onLogin(UserProfile profile) =>
      setState(() => _loggedProfile = profile);

  void _onSetupDone() => setState(() => _configured = true);

  AccessScreen _buildAccessScreen(UserProfile profile) => AccessScreen(
        cameras: widget.cameras,
        faceRecognizer: widget.faceRecognizer,
        evaluateAccess: widget.evaluateAccess,
        doorController: widget.doorController,
        ttsService: widget.ttsService,
        faceDatabase: widget.faceDatabase,
        firebaseDatabase: widget.firebaseDatabase,
        tabletConfig: widget.tabletConfig,
        accessLogService: AccessLogService(
          tabletId: widget.tabletConfig.id,
          tabletName: widget.tabletConfig.name,
          unit: widget.tabletConfig.unit,
        ),
        profile: profile,
      );

  @override
  Widget build(BuildContext context) {
    Widget home;

    // 1. Login sempre primeiro
    if (_loggedProfile == null) {
      home = LoginScreen(
        authService: widget.authService,
        tabletConfig: widget.tabletConfig,
        onLogin: _onLogin,
      );
    }
    // 2. Admin → acesso direto, sem precisar configurar o tablet
    else if (_loggedProfile == UserProfile.admin) {
      home = _buildAccessScreen(UserProfile.admin);
    }
    // 3. Porta → precisa configurar nome/unidade se ainda não configurado
    else if (!_configured) {
      home = TabletSetupScreen(
        config: widget.tabletConfig,
        onDone: _onSetupDone,
      );
    }
    // 4. Porta configurado → acesso normal
    else {
      home = _buildAccessScreen(UserProfile.porta);
    }

    return MaterialApp(
      title: 'BemBrasil',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: home,
    );
  }
}

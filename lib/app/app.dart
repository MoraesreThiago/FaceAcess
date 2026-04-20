import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/use_cases/evaluate_access_use_case.dart';
import '../domain/entities/user_profile.dart';
import '../infrastructure/access_log_service.dart';
import '../infrastructure/face_database.dart';
import '../infrastructure/face_recognizer.dart';
import '../infrastructure/firebase_database.dart';
import '../infrastructure/mqtt_door_controller.dart';
import '../infrastructure/tablet_config.dart';
import '../infrastructure/tts_service.dart';
import '../presentation/access_screen.dart';
import '../presentation/login_screen.dart';
import '../presentation/tablet_setup_screen.dart';
import 'providers/application_providers.dart';
import 'providers/bootstrap_providers.dart';
import 'providers/infrastructure_providers.dart';

/// Raiz da aplicação. Responsável por:
///
/// 1. Materializar o `MaterialApp` e o tema.
/// 2. Aguardar todos os providers de boot (câmeras + infraestrutura) antes
///    de decidir qual tela mostrar.
/// 3. Disparar a sincronização Firestore → Hive em background, uma única
///    vez, assim que o boot termina (mesmo comportamento do `main()`
///    anterior).
/// 4. Preservar o roteamento legado: login → (admin direto | porta →
///    setup? → access).
///
/// Nenhuma lógica funcional foi alterada neste PR — apenas o ponto onde
/// ela acontece. A migração real de contratos (AuthRepository,
/// OperatorRole, TabletAssignment) fica para os PRs seguintes.
class FaceAccessApp extends ConsumerStatefulWidget {
  const FaceAccessApp({super.key});

  @override
  ConsumerState<FaceAccessApp> createState() => _FaceAccessAppState();
}

class _FaceAccessAppState extends ConsumerState<FaceAccessApp> {
  UserProfile? _loggedProfile;
  bool? _configured;
  bool _syncStarted = false;

  void _onLogin(UserProfile profile) =>
      setState(() => _loggedProfile = profile);

  void _onSetupDone() => setState(() => _configured = true);

  /// Sincroniza Firestore → Hive na inicialização (somente pessoas da
  /// unidade). Mantém o comportamento "fire and forget" original: erros
  /// são silenciosos e o app segue operando pelo cache local do Hive.
  void _startFirestoreSync({
    required FirebaseDatabase firebaseDatabase,
    required FaceDatabase faceDatabase,
    required String unit,
  }) {
    if (_syncStarted) return;
    _syncStarted = true;
    Future(() async {
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
        // Sem conexão — usa cache local do Hive.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cameras = ref.watch(camerasProvider);
    final tabletConfig = ref.watch(tabletConfigProvider);
    final loginUseCase = ref.watch(loginUseCaseProvider);
    final faceDatabase = ref.watch(faceDatabaseProvider);
    final firebaseDatabase = ref.watch(firebaseDatabaseProvider);
    final faceRecognizer = ref.watch(faceRecognizerProvider);
    final doorController = ref.watch(doorControllerProvider);
    final ttsService = ref.watch(ttsServiceProvider);
    final evaluateAccess = ref.watch(evaluateAccessUseCaseProvider);

    final asyncs = <AsyncValue<Object?>>[
      cameras,
      tabletConfig,
      loginUseCase,
      faceDatabase,
      faceRecognizer,
      ttsService,
      evaluateAccess,
    ];

    Widget home;

    if (asyncs.any((a) => a.hasError)) {
      final failing = asyncs.firstWhere((a) => a.hasError);
      home = _ErrorScreen(
        error: failing.error!,
        stackTrace: failing.stackTrace,
      );
    } else if (asyncs.any((a) => !a.hasValue)) {
      home = const _SplashScreen();
    } else {
      final config = tabletConfig.requireValue;

      // Captura o estado inicial de "configurado" apenas uma vez —
      // depois do setup, o callback `_onSetupDone` assume o controle.
      _configured ??= config.isConfigured;

      // Dispara a sincronização uma única vez, após todos os providers
      // terem resolvido.
      _startFirestoreSync(
        firebaseDatabase: firebaseDatabase,
        faceDatabase: faceDatabase.requireValue,
        unit: config.unit,
      );

      home = _buildHome(
        cameras: cameras.requireValue,
        tabletConfig: config,
        faceDatabase: faceDatabase.requireValue,
        firebaseDatabase: firebaseDatabase,
        faceRecognizer: faceRecognizer.requireValue,
        doorController: doorController,
        ttsService: ttsService.requireValue,
        evaluateAccess: evaluateAccess.requireValue,
      );
    }

    return MaterialApp(
      title: 'BemBrasil',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: home,
    );
  }

  Widget _buildHome({
    required List<CameraDescription> cameras,
    required TabletConfig tabletConfig,
    required FaceDatabase faceDatabase,
    required FirebaseDatabase firebaseDatabase,
    required FaceRecognizer faceRecognizer,
    required MqttDoorController doorController,
    required TtsService ttsService,
    required EvaluateAccessUseCase evaluateAccess,
  }) {
    // 1. Login sempre primeiro
    if (_loggedProfile == null) {
      return LoginScreen(
        tabletConfig: tabletConfig,
        onLogin: _onLogin,
      );
    }

    // 2. Admin → acesso direto, sem precisar configurar o tablet
    if (_loggedProfile == UserProfile.admin) {
      return _buildAccessScreen(
        profile: UserProfile.admin,
        cameras: cameras,
        tabletConfig: tabletConfig,
        faceDatabase: faceDatabase,
        firebaseDatabase: firebaseDatabase,
        faceRecognizer: faceRecognizer,
        doorController: doorController,
        ttsService: ttsService,
        evaluateAccess: evaluateAccess,
      );
    }

    // 3. Porta → precisa configurar nome/unidade se ainda não configurado
    if (_configured != true) {
      return TabletSetupScreen(
        config: tabletConfig,
        onDone: _onSetupDone,
      );
    }

    // 4. Porta configurado → acesso normal
    return _buildAccessScreen(
      profile: UserProfile.porta,
      cameras: cameras,
      tabletConfig: tabletConfig,
      faceDatabase: faceDatabase,
      firebaseDatabase: firebaseDatabase,
      faceRecognizer: faceRecognizer,
      doorController: doorController,
      ttsService: ttsService,
      evaluateAccess: evaluateAccess,
    );
  }

  AccessScreen _buildAccessScreen({
    required UserProfile profile,
    required List<CameraDescription> cameras,
    required TabletConfig tabletConfig,
    required FaceDatabase faceDatabase,
    required FirebaseDatabase firebaseDatabase,
    required FaceRecognizer faceRecognizer,
    required MqttDoorController doorController,
    required TtsService ttsService,
    required EvaluateAccessUseCase evaluateAccess,
  }) {
    return AccessScreen(
      cameras: cameras,
      faceRecognizer: faceRecognizer,
      evaluateAccess: evaluateAccess,
      doorController: doorController,
      ttsService: ttsService,
      faceDatabase: faceDatabase,
      firebaseDatabase: firebaseDatabase,
      tabletConfig: tabletConfig,
      accessLogService: AccessLogService(
        tabletId: tabletConfig.id,
        tabletName: tabletConfig.name,
        unit: tabletConfig.unit,
      ),
      profile: profile,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error, this.stackTrace});

  final Object error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              const Text(
                'Falha ao inicializar o aplicativo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

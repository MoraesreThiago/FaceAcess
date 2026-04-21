import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/use_cases/evaluate_access_use_case.dart';
import '../domain/entities/operator_role.dart';
import '../domain/entities/tablet_assignment.dart';
import '../domain/entities/tablet_identity.dart';
import '../infrastructure/access_log_service.dart';
import '../infrastructure/face_database.dart';
import '../infrastructure/face_recognizer.dart';
import '../infrastructure/firebase_database.dart';
import '../infrastructure/mqtt_door_controller.dart';
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
///    vez, assim que o boot termina.
/// 4. Preservar o roteamento legado: login → (admin direto | porta →
///    setup? → access).
///
/// PR #6 migrou `TabletConfig` para os pares `TabletIdentity` +
/// `TabletAssignment`. O routing agora depende de `assignment != null`
/// (qualquer atribuição já conta como "configurado" para o escopo deste
/// PR — door-selection UX vem em PR futuro).
class FaceAccessApp extends ConsumerStatefulWidget {
  const FaceAccessApp({super.key});

  @override
  ConsumerState<FaceAccessApp> createState() => _FaceAccessAppState();
}

class _FaceAccessAppState extends ConsumerState<FaceAccessApp> {
  OperatorRole? _loggedProfile;
  bool _syncStarted = false;

  void _onLogin(OperatorRole profile) =>
      setState(() => _loggedProfile = profile);

  /// Após o setup gravar identity+assignment, a tela invalida os providers
  /// e o rebuild reage automaticamente. Nada a fazer aqui além de forçar
  /// o rebuild caso a árvore esteja ativa (defensivo).
  void _onSetupDone() => setState(() {});

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
    final identity = ref.watch(tabletIdentityProvider);
    final assignment = ref.watch(tabletAssignmentProvider);
    final loginUseCase = ref.watch(loginUseCaseProvider);
    final faceDatabase = ref.watch(faceDatabaseProvider);
    final firebaseDatabase = ref.watch(firebaseDatabaseProvider);
    final faceRecognizer = ref.watch(faceRecognizerProvider);
    final doorController = ref.watch(doorControllerProvider);
    final ttsService = ref.watch(ttsServiceProvider);
    final evaluateAccess = ref.watch(evaluateAccessUseCaseProvider);

    final asyncs = <AsyncValue<Object?>>[
      cameras,
      identity,
      assignment,
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
      final identityValue = identity.requireValue;
      final assignmentValue = assignment.requireValue;

      // Dispara a sincronização uma única vez, após todos os providers
      // terem resolvido. Mantém o comportamento do legado: se o tablet
      // não tem unidade atribuída ainda, passa string vazia (loadAll
      // então não filtra).
      _startFirestoreSync(
        firebaseDatabase: firebaseDatabase,
        faceDatabase: faceDatabase.requireValue,
        unit: assignmentValue?.locationId ?? '',
      );

      home = _buildHome(
        cameras: cameras.requireValue,
        identity: identityValue,
        assignment: assignmentValue,
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
    required TabletIdentity identity,
    required TabletAssignment? assignment,
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
        identity: identity,
        assignment: assignment,
        onLogin: _onLogin,
      );
    }

    // 2. Admin → acesso direto, sem precisar configurar o tablet
    if (_loggedProfile == OperatorRole.admin) {
      return _buildAccessScreen(
        profile: OperatorRole.admin,
        cameras: cameras,
        identity: identity,
        assignment: assignment,
        faceDatabase: faceDatabase,
        firebaseDatabase: firebaseDatabase,
        faceRecognizer: faceRecognizer,
        doorController: doorController,
        ttsService: ttsService,
        evaluateAccess: evaluateAccess,
      );
    }

    // 3. Porta → precisa configurar unidade se ainda não há assignment.
    // No escopo do PR #6, considera-se "configurado" assim que existe
    // qualquer `TabletAssignment` persistido (doorId ainda é null).
    if (assignment == null) {
      return TabletSetupScreen(
        identity: identity,
        onDone: _onSetupDone,
      );
    }

    // 4. Porta configurado → acesso normal
    return _buildAccessScreen(
      profile: OperatorRole.porta,
      cameras: cameras,
      identity: identity,
      assignment: assignment,
      faceDatabase: faceDatabase,
      firebaseDatabase: firebaseDatabase,
      faceRecognizer: faceRecognizer,
      doorController: doorController,
      ttsService: ttsService,
      evaluateAccess: evaluateAccess,
    );
  }

  AccessScreen _buildAccessScreen({
    required OperatorRole profile,
    required List<CameraDescription> cameras,
    required TabletIdentity identity,
    required TabletAssignment? assignment,
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
      tabletIdentity: identity,
      tabletAssignment: assignment,
      accessLogService: AccessLogService(
        tabletId: identity.id,
        tabletName: identity.name,
        unit: assignment?.locationId ?? '',
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

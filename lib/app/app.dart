import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../application/use_cases/evaluate_access_use_case.dart';
import '../domain/entities/face_embedding.dart';
import '../domain/entities/operator_role.dart';
import '../domain/entities/person.dart';
import '../domain/entities/tablet_assignment.dart';
import '../domain/entities/tablet_identity.dart';
import '../domain/repositories/person_repository.dart';
import '../infrastructure/access_log_service.dart';
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
import 'providers/repository_providers.dart';

/// Raiz da aplicação. Responsável por:
///
/// 1. Materializar o `MaterialApp` e o tema.
/// 2. Aguardar todos os providers de boot (câmeras + infraestrutura) antes
///    de decidir qual tela mostrar.
/// 3. Disparar a sincronização Firestore → `PersonRepository` em background,
///    uma única vez, assim que o boot termina.
/// 4. Preservar o roteamento legado: login → (admin direto | porta →
///    setup? → access).
///
/// PR #7: o sync agora escreve no [PersonRepository] (UUID-keyed). Como
/// o Firestore ainda é keyed por nome (a migração remota é PR #8), o sync
/// faz um lookup name→Person local para preservar/reutilizar o UUID
/// estável das pessoas já conhecidas.
class FaceAccessApp extends ConsumerStatefulWidget {
  const FaceAccessApp({super.key});

  @override
  ConsumerState<FaceAccessApp> createState() => _FaceAccessAppState();
}

class _FaceAccessAppState extends ConsumerState<FaceAccessApp> {
  OperatorRole? _loggedProfile;
  bool _syncStarted = false;
  final Uuid _uuid = const Uuid();

  void _onLogin(OperatorRole profile) =>
      setState(() => _loggedProfile = profile);

  /// Após o setup gravar identity+assignment, a tela invalida os providers
  /// e o rebuild reage automaticamente. Nada a fazer aqui além de forçar
  /// o rebuild caso a árvore esteja ativa (defensivo).
  void _onSetupDone() => setState(() {});

  /// Sincroniza Firestore → `PersonRepository` na inicialização (somente
  /// pessoas da unidade). "Fire and forget": erros são silenciosos e o
  /// app segue operando pelo cache local.
  ///
  /// Estratégia de UUID durante o sync (enquanto o Firestore continuar
  /// keyed por nome, até o PR #8):
  /// - Pessoa já existe localmente com o mesmo `name` → reusa `id` e
  ///   `createdAt`; embeddings/role são atualizados e o `locationId` do
  ///   tablet entra no conjunto `locationIds`.
  /// - Pessoa nova → gera UUID novo, `createdAt = now`, e o `locationId`
  ///   do tablet é o ponto de partida de `locationIds`.
  void _startFirestoreSync({
    required FirebaseDatabase firebaseDatabase,
    required PersonRepository personRepository,
    required String unit,
  }) {
    if (_syncStarted) return;
    _syncStarted = true;
    Future(() async {
      try {
        final remote = await firebaseDatabase.loadAll(
          unit: unit.isNotEmpty ? unit : null,
        );

        final existing = await personRepository.findAll();
        final byName = <String, Person>{
          for (final p in existing) p.name: p,
        };

        for (final entry in remote.entries) {
          final name = entry.key;
          final record = entry.value;
          final prev = byName[name];
          final id = prev?.id ?? _uuid.v4();
          final createdAt = prev?.createdAt ?? DateTime.now().toUtc();
          final locationIds = <String>{
            ...(prev?.locationIds ?? const <String>{}),
            if (unit.isNotEmpty) unit,
          };
          await personRepository.save(
            Person(
              id: id,
              name: name,
              role: record.role,
              locationIds: locationIds,
              embeddings: [
                for (final e in record.embeddings) FaceEmbedding(e),
              ],
              createdAt: createdAt,
            ),
          );
        }
      } catch (_) {
        // Sem conexão — usa cache local do PersonRepository.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cameras = ref.watch(camerasProvider);
    final identity = ref.watch(tabletIdentityProvider);
    final assignment = ref.watch(tabletAssignmentProvider);
    final loginUseCase = ref.watch(loginUseCaseProvider);
    final personRepository = ref.watch(personRepositoryProvider);
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
      personRepository,
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

      _startFirestoreSync(
        firebaseDatabase: firebaseDatabase,
        personRepository: personRepository.requireValue,
        unit: assignmentValue?.locationId ?? '',
      );

      home = _buildHome(
        cameras: cameras.requireValue,
        identity: identityValue,
        assignment: assignmentValue,
        personRepository: personRepository.requireValue,
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
    required PersonRepository personRepository,
    required FirebaseDatabase firebaseDatabase,
    required FaceRecognizer faceRecognizer,
    required MqttDoorController doorController,
    required TtsService ttsService,
    required EvaluateAccessUseCase evaluateAccess,
  }) {
    if (_loggedProfile == null) {
      return LoginScreen(
        identity: identity,
        assignment: assignment,
        onLogin: _onLogin,
      );
    }

    if (_loggedProfile == OperatorRole.admin) {
      return _buildAccessScreen(
        profile: OperatorRole.admin,
        cameras: cameras,
        identity: identity,
        assignment: assignment,
        personRepository: personRepository,
        firebaseDatabase: firebaseDatabase,
        faceRecognizer: faceRecognizer,
        doorController: doorController,
        ttsService: ttsService,
        evaluateAccess: evaluateAccess,
      );
    }

    if (assignment == null) {
      return TabletSetupScreen(
        identity: identity,
        onDone: _onSetupDone,
      );
    }

    return _buildAccessScreen(
      profile: OperatorRole.porta,
      cameras: cameras,
      identity: identity,
      assignment: assignment,
      personRepository: personRepository,
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
    required PersonRepository personRepository,
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
      personRepository: personRepository,
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

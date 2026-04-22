import 'package:faceaccess/application/use_cases/evaluate_access_use_case.dart';
import 'package:faceaccess/domain/entities/access_decision.dart';
import 'package:faceaccess/domain/entities/person.dart';
import 'package:faceaccess/domain/entities/user_role.dart';
import 'package:faceaccess/domain/repositories/person_repository.dart';
import 'package:faceaccess/infrastructure/access_log_service.dart';
import 'package:faceaccess/infrastructure/face_recognizer.dart';
import 'package:faceaccess/infrastructure/mqtt_door_controller.dart';
import 'package:faceaccess/infrastructure/tts_service.dart';
import 'package:faceaccess/presentation/access/access_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AccessController', () {
    late _FakeDoorController doorController;
    late _FakeTtsService ttsService;
    late _FakeAccessLogService accessLogService;
    late DateTime now;
    late AccessController controller;

    setUp(() {
      doorController = _FakeDoorController();
      ttsService = _FakeTtsService();
      accessLogService = _FakeAccessLogService();
      now = DateTime.utc(2026, 4, 21, 8, 0, 0);
      controller = AccessController(
        cameras: const [],
        faceRecognizer: FaceRecognizer(),
        evaluateAccess: EvaluateAccessUseCase(
          personRepository: _NoopPersonRepository(),
        ),
        doorController: doorController,
        ttsService: ttsService,
        accessLogService: accessLogService,
        clock: () => now,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('só autoriza após duas decisões compatíveis na janela', () async {
      final decision = _authorizedDecision('Thiago');

      controller.registerDecision(decision);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.lastDecision, isNull);
      expect(controller.state.overlayVisible, isFalse);
      expect(doorController.openDoorCalls, 0);

      controller.registerDecision(decision);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.lastDecision?.personName, 'Thiago');
      expect(controller.state.lastDecision?.isAuthorized, isTrue);
      expect(controller.state.overlayVisible, isTrue);
      expect(doorController.openDoorCalls, 1);
      expect(ttsService.authorizedAnnouncements, equals(['Thiago']));
      expect(accessLogService.entries.single.personName, 'Thiago');
      expect(accessLogService.entries.single.authorized, isTrue);
      expect(accessLogService.entries.single.role, UserRole.gerente.key);
    });

    test('nega após duas decisões denied e registra log/tts equivalentes',
        () async {
      controller.registerDecision(AccessDecision.denied());
      controller.registerDecision(AccessDecision.denied());
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.lastDecision?.isAuthorized, isFalse);
      expect(controller.state.overlayVisible, isTrue);
      expect(ttsService.deniedCalls, 1);
      expect(accessLogService.entries.single.personName, 'Desconhecido');
      expect(accessLogService.entries.single.authorized, isFalse);
    });

    test('mantém cooldown da porta mesmo quando o overlay pode reaparecer',
        () async {
      final decision = _authorizedDecision('Thiago');

      controller.registerDecision(decision);
      controller.registerDecision(decision);
      await Future<void>.delayed(Duration.zero);
      expect(doorController.openDoorCalls, 1);

      now = now.add(const Duration(seconds: 4));
      controller.registerDecision(decision);
      await Future<void>.delayed(Duration.zero);

      expect(
        doorController.openDoorCalls,
        1,
        reason: 'porta não deve reabrir antes do cooldown de 5s',
      );
      expect(
        ttsService.authorizedAnnouncements,
        equals(['Thiago', 'Thiago']),
        reason:
            'overlay/áudio podem reaparecer após 3s, mantendo o fluxo atual',
      );
    });

    test('oculta overlay no tempo esperado e limpa decisão após o fade', () {
      fakeAsync((async) {
        final decision = _authorizedDecision('Thiago');

        controller.registerDecision(decision);
        controller.registerDecision(decision);
        async.flushMicrotasks();

        expect(controller.state.overlayVisible, isTrue);
        expect(controller.state.lastDecision, isNotNull);

        async.elapse(const Duration(seconds: 4));
        expect(controller.state.overlayVisible, isFalse);
        expect(controller.state.lastDecision, isNotNull);

        async.elapse(const Duration(milliseconds: 400));
        expect(controller.state.lastDecision, isNull);
      });
    });
  });
}

AccessDecision _authorizedDecision(String name) {
  return AccessDecision(
    isAuthorized: true,
    personName: name,
    role: UserRole.gerente,
    confidence: 0.91,
    timestamp: DateTime.utc(2026, 4, 21, 8, 0, 0),
  );
}

class _FakeDoorController implements MqttDoorController {
  int openDoorCalls = 0;
  @override
  bool get isConnected => true;

  @override
  Future<void> connect() async {}

  @override
  Future<void> openDoor() async {
    openDoorCalls++;
  }

  @override
  Future<void> disconnect() async {}
}

class _FakeTtsService implements TtsService {
  final List<String> authorizedAnnouncements = <String>[];
  int deniedCalls = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> announceAuthorized(String personName) async {
    authorizedAnnouncements.add(personName);
  }

  @override
  Future<void> announceDenied() async {
    deniedCalls++;
  }

  @override
  Future<void> announceGreeting(String greeting, String personName) async {
    authorizedAnnouncements.add(personName);
  }

  @override
  Future<void> dispose() async {}
}

class _FakeAccessLogService implements AccessLogService {
  final List<_AccessLogEntry> entries = <_AccessLogEntry>[];

  @override
  String get tabletId => 'tablet-1';

  @override
  String get tabletName => 'Tablet 1';

  @override
  String get locationId => 'araxa';

  @override
  String get doorId => 'porta-principal';

  @override
  Future<void> log({
    required String personName,
    required bool authorized,
    String? role,
  }) async {
    entries.add(
      _AccessLogEntry(
        personName: personName,
        authorized: authorized,
        role: role,
      ),
    );
  }
}

class _AccessLogEntry {
  _AccessLogEntry({
    required this.personName,
    required this.authorized,
    this.role,
  });

  final String personName;
  final bool authorized;
  final String? role;
}

class _NoopPersonRepository implements PersonRepository {
  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<List<Person>> findAll({String? locationId}) async => const <Person>[];

  @override
  Future<Person?> findById(String id) async => null;

  @override
  Future<void> save(Person person) async {}
}

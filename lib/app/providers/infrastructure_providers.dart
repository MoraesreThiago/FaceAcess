import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/use_cases/evaluate_access_use_case.dart';
import '../../domain/entities/tablet_assignment.dart';
import '../../domain/entities/tablet_identity.dart';
import '../../infrastructure/face_recognizer.dart';
import '../../infrastructure/firebase_database.dart';
import '../../infrastructure/mqtt_door_controller.dart';
import '../../infrastructure/tts_service.dart';
import 'repository_providers.dart';

/// Providers que expõem as classes **legadas** de infraestrutura.
///
/// Nenhuma migração de contratos acontece aqui — o objetivo do PR #3 é
/// apenas mover o wiring do `main()` para o Riverpod. Cada provider devolve
/// a instância já inicializada, preservando exatamente o comportamento que
/// existia antes no `main()`.

/// Identidade persistente do tablet (PR #6). Materializada a partir do
/// [tabletConfigRepositoryProvider]. Imutável após o primeiro boot —
/// invalidar só é necessário depois que o operador renomeia o tablet
/// via [TabletSetupScreen].
final tabletIdentityProvider = FutureProvider<TabletIdentity>((ref) async {
  final repo = await ref.watch(tabletConfigRepositoryProvider.future);
  return repo.getOrCreateIdentity();
});

/// Atribuição atual do tablet (unidade / porta). `null` indica que o
/// tablet ainda não passou pelo setup. Invalidado pelo setup após salvar.
final tabletAssignmentProvider =
    FutureProvider<TabletAssignment?>((ref) async {
  final repo = await ref.watch(tabletConfigRepositoryProvider.future);
  return repo.getAssignment();
});

final firebaseDatabaseProvider = Provider<FirebaseDatabase>((ref) {
  return FirebaseDatabase();
});

final faceRecognizerProvider = FutureProvider<FaceRecognizer>((ref) async {
  final recognizer = FaceRecognizer();
  await recognizer.initialize();
  return recognizer;
});

final doorControllerProvider = Provider<MqttDoorController>((ref) {
  return MqttDoorController();
});

final ttsServiceProvider = FutureProvider<TtsService>((ref) async {
  final tts = TtsService();
  await tts.initialize();
  return tts;
});

final evaluateAccessUseCaseProvider =
    FutureProvider<EvaluateAccessUseCase>((ref) async {
  final personRepository = await ref.watch(personRepositoryProvider.future);
  return EvaluateAccessUseCase(personRepository: personRepository);
});

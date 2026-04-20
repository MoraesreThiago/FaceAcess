import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/use_cases/evaluate_access_use_case.dart';
import '../../infrastructure/auth_service.dart';
import '../../infrastructure/face_database.dart';
import '../../infrastructure/face_recognizer.dart';
import '../../infrastructure/firebase_database.dart';
import '../../infrastructure/mqtt_door_controller.dart';
import '../../infrastructure/tablet_config.dart';
import '../../infrastructure/tts_service.dart';

/// Providers que expõem as classes **legadas** de infraestrutura.
///
/// Nenhuma migração de contratos acontece aqui — o objetivo do PR #3 é
/// apenas mover o wiring do `main()` para o Riverpod. Cada provider devolve
/// a instância já inicializada, preservando exatamente o comportamento que
/// existia antes no `main()`.

final tabletConfigProvider = FutureProvider<TabletConfig>((ref) async {
  final config = TabletConfig();
  await config.initialize();
  return config;
});

final authServiceProvider = FutureProvider<AuthService>((ref) async {
  final service = AuthService();
  await service.initialize();
  return service;
});

final faceDatabaseProvider = FutureProvider<FaceDatabase>((ref) async {
  final database = FaceDatabase();
  await database.initialize();
  return database;
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
  final faceDatabase = await ref.watch(faceDatabaseProvider.future);
  return EvaluateAccessUseCase(faceDatabase: faceDatabase);
});

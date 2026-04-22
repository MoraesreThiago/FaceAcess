import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/person_repository.dart';
import '../../domain/repositories/tablet_config_repository.dart';
import '../../infrastructure/auth/shared_prefs_auth_repository.dart';
import '../../infrastructure/persistence/hive/hive_person_repository.dart';
import '../../infrastructure/tablet/shared_prefs_tablet_config_repository.dart';

/// Providers que expõem **contratos de domínio** em cima das implementações
/// concretas de infraestrutura.

/// Autenticação usa [SharedPrefsAuthRepository] (ver PR #4).
final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final repository = SharedPrefsAuthRepository(prefs);
  await repository.ensureDefaults();
  return repository;
});

/// Identidade e atribuição do tablet (PR #6). O `initialize()` roda a
/// migração legada do antigo `TabletConfig` e garante que exista uma
/// `TabletIdentity` persistida antes de qualquer leitura.
final tabletConfigRepositoryProvider =
    FutureProvider<TabletConfigRepository>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final repository = SharedPrefsTabletConfigRepository(prefs);
  await repository.initialize();
  return repository;
});

/// Pessoas cadastradas (PR #7). Substitui o antigo `FaceDatabase` local
/// e usa `Person.id` (UUID) como chave estável. O `initialize()` roda a
/// migração idempotente da box legada `face_embeddings_v2` para a nova
/// `people_v2`, preservando a legada para rollback.
final personRepositoryProvider = FutureProvider<PersonRepository>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final repository = HivePersonRepository(prefs: prefs);
  await repository.initialize();
  return repository;
});

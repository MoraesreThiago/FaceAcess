import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/auth_repository.dart';
import '../../infrastructure/auth/_legacy_auth_repository_adapter.dart';
import 'infrastructure_providers.dart';

/// Providers que expõem **contratos de domínio** usando as implementações
/// legadas por trás de adaptadores.
///
/// No PR #3 apenas [authRepositoryProvider] existe, e ainda não é consumido
/// por nenhuma tela — ele materializa o fio de ligação `AuthService →
/// AuthRepository` para validar o contrato. Os demais repositórios
/// (`FaceRecognitionRepository`, `DoorController` de domínio,
/// `TabletAssignmentRepository`, etc.) serão adicionados nos PRs seguintes,
/// conforme cada tela for migrada.
final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final authService = await ref.watch(authServiceProvider.future);
  return LegacyAuthRepositoryAdapter(authService);
});

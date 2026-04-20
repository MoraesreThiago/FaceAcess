import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/use_cases/login_use_case.dart';
import 'repository_providers.dart';

/// Providers da camada de **application** (casos de uso).
///
/// Cada use case é montado a partir dos repositórios de domínio expostos
/// em `repository_providers.dart` — a camada de aplicação não conhece
/// implementações concretas.
final loginUseCaseProvider = FutureProvider<LoginUseCase>((ref) async {
  final authRepository = await ref.watch(authRepositoryProvider.future);
  return LoginUseCase(authRepository: authRepository);
});

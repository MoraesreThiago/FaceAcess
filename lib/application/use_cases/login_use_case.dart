import '../../domain/entities/operator_role.dart';
import '../../domain/errors/failures.dart';
import '../../domain/repositories/auth_repository.dart';
import '../result.dart';

/// Autenticação local de operador (admin/porta).
///
/// Regras:
/// - Senha válida → `Success(role)`.
/// - Senha inválida → `Err(AuthFailure.invalidPassword)`.
/// - Falha inesperada no repositório (I/O, SharedPreferences corrompido…)
///   → `Err(PersistenceFailure(...))`. Exceções não vazam para a UI.
class LoginUseCase {
  LoginUseCase({required AuthRepository authRepository})
      : _authRepository = authRepository;

  final AuthRepository _authRepository;

  Future<Result<OperatorRole>> call({
    required OperatorRole role,
    required String password,
  }) async {
    try {
      final valid = await _authRepository.validate(role, password);
      if (!valid) {
        return const Err(AuthFailure.invalidPassword);
      }
      return Success(role);
    } catch (e) {
      return Err(PersistenceFailure('Falha ao validar senha: $e'));
    }
  }
}

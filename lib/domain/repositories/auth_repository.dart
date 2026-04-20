import '../entities/operator_role.dart';

/// Contrato de autenticação local para os perfis do app (admin/porta).
///
/// Implementação inicial (Fase 4) será sobre SharedPreferences + SHA-256,
/// preservando o formato atual das senhas. Implementações futuras podem
/// migrar para Firebase Auth, HTTP, etc., sem tocar no domínio.
abstract class AuthRepository {
  Future<bool> validate(OperatorRole role, String password);

  Future<void> changePassword(OperatorRole role, String newPassword);
}

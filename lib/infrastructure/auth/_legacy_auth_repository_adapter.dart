import '../../domain/entities/operator_role.dart';
import '../../domain/repositories/auth_repository.dart';
import '../auth_service.dart';

/// Adaptador temporário que expõe o legado [AuthService] através do contrato
/// de domínio [AuthRepository].
///
/// Escopo PR #3: **não** é usado por nenhum código de produção ainda — o
/// objetivo é apenas provar que o contrato de domínio encaixa no serviço
/// legado. A migração real (`LoginScreen` passar a consumir `AuthRepository`)
/// fica para o PR #4.
///
/// Prefixo `_legacy_` no arquivo sinaliza que esta classe é efêmera e será
/// removida quando `AuthService` for substituído por uma implementação que
/// já nasça contra `AuthRepository`.
class LegacyAuthRepositoryAdapter implements AuthRepository {
  LegacyAuthRepositoryAdapter(this._service);

  final AuthService _service;

  @override
  Future<bool> validate(OperatorRole role, String password) async {
    switch (role) {
      case OperatorRole.admin:
        return _service.validateAdmin(password);
      case OperatorRole.porta:
        return _service.validatePorta(password);
    }
  }

  @override
  Future<void> changePassword(OperatorRole role, String newPassword) async {
    switch (role) {
      case OperatorRole.admin:
        await _service.changeAdminPassword(newPassword);
        break;
      case OperatorRole.porta:
        await _service.changePortaPassword(newPassword);
        break;
    }
  }
}

/// Papel de operação do app/tablet.
///
/// Diferente de [UserRole] (que descreve o cargo da pessoa cadastrada
/// no sistema de controle de acesso), [OperatorRole] descreve quem está
/// **operando o tablet** no momento:
///
/// - [admin]: responsável por cadastros e gerenciamento;
/// - [porta]: tablet rodando em modo de reconhecimento na portaria.
enum OperatorRole {
  admin,
  porta,
}

extension OperatorRoleX on OperatorRole {
  String get label {
    switch (this) {
      case OperatorRole.admin:
        return 'Administrador';
      case OperatorRole.porta:
        return 'Acesso - Porta';
    }
  }

  String get key => name;

  static OperatorRole fromKey(String key) {
    return OperatorRole.values.firstWhere(
      (r) => r.name == key,
      orElse: () => OperatorRole.porta,
    );
  }
}

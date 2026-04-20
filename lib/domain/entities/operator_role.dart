/// Papel de operação do app/tablet.
///
/// Diferente de [UserRole] (que descreve o cargo da pessoa cadastrada
/// no sistema de controle de acesso), [OperatorRole] descreve quem está
/// **operando o tablet** no momento:
///
/// - [admin]: responsável por cadastros e gerenciamento;
/// - [porta]: tablet rodando em modo de reconhecimento na portaria.
///
/// Criado neste PR para ser usado a partir da Fase 5, quando substituirá
/// gradualmente o atual `UserProfile`. Intencionalmente ainda não é
/// referenciado por nenhum código legado.
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

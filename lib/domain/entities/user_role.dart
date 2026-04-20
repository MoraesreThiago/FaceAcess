import 'package:flutter/material.dart';

enum UserRole {
  admin,
  diretor,
  gerente,
  supervisor,
  lider,
  manutentor,
  operador,
}

extension UserRoleExtension on UserRole {
  String get label {
    switch (this) {
      case UserRole.admin:        return 'Administrador';
      case UserRole.diretor:      return 'Diretor';
      case UserRole.gerente:      return 'Gerente';
      case UserRole.supervisor:   return 'Supervisor';
      case UserRole.lider:        return 'Líder';
      case UserRole.manutentor:   return 'Manutentor';
      case UserRole.operador:     return 'Operador';
    }
  }

  Color get color {
    switch (this) {
      case UserRole.admin:        return const Color(0xFF9C27B0); // roxo
      case UserRole.diretor:      return const Color(0xFFFFD700); // ouro
      case UserRole.gerente:      return const Color(0xFFFF6F00); // laranja
      case UserRole.supervisor:   return const Color(0xFF1565C0); // azul
      case UserRole.lider:        return const Color(0xFF00838F); // ciano
      case UserRole.manutentor:   return const Color(0xFF00695C); // teal
      case UserRole.operador:     return const Color(0xFF2E7D32); // verde
    }
  }

  IconData get icon {
    switch (this) {
      case UserRole.admin:        return Icons.admin_panel_settings;
      case UserRole.diretor:      return Icons.star;
      case UserRole.gerente:      return Icons.business_center;
      case UserRole.supervisor:   return Icons.supervisor_account;
      case UserRole.lider:        return Icons.group;
      case UserRole.manutentor:   return Icons.build;
      case UserRole.operador:     return Icons.engineering;
    }
  }

  String get key => name;

  static UserRole fromKey(String key) {
    return UserRole.values.firstWhere(
      (r) => r.name == key,
      orElse: () => UserRole.operador,
    );
  }
}

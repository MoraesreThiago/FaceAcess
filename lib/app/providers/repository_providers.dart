import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/auth_repository.dart';
import '../../infrastructure/auth/shared_prefs_auth_repository.dart';

/// Providers que expõem **contratos de domínio** em cima das implementações
/// concretas de infraestrutura.
///
/// Autenticação usa [SharedPrefsAuthRepository] — substitui o adaptador
/// legado do PR #3 (já removido). Mantém exatamente as mesmas chaves,
/// hash e senhas padrão do antigo `AuthService`, então tablets já em uso
/// continuam fazendo login sem nenhum reset.
final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final repository = SharedPrefsAuthRepository(prefs);
  await repository.ensureDefaults();
  return repository;
});

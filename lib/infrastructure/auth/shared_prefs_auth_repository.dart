import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/operator_role.dart';
import '../../domain/repositories/auth_repository.dart';

/// Implementação real de [AuthRepository] sobre [SharedPreferences].
///
/// **Compatibilidade com o estado legado**: preserva *exatamente* as mesmas
/// chaves, o mesmo algoritmo de hash (SHA-256) e as mesmas senhas padrão
/// que o antigo `AuthService` usava. Isso garante que tablets já em uso
/// continuem fazendo login sem nenhum reset manual.
///
/// - Chaves:
///   - admin → `auth_admin_hash`
///   - porta → `auth_porta_hash`
/// - Hash: `sha256(utf8(password))`, serializado como hex.
/// - Senhas padrão (1ª execução): `admin123` / `porta123`.
class SharedPrefsAuthRepository implements AuthRepository {
  SharedPrefsAuthRepository(this._prefs);

  final SharedPreferences _prefs;

  // Mantidas iguais ao `AuthService` legado para compatibilidade.
  static const String _adminHashKey = 'auth_admin_hash';
  static const String _portaHashKey = 'auth_porta_hash';

  static const String defaultAdminPass = 'admin123';
  static const String defaultPortaPass = 'porta123';

  /// Garante que as senhas padrão existam na primeira execução.
  /// **Não sobrescreve** hashes já definidos — idempotente.
  Future<void> ensureDefaults() async {
    if (!_prefs.containsKey(_adminHashKey)) {
      await _prefs.setString(_adminHashKey, _hash(defaultAdminPass));
    }
    if (!_prefs.containsKey(_portaHashKey)) {
      await _prefs.setString(_portaHashKey, _hash(defaultPortaPass));
    }
  }

  @override
  Future<bool> validate(OperatorRole role, String password) async {
    final stored = _prefs.getString(_keyFor(role));
    if (stored == null) return false;
    return stored == _hash(password);
  }

  @override
  Future<void> changePassword(OperatorRole role, String newPassword) async {
    await _prefs.setString(_keyFor(role), _hash(newPassword));
  }

  String _keyFor(OperatorRole role) {
    switch (role) {
      case OperatorRole.admin:
        return _adminHashKey;
      case OperatorRole.porta:
        return _portaHashKey;
    }
  }

  String _hash(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }
}

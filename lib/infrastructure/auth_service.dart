import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gerencia autenticação por senha para os perfis Admin e Porta.
/// Senhas são armazenadas como hash SHA-256 no SharedPreferences.
class AuthService {
  static const _adminHashKey = 'auth_admin_hash';
  static const _portaHashKey = 'auth_porta_hash';

  // Senhas padrão (primeira execução)
  static const defaultAdminPass = 'admin123';
  static const defaultPortaPass = 'porta123';

  late SharedPreferences _prefs;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    // Define senhas padrão se ainda não foram configuradas
    if (!_prefs.containsKey(_adminHashKey)) {
      await _prefs.setString(_adminHashKey, _hash(defaultAdminPass));
    }
    if (!_prefs.containsKey(_portaHashKey)) {
      await _prefs.setString(_portaHashKey, _hash(defaultPortaPass));
    }
  }

  String _hash(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  bool validateAdmin(String password) =>
      _prefs.getString(_adminHashKey) == _hash(password);

  bool validatePorta(String password) =>
      _prefs.getString(_portaHashKey) == _hash(password);

  Future<void> changeAdminPassword(String newPassword) async =>
      _prefs.setString(_adminHashKey, _hash(newPassword));

  Future<void> changePortaPassword(String newPassword) async =>
      _prefs.setString(_portaHashKey, _hash(newPassword));
}

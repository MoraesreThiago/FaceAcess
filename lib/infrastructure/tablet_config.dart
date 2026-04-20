import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Armazena identidade persistente do tablet (nome, unidade, ID único).
class TabletConfig {
  static const String _keyId = 'tablet_id';
  static const String _keyName = 'tablet_name';
  static const String _keyUnit = 'tablet_unit';

  late String id;
  late String name;
  late String unit;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    // Gera ID único na primeira vez
    String? storedId = prefs.getString(_keyId);
    if (storedId == null) {
      storedId = const Uuid().v4();
      await prefs.setString(_keyId, storedId);
    }
    id = storedId;
    name = prefs.getString(_keyName) ?? 'Tablet';
    unit = prefs.getString(_keyUnit) ?? '';
  }

  Future<void> save({required String name, required String unit}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, name);
    await prefs.setString(_keyUnit, unit);
    this.name = name;
    this.unit = unit;
  }

  bool get isConfigured => unit.isNotEmpty && name.isNotEmpty;
}

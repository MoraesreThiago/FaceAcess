import 'package:hive_flutter/hive_flutter.dart';

import '../domain/entities/user_role.dart';
import '../domain/repositories/face_database_repository.dart';

/// Record stored per person in Hive:
/// { 'role': 'operador', 'embeddings': [[...], [...]] }
class FaceDatabase implements FaceDatabaseRepository {
  static const String _boxName = 'face_embeddings_v2';
  Box? _box;

  Future<void> initialize() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
  }

  @override
  Future<void> savePerson(
    String name,
    List<List<double>> embeddings, {
    UserRole role = UserRole.operador,
  }) async {
    await _box!.put(name, {
      'role': role.key,
      'embeddings': embeddings.map((e) => e.toList()).toList(),
    });
  }

  @override
  Future<Map<String, PersonRecord>> loadAll() async {
    final result = <String, PersonRecord>{};
    for (final key in _box!.keys) {
      final raw = _box!.get(key);
      if (raw is Map) {
        final roleKey = raw['role'] as String? ?? 'operador';
        final embRaw = raw['embeddings'];
        if (embRaw is List) {
          final embeddings = embRaw
              .map((row) =>
                  (row as List).map((v) => (v as num).toDouble()).toList())
              .toList();
          result[key.toString()] = PersonRecord(
            role: UserRoleExtension.fromKey(roleKey),
            embeddings: embeddings,
          );
        }
      }
    }
    return result;
  }

  @override
  Future<void> deletePerson(String name) async => _box!.delete(name);

  @override
  Future<List<String>> listPersons() async =>
      _box!.keys.map((k) => k.toString()).toList();

  void close() => _box?.close();
}

class PersonRecord {
  final UserRole role;
  final List<List<double>> embeddings;
  const PersonRecord({required this.role, required this.embeddings});
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/entities/user_role.dart';

/// DTO interno do sync remoto.
///
/// Até o PR #6 este tipo vivia em `face_database.dart`. Foi movido para
/// cá no PR #7 porque o `FaceDatabase` legado foi removido e esta classe
/// continua sendo o "envelope de leitura" do Firestore. A redesenhagem
/// do lado remoto (Firestore keyed por UUID, com sync bidirecional)
/// é escopo do PR #8 — nada foi alterado aqui além do necessário para
/// o código compilar sem o `FaceDatabase`.
class PersonRecord {
  final UserRole role;
  final List<List<double>> embeddings;
  const PersonRecord({required this.role, required this.embeddings});
}

/// Sincroniza pessoas com o Firestore.
/// Embeddings são salvos como Map<String, List<double>> porque o Firestore
/// não suporta arrays aninhados (List<List<double>>).
class FirebaseDatabase {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'people';

  /// Salva ou atualiza uma pessoa no Firestore.
  Future<void> savePerson(
    String name,
    List<List<double>> embeddings, {
    UserRole role = UserRole.operador,
    List<String> allowedUnits = const [],
  }) async {
    // Converte List<List<double>> → Map{'0': [...], '1': [...], ...}
    // para contornar a limitação do Firestore com arrays aninhados.
    final embMap = <String, List<double>>{
      for (int i = 0; i < embeddings.length; i++) '$i': embeddings[i],
    };

    await _db.collection(_collection).doc(name).set({
      'name': name,
      'role': role.key,
      'embeddings': embMap,
      'allowedUnits': allowedUnits,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Carrega todas as pessoas (com cache offline automático do Firestore).
  Future<Map<String, PersonRecord>> loadAll({String? unit}) async {
    final result = <String, PersonRecord>{};
    try {
      Query query = _db.collection(_collection);
      if (unit != null && unit.isNotEmpty) {
        query = query.where('allowedUnits', arrayContains: unit);
      }
      final snapshot = await query.get(
        const GetOptions(source: Source.serverAndCache),
      );
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final embeddings = _parseEmbeddings(data['embeddings']);
        if (embeddings == null) continue;
        final roleKey = data['role'] as String? ?? 'operador';
        result[doc.id] = PersonRecord(
          role: UserRoleExtension.fromKey(roleKey),
          embeddings: embeddings,
        );
      }
    } catch (_) {
      // Offline: Firestore retorna cache automaticamente
    }
    return result;
  }

  /// Remove uma pessoa do Firestore.
  Future<void> deletePerson(String name) async {
    await _db.collection(_collection).doc(name).delete();
  }

  /// Stream em tempo real — notifica quando a lista muda.
  Stream<Map<String, PersonRecord>> watchAll({String? unit}) {
    Query query = _db.collection(_collection);
    if (unit != null && unit.isNotEmpty) {
      query = query.where('allowedUnits', arrayContains: unit);
    }
    return query.snapshots().map((snapshot) {
      final result = <String, PersonRecord>{};
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final embeddings = _parseEmbeddings(data['embeddings']);
        if (embeddings == null) continue;
        final roleKey = data['role'] as String? ?? 'operador';
        result[doc.id] = PersonRecord(
          role: UserRoleExtension.fromKey(roleKey),
          embeddings: embeddings,
        );
      }
      return result;
    });
  }

  /// Converte o campo embeddings do Firestore de volta para List<List<double>>.
  /// Suporta o formato Map {'0': [...], '1': [...]} usado atualmente.
  List<List<double>>? _parseEmbeddings(dynamic raw) {
    if (raw == null) return null;

    if (raw is Map) {
      // Formato atual: {'0': [...], '1': [...]}
      final entries = raw.entries.toList()
        ..sort((a, b) {
          final ia = int.tryParse(a.key.toString()) ?? 0;
          final ib = int.tryParse(b.key.toString()) ?? 0;
          return ia.compareTo(ib);
        });
      return entries.map((e) {
        final row = e.value as List<dynamic>;
        return row.map((v) => (v as num).toDouble()).toList();
      }).toList();
    }

    if (raw is List) {
      // Formato legado (caso existam docs antigos no Firestore)
      try {
        return raw
            .map((row) =>
                (row as List<dynamic>).map((v) => (v as num).toDouble()).toList())
            .toList();
      } catch (_) {
        return null;
      }
    }

    return null;
  }
}

import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/entities/face_embedding.dart';
import '../../../domain/entities/person.dart';
import '../../../domain/entities/user_role.dart';
import '../../../domain/repositories/person_repository.dart';

/// Implementação real de [PersonRepository] sobre Hive.
///
/// **Estrutura (nova, a partir do PR #7)**
///   Box .............. `people_v2`
///   Chave ............ `Person.id` (UUID v4, estável)
///   Valor ............ Map com a seguinte forma:
///                       {
///                         'id'         : String,
///                         'name'       : String,
///                         'roleKey'    : String,         // UserRole.key
///                         'locationIds': List<String>,
///                         'embeddings' : List<List<double>>,
///                         'createdAt'  : int (millis UTC)
///                       }
///
/// **Estrutura (legada, preservada para rollback)**
///   Box .............. `face_embeddings_v2`
///   Chave ............ `Person.name` (frágil — colisão de homônimos)
///   Valor ............ { 'role': String, 'embeddings': List<List<double>> }
///
/// **Migração (idempotente)**
/// - Flag em SharedPreferences: `people_repo_migrated_v1`.
/// - `initialize()` abre a box nova, e, se a flag não estiver setada e
///   a box legada existir, lê cada registro legado, gera um UUID novo
///   e grava uma `Person` correspondente na box nova. A box legada
///   **não é apagada** — serve de rede de rollback nesta fase.
/// - Registros legados cujo nome já existe na box nova (idempotência
///   de segunda linha, caso a flag tenha sido manualmente removida)
///   são ignorados, evitando sobrescrever embeddings atualizados.
/// - `locationIds` dos registros migrados nasce **vazio**: a box legada
///   não tinha essa informação. A sincronização Firestore → Hive
///   (em `app.dart`) e futuros PRs hidratam o campo conforme a pessoa
///   é vista em cada unidade.
///
/// **Não faz parte deste PR**: migração remota (Firestore), seleção de
/// porta, mudança na lógica de reconhecimento ou UI de gestão. Tudo
/// isso é tratado em PRs posteriores.
class HivePersonRepository implements PersonRepository {
  HivePersonRepository({
    required SharedPreferences prefs,
    Uuid? uuid,
  })  : _prefs = prefs,
        _uuid = uuid ?? const Uuid();

  // ── Constantes (públicas para uso em testes/diagnóstico) ───────────
  static const String legacyBoxName = 'face_embeddings_v2';
  static const String personsBoxName = 'people_v2';
  static const String migrationFlagKey = 'people_repo_migrated_v1';

  final SharedPreferences _prefs;
  final Uuid _uuid;

  Box<dynamic>? _box;

  /// Inicializa Hive, abre a box nova e executa a migração legada
  /// (idempotente). Deve ser chamado antes de qualquer leitura/escrita.
  ///
  /// [hiveHomeDir] é uma **hook de testes**: em produção deixe `null`
  /// para usar `Hive.initFlutter()` (que resolve o diretório via
  /// `path_provider`). Em testes, passe um diretório temporário para
  /// bypassar o plugin.
  Future<void> initialize({String? hiveHomeDir}) async {
    if (hiveHomeDir != null) {
      Hive.init(hiveHomeDir);
    } else {
      await Hive.initFlutter();
    }
    _box = await Hive.openBox<dynamic>(personsBoxName);
    await _migrateLegacyIfNeeded();
  }

  Future<void> _migrateLegacyIfNeeded() async {
    if (_prefs.getBool(migrationFlagKey) == true) return;

    final legacyExists = await Hive.boxExists(legacyBoxName);
    if (!legacyExists) {
      await _prefs.setBool(migrationFlagKey, true);
      return;
    }

    final legacy = await Hive.openBox<dynamic>(legacyBoxName);
    try {
      // Set de nomes já presentes na box nova (belt-and-suspenders
      // contra flag removida manualmente).
      final existingNames = <String>{};
      for (final key in _box!.keys) {
        final raw = _box!.get(key);
        if (raw is Map && raw['name'] is String) {
          existingNames.add(raw['name'] as String);
        }
      }

      for (final key in legacy.keys) {
        final name = key.toString();
        if (existingNames.contains(name)) continue;

        final raw = legacy.get(key);
        if (raw is! Map) continue;

        final roleKey = raw['role'] as String? ?? 'operador';
        final embRaw = raw['embeddings'];
        if (embRaw is! List) continue;

        final embeddings = <List<double>>[];
        for (final row in embRaw) {
          if (row is List) {
            embeddings.add(
              row.map((v) => (v as num).toDouble()).toList(growable: false),
            );
          }
        }
        if (embeddings.isEmpty) continue;

        final person = Person(
          id: _uuid.v4(),
          name: name,
          role: UserRoleExtension.fromKey(roleKey),
          locationIds: const <String>{},
          embeddings: [for (final e in embeddings) FaceEmbedding(e)],
          createdAt: DateTime.now().toUtc(),
        );
        await _box!.put(person.id, _encode(person));
      }
    } finally {
      await legacy.close();
    }

    await _prefs.setBool(migrationFlagKey, true);
  }

  // ── PersonRepository ────────────────────────────────────────────────

  @override
  Future<void> save(Person person) async {
    _ensureOpen();
    await _box!.put(person.id, _encode(person));
  }

  @override
  Future<Person?> findById(String id) async {
    _ensureOpen();
    return _decode(_box!.get(id));
  }

  @override
  Future<List<Person>> findAll({String? locationId}) async {
    _ensureOpen();
    final result = <Person>[];
    for (final key in _box!.keys) {
      final person = _decode(_box!.get(key));
      if (person == null) continue;
      if (locationId != null && !person.locationIds.contains(locationId)) {
        continue;
      }
      result.add(person);
    }
    return result;
  }

  @override
  Future<void> deleteById(String id) async {
    _ensureOpen();
    await _box!.delete(id);
  }

  // ── Serialização ────────────────────────────────────────────────────

  Map<String, dynamic> _encode(Person p) => {
        'id': p.id,
        'name': p.name,
        'roleKey': p.role.key,
        'locationIds': p.locationIds.toList(growable: false),
        'embeddings': [
          for (final e in p.embeddings) List<double>.from(e.values),
        ],
        'createdAt': p.createdAt.millisecondsSinceEpoch,
      };

  Person? _decode(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || name is! String) return null;

    final roleKey = raw['roleKey'] as String? ?? 'operador';
    final locationIds = <String>{};
    final rawLocs = raw['locationIds'];
    if (rawLocs is List) {
      for (final l in rawLocs) {
        locationIds.add(l.toString());
      }
    }

    final embRaw = raw['embeddings'];
    final embeddings = <FaceEmbedding>[];
    if (embRaw is List) {
      for (final row in embRaw) {
        if (row is List) {
          embeddings.add(
            FaceEmbedding(
              row.map((v) => (v as num).toDouble()).toList(growable: false),
            ),
          );
        }
      }
    }

    final createdAtMs = raw['createdAt'];
    final createdAt = createdAtMs is int
        ? DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true)
        : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    return Person(
      id: id,
      name: name,
      role: UserRoleExtension.fromKey(roleKey),
      locationIds: locationIds,
      embeddings: embeddings,
      createdAt: createdAt,
    );
  }

  void _ensureOpen() {
    if (_box == null) {
      throw StateError(
        'HivePersonRepository não foi inicializado. Chame initialize() '
        'antes de qualquer operação de leitura/escrita.',
      );
    }
  }
}

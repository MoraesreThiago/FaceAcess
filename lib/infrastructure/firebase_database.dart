import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../domain/entities/face_embedding.dart';
import '../domain/entities/person.dart';
import '../domain/entities/user_role.dart';
import '../domain/repositories/person_repository.dart';

/// Snapshot remoto com metadados de sincronização.
class RemotePersonSnapshot {
  final Person person;
  final DateTime? updatedAt;
  final String documentId;
  final bool isLegacy;

  const RemotePersonSnapshot({
    required this.person,
    required this.updatedAt,
    required this.documentId,
    required this.isLegacy,
  });
}

/// Sincroniza pessoas com o Firestore.
///
/// A coleção `people` agora é keyed por `Person.id` (UUID). Documentos
/// legados keyed por nome continuam legíveis nesta fase para permitir a
/// migração remota idempotente sem bloquear tablets que já estejam em campo.
///
/// Embeddings são salvos como `Map<String, List<double>>` porque o Firestore
/// não suporta arrays aninhados (`List<List<double>>`).
class FirebaseDatabase {
  FirebaseDatabase({
    FirebaseFirestore? firestore,
    Uuid? uuid,
    DateTime Function()? clock,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? _defaultClock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  final FirebaseFirestore _db;
  final Uuid _uuid;
  final DateTime Function() _clock;

  static const String _collection = 'people';
  static const String _metaCollection = '_meta';
  static const String _migrationsDoc = 'migrations';
  static const String _migrationFlagKey = 'people_v1_to_v2';
  static const String _legacyIdNamespace = 'faceaccess/people/legacy-name';

  CollectionReference<Map<String, dynamic>> get _people =>
      _db.collection(_collection);

  /// Salva ou atualiza uma pessoa no Firestore usando `Person.id` como
  /// chave estável.
  Future<void> savePerson(Person person) async {
    await _people.doc(person.id).set(_encodePerson(person));
  }

  /// Remove uma pessoa do Firestore pelo UUID.
  Future<void> deletePerson(String id) async {
    await _people.doc(id).delete();
  }

  /// Carrega todas as pessoas keyed por UUID.
  Future<Map<String, Person>> loadAll({String? locationId}) async {
    final snapshots = await loadAllSnapshots(locationId: locationId);
    return {
      for (final entry in snapshots.entries) entry.key: entry.value.person,
    };
  }

  /// Stream em tempo real keyed por UUID.
  Stream<Map<String, Person>> watchAll({String? locationId}) {
    return _queryPeople(locationId: locationId).snapshots().map((snapshot) {
      final result = <String, Person>{};
      for (final doc in snapshot.docs) {
        final parsed = _parseRemoteDoc(doc);
        if (parsed == null || !_matchesLocation(parsed.person, locationId)) {
          continue;
        }
        result[parsed.person.id] = parsed.person;
      }
      return result;
    });
  }

  /// Carrega snapshots remotos completos, incluindo `updatedAt`.
  Future<Map<String, RemotePersonSnapshot>> loadAllSnapshots({
    String? locationId,
    Iterable<Person> localPeople = const <Person>[],
  }) async {
    final result = <String, RemotePersonSnapshot>{};
    final localByName = {
      for (final person in localPeople) person.name: person,
    };

    try {
      final snapshot = await _queryPeople(locationId: locationId).get(
        const GetOptions(source: Source.serverAndCache),
      );

      for (final doc in snapshot.docs) {
        final parsed = _parseRemoteDoc(
          doc,
          localMatch: localByName[_readName(doc)],
        );
        if (parsed == null || !_matchesLocation(parsed.person, locationId)) {
          continue;
        }

        final existing = result[parsed.person.id];
        if (existing == null || _preferOver(existing, parsed)) {
          result[parsed.person.id] = parsed;
        }
      }
    } catch (_) {
      // Offline: Firestore retorna cache automaticamente quando disponível.
    }

    return result;
  }

  /// Migra docs legados keyed por nome para o formato keyed por UUID.
  ///
  /// - O doc antigo é preservado e marcado com `migrated: true`.
  /// - A flag global fica em `/_meta/migrations`.
  /// - Quando existe pessoa local com o mesmo nome, o UUID local é
  ///   reaproveitado.
  /// - Sem match local, usa UUID determinístico por nome para evitar
  ///   duplicação entre tablets diferentes durante a janela de migração.
  Future<void> migrateRemoteIfNeeded({
    Iterable<Person> localPeople = const <Person>[],
  }) async {
    final migrationsRef = _db.collection(_metaCollection).doc(_migrationsDoc);

    try {
      final metaSnapshot = await migrationsRef.get(
        const GetOptions(source: Source.serverAndCache),
      );
      final meta = metaSnapshot.data();
      if (meta != null && meta[_migrationFlagKey] == true) {
        return;
      }
    } catch (_) {
      // Se o metadata não puder ser lido agora, seguimos tentando migrar.
    }

    final localByName = {
      for (final person in localPeople) person.name: person,
    };

    bool hadUnprocessedLegacyDoc = false;

    try {
      final snapshot = await _people.get(
        const GetOptions(source: Source.serverAndCache),
      );

      for (final doc in snapshot.docs) {
        if (_isUuidKeyedDoc(doc) || _isMigratedLegacyDoc(doc)) {
          continue;
        }

        final parsed = _parseRemoteDoc(
          doc,
          localMatch: localByName[_readName(doc)],
        );
        if (parsed == null) {
          hadUnprocessedLegacyDoc = true;
          continue;
        }

        await _people.doc(parsed.person.id).set(_encodePerson(parsed.person));
        await doc.reference.set(
          {
            'migrated': true,
            'migratedTo': parsed.person.id,
            'migratedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (_) {
      // Offline: a migração remota fica para a próxima oportunidade.
      return;
    }

    if (!hadUnprocessedLegacyDoc) {
      await migrationsRef.set(
        {
          _migrationFlagKey: true,
          'migratedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

  /// Reconcilia o Firestore com o [PersonRepository] local.
  ///
  /// Enquanto o domínio ainda não carrega um `updatedAt` próprio, usamos
  /// `Person.createdAt` como carimbo local mais recente. Isso é suficiente
  /// para o estado atual do app, no qual a UI cria/remove pessoas, mas ainda
  /// não existe fluxo de edição manual de cadastro.
  Future<void> synchronize({
    required PersonRepository personRepository,
    String? locationId,
  }) async {
    final normalizedLocationId = _normalizeLocationId(locationId);
    final localPeople = await personRepository.findAll();

    await migrateRemoteIfNeeded(localPeople: localPeople);

    final remoteSnapshots = await loadAllSnapshots(
      locationId: normalizedLocationId,
      localPeople: localPeople,
    );

    final localById = {
      for (final person in localPeople) person.id: person,
    };
    final localByName = {
      for (final person in localPeople) person.name: person,
    };
    final remoteByName = {
      for (final snapshot in remoteSnapshots.values)
        snapshot.person.name: snapshot,
    };
    final matchedLocalIds = <String>{};

    for (final snapshot in remoteSnapshots.values) {
      final remotePerson = snapshot.person;
      final localByIdMatch = localById[remotePerson.id];
      if (localByIdMatch != null) {
        matchedLocalIds.add(localByIdMatch.id);

        if (_samePerson(localByIdMatch, remotePerson)) {
          continue;
        }

        if (_shouldPullRemote(localByIdMatch, snapshot)) {
          await personRepository.save(remotePerson);
        } else {
          await savePerson(localByIdMatch);
        }
        continue;
      }

      final localByNameMatch = localByName[remotePerson.name];
      if (localByNameMatch != null) {
        matchedLocalIds.add(localByNameMatch.id);
        if (localByNameMatch.id != remotePerson.id) {
          await personRepository.deleteById(localByNameMatch.id);
        }
      }

      await personRepository.save(remotePerson);
      matchedLocalIds.add(remotePerson.id);
    }

    for (final localPerson in localPeople) {
      if (matchedLocalIds.contains(localPerson.id)) {
        continue;
      }

      // Compatibilidade: evita criar doc remoto duplicado caso a migração
      // já tenha escolhido outro UUID para o mesmo nome.
      if (remoteByName.containsKey(localPerson.name)) {
        continue;
      }

      await savePerson(localPerson);
    }
  }

  Query<Map<String, dynamic>> _queryPeople({String? locationId}) {
    final normalizedLocationId = _normalizeLocationId(locationId);
    if (normalizedLocationId == null) {
      return _people;
    }
    return _people.where('locationIds', arrayContains: normalizedLocationId);
  }

  Map<String, dynamic> _encodePerson(Person person) {
    final embeddings = <String, List<double>>{
      for (int i = 0; i < person.embeddings.length; i++)
        '$i': List<double>.from(person.embeddings[i].values),
    };

    return {
      'id': person.id,
      'name': person.name,
      'roleKey': person.role.key,
      'locationIds': person.locationIds.toList(growable: false),
      'embeddings': embeddings,
      'createdAt': person.createdAt.millisecondsSinceEpoch,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  RemotePersonSnapshot? _parseRemoteDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    Person? localMatch,
  }) {
    final data = doc.data();
    if (_isMigratedLegacyDoc(doc)) {
      return null;
    }

    final embeddings = _parseEmbeddings(data['embeddings']);
    if (embeddings == null || embeddings.isEmpty) {
      return null;
    }

    final name = _readName(doc);
    final roleKey = (data['roleKey'] as String?) ?? (data['role'] as String?);
    final createdAt =
        _parseDateTime(data['createdAt']) ?? localMatch?.createdAt ?? _clock();

    final person = Person(
      id: _resolveId(doc, localMatch),
      name: name,
      role: UserRoleExtension.fromKey(roleKey ?? 'operador'),
      locationIds: _parseLocationIds(data),
      embeddings: [
        for (final values in embeddings) FaceEmbedding(values),
      ],
      createdAt: createdAt,
    );

    return RemotePersonSnapshot(
      person: person,
      updatedAt: _parseDateTime(data['updatedAt']),
      documentId: doc.id,
      isLegacy: !_isUuidKeyedDoc(doc),
    );
  }

  String _resolveId(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Person? localMatch,
  ) {
    final data = doc.data();
    final rawId = data['id'];
    if (rawId is String && rawId.isNotEmpty) {
      return rawId;
    }
    if (localMatch != null) {
      return localMatch.id;
    }
    return _uuid.v5(
      Namespace.url.value,
      '$_legacyIdNamespace/${_readName(doc)}',
    );
  }

  bool _isUuidKeyedDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final rawId = doc.data()['id'];
    return rawId is String && rawId.isNotEmpty && rawId == doc.id;
  }

  bool _isMigratedLegacyDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return !_isUuidKeyedDoc(doc) && data['migrated'] == true;
  }

  String _readName(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final rawName = doc.data()['name'];
    if (rawName is String && rawName.trim().isNotEmpty) {
      return rawName.trim();
    }
    return doc.id;
  }

  Set<String> _parseLocationIds(Map<String, dynamic> data) {
    final result = <String>{};
    final raw = data['locationIds'] ?? data['allowedUnits'];
    if (raw is List) {
      for (final entry in raw) {
        final value = entry.toString().trim();
        if (value.isNotEmpty) {
          result.add(value);
        }
      }
    }
    return result;
  }

  List<List<double>>? _parseEmbeddings(dynamic raw) {
    if (raw == null) return null;

    if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((a, b) {
          final ia = int.tryParse(a.key.toString()) ?? 0;
          final ib = int.tryParse(b.key.toString()) ?? 0;
          return ia.compareTo(ib);
        });

      return entries
          .map((entry) => _parseEmbeddingRow(entry.value))
          .whereType<List<double>>()
          .toList();
    }

    if (raw is List) {
      return raw.map(_parseEmbeddingRow).whereType<List<double>>().toList();
    }

    return null;
  }

  List<double>? _parseEmbeddingRow(dynamic raw) {
    if (raw is! List) return null;
    return raw.map((value) => (value as num).toDouble()).toList();
  }

  DateTime? _parseDateTime(dynamic raw) {
    if (raw is Timestamp) return raw.toDate().toUtc();
    if (raw is DateTime) return raw.toUtc();
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
    }
    return null;
  }

  String? _normalizeLocationId(String? locationId) {
    if (locationId == null) return null;
    final trimmed = locationId.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _matchesLocation(Person person, String? locationId) {
    final normalizedLocationId = _normalizeLocationId(locationId);
    if (normalizedLocationId == null) return true;
    return person.locationIds.contains(normalizedLocationId);
  }

  bool _preferOver(
    RemotePersonSnapshot existing,
    RemotePersonSnapshot candidate,
  ) {
    final existingUpdatedAt = existing.updatedAt ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final candidateUpdatedAt = candidate.updatedAt ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    if (candidateUpdatedAt.isAfter(existingUpdatedAt)) {
      return true;
    }

    if (candidateUpdatedAt.isAtSameMomentAs(existingUpdatedAt)) {
      return existing.isLegacy && !candidate.isLegacy;
    }

    return false;
  }

  bool _shouldPullRemote(Person localPerson, RemotePersonSnapshot remote) {
    if (_samePerson(localPerson, remote.person)) {
      return false;
    }
    final updatedAt = remote.updatedAt;
    if (updatedAt == null) {
      return true;
    }
    return !localPerson.createdAt.isAfter(updatedAt);
  }

  bool _samePerson(Person a, Person b) {
    if (a.id != b.id ||
        a.name != b.name ||
        a.role != b.role ||
        a.createdAt.millisecondsSinceEpoch !=
            b.createdAt.millisecondsSinceEpoch) {
      return false;
    }

    if (a.locationIds.length != b.locationIds.length ||
        !a.locationIds.containsAll(b.locationIds)) {
      return false;
    }

    if (a.embeddings.length != b.embeddings.length) {
      return false;
    }

    for (var i = 0; i < a.embeddings.length; i++) {
      final left = a.embeddings[i].values;
      final right = b.embeddings[i].values;
      if (left.length != right.length) {
        return false;
      }
      for (var j = 0; j < left.length; j++) {
        if (left[j] != right[j]) {
          return false;
        }
      }
    }

    return true;
  }
}

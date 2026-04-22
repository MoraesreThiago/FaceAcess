import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:faceaccess/domain/entities/face_embedding.dart';
import 'package:faceaccess/domain/entities/person.dart';
import 'package:faceaccess/domain/entities/user_role.dart';
import 'package:faceaccess/domain/repositories/person_repository.dart';
import 'package:faceaccess/infrastructure/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FirebaseDatabase', () {
    late FakeFirebaseFirestore firestore;
    late FirebaseDatabase database;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      database = FirebaseDatabase(
        firestore: firestore,
        clock: () => DateTime.fromMillisecondsSinceEpoch(
          1700000000000,
          isUtc: true,
        ),
      );
    });

    test('savePerson grava doc keyed por UUID com schema v2', () async {
      final person = _person(
        id: 'person-1',
        name: 'Thiago',
        role: UserRole.gerente,
        locationIds: const {'araxa', 'perdizes'},
      );

      await database.savePerson(person);

      final doc = await firestore.collection('people').doc('person-1').get();
      final data = doc.data()!;

      expect(data['id'], 'person-1');
      expect(data['name'], 'Thiago');
      expect(data['roleKey'], UserRole.gerente.key);
      expect(
        (data['locationIds'] as List<dynamic>).cast<String>(),
        containsAll(<String>['araxa', 'perdizes']),
      );
      expect(data['embeddings'], isA<Map<String, dynamic>>());
      expect(data['updatedAt'], isA<Timestamp>());
      expect(data.containsKey('allowedUnits'), isFalse);
    });

    test('loadAll filtra por locationIds', () async {
      await firestore.collection('people').doc('araxa-1').set({
        'id': 'araxa-1',
        'name': 'Alice',
        'roleKey': UserRole.operador.key,
        'locationIds': ['araxa'],
        'embeddings': {
          '0': [0.1, 0.2],
        },
        'createdAt': 1700000000000,
        'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1700000000100),
      });
      await firestore.collection('people').doc('perdizes-1').set({
        'id': 'perdizes-1',
        'name': 'Bruno',
        'roleKey': UserRole.supervisor.key,
        'locationIds': ['perdizes'],
        'embeddings': {
          '0': [0.3, 0.4],
        },
        'createdAt': 1700000000000,
        'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1700000000200),
      });

      final loaded = await database.loadAll(locationId: 'araxa');

      expect(loaded.keys, equals(<String>{'araxa-1'}));
      expect(loaded['araxa-1']!.name, 'Alice');
    });

    test('deletePerson apaga o doc correto por id', () async {
      await firestore.collection('people').doc('person-1').set({
        'id': 'person-1',
        'name': 'Alice',
        'roleKey': UserRole.operador.key,
        'locationIds': ['araxa'],
        'embeddings': {
          '0': [0.1, 0.2],
        },
        'createdAt': 1700000000000,
        'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1700000000100),
      });
      await firestore.collection('people').doc('person-2').set({
        'id': 'person-2',
        'name': 'Bruno',
        'roleKey': UserRole.operador.key,
        'locationIds': ['araxa'],
        'embeddings': {
          '0': [0.3, 0.4],
        },
        'createdAt': 1700000000000,
        'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1700000000200),
      });

      await database.deletePerson('person-1');

      expect(
        (await firestore.collection('people').doc('person-1').get()).exists,
        isFalse,
      );
      expect(
        (await firestore.collection('people').doc('person-2').get()).exists,
        isTrue,
      );
    });

    test('migrateRemoteIfNeeded converte doc legado keyed por nome', () async {
      await firestore.collection('people').doc('Thiago').set({
        'name': 'Thiago',
        'role': UserRole.gerente.key,
        'allowedUnits': ['araxa'],
        'embeddings': {
          '0': [0.1, 0.2],
        },
      });

      final local = _person(
        id: 'local-uuid',
        name: 'Thiago',
        role: UserRole.operador,
        locationIds: const {'perdizes'},
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          1699999999000,
          isUtc: true,
        ),
      );

      await database.migrateRemoteIfNeeded(localPeople: [local]);

      final migrated =
          await firestore.collection('people').doc('local-uuid').get();
      final migratedData = migrated.data()!;
      final legacy = await firestore.collection('people').doc('Thiago').get();
      final meta = await firestore.collection('_meta').doc('migrations').get();

      expect(migrated.exists, isTrue);
      expect(migratedData['id'], 'local-uuid');
      expect(migratedData['name'], 'Thiago');
      expect(migratedData['roleKey'], UserRole.gerente.key);
      expect(
        (migratedData['locationIds'] as List<dynamic>).cast<String>(),
        equals(<String>['araxa']),
      );
      expect(migratedData['createdAt'], 1699999999000);
      expect(legacy.data()!['migrated'], isTrue);
      expect(legacy.data()!['migratedTo'], 'local-uuid');
      expect(meta.data()!['people_v1_to_v2'], isTrue);
    });

    test('synchronize aplica last-write-wins usando updatedAt remoto',
        () async {
      final repo = _InMemoryPersonRepository([
        _person(
          id: 'person-1',
          name: 'Nome Antigo',
          role: UserRole.operador,
          locationIds: const {'araxa'},
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            1700000000000,
            isUtc: true,
          ),
        ),
      ]);

      await firestore.collection('people').doc('person-1').set({
        'id': 'person-1',
        'name': 'Nome Remoto',
        'roleKey': UserRole.supervisor.key,
        'locationIds': ['araxa'],
        'embeddings': {
          '0': [0.9, 0.8],
        },
        'createdAt': 1700000000000,
        'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1700000005000),
      });

      await database.synchronize(
        personRepository: repo,
        locationId: 'araxa',
      );

      final saved = await repo.findById('person-1');

      expect(saved, isNotNull);
      expect(saved!.name, 'Nome Remoto');
      expect(saved.role, UserRole.supervisor);
      expect(saved.embeddings.first.values, equals(<double>[0.9, 0.8]));
    });

    test(
      'synchronize evita duplicar quando remoto já migrou o mesmo nome para outro id',
      () async {
        final repo = _InMemoryPersonRepository([
          _person(
            id: 'local-uuid',
            name: 'Thiago',
            role: UserRole.operador,
            locationIds: const {'araxa'},
          ),
        ]);

        await firestore.collection('people').doc('remote-uuid').set({
          'id': 'remote-uuid',
          'name': 'Thiago',
          'roleKey': UserRole.gerente.key,
          'locationIds': ['araxa'],
          'embeddings': {
            '0': [0.7, 0.6],
          },
          'createdAt': 1700000000000,
          'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1700000007000),
        });

        await database.synchronize(
          personRepository: repo,
          locationId: 'araxa',
        );

        final all = await repo.findAll();

        expect(all, hasLength(1));
        expect(all.single.id, 'remote-uuid');
        expect(all.single.name, 'Thiago');
        expect(
          (await firestore.collection('people').doc('local-uuid').get()).exists,
          isFalse,
        );
      },
    );
  });
}

Person _person({
  required String id,
  required String name,
  UserRole role = UserRole.operador,
  Set<String> locationIds = const <String>{},
  List<FaceEmbedding> embeddings = const <FaceEmbedding>[
    FaceEmbedding([0.1, 0.2]),
  ],
  DateTime? createdAt,
}) {
  return Person(
    id: id,
    name: name,
    role: role,
    locationIds: locationIds,
    embeddings: embeddings,
    createdAt: createdAt ??
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
  );
}

class _InMemoryPersonRepository implements PersonRepository {
  _InMemoryPersonRepository([Iterable<Person> initial = const <Person>[]])
      : _people = {
          for (final person in initial) person.id: person,
        };

  final Map<String, Person> _people;

  @override
  Future<void> deleteById(String id) async {
    _people.remove(id);
  }

  @override
  Future<List<Person>> findAll({String? locationId}) async {
    return _people.values.where((person) {
      if (locationId == null) return true;
      return person.locationIds.contains(locationId);
    }).toList(growable: false);
  }

  @override
  Future<Person?> findById(String id) async => _people[id];

  @override
  Future<void> save(Person person) async {
    _people[person.id] = person;
  }
}

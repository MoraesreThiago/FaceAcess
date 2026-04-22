import 'dart:io';

import 'package:faceaccess/domain/entities/face_embedding.dart';
import 'package:faceaccess/domain/entities/person.dart';
import 'package:faceaccess/domain/entities/user_role.dart';
import 'package:faceaccess/infrastructure/persistence/hive/hive_person_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// UUID determinístico. Todas as variantes (v1/v4/v5) retornam o mesmo
/// valor via `noSuchMethod` — só `v4` é exercitado pela implementação.
class _FixedUuid implements Uuid {
  _FixedUuid(this._value);
  final String _value;

  @override
  dynamic noSuchMethod(Invocation invocation) => _value;
}

/// Gera UUIDs sequenciais, úteis quando precisamos que várias pessoas
/// migradas recebam IDs distintos mas previsíveis.
class _SequentialUuid implements Uuid {
  int _counter = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => 'uuid-${++_counter}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('faceaccess_hive_test_');
    SharedPreferences.setMockInitialValues({});
    await Hive.close();
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Person samplePerson({String id = 'pid-1', String name = 'Alice'}) {
    return Person(
      id: id,
      name: name,
      role: UserRole.operador,
      locationIds: const {'araxa'},
      embeddings: const [
        FaceEmbedding([1.0, 0.0, 0.0]),
        FaceEmbedding([0.9, 0.1, 0.0]),
      ],
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
    );
  }

  group('HivePersonRepository — fresh install', () {
    test('sem box legada, inicializa vazio e marca flag', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = HivePersonRepository(prefs: prefs);

      await repo.initialize(hiveHomeDir: tempDir.path);

      expect(await repo.findAll(), isEmpty);
      expect(prefs.getBool(HivePersonRepository.migrationFlagKey), isTrue);
    });

    test('save + findById + findAll + deleteById (roundtrip)', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = HivePersonRepository(prefs: prefs);
      await repo.initialize(hiveHomeDir: tempDir.path);

      await repo.save(samplePerson());

      final fetched = await repo.findById('pid-1');
      expect(fetched, isNotNull);
      expect(fetched!.name, 'Alice');
      expect(fetched.role, UserRole.operador);
      expect(fetched.locationIds, equals({'araxa'}));
      expect(fetched.embeddings.length, 2);
      expect(fetched.embeddings.first.values, equals([1.0, 0.0, 0.0]));

      final all = await repo.findAll();
      expect(all.length, 1);

      await repo.deleteById('pid-1');
      expect(await repo.findById('pid-1'), isNull);
      expect(await repo.findAll(), isEmpty);
    });

    test('findAll filtra por locationId', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = HivePersonRepository(prefs: prefs);
      await repo.initialize(hiveHomeDir: tempDir.path);

      await repo.save(samplePerson(id: 'a', name: 'Alice'));
      await repo.save(Person(
        id: 'b',
        name: 'Bob',
        role: UserRole.gerente,
        locationIds: const {'perdizes'},
        embeddings: const [FaceEmbedding([0.0, 1.0, 0.0])],
        createdAt: DateTime.now().toUtc(),
      ));

      final araxa = await repo.findAll(locationId: 'araxa');
      expect(araxa.map((p) => p.name), equals(['Alice']));

      final perdizes = await repo.findAll(locationId: 'perdizes');
      expect(perdizes.map((p) => p.name), equals(['Bob']));

      final nenhum = await repo.findAll(locationId: 'nonexistent');
      expect(nenhum, isEmpty);
    });
  });

  group('HivePersonRepository — migração da box legada', () {
    /// Popula a box legada `face_embeddings_v2` no formato antigo
    /// (key = nome, value = { role, embeddings }).
    Future<void> seedLegacyBox(Map<String, Map<String, dynamic>> data) async {
      Hive.init(tempDir.path);
      final box = await Hive.openBox<dynamic>(
        HivePersonRepository.legacyBoxName,
      );
      for (final entry in data.entries) {
        await box.put(entry.key, entry.value);
      }
      await box.close();
    }

    test(
        'copia registros legados para a nova box gerando UUIDs, flag vira true',
        () async {
      await seedLegacyBox({
        'Alice': {
          'role': 'gerente',
          'embeddings': [
            [1.0, 0.0],
            [0.9, 0.1],
          ],
        },
        'Bob': {
          'role': 'operador',
          'embeddings': [
            [0.0, 1.0],
          ],
        },
      });

      final prefs = await SharedPreferences.getInstance();
      final repo = HivePersonRepository(
        prefs: prefs,
        uuid: _SequentialUuid(),
      );
      await repo.initialize(hiveHomeDir: tempDir.path);

      final people = await repo.findAll();
      expect(people.length, 2);
      final names = people.map((p) => p.name).toSet();
      expect(names, equals({'Alice', 'Bob'}));

      final alice = people.firstWhere((p) => p.name == 'Alice');
      expect(alice.role, UserRole.gerente);
      expect(alice.locationIds, isEmpty,
          reason: 'box legada não tinha locationIds — campo nasce vazio');
      expect(alice.embeddings.length, 2);
      expect(alice.embeddings.first.values, equals([1.0, 0.0]));
      expect(alice.id, startsWith('uuid-'));

      // Box legada preservada (rollback).
      final legacy = await Hive.openBox<dynamic>(
        HivePersonRepository.legacyBoxName,
      );
      expect(legacy.get('Alice'), isNotNull);
      expect(legacy.get('Bob'), isNotNull);
      await legacy.close();

      expect(prefs.getBool(HivePersonRepository.migrationFlagKey), isTrue);
    });

    test('migração é idempotente via flag: segundo initialize é no-op',
        () async {
      await seedLegacyBox({
        'Alice': {
          'role': 'operador',
          'embeddings': [
            [1.0, 0.0],
          ],
        },
      });

      final prefs = await SharedPreferences.getInstance();
      final repo1 = HivePersonRepository(
        prefs: prefs,
        uuid: _FixedUuid('uuid-first-run'),
      );
      await repo1.initialize(hiveHomeDir: tempDir.path);
      final idsAfterFirstRun =
          (await repo1.findAll()).map((p) => p.id).toList();

      await Hive.close();

      final repo2 = HivePersonRepository(
        prefs: prefs,
        uuid: _FixedUuid('uuid-second-run-should-not-fire'),
      );
      await repo2.initialize(hiveHomeDir: tempDir.path);
      final idsAfterSecondRun =
          (await repo2.findAll()).map((p) => p.id).toList();

      expect(idsAfterSecondRun, equals(idsAfterFirstRun));
    });

    test(
        'belt-and-suspenders: se a flag for removida mas a pessoa já '
        'existir na nova box com o mesmo nome, a migração NÃO sobrescreve',
        () async {
      await seedLegacyBox({
        'Alice': {
          'role': 'operador',
          'embeddings': [
            [1.0, 0.0],
          ],
        },
      });

      final prefs = await SharedPreferences.getInstance();
      final repo1 = HivePersonRepository(prefs: prefs);
      await repo1.initialize(hiveHomeDir: tempDir.path);
      final originalId = (await repo1.findAll()).first.id;

      // Atualiza Alice com novos dados (simula uso normal pós-migração).
      await repo1.save(Person(
        id: originalId,
        name: 'Alice',
        role: UserRole.gerente,
        locationIds: const {'araxa'},
        embeddings: const [FaceEmbedding([0.5, 0.5])],
        createdAt: DateTime.now().toUtc(),
      ));

      await Hive.close();

      // Alguém removeu a flag manualmente.
      await prefs.remove(HivePersonRepository.migrationFlagKey);

      final repo2 = HivePersonRepository(prefs: prefs);
      await repo2.initialize(hiveHomeDir: tempDir.path);

      final all = await repo2.findAll();
      expect(all.length, 1,
          reason: 'sem duplicata — mesmo nome, mesmo registro');
      expect(all.first.id, originalId);
      expect(all.first.role, UserRole.gerente);
      expect(all.first.locationIds, equals({'araxa'}));
      expect(all.first.embeddings.first.values, equals([0.5, 0.5]));
    });
  });

  group('HivePersonRepository — serialização', () {
    test('preserva embeddings, role, locationIds e createdAt fielmente',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = HivePersonRepository(prefs: prefs);
      await repo.initialize(hiveHomeDir: tempDir.path);

      final original = Person(
        id: 'persisted',
        name: 'João',
        role: UserRole.diretor,
        locationIds: const {'araxa', 'perdizes'},
        embeddings: const [
          FaceEmbedding([0.1, 0.2, 0.3]),
          FaceEmbedding([0.4, 0.5, 0.6]),
        ],
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000,
            isUtc: true),
      );
      await repo.save(original);

      // "Reboot" do repositório: garante que a leitura vem do disco.
      await Hive.close();
      final repo2 = HivePersonRepository(prefs: prefs);
      await repo2.initialize(hiveHomeDir: tempDir.path);

      final loaded = await repo2.findById('persisted');
      expect(loaded, isNotNull);
      expect(loaded!.name, 'João');
      expect(loaded.role, UserRole.diretor);
      expect(loaded.locationIds, equals({'araxa', 'perdizes'}));
      expect(loaded.embeddings.length, 2);
      expect(loaded.embeddings[0].values, equals([0.1, 0.2, 0.3]));
      expect(loaded.embeddings[1].values, equals([0.4, 0.5, 0.6]));
      expect(loaded.createdAt.millisecondsSinceEpoch, 1700000000000);
    });
  });

  test('operações antes de initialize lançam StateError', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = HivePersonRepository(prefs: prefs);
    expect(() => repo.findAll(), throwsA(isA<StateError>()));
  });
}

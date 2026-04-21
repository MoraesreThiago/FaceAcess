import 'package:faceaccess/domain/entities/tablet_assignment.dart';
import 'package:faceaccess/domain/entities/tablet_identity.dart';
import 'package:faceaccess/infrastructure/tablet/shared_prefs_tablet_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// UUID fixo para tornar os testes determinísticos. Só o `v4()` é
/// usado pela implementação; os demais métodos caem em noSuchMethod
/// e também retornam o mesmo valor, o que basta para testes.
class _FixedUuid implements Uuid {
  _FixedUuid(this._value);
  final String _value;

  @override
  dynamic noSuchMethod(Invocation invocation) => _value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsTabletConfigRepository', () {
    late SharedPreferences prefs;

    Future<SharedPrefsTabletConfigRepository> build({
      Map<String, Object> initial = const {},
      String generatedId = '00000000-0000-4000-8000-000000000001',
    }) async {
      SharedPreferences.setMockInitialValues(initial);
      prefs = await SharedPreferences.getInstance();
      return SharedPrefsTabletConfigRepository(
        prefs,
        uuid: _FixedUuid(generatedId),
      );
    }

    test('fresh install: cria UUID novo, assignment null, marca flag',
        () async {
      final repo = await build(generatedId: 'fresh-uuid');

      await repo.initialize();

      expect(prefs.getString(SharedPrefsTabletConfigRepository.identityIdKey),
          'fresh-uuid');
      expect(prefs.getBool(SharedPrefsTabletConfigRepository.migrationFlagKey),
          isTrue);

      final identity = await repo.getOrCreateIdentity();
      expect(identity.id, 'fresh-uuid');
      expect(identity.name, '');

      final assignment = await repo.getAssignment();
      expect(assignment, isNull);
    });

    test('migração legada: copia id/name/unit para as novas chaves', () async {
      final repo = await build(
        initial: {
          SharedPrefsTabletConfigRepository.legacyIdKey: 'legacy-id',
          SharedPrefsTabletConfigRepository.legacyNameKey: 'Porta Principal',
          SharedPrefsTabletConfigRepository.legacyUnitKey: 'araxa',
        },
      );

      await repo.initialize();

      // Novas chaves populadas a partir das legadas.
      expect(prefs.getString(SharedPrefsTabletConfigRepository.identityIdKey),
          'legacy-id');
      expect(prefs.getString(SharedPrefsTabletConfigRepository.identityNameKey),
          'Porta Principal');
      expect(
          prefs.getString(
              SharedPrefsTabletConfigRepository.assignmentLocationIdKey),
          'araxa');

      // Chaves legadas NÃO são apagadas (rede de rollback).
      expect(prefs.getString(SharedPrefsTabletConfigRepository.legacyIdKey),
          'legacy-id');
      expect(prefs.getString(SharedPrefsTabletConfigRepository.legacyNameKey),
          'Porta Principal');
      expect(prefs.getString(SharedPrefsTabletConfigRepository.legacyUnitKey),
          'araxa');

      final identity = await repo.getOrCreateIdentity();
      expect(identity, const TabletIdentity(id: 'legacy-id', name: 'Porta Principal'));

      final assignment = await repo.getAssignment();
      expect(assignment, isNotNull);
      expect(assignment!.locationId, 'araxa');
      expect(assignment.doorId, isNull);
      expect(assignment.tabletId, 'legacy-id');
    });

    test('migração é idempotente: segundo initialize não sobrescreve', () async {
      // Primeira passada: migração roda.
      final repo1 = await build(
        initial: {
          SharedPrefsTabletConfigRepository.legacyIdKey: 'legacy-id',
          SharedPrefsTabletConfigRepository.legacyNameKey: 'Porta A',
          SharedPrefsTabletConfigRepository.legacyUnitKey: 'araxa',
        },
      );
      await repo1.initialize();

      // Operador renomeia via saveIdentity.
      await repo1.saveIdentity(
        const TabletIdentity(id: 'legacy-id', name: 'Porta Renomeada'),
      );

      // Segundo boot: NÃO pode sobrescrever o novo nome com o legado.
      final repo2 = SharedPrefsTabletConfigRepository(
        prefs,
        uuid: _FixedUuid('should-not-be-used'),
      );
      await repo2.initialize();

      expect(prefs.getString(SharedPrefsTabletConfigRepository.identityNameKey),
          'Porta Renomeada');
    });

    test('saveAssignment + getAssignment roundtrip', () async {
      final repo = await build();
      await repo.initialize();

      await repo.saveAssignment(
        const TabletAssignment(
          tabletId: 'any',
          locationId: 'perdizes',
          doorId: 'door-42',
        ),
      );

      final got = await repo.getAssignment();
      expect(got, isNotNull);
      expect(got!.locationId, 'perdizes');
      expect(got.doorId, 'door-42');
    });

    test('getAssignment retorna null quando location e door estão vazios',
        () async {
      final repo = await build();
      await repo.initialize();

      // Salva assignment com todos os campos nulos → chaves removidas.
      await repo.saveAssignment(
        const TabletAssignment(tabletId: 'any'),
      );

      expect(await repo.getAssignment(), isNull);
    });

    test(
        'chaves novas já existentes não são tocadas pela migração (cenário anômalo)',
        () async {
      final repo = await build(
        initial: {
          SharedPrefsTabletConfigRepository.identityIdKey: 'new-id',
          SharedPrefsTabletConfigRepository.identityNameKey: 'Novo',
          SharedPrefsTabletConfigRepository.legacyIdKey: 'legacy-id',
          SharedPrefsTabletConfigRepository.legacyNameKey: 'Legado',
        },
      );

      await repo.initialize();

      expect(prefs.getString(SharedPrefsTabletConfigRepository.identityIdKey),
          'new-id');
      expect(prefs.getString(SharedPrefsTabletConfigRepository.identityNameKey),
          'Novo');
      expect(prefs.getBool(SharedPrefsTabletConfigRepository.migrationFlagKey),
          isTrue);
    });
  });
}

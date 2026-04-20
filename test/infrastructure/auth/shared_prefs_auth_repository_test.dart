import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:faceaccess/domain/entities/operator_role.dart';
import 'package:faceaccess/infrastructure/auth/shared_prefs_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _legacyHash(String password) =>
    sha256.convert(utf8.encode(password)).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsAuthRepository', () {
    late SharedPreferences prefs;
    late SharedPrefsAuthRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      repo = SharedPrefsAuthRepository(prefs);
    });

    test('ensureDefaults cria as senhas padrão na primeira execução',
        () async {
      await repo.ensureDefaults();

      expect(await repo.validate(OperatorRole.admin, 'admin123'), isTrue);
      expect(await repo.validate(OperatorRole.porta, 'porta123'), isTrue);
    });

    test('ensureDefaults não sobrescreve hashes já definidos', () async {
      await repo.ensureDefaults();
      await repo.changePassword(OperatorRole.admin, 'custom-admin');

      // Chama novamente — não pode voltar para o padrão.
      await repo.ensureDefaults();

      expect(await repo.validate(OperatorRole.admin, 'admin123'), isFalse);
      expect(await repo.validate(OperatorRole.admin, 'custom-admin'), isTrue);
    });

    test('validate retorna false para senha errada', () async {
      await repo.ensureDefaults();

      expect(await repo.validate(OperatorRole.admin, 'errada'), isFalse);
      expect(await repo.validate(OperatorRole.porta, ''), isFalse);
    });

    test('changePassword substitui a senha anterior', () async {
      await repo.ensureDefaults();
      await repo.changePassword(OperatorRole.porta, 'nova-porta');

      expect(await repo.validate(OperatorRole.porta, 'porta123'), isFalse);
      expect(await repo.validate(OperatorRole.porta, 'nova-porta'), isTrue);
    });

    test('admin e porta são independentes', () async {
      await repo.ensureDefaults();
      await repo.changePassword(OperatorRole.admin, 'nova-admin');

      expect(await repo.validate(OperatorRole.admin, 'nova-admin'), isTrue);
      // porta não foi tocada:
      expect(await repo.validate(OperatorRole.porta, 'porta123'), isTrue);
    });

    test('compatibilidade de chaves/hash com o AuthService legado', () async {
      // Simula estado pré-existente gravado pela versão antiga do app:
      // chaves `auth_admin_hash` / `auth_porta_hash` com sha256(password)
      // exatamente como o antigo `AuthService` fazia.
      SharedPreferences.setMockInitialValues({
        'auth_admin_hash': _legacyHash('admin123'),
        'auth_porta_hash': _legacyHash('porta123'),
      });
      prefs = await SharedPreferences.getInstance();
      repo = SharedPrefsAuthRepository(prefs);

      // Sem chamar ensureDefaults: dados legados são respeitados tal qual.
      expect(await repo.validate(OperatorRole.admin, 'admin123'), isTrue);
      expect(await repo.validate(OperatorRole.porta, 'porta123'), isTrue);
    });
  });
}

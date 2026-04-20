import 'package:faceaccess/application/result.dart';
import 'package:faceaccess/application/use_cases/login_use_case.dart';
import 'package:faceaccess/domain/entities/operator_role.dart';
import 'package:faceaccess/domain/errors/failures.dart';
import 'package:faceaccess/domain/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({
    this.validator,
    this.throwOnValidate = false,
  });

  final bool Function(OperatorRole role, String password)? validator;
  final bool throwOnValidate;
  final List<(OperatorRole, String)> changes = [];

  @override
  Future<bool> validate(OperatorRole role, String password) async {
    if (throwOnValidate) {
      throw StateError('prefs indisponível');
    }
    return validator?.call(role, password) ?? false;
  }

  @override
  Future<void> changePassword(OperatorRole role, String newPassword) async {
    changes.add((role, newPassword));
  }
}

void main() {
  group('LoginUseCase', () {
    test('Success quando a senha é válida', () async {
      final repo = _FakeAuthRepository(
        validator: (role, pass) =>
            role == OperatorRole.admin && pass == 'certa',
      );
      final useCase = LoginUseCase(authRepository: repo);

      final result = await useCase.call(
        role: OperatorRole.admin,
        password: 'certa',
      );

      expect(result, isA<Success<OperatorRole>>());
      expect((result as Success<OperatorRole>).value, OperatorRole.admin);
    });

    test('Err(AuthFailure.invalidPassword) quando a senha é inválida',
        () async {
      final repo = _FakeAuthRepository(validator: (_, __) => false);
      final useCase = LoginUseCase(authRepository: repo);

      final result = await useCase.call(
        role: OperatorRole.porta,
        password: 'errada',
      );

      expect(result, isA<Err<OperatorRole>>());
      expect(
        (result as Err<OperatorRole>).failure,
        same(AuthFailure.invalidPassword),
      );
    });

    test(
        'Err(PersistenceFailure) quando o repositório lança — exceção não '
        'vaza', () async {
      final repo = _FakeAuthRepository(throwOnValidate: true);
      final useCase = LoginUseCase(authRepository: repo);

      final result = await useCase.call(
        role: OperatorRole.admin,
        password: 'qualquer',
      );

      expect(result, isA<Err<OperatorRole>>());
      expect(
        (result as Err<OperatorRole>).failure,
        isA<PersistenceFailure>(),
      );
    });

    test('role do Success é a mesma recebida na entrada', () async {
      final repo = _FakeAuthRepository(validator: (_, __) => true);
      final useCase = LoginUseCase(authRepository: repo);

      final admin = await useCase.call(
        role: OperatorRole.admin,
        password: 'x',
      );
      final porta = await useCase.call(
        role: OperatorRole.porta,
        password: 'x',
      );

      expect((admin as Success<OperatorRole>).value, OperatorRole.admin);
      expect((porta as Success<OperatorRole>).value, OperatorRole.porta);
    });
  });
}

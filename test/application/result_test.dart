import 'package:flutter_test/flutter_test.dart';

import 'package:faceaccess/application/result.dart';
import 'package:faceaccess/domain/errors/failures.dart';

void main() {
  group('Result', () {
    test('Success carrega valor e é isSuccess', () {
      const r = Success<int>(42);
      expect(r.isSuccess, isTrue);
      expect(r.isError, isFalse);
      expect(r.value, 42);
    });

    test('Err carrega falha e é isError', () {
      const r = Err<int>(AuthFailure.invalidPassword);
      expect(r.isError, isTrue);
      expect(r.isSuccess, isFalse);
      expect(r.failure, AuthFailure.invalidPassword);
    });

    test('pattern matching exaustivo compila e discrimina', () {
      Result<String> sample(bool ok) =>
          ok ? const Success('ok') : const Err(UnknownFailure('boom'));

      String describe(Result<String> r) => switch (r) {
            Success(value: final v) => 'ok:$v',
            Err(failure: final f) => 'err:${f.message}',
          };

      expect(describe(sample(true)), 'ok:ok');
      expect(describe(sample(false)), 'err:boom');
    });
  });
}

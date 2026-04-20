import '../domain/errors/failures.dart';

/// Resultado tipado de um caso de uso.
///
/// Convenção: casos de uso **não lançam** exceções para falhas
/// esperadas; retornam [Err] com uma [Failure] específica.
/// Exceções seguem reservadas para bugs de programação.
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isError => this is Err<T>;
}

class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);
}

class Err<T> extends Result<T> {
  final Failure failure;
  const Err(this.failure);
}

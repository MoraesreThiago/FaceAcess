/// Hierarquia selada de falhas esperadas do domínio.
///
/// Falhas representam **erros previsíveis** (senha inválida, sem rede,
/// pessoa não encontrada, porta não acionada). Bugs de programação
/// continuam sendo exceções não tipadas.
sealed class Failure {
  final String message;
  const Failure(this.message);
}

/// Falhas relacionadas a autenticação/senhas.
class AuthFailure extends Failure {
  const AuthFailure(super.message);
  static const AuthFailure invalidPassword =
      AuthFailure('Senha incorreta');
}

/// Falhas ao ler/escrever em armazenamento local ou remoto.
class PersistenceFailure extends Failure {
  const PersistenceFailure(super.message);
}

/// Falhas de rede / comunicação externa (Firestore, MQTT broker, etc).
class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

/// Falha ao acionar a porta (broker indisponível, timeout, etc).
class DoorActuationFailure extends Failure {
  const DoorActuationFailure(super.message);
}

/// Falha genérica não mapeada — usar com parcimônia.
class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}

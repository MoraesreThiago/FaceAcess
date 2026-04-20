import '../entities/door.dart';

/// Serviço de acionamento de porta.
///
/// Mantido **neutro** em relação à tecnologia: nenhuma referência a
/// MQTT, tópico, broker ou protocolo aqui. Implementações concretas
/// (ex.: `MqttDoorController` em `infrastructure/door/`) resolvem o
/// mapeamento para o transporte real.
abstract class DoorController {
  Future<void> open(Door door);
}

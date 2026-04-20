import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../domain/repositories/door_controller_repository.dart';

class MqttDoorController implements DoorControllerRepository {
  static const String _broker = 'broker.hivemq.com';
  static const int _port = 1883;
  static const String _clientId = 'tablet_face_access_01';
  static const String _topic = 'porta/abrir';
  static const String _message = 'ABRIR';

  MqttServerClient? _client;
  bool _isConnected = false;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    _client = MqttServerClient.withPort(_broker, _clientId, _port);
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 60;
    _client!.autoReconnect = true;
    _client!.onDisconnected = () => _isConnected = false;
    _client!.onConnected = () => _isConnected = true;
    _client!.onAutoReconnected = () => _isConnected = true;

    _client!.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(_clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    try {
      await _client!.connect();
    } catch (_) {
      _client!.disconnect();
      _isConnected = false;
    }
  }

  @override
  Future<void> openDoor() async {
    if (!_isConnected) await connect();
    if (!_isConnected) return;

    final builder = MqttClientPayloadBuilder()..addString(_message);
    _client!.publishMessage(_topic, MqttQos.atLeastOnce, builder.payload!);
  }

  @override
  Future<void> disconnect() async => _client?.disconnect();
}

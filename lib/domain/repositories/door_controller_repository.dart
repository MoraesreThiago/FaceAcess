abstract class DoorControllerRepository {
  Future<void> connect();
  Future<void> openDoor();
  Future<void> disconnect();
  bool get isConnected;
}

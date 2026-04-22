import '../entities/door.dart';

/// Contrato para persistência remota de [Door].
///
/// [Door.id] é estável e [Door.locationId] vincula a porta a uma unidade.
abstract class DoorRepository {
  Future<void> save(Door door);

  Future<Door?> findById(String id);

  Future<List<Door>> findAll({String? locationId});

  Future<void> deleteById(String id);
}

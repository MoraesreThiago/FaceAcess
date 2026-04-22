import '../entities/location.dart';

/// Contrato para persistência remota de [Location].
///
/// [Location.id] é um identificador estável usado em referências cruzadas
/// como `Person.locationIds` e `TabletAssignment.locationId`.
abstract class LocationRepository {
  Future<void> save(Location location);

  Future<Location?> findById(String id);

  Future<List<Location>> findAll();

  Future<void> deleteById(String id);
}

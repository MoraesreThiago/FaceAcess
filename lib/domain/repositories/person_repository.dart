import '../entities/person.dart';

/// Contrato para persistência de [Person].
///
/// Substitui, a partir da Fase 7, o atual `FaceDatabaseRepository` que
/// usa o nome como chave. Aqui a chave primária é o UUID em [Person.id].
///
/// Implementações possíveis (futuras):
/// - `HivePersonRepository` (local, offline-first)
/// - `FirestorePersonRepository` (remoto, sync)
abstract class PersonRepository {
  Future<void> save(Person person);

  Future<Person?> findById(String id);

  /// Lista todas as pessoas conhecidas. Se [locationId] for fornecido,
  /// restringe ao conjunto de pessoas cujo `locationIds` contém o id.
  Future<List<Person>> findAll({String? locationId});

  Future<void> deleteById(String id);
}

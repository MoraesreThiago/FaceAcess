import '../entities/user_role.dart';
import '../../infrastructure/face_database.dart';

abstract class FaceDatabaseRepository {
  Future<void> savePerson(
    String name,
    List<List<double>> embeddings, {
    UserRole role,
  });
  Future<Map<String, PersonRecord>> loadAll();
  Future<void> deletePerson(String name);
  Future<List<String>> listPersons();
}

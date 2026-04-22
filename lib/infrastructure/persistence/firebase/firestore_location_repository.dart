import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/entities/location.dart';
import '../../../domain/repositories/location_repository.dart';
import 'dto/location_dto.dart';

class FirestoreLocationRepository implements LocationRepository {
  FirestoreLocationRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String _collection = 'locations';

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _locations =>
      _firestore.collection(_collection);

  @override
  Future<void> save(Location location) async {
    final dto = LocationDto.fromDomain(location);
    await _locations.doc(dto.id).set(dto.toMap());
  }

  @override
  Future<Location?> findById(String id) async {
    final snapshot = await _locations.doc(id).get(
          const GetOptions(source: Source.serverAndCache),
        );
    return LocationDto.fromDocument(snapshot)?.toDomain();
  }

  @override
  Future<List<Location>> findAll() async {
    final snapshot = await _locations.get(
      const GetOptions(source: Source.serverAndCache),
    );

    final locations = snapshot.docs
        .map(LocationDto.fromDocument)
        .whereType<LocationDto>()
        .map((dto) => dto.toDomain())
        .toList(growable: false);

    final sorted = locations.toList(growable: false)
      ..sort((left, right) {
        final byName = left.name.toLowerCase().compareTo(right.name.toLowerCase());
        if (byName != 0) return byName;
        return left.id.compareTo(right.id);
      });

    return sorted;
  }

  @override
  Future<void> deleteById(String id) async {
    await _locations.doc(id).delete();
  }
}

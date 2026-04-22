import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/entities/door.dart';
import '../../../domain/repositories/door_repository.dart';
import 'dto/door_dto.dart';

class FirestoreDoorRepository implements DoorRepository {
  FirestoreDoorRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String _collection = 'doors';

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _doors =>
      _firestore.collection(_collection);

  @override
  Future<void> save(Door door) async {
    final dto = DoorDto.fromDomain(door);
    await _doors.doc(dto.id).set(dto.toMap());
  }

  @override
  Future<Door?> findById(String id) async {
    final snapshot = await _doors.doc(id).get(
          const GetOptions(source: Source.serverAndCache),
        );
    return DoorDto.fromDocument(snapshot)?.toDomain();
  }

  @override
  Future<List<Door>> findAll({String? locationId}) async {
    final normalizedLocationId = _normalizeLocationId(locationId);
    final query = normalizedLocationId == null
        ? _doors
        : _doors.where('locationId', isEqualTo: normalizedLocationId);

    final snapshot = await query.get(
      const GetOptions(source: Source.serverAndCache),
    );

    final doors = snapshot.docs
        .map(DoorDto.fromDocument)
        .whereType<DoorDto>()
        .map((dto) => dto.toDomain())
        .toList(growable: false);

    final sorted = doors.toList(growable: false)
      ..sort((left, right) {
        final byLocation =
            left.locationId.toLowerCase().compareTo(right.locationId.toLowerCase());
        if (byLocation != 0) return byLocation;
        final byName = left.name.toLowerCase().compareTo(right.name.toLowerCase());
        if (byName != 0) return byName;
        return left.id.compareTo(right.id);
      });

    return sorted;
  }

  @override
  Future<void> deleteById(String id) async {
    await _doors.doc(id).delete();
  }

  String? _normalizeLocationId(String? locationId) {
    if (locationId == null) return null;
    final trimmed = locationId.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

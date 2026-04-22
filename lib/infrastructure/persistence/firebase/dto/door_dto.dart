import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../domain/entities/door.dart';

class DoorDto {
  const DoorDto({
    required this.id,
    required this.name,
    required this.locationId,
  });

  final String id;
  final String name;
  final String locationId;

  factory DoorDto.fromDomain(Door door) {
    return DoorDto(
      id: door.id,
      name: door.name,
      locationId: door.locationId,
    );
  }

  static DoorDto? fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) return null;

    final resolvedId = (data['id'] as String?)?.trim() ?? document.id.trim();
    final resolvedName = (data['name'] as String?)?.trim();
    final resolvedLocationId = (data['locationId'] as String?)?.trim();

    if (resolvedId.isEmpty ||
        resolvedName == null ||
        resolvedName.isEmpty ||
        resolvedLocationId == null ||
        resolvedLocationId.isEmpty) {
      return null;
    }

    return DoorDto(
      id: resolvedId,
      name: resolvedName,
      locationId: resolvedLocationId,
    );
  }

  Door toDomain() {
    return Door(
      id: id,
      name: name,
      locationId: locationId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'locationId': locationId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

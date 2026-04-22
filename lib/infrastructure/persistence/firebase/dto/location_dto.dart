import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../domain/entities/location.dart';

class LocationDto {
  const LocationDto({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  factory LocationDto.fromDomain(Location location) {
    return LocationDto(
      id: location.id,
      name: location.name,
    );
  }

  static LocationDto? fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) return null;

    final resolvedId = (data['id'] as String?)?.trim() ?? document.id.trim();
    final resolvedName = (data['name'] as String?)?.trim();

    if (resolvedId.isEmpty || resolvedName == null || resolvedName.isEmpty) {
      return null;
    }

    return LocationDto(
      id: resolvedId,
      name: resolvedName,
    );
  }

  Location toDomain() {
    return Location(
      id: id,
      name: name,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

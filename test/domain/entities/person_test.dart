import 'package:flutter_test/flutter_test.dart';

import 'package:faceaccess/domain/entities/face_embedding.dart';
import 'package:faceaccess/domain/entities/person.dart';
import 'package:faceaccess/domain/entities/user_role.dart';

void main() {
  group('Person', () {
    final now = DateTime(2026, 1, 1);

    Person make({
      String id = 'uuid-1',
      String name = 'Fulano',
      Set<String> locations = const {'araxa'},
    }) {
      return Person(
        id: id,
        name: name,
        role: UserRole.operador,
        locationIds: locations,
        embeddings: const [FaceEmbedding([0.1, 0.2, 0.3])],
        createdAt: now,
      );
    }

    test('constrói com campos obrigatórios e preserva valores', () {
      final p = make();
      expect(p.id, 'uuid-1');
      expect(p.name, 'Fulano');
      expect(p.role, UserRole.operador);
      expect(p.locationIds, {'araxa'});
      expect(p.embeddings.length, 1);
      expect(p.embeddings.first.length, 3);
      expect(p.createdAt, now);
    });

    test('suporta múltiplas locations', () {
      final p = make(locations: {'araxa', 'perdizes'});
      expect(p.locationIds.length, 2);
      expect(p.locationIds.contains('araxa'), isTrue);
      expect(p.locationIds.contains('perdizes'), isTrue);
    });

    test('igualdade baseada no id', () {
      final a = make(id: 'x', name: 'A');
      final b = make(id: 'x', name: 'B');
      final c = make(id: 'y', name: 'A');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, b.hashCode);
    });
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:faceaccess/domain/entities/door.dart';
import 'package:faceaccess/infrastructure/persistence/firebase/firestore_door_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FirestoreDoorRepository', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreDoorRepository repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repository = FirestoreDoorRepository(firestore: firestore);
    });

    test('save grava doc keyed por id estável e findById faz roundtrip', () async {
      await repository.save(
        const Door(
          id: 'door-1',
          name: 'Porta principal',
          locationId: 'araxa',
        ),
      );

      final document = await firestore.collection('doors').doc('door-1').get();
      final loaded = await repository.findById('door-1');

      expect(document.exists, isTrue);
      expect(document.data()!['id'], 'door-1');
      expect(document.data()!['name'], 'Porta principal');
      expect(document.data()!['locationId'], 'araxa');
      expect(document.data()!['updatedAt'], isA<Timestamp>());
      expect(loaded, isNotNull);
      expect(loaded!.id, 'door-1');
      expect(loaded.name, 'Porta principal');
      expect(loaded.locationId, 'araxa');
    });

    test('findAll filtra por locationId e deleteById remove a porta correta',
        () async {
      await firestore.collection('doors').doc('door-1').set({
        'id': 'door-1',
        'name': 'Porta principal',
        'locationId': 'araxa',
      });
      await firestore.collection('doors').doc('door-2').set({
        'id': 'door-2',
        'name': 'Porta lateral',
        'locationId': 'perdizes',
      });

      final filtered = await repository.findAll(locationId: 'araxa');
      await repository.deleteById('door-1');

      expect(filtered, hasLength(1));
      expect(filtered.single.id, 'door-1');
      expect(
        (await firestore.collection('doors').doc('door-1').get()).exists,
        isFalse,
      );
      expect(
        (await firestore.collection('doors').doc('door-2').get()).exists,
        isTrue,
      );
    });
  });
}

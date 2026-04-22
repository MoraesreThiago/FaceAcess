import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:faceaccess/domain/entities/location.dart';
import 'package:faceaccess/infrastructure/persistence/firebase/firestore_location_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FirestoreLocationRepository', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreLocationRepository repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repository = FirestoreLocationRepository(firestore: firestore);
    });

    test('save grava doc keyed por id estável e findAll faz roundtrip', () async {
      await repository.save(
        const Location(
          id: 'araxa',
          name: 'Araxá',
        ),
      );

      final document = await firestore.collection('locations').doc('araxa').get();
      final all = await repository.findAll();

      expect(document.exists, isTrue);
      expect(document.data()!['id'], 'araxa');
      expect(document.data()!['name'], 'Araxá');
      expect(document.data()!['updatedAt'], isA<Timestamp>());
      expect(all, hasLength(1));
      expect(all.single.id, 'araxa');
      expect(all.single.name, 'Araxá');
    });

    test('deleteById remove apenas o documento correto', () async {
      await firestore.collection('locations').doc('araxa').set({
        'id': 'araxa',
        'name': 'Araxá',
      });
      await firestore.collection('locations').doc('perdizes').set({
        'id': 'perdizes',
        'name': 'Perdizes',
      });

      await repository.deleteById('araxa');

      expect(
        (await firestore.collection('locations').doc('araxa').get()).exists,
        isFalse,
      );
      expect(
        (await firestore.collection('locations').doc('perdizes').get()).exists,
        isTrue,
      );
    });
  });
}

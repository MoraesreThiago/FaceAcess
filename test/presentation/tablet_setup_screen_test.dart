import 'package:faceaccess/app/providers/repository_providers.dart';
import 'package:faceaccess/domain/entities/door.dart';
import 'package:faceaccess/domain/entities/location.dart';
import 'package:faceaccess/domain/entities/tablet_assignment.dart';
import 'package:faceaccess/domain/entities/tablet_identity.dart';
import 'package:faceaccess/domain/repositories/door_repository.dart';
import 'package:faceaccess/domain/repositories/location_repository.dart';
import 'package:faceaccess/domain/repositories/tablet_config_repository.dart';
import 'package:faceaccess/presentation/tablet_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TabletSetupScreen', () {
    late _FakeLocationRepository locationRepository;
    late _FakeDoorRepository doorRepository;
    late _FakeTabletConfigRepository tabletConfigRepository;
    late TabletIdentity identity;
    late int onDoneCalls;

    Widget buildHarness({
      TabletAssignment? initialAssignment,
    }) {
      return ProviderScope(
        overrides: [
          locationRepositoryProvider.overrideWithValue(locationRepository),
          doorRepositoryProvider.overrideWithValue(doorRepository),
          tabletConfigRepositoryProvider.overrideWith(
            (ref) async => tabletConfigRepository,
          ),
        ],
        child: MaterialApp(
          home: TabletSetupScreen(
            identity: identity,
            initialAssignment: initialAssignment,
            onDone: () => onDoneCalls++,
          ),
        ),
      );
    }

    setUp(() {
      locationRepository = _FakeLocationRepository(
        locations: const <Location>[
          Location(id: 'loc-araxa', name: 'Araxa'),
          Location(id: 'loc-perdizes', name: 'Perdizes'),
        ],
      );
      doorRepository = _FakeDoorRepository(
        doors: const <Door>[
          Door(
            id: 'door-araxa-1',
            name: 'Porta Principal',
            locationId: 'loc-araxa',
          ),
          Door(
            id: 'door-araxa-2',
            name: 'Porta Recebimento',
            locationId: 'loc-araxa',
          ),
          Door(
            id: 'door-perdizes-1',
            name: 'Porta Expedicao',
            locationId: 'loc-perdizes',
          ),
        ],
      );
      tabletConfigRepository = _FakeTabletConfigRepository(
        identity: const TabletIdentity(id: 'tablet-1', name: ''),
      );
      identity = const TabletIdentity(id: 'tablet-1', name: '');
      onDoneCalls = 0;
    });

    testWidgets(
      'salva assignment com locationId e doorId reais',
      (tester) async {
        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('tablet-setup-name-field')),
          'Porta Norte',
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const ValueKey('tablet-setup-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('tablet-setup-save-button')),
        );
        await tester.pumpAndSettle();

        expect(tabletConfigRepository.savedIdentity, isNotNull);
        expect(tabletConfigRepository.savedIdentity!.name, 'Porta Norte');
        expect(tabletConfigRepository.savedAssignment, isNotNull);
        expect(tabletConfigRepository.savedAssignment!.tabletId, 'tablet-1');
        expect(tabletConfigRepository.savedAssignment!.locationId, 'loc-araxa');
        expect(tabletConfigRepository.savedAssignment!.doorId, 'door-araxa-1');
        expect(onDoneCalls, 1);
      },
    );

    testWidgets(
      'trocar location recarrega e preseleciona porta da unidade escolhida',
      (tester) async {
        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('tablet-setup-location-field')),
        );
        await tester.tap(
          find.byKey(const ValueKey('tablet-setup-location-field')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey('tablet-setup-location-option-loc-perdizes'),
          ).last,
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('tablet-setup-door-field')),
          findsOneWidget,
        );
        expect(find.text('Porta Expedicao'), findsWidgets);

        await tester.enterText(
          find.byKey(const ValueKey('tablet-setup-name-field')),
          'Porta Sul',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('tablet-setup-save-button')),
        );
        final saveButton = tester.widget<ElevatedButton>(
          find.byKey(const ValueKey('tablet-setup-save-button')),
        );
        expect(saveButton.onPressed, isNotNull);
        await tester.tap(
          find.byKey(const ValueKey('tablet-setup-save-button')),
        );
        await tester.pumpAndSettle();

        expect(tabletConfigRepository.savedAssignment, isNotNull);
        expect(tabletConfigRepository.savedAssignment!.locationId, 'loc-perdizes');
        expect(tabletConfigRepository.savedAssignment!.doorId, 'door-perdizes-1');
      },
    );

    testWidgets(
      'assignment inicial preseleciona location e door existentes',
      (tester) async {
        await tester.pumpWidget(
          buildHarness(
            initialAssignment: const TabletAssignment(
              tabletId: 'tablet-1',
              locationId: 'loc-araxa',
              doorId: 'door-araxa-2',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('tablet-setup-location-field')),
          findsOneWidget,
        );
        expect(find.text('Araxa'), findsWidgets);
        expect(find.text('Porta Recebimento'), findsWidgets);
      },
    );
  });
}

class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository({required this.locations});

  final List<Location> locations;

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<List<Location>> findAll() async => locations;

  @override
  Future<Location?> findById(String id) async {
    for (final location in locations) {
      if (location.id == id) {
        return location;
      }
    }
    return null;
  }

  @override
  Future<void> save(Location location) async {}
}

class _FakeDoorRepository implements DoorRepository {
  _FakeDoorRepository({required this.doors});

  final List<Door> doors;

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<List<Door>> findAll({String? locationId}) async {
    if (locationId == null || locationId.isEmpty) {
      return doors;
    }

    return doors
        .where((door) => door.locationId == locationId)
        .toList(growable: false);
  }

  @override
  Future<Door?> findById(String id) async {
    for (final door in doors) {
      if (door.id == id) {
        return door;
      }
    }
    return null;
  }

  @override
  Future<void> save(Door door) async {}
}

class _FakeTabletConfigRepository implements TabletConfigRepository {
  _FakeTabletConfigRepository({
    required this.identity,
  });

  TabletIdentity identity;
  TabletAssignment? assignment;
  TabletIdentity? savedIdentity;
  TabletAssignment? savedAssignment;

  @override
  Future<TabletAssignment?> getAssignment() async => assignment;

  @override
  Future<TabletIdentity> getOrCreateIdentity() async => identity;

  @override
  Future<void> saveAssignment(TabletAssignment assignment) async {
    savedAssignment = assignment;
    this.assignment = assignment;
  }

  @override
  Future<void> saveIdentity(TabletIdentity identity) async {
    savedIdentity = identity;
    this.identity = identity;
  }
}

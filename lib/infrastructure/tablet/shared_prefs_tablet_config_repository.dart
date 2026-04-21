import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/tablet_assignment.dart';
import '../../domain/entities/tablet_identity.dart';
import '../../domain/repositories/tablet_config_repository.dart';

/// Implementação real de [TabletConfigRepository] sobre [SharedPreferences].
///
/// **Chaves (novas)** — gravadas a partir deste PR:
///   - `tablet_identity_id`        → UUID do tablet (imutável)
///   - `tablet_identity_name`      → nome amigável escolhido pelo operador
///   - `tablet_assignment_location_id` → unidade atualmente atribuída
///   - `tablet_assignment_door_id`     → porta atualmente atribuída
///     (pode continuar `null` nesta fase — UX de seleção de porta
///     chega em PR futuro)
///
/// **Chaves (legadas)** — do antigo `TabletConfig`, preservadas
/// para rollback nesta fase:
///   - `tablet_id`    → lida como semente do novo `tablet_identity_id`
///   - `tablet_name`  → lida como semente do novo `tablet_identity_name`
///   - `tablet_unit`  → lida como semente do novo
///                      `tablet_assignment_location_id`
///
/// **Flag de migração**: `tablet_config_migrated_v1`. Garante que a
/// rotina de migração legada só rode uma vez, mesmo em boots futuros.
///
/// **Garantias de compatibilidade**:
/// - Tablets já em produção: o `initialize()` copia as chaves legadas
///   para as novas sem perda, e o app continua enxergando o mesmo
///   `id`/`name`/`locationId` que tinha antes.
/// - Tablets novos: as chaves legadas simplesmente não existem; a
///   identidade é criada com UUID fresco e o tablet segue direto para
///   a tela de setup.
/// - A migração é **idempotente**: chamar `initialize()` várias vezes
///   não corrompe nada.
/// - As chaves legadas **não são apagadas** nesta fase — servem de
///   rede de segurança para rollback.
class SharedPrefsTabletConfigRepository implements TabletConfigRepository {
  SharedPrefsTabletConfigRepository(this._prefs, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final SharedPreferences _prefs;
  final Uuid _uuid;

  // ── Chaves novas ────────────────────────────────────────────────────
  static const String identityIdKey = 'tablet_identity_id';
  static const String identityNameKey = 'tablet_identity_name';
  static const String assignmentLocationIdKey = 'tablet_assignment_location_id';
  static const String assignmentDoorIdKey = 'tablet_assignment_door_id';

  // ── Chaves legadas (preservadas para rollback) ─────────────────────
  static const String legacyIdKey = 'tablet_id';
  static const String legacyNameKey = 'tablet_name';
  static const String legacyUnitKey = 'tablet_unit';

  // ── Flag de migração ────────────────────────────────────────────────
  static const String migrationFlagKey = 'tablet_config_migrated_v1';

  /// Executa a migração legada (idempotente) e garante que exista uma
  /// identidade persistida. Deve ser chamado antes de qualquer leitura.
  Future<void> initialize() async {
    await _migrateLegacyIfNeeded();
    await getOrCreateIdentity();
  }

  Future<void> _migrateLegacyIfNeeded() async {
    // Já migrou antes? sai silenciosamente.
    if (_prefs.getBool(migrationFlagKey) == true) return;

    // Se já existem chaves novas (ex.: instalação limpa + cenário
    // anômalo), também marca como migrado sem tocar nelas.
    final hasNewData = _prefs.containsKey(identityIdKey);

    if (!hasNewData) {
      final legacyId = _prefs.getString(legacyIdKey);
      final legacyName = _prefs.getString(legacyNameKey);
      final legacyUnit = _prefs.getString(legacyUnitKey);

      if (legacyId != null && legacyId.isNotEmpty) {
        await _prefs.setString(identityIdKey, legacyId);
      }
      if (legacyName != null && legacyName.isNotEmpty) {
        await _prefs.setString(identityNameKey, legacyName);
      }
      if (legacyUnit != null && legacyUnit.isNotEmpty) {
        await _prefs.setString(assignmentLocationIdKey, legacyUnit);
      }
      // Observação deliberada: NÃO removemos as chaves legadas neste
      // PR. Elas ficam intactas como seguro de rollback. A limpeza
      // (e a remoção do próprio código de migração) é tarefa de um
      // PR futuro, quando esta migração estiver comprovadamente
      // estável em produção.
    }

    await _prefs.setBool(migrationFlagKey, true);
  }

  @override
  Future<TabletIdentity> getOrCreateIdentity() async {
    var id = _prefs.getString(identityIdKey);
    if (id == null || id.isEmpty) {
      id = _uuid.v4();
      await _prefs.setString(identityIdKey, id);
    }
    final name = _prefs.getString(identityNameKey) ?? '';
    return TabletIdentity(id: id, name: name);
  }

  @override
  Future<TabletAssignment?> getAssignment() async {
    final identity = await getOrCreateIdentity();
    final locationId = _prefs.getString(assignmentLocationIdKey);
    final doorId = _prefs.getString(assignmentDoorIdKey);

    // Sem nada atribuído ainda → o tablet precisa ir para setup.
    if ((locationId == null || locationId.isEmpty) &&
        (doorId == null || doorId.isEmpty)) {
      return null;
    }

    return TabletAssignment(
      tabletId: identity.id,
      locationId: (locationId != null && locationId.isNotEmpty)
          ? locationId
          : null,
      doorId: (doorId != null && doorId.isNotEmpty) ? doorId : null,
    );
  }

  @override
  Future<void> saveIdentity(TabletIdentity identity) async {
    await _prefs.setString(identityIdKey, identity.id);
    await _prefs.setString(identityNameKey, identity.name);
  }

  @override
  Future<void> saveAssignment(TabletAssignment assignment) async {
    if (assignment.locationId != null && assignment.locationId!.isNotEmpty) {
      await _prefs.setString(assignmentLocationIdKey, assignment.locationId!);
    } else {
      await _prefs.remove(assignmentLocationIdKey);
    }
    if (assignment.doorId != null && assignment.doorId!.isNotEmpty) {
      await _prefs.setString(assignmentDoorIdKey, assignment.doorId!);
    } else {
      await _prefs.remove(assignmentDoorIdKey);
    }
  }
}

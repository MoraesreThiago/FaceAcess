import '../entities/tablet_assignment.dart';
import '../entities/tablet_identity.dart';

/// Contrato para gerenciar a identidade e a atribuição do tablet.
///
/// Separação deliberada: [TabletIdentity] é imutável após a primeira
/// criação; [TabletAssignment] pode mudar sempre que o tablet for
/// realocado para outra porta ou unidade.
abstract class TabletConfigRepository {
  /// Retorna a identidade do tablet, criando-a na primeira chamada.
  Future<TabletIdentity> getOrCreateIdentity();

  /// Retorna a atribuição atual do tablet, ou `null` se ainda não
  /// tiver sido configurado (porta/unidade não definidos).
  Future<TabletAssignment?> getAssignment();

  Future<void> saveIdentity(TabletIdentity identity);

  Future<void> saveAssignment(TabletAssignment assignment);
}

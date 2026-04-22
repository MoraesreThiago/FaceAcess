/// Atribuição funcional de um tablet: a qual porta e/ou unidade ele
/// está vinculado no momento.
///
/// Modelagem simples com vínculos singulares:
/// - [tabletId]: referência para a [TabletIdentity] correspondente.
/// - [doorId]: porta específica que este tablet controla (pode ser nulo
///   enquanto ainda não foi configurado).
/// - [locationId]: unidade à qual a porta/tablet pertence (pode ser
///   nulo enquanto não configurado).
///
/// Este registro é mutável — pode ser trocado sem afetar a
/// [TabletIdentity] subjacente.
class TabletAssignment {
  final String tabletId;
  final String? doorId;
  final String? locationId;

  const TabletAssignment({
    required this.tabletId,
    this.doorId,
    this.locationId,
  });

  bool get isConfigured =>
      doorId != null &&
      doorId!.isNotEmpty &&
      locationId != null &&
      locationId!.isNotEmpty;

  TabletAssignment copyWith({
    String? doorId,
    String? locationId,
  }) {
    return TabletAssignment(
      tabletId: tabletId,
      doorId: doorId ?? this.doorId,
      locationId: locationId ?? this.locationId,
    );
  }
}

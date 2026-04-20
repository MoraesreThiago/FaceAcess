/// Porta física cadastrada no sistema.
///
/// O domínio é neutro em relação ao meio de acionamento: detalhes como
/// tópico MQTT vivem exclusivamente na infraestrutura (ex.:
/// `infrastructure/door/`). Aqui mantemos apenas a identidade e o
/// vínculo com a unidade.
class Door {
  final String id;
  final String name;
  final String locationId;

  const Door({
    required this.id,
    required this.name,
    required this.locationId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Door && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

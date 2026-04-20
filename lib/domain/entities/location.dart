/// Unidade física onde o sistema opera (ex.: "araxa", "perdizes").
///
/// [id] é um slug estável usado como chave em referências cruzadas
/// (ex.: [Person.locationIds], [TabletAssignment.locationId]).
/// [name] é o rótulo amigável para exibição.
class Location {
  final String id;
  final String name;

  const Location({
    required this.id,
    required this.name,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Location && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

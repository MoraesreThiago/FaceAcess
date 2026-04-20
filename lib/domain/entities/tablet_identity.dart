/// Identidade física de um tablet.
///
/// [id] é um UUID gerado uma única vez no primeiro boot e não muda
/// mesmo que o tablet seja realocado para outra porta/unidade.
/// [name] é o nome amigável definido pelo operador.
///
/// A atribuição funcional (qual porta/unidade o tablet controla) vive
/// em [TabletAssignment] e é mutável.
class TabletIdentity {
  final String id;
  final String name;

  const TabletIdentity({
    required this.id,
    required this.name,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TabletIdentity && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

import 'face_embedding.dart';
import 'user_role.dart';

/// Pessoa cadastrada no sistema de controle de acesso.
///
/// [id] é um UUID estável, independente do nome (resolve o problema
/// histórico de usar o nome como chave primária).
///
/// [locationIds] é um conjunto: uma pessoa pode ter acesso a múltiplas
/// unidades (ex.: gerente que circula entre Araxá e Perdizes).
///
/// [role] reutiliza o enum `UserRole` já existente no projeto, que
/// reflete os cargos reais (admin, diretor, gerente, supervisor, lider,
/// manutentor, operador). Enquanto `user_role.dart` ainda depender de
/// Flutter, esta entidade herda essa dependência transitivamente —
/// dívida pré-existente a ser resolvida em fase posterior.
class Person {
  final String id;
  final String name;
  final UserRole role;
  final Set<String> locationIds;
  final List<FaceEmbedding> embeddings;
  final DateTime createdAt;

  const Person({
    required this.id,
    required this.name,
    required this.role,
    required this.locationIds,
    required this.embeddings,
    required this.createdAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Person && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

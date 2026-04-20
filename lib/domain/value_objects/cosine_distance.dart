import 'dart:math' as math;

import '../entities/face_embedding.dart';

/// Value object para distância de cosseno entre dois embeddings.
///
/// Convenção: **distância** (1 - similaridade), não similaridade.
/// Valores menores = mais parecidos. Valor 0 = idênticos em direção.
///
/// Usado pela lógica de matching facial para decidir se um embedding
/// observado é suficientemente próximo de um embedding cadastrado.
class CosineDistance {
  final double value;

  const CosineDistance(this.value);

  /// Calcula a distância de cosseno entre dois embeddings.
  /// Lança [ArgumentError] se os vetores tiverem tamanhos diferentes.
  factory CosineDistance.between(FaceEmbedding a, FaceEmbedding b) {
    if (a.length != b.length) {
      throw ArgumentError(
        'Embeddings com dimensões diferentes: ${a.length} vs ${b.length}',
      );
    }
    double dot = 0;
    double normA = 0;
    double normB = 0;
    for (int i = 0; i < a.length; i++) {
      final va = a.values[i];
      final vb = b.values[i];
      dot += va * vb;
      normA += va * va;
      normB += vb * vb;
    }
    final denom = math.sqrt(normA) * math.sqrt(normB);
    if (denom == 0) return const CosineDistance(1.0);
    final similarity = dot / denom;
    return CosineDistance(1.0 - similarity);
  }

  bool isBelow(double threshold) => value < threshold;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CosineDistance && other.value == value);

  @override
  int get hashCode => value.hashCode;
}

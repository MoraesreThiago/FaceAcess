import 'dart:math' as math;

/// Vetor de embedding facial produzido pelo modelo de reconhecimento
/// (FaceNet 512-d). Encapsula a lista de doubles com operações comuns
/// de distância/normalização em Dart puro.
class FaceEmbedding {
  final List<double> values;

  const FaceEmbedding(this.values);

  int get length => values.length;

  /// Retorna uma nova instância com norma L2 = 1.
  /// Se a norma for zero, retorna uma cópia inalterada.
  FaceEmbedding l2Normalized() {
    double sumSq = 0;
    for (final v in values) {
      sumSq += v * v;
    }
    final norm = math.sqrt(sumSq);
    if (norm == 0) return FaceEmbedding(List<double>.from(values));
    return FaceEmbedding([for (final v in values) v / norm]);
  }
}

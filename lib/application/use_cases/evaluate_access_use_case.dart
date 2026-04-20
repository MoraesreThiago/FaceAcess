import 'dart:math';

import '../../domain/entities/access_decision.dart';
import '../../infrastructure/face_database.dart';

class EvaluateAccessUseCase {
  final FaceDatabase _faceDatabase;

  // Cosine distance threshold — lower is stricter.
  // 0.45 is a good balance between security and usability for FaceNet 512-d.
  static const double _threshold = 0.45;

  EvaluateAccessUseCase({required FaceDatabase faceDatabase})
      : _faceDatabase = faceDatabase;

  Future<AccessDecision> execute(List<double> queryEmbedding) async {
    final db = await _faceDatabase.loadAll();

    String? bestMatch;
    PersonRecord? bestRecord;
    double bestDistance = double.infinity;

    for (final entry in db.entries) {
      for (final stored in entry.value.embeddings) {
        final d = _cosineDistance(queryEmbedding, stored);
        if (d < bestDistance) {
          bestDistance = d;
          bestMatch = entry.key;
          bestRecord = entry.value;
        }
      }
    }

    if (bestMatch != null && bestRecord != null && bestDistance <= _threshold) {
      return AccessDecision.authorized(
        personName: bestMatch,
        role: bestRecord.role,
        confidence: 1.0 - bestDistance,
      );
    }

    return AccessDecision.denied();
  }

  double _cosineDistance(List<double> a, List<double> b) {
    double dot = 0, na = 0, nb = 0;
    final len = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < len; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    final denom = sqrt(na) * sqrt(nb);
    if (denom == 0) return 1.0;
    return 1.0 - dot / denom;
  }
}

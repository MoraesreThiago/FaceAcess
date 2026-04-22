import 'dart:math';

import '../../domain/entities/access_decision.dart';
import '../../domain/entities/person.dart';
import '../../domain/repositories/person_repository.dart';

/// Avalia um embedding de query contra todas as pessoas conhecidas e
/// decide se o acesso é autorizado.
///
/// PR #7: passou a depender do contrato `PersonRepository` em vez do
/// `FaceDatabase` concreto. A **lógica de matching** (cosine distance,
/// threshold 0.45) é intencionalmente idêntica à anterior — alterações
/// na lógica de reconhecimento são escopo de PRs futuros (#9/#10).
class EvaluateAccessUseCase {
  EvaluateAccessUseCase({required PersonRepository personRepository})
      : _personRepository = personRepository;

  final PersonRepository _personRepository;

  // Cosine distance threshold — lower is stricter.
  // 0.45 is a good balance between security and usability for FaceNet 512-d.
  static const double _threshold = 0.45;

  Future<AccessDecision> execute(List<double> queryEmbedding) async {
    final people = await _personRepository.findAll();

    Person? bestMatch;
    double bestDistance = double.infinity;

    for (final person in people) {
      for (final stored in person.embeddings) {
        final d = _cosineDistance(queryEmbedding, stored.values);
        if (d < bestDistance) {
          bestDistance = d;
          bestMatch = person;
        }
      }
    }

    if (bestMatch != null && bestDistance <= _threshold) {
      return AccessDecision.authorized(
        personName: bestMatch.name,
        role: bestMatch.role,
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

/// Contrato para registrar eventos de acesso (tentativas e liberações).
///
/// O domínio não conhece Firestore nem Hive. A implementação decide
/// onde/como persistir.
abstract class AccessLogRepository {
  Future<void> record({
    required DateTime timestamp,
    required String tabletId,
    required String tabletName,
    required String? locationId,
    required String? doorId,
    required bool granted,
    String? personId,
    String? personName,
    String? roleKey,
    double? confidence,
  });
}

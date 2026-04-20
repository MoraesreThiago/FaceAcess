import 'package:cloud_firestore/cloud_firestore.dart';

/// Grava cada tentativa de acesso no Firestore.
class AccessLogService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'access_logs';

  final String tabletId;
  final String tabletName;
  final String unit;

  AccessLogService({
    required this.tabletId,
    required this.tabletName,
    required this.unit,
  });

  Future<void> log({
    required String personName,
    required bool authorized,
    String? role,
  }) async {
    try {
      await _db.collection(_collection).add({
        'personName': personName,
        'authorized': authorized,
        'role': role,
        'tabletId': tabletId,
        'tabletName': tabletName,
        'unit': unit,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Falha silenciosa — log não deve interromper o fluxo de acesso
    }
  }
}

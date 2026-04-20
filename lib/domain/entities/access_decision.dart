import 'user_role.dart';

class AccessDecision {
  final bool isAuthorized;
  final String? personName;
  final UserRole? role;
  final double? confidence;
  final DateTime timestamp;

  const AccessDecision({
    required this.isAuthorized,
    this.personName,
    this.role,
    this.confidence,
    required this.timestamp,
  });

  factory AccessDecision.authorized({
    required String personName,
    required UserRole role,
    required double confidence,
  }) =>
      AccessDecision(
        isAuthorized: true,
        personName: personName,
        role: role,
        confidence: confidence,
        timestamp: DateTime.now(),
      );

  factory AccessDecision.denied() => AccessDecision(
        isAuthorized: false,
        timestamp: DateTime.now(),
      );
}

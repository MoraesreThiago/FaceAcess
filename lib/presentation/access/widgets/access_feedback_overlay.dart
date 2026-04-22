import 'package:flutter/material.dart';

import '../../../domain/entities/access_decision.dart';
import '../../../domain/entities/user_role.dart';

class AccessFeedbackOverlay extends StatelessWidget {
  const AccessFeedbackOverlay({
    super.key,
    required this.visible,
    required this.decision,
    required this.greeting,
  });

  final bool visible;
  final AccessDecision decision;
  final String greeting;

  @override
  Widget build(BuildContext context) {
    final authorized = decision.isAuthorized;
    final role = decision.role;
    final baseColor = authorized ? (role?.color ?? Colors.green) : Colors.red;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                baseColor.withValues(alpha: 0.95),
                baseColor.withValues(alpha: 0.75),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: Icon(
                  authorized
                      ? (role?.icon ?? Icons.check_circle_outline)
                      : Icons.block,
                  size: 70,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              if (authorized && decision.personName != null) ...[
                Text(
                  '$greeting,',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  decision.personName!,
                  style: const TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                if (role != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white54, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(role.icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          role.label.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
              ] else ...[
                const Text(
                  'NÃO AUTORIZADO',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/flavor.dart';
import '../app/providers/application_providers.dart';
import '../app/providers/repository_providers.dart';
import '../application/result.dart';
import '../domain/entities/operator_role.dart';
import '../domain/entities/tablet_assignment.dart';
import '../domain/entities/tablet_identity.dart';

class LoginScreen extends ConsumerWidget {
  final TabletIdentity identity;
  final TabletAssignment? assignment;
  final void Function(OperatorRole role) onLogin;

  const LoginScreen({
    super.key,
    required this.identity,
    required this.assignment,
    required this.onLogin,
  });

  Future<void> _askPassword(
    BuildContext context,
    WidgetRef ref,
    OperatorRole role,
  ) async {
    final controller = TextEditingController();
    bool obscure = true;
    String? errorText;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                role == OperatorRole.admin ? Icons.admin_panel_settings : Icons.door_front_door,
                color: role == OperatorRole.admin
                    ? Colors.amberAccent
                    : Colors.cyanAccent,
              ),
              const SizedBox(width: 10),
              Text(
                role.label,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                obscureText: obscure,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Senha',
                  hintStyle: const TextStyle(color: Colors.white38),
                  errorText: errorText,
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white24),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: role == OperatorRole.admin
                          ? Colors.amberAccent
                          : Colors.cyanAccent,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.redAccent),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.redAccent),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white38,
                    ),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
                onSubmitted: (_) => _tryLogin(
                  ctx, ref, role, controller.text, setDialogState,
                  (err) => errorText = err,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => _tryLogin(
                ctx, ref, role, controller.text, setDialogState,
                (err) => errorText = err,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: role == OperatorRole.admin
                    ? Colors.amber[700]
                    : Colors.cyan[700],
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Entrar',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _tryLogin(
    BuildContext ctx,
    WidgetRef ref,
    OperatorRole role,
    String password,
    StateSetter setDialogState,
    void Function(String?) setError,
  ) async {
    // A tela só é mostrada depois que `loginUseCaseProvider` resolveu no
    // boot (ver `app.dart`), portanto `requireValue` é seguro aqui.
    final useCase = ref.read(loginUseCaseProvider).requireValue;
    final result = await useCase.call(role: role, password: password);

    if (!ctx.mounted) return;

    switch (result) {
      case Success():
        Navigator.pop(ctx);
        onLogin(role);
      case Err():
        setDialogState(() => setError('Senha incorreta'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // PR #6.5: cada APK (flavor) só expõe o perfil que lhe pertence.
    // O flavor é decidido no entrypoint (`main_admin` / `main_porta`),
    // não pelo operador — por isso o card do outro perfil nem aparece.
    final flavor = ref.watch(appFlavorProvider);
    final role = flavor == AppFlavor.admin
        ? OperatorRole.admin
        : OperatorRole.porta;
    final assignmentConfigured = assignment?.isConfigured ?? false;
    final locationId = assignment?.locationId;
    final doorId = assignment?.doorId;
    final location = locationId == null
        ? null
        : ref.watch(locationByIdProvider(locationId)).valueOrNull;
    final door =
        doorId == null ? null : ref.watch(doorByIdProvider(doorId)).valueOrNull;
    final footerLabel = _buildFooterLabel(
      assignmentConfigured: assignmentConfigured,
      locationName: location?.name ?? locationId,
      doorName: door?.name ?? doorId,
    );
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // ── Topo ───────────────────────────────────────────────────────────
            Expanded(
              flex: 3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/logo_bembrasil.png',
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield, color: Colors.white54, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'FACE ACCESS',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    identity.name.isNotEmpty ? identity.name : 'Tablet',
                    style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),

            // ── Cards de perfil ────────────────────────────────────────────────
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      role == OperatorRole.admin
                          ? 'Acesso de administrador'
                          : 'Acesso porta',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 14),
                    ),
                    const SizedBox(height: 32),
                    // Um único card — o flavor define qual perfil aparece.
                    // A outra metade do Row é um Spacer para manter o card
                    // com a mesma largura dos mockups anteriores (~50% da
                    // área útil).
                    Row(
                      children: [
                        Expanded(
                          child: _ProfileCard(
                            icon: role == OperatorRole.admin
                                ? Icons.admin_panel_settings
                                : Icons.door_front_door,
                            label: role == OperatorRole.admin
                                ? 'Administrador'
                                : 'Acesso\nPorta',
                            color: role == OperatorRole.admin
                                ? Colors.amberAccent
                                : Colors.cyanAccent,
                            onTap: () => _askPassword(context, ref, role),
                          ),
                        ),
                        const SizedBox(width: 20),
                        const Spacer(),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Rodapé ─────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                footerLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white24, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildFooterLabel({
    required bool assignmentConfigured,
    String? locationName,
    String? doorName,
  }) {
    if (!assignmentConfigured) {
      return 'Configuracao do tablet pendente';
    }

    final normalizedLocation = locationName?.trim();
    final normalizedDoor = doorName?.trim();

    if (normalizedLocation != null &&
        normalizedLocation.isNotEmpty &&
        normalizedDoor != null &&
        normalizedDoor.isNotEmpty) {
      return 'Unidade: $normalizedLocation • Porta: $normalizedDoor';
    }

    if (normalizedDoor != null && normalizedDoor.isNotEmpty) {
      return 'Porta: $normalizedDoor';
    }

    if (normalizedLocation != null && normalizedLocation.isNotEmpty) {
      return 'Unidade: $normalizedLocation';
    }

    return 'Configuracao do tablet pendente';
  }
}

class _ProfileCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 48),
            const SizedBox(height: 16),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

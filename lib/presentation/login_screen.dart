import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers/application_providers.dart';
import '../application/result.dart';
import '../domain/entities/operator_role.dart';
import '../infrastructure/tablet_config.dart';

class LoginScreen extends ConsumerWidget {
  final TabletConfig tabletConfig;
  final void Function(OperatorRole role) onLogin;

  const LoginScreen({
    super.key,
    required this.tabletConfig,
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
                    tabletConfig.name.isNotEmpty
                        ? tabletConfig.name
                        : 'Tablet',
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
                    const Text(
                      'Selecione o perfil de acesso',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        // Admin
                        Expanded(
                          child: _ProfileCard(
                            icon: Icons.admin_panel_settings,
                            label: 'Administrador',
                            color: Colors.amberAccent,
                            onTap: () =>
                                _askPassword(context, ref, OperatorRole.admin),
                          ),
                        ),
                        const SizedBox(width: 20),
                        // Porta
                        Expanded(
                          child: _ProfileCard(
                            icon: Icons.door_front_door,
                            label: 'Acesso\nPorta',
                            color: Colors.cyanAccent,
                            onTap: () =>
                                _askPassword(context, ref, OperatorRole.porta),
                          ),
                        ),
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
                tabletConfig.unit.isNotEmpty
                    ? 'Unidade: ${tabletConfig.unit[0].toUpperCase()}${tabletConfig.unit.substring(1)}'
                    : '',
                style:
                    const TextStyle(color: Colors.white12, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
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

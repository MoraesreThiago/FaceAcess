import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers/infrastructure_providers.dart';
import '../app/providers/repository_providers.dart';
import '../domain/entities/tablet_assignment.dart';
import '../domain/entities/tablet_identity.dart';

class TabletSetupScreen extends ConsumerStatefulWidget {
  final TabletIdentity identity;
  final VoidCallback onDone;

  const TabletSetupScreen({
    super.key,
    required this.identity,
    required this.onDone,
  });

  @override
  ConsumerState<TabletSetupScreen> createState() => _TabletSetupScreenState();
}

class _TabletSetupScreenState extends ConsumerState<TabletSetupScreen> {
  final _nameController = TextEditingController();
  String _selectedUnit = 'araxa';
  bool _saving = false;

  final _units = const [
    {'key': 'araxa', 'label': 'Araxá'},
    {'key': 'perdizes', 'label': 'Perdizes'},
  ];

  @override
  void initState() {
    super.initState();
    // Prefill com o nome atual, se já existir (caso o tablet seja
    // reconfigurado). Comportamento equivalente ao legado, que também
    // deixava o campo em branco em setup novo.
    _nameController.text = widget.identity.name;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);

    final repo = await ref.read(tabletConfigRepositoryProvider.future);
    await repo.saveIdentity(
      TabletIdentity(id: widget.identity.id, name: name),
    );
    await repo.saveAssignment(
      TabletAssignment(
        tabletId: widget.identity.id,
        locationId: _selectedUnit,
        // doorId permanece null nesta fase — seleção de porta chega
        // em PR futuro.
      ),
    );

    // Invalida as views — app.dart re-lê e roteia para AccessScreen.
    ref.invalidate(tabletIdentityProvider);
    ref.invalidate(tabletAssignmentProvider);

    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.tablet_android,
                    color: Colors.white54, size: 64),
                const SizedBox(height: 24),
                const Text(
                  'Configuração do Tablet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Esta configuração só é feita uma vez.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
                const SizedBox(height: 40),

                // Nome do tablet
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nome do tablet (ex: Porta Principal)',
                    labelStyle: const TextStyle(color: Colors.white54),
                    prefixIcon:
                        const Icon(Icons.label_outline, color: Colors.white38),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          const BorderSide(color: Colors.cyanAccent, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),

                // Unidade
                const Text(
                  'UNIDADE',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: _units.map((u) {
                    final selected = _selectedUnit == u['key'];
                    return Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedUnit = u['key']!),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.cyanAccent.withOpacity(0.15)
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? Colors.cyanAccent
                                  : Colors.white12,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            u['label']!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: selected
                                  ? Colors.cyanAccent
                                  : Colors.white54,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 40),

                ElevatedButton(
                  onPressed: _nameController.text.trim().isEmpty || _saving
                      ? null
                      : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text(
                          'Confirmar e iniciar',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}

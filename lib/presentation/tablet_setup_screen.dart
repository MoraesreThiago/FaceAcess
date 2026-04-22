import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers/infrastructure_providers.dart';
import '../app/providers/repository_providers.dart';
import '../domain/entities/door.dart';
import '../domain/entities/location.dart';
import '../domain/entities/tablet_assignment.dart';
import '../domain/entities/tablet_identity.dart';

class TabletSetupScreen extends ConsumerStatefulWidget {
  const TabletSetupScreen({
    super.key,
    required this.identity,
    required this.onDone,
    this.initialAssignment,
  });

  final TabletIdentity identity;
  final TabletAssignment? initialAssignment;
  final VoidCallback onDone;

  @override
  ConsumerState<TabletSetupScreen> createState() => _TabletSetupScreenState();
}

class _TabletSetupScreenState extends ConsumerState<TabletSetupScreen> {
  final _nameController = TextEditingController();

  List<Location> _locations = const <Location>[];
  List<Door> _doors = const <Door>[];
  String? _selectedLocationId;
  String? _selectedDoorId;
  bool _loading = true;
  bool _loadingDoors = false;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.identity.name;
    Future<void>.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final locationRepository = ref.read(locationRepositoryProvider);
      final locations = await locationRepository.findAll();
      final selectedLocationId = _resolveLocationId(locations);
      final doors = selectedLocationId == null
          ? const <Door>[]
          : await ref
              .read(doorRepositoryProvider)
              .findAll(locationId: selectedLocationId);
      final selectedDoorId = _resolveDoorId(
        doors,
        preferredDoorId: widget.initialAssignment?.doorId,
      );

      if (!mounted) return;
      setState(() {
        _locations = locations;
        _doors = doors;
        _selectedLocationId = selectedLocationId;
        _selectedDoorId = selectedDoorId;
        _loading = false;
        _loadingDoors = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingDoors = false;
        _errorMessage = 'Nao foi possivel carregar unidades e portas.';
      });
    }
  }

  String? _resolveLocationId(List<Location> locations) {
    if (locations.isEmpty) return null;

    final preferredLocationId = widget.initialAssignment?.locationId;
    final preferredLocationExists = preferredLocationId != null &&
        locations.any((location) => location.id == preferredLocationId);

    if (preferredLocationExists) {
      return preferredLocationId;
    }

    return locations.first.id;
  }

  String? _resolveDoorId(
    List<Door> doors, {
    String? preferredDoorId,
  }) {
    if (doors.isEmpty) return null;

    final preferredDoorExists = preferredDoorId != null &&
        doors.any((door) => door.id == preferredDoorId);
    if (preferredDoorExists) {
      return preferredDoorId;
    }

    return doors.first.id;
  }

  Future<void> _onLocationChanged(String? locationId) async {
    if (locationId == null || locationId == _selectedLocationId) return;

    setState(() {
      _selectedLocationId = locationId;
      _selectedDoorId = null;
      _doors = const <Door>[];
      _loadingDoors = true;
      _errorMessage = null;
    });

    try {
      final doors =
          await ref.read(doorRepositoryProvider).findAll(locationId: locationId);
      if (!mounted || _selectedLocationId != locationId) return;

      setState(() {
        _doors = doors;
        _selectedDoorId = _resolveDoorId(doors);
        _loadingDoors = false;
      });
    } catch (_) {
      if (!mounted || _selectedLocationId != locationId) return;

      setState(() {
        _doors = const <Door>[];
        _selectedDoorId = null;
        _loadingDoors = false;
        _errorMessage = 'Nao foi possivel carregar as portas desta unidade.';
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final locationId = _selectedLocationId;
    final doorId = _selectedDoorId;
    if (name.isEmpty || locationId == null || doorId == null) return;

    setState(() => _saving = true);

    try {
      final repo = await ref.read(tabletConfigRepositoryProvider.future);
      await repo.saveIdentity(
        TabletIdentity(id: widget.identity.id, name: name),
      );
      await repo.saveAssignment(
        TabletAssignment(
          tabletId: widget.identity.id,
          locationId: locationId,
          doorId: doorId,
        ),
      );

      ref.invalidate(tabletIdentityProvider);
      ref.invalidate(tabletAssignmentProvider);

      widget.onDone();

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  bool get _canSave =>
      !_loading &&
      !_loadingDoors &&
      !_saving &&
      _nameController.text.trim().isNotEmpty &&
      _selectedLocationId != null &&
      _selectedDoorId != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 64,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.tablet_android,
                          color: Colors.white54,
                          size: 64,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Configuracao do tablet',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Defina a identidade do tablet e vincule a operacao a uma unidade e porta reais.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                        const SizedBox(height: 32),
                        TextField(
                          key: const ValueKey('tablet-setup-name-field'),
                          controller: _nameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            labelText: 'Nome do tablet',
                            icon: Icons.label_outline,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 20),
                        if (_loading)
                          const _SetupFeedbackState(
                            icon: Icons.sync,
                            message: 'Carregando unidades e portas...',
                            isLoading: true,
                          )
                        else if (_errorMessage != null)
                          _SetupFeedbackState(
                            icon: Icons.cloud_off,
                            message: _errorMessage!,
                            actionLabel: 'Tentar novamente',
                            onAction: _bootstrap,
                          )
                        else if (_locations.isEmpty)
                          _SetupFeedbackState(
                            icon: Icons.map_outlined,
                            message:
                                'Nenhuma unidade cadastrada ainda. Crie Locations e Doors no app admin antes de vincular este tablet.',
                            actionLabel: 'Atualizar',
                            onAction: _bootstrap,
                          )
                        else ...[
                          DropdownButtonFormField<String>(
                            key: const ValueKey('tablet-setup-location-field'),
                            initialValue: _selectedLocationId,
                            dropdownColor: const Color(0xFF161616),
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration(
                              labelText: 'Unidade',
                              icon: Icons.location_on_outlined,
                            ),
                            items: _locations
                                .map(
                                  (location) => DropdownMenuItem<String>(
                                    value: location.id,
                                    child: Text(
                                      location.name,
                                      key: ValueKey<String>(
                                        'tablet-setup-location-option-${location.id}',
                                      ),
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: _saving ? null : _onLocationChanged,
                          ),
                          const SizedBox(height: 20),
                          DropdownButtonFormField<String>(
                            key: const ValueKey('tablet-setup-door-field'),
                            initialValue: _selectedDoorId,
                            dropdownColor: const Color(0xFF161616),
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration(
                              labelText: 'Porta',
                              icon: Icons.door_front_door_outlined,
                              helperText: _loadingDoors
                                  ? 'Carregando portas desta unidade...'
                                  : _doors.isEmpty
                                      ? 'Nenhuma porta cadastrada para a unidade selecionada.'
                                      : null,
                            ),
                            items: _doors
                                .map(
                                  (door) => DropdownMenuItem<String>(
                                    value: door.id,
                                    child: Text(
                                      door.name,
                                      key: ValueKey<String>(
                                        'tablet-setup-door-option-${door.id}',
                                      ),
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: _saving || _loadingDoors || _doors.isEmpty
                                ? null
                                : (value) =>
                                    setState(() => _selectedDoorId = value),
                          ),
                        ],
                        const SizedBox(height: 32),
                        ElevatedButton(
                          key: const ValueKey('tablet-setup-save-button'),
                          onPressed: _canSave ? _save : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : const Text(
                                  'Salvar vinculacao',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String labelText,
    required IconData icon,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: labelText,
      helperText: helperText,
      labelStyle: const TextStyle(color: Colors.white54),
      helperStyle: const TextStyle(color: Colors.white38),
      prefixIcon: Icon(icon, color: Colors.white38),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white12),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.cyanAccent, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      disabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white10),
        borderRadius: BorderRadius.circular(8),
      ),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}

class _SetupFeedbackState extends StatelessWidget {
  const _SetupFeedbackState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.isLoading = false,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.cyanAccent,
                  ),
                )
              else
                Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ],
          ),
          if (!isLoading && actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

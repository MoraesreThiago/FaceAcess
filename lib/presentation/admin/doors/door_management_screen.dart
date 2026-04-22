import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/entities/door.dart';
import '../../../domain/entities/location.dart';
import '../../../domain/repositories/door_repository.dart';
import '../../../domain/repositories/location_repository.dart';

class DoorManagementScreen extends StatefulWidget {
  const DoorManagementScreen({
    super.key,
    required this.locationRepository,
    required this.doorRepository,
  });

  final LocationRepository locationRepository;
  final DoorRepository doorRepository;

  @override
  State<DoorManagementScreen> createState() => _DoorManagementScreenState();
}

class _DoorManagementScreenState extends State<DoorManagementScreen> {
  List<Location> _locations = const <Location>[];
  List<Door> _doors = const <Door>[];
  String? _selectedLocationId;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final locations = await widget.locationRepository.findAll();
      final stillValidFilter = _selectedLocationId != null &&
          locations.any((location) => location.id == _selectedLocationId);
      final effectiveFilter = stillValidFilter ? _selectedLocationId : null;
      final doors =
          await widget.doorRepository.findAll(locationId: effectiveFilter);

      if (!mounted) return;
      setState(() {
        _locations = locations;
        _selectedLocationId = effectiveFilter;
        _doors = doors;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Não foi possível carregar as portas agora.';
        _loading = false;
      });
    }
  }

  Future<void> _openForm({Door? initial}) async {
    if (_locations.isEmpty) {
      _showSnack(
        'Cadastre ao menos uma unidade antes de criar portas.',
        color: Colors.orange[800],
      );
      return;
    }

    final draft = await showDialog<_DoorDraft>(
      context: context,
      builder: (_) => _DoorFormDialog(
        initial: initial,
        locations: _locations,
      ),
    );

    if (draft == null) return;

    try {
      await widget.doorRepository.save(
        Door(
          id: initial?.id ?? const Uuid().v4(),
          name: draft.name,
          locationId: draft.locationId,
        ),
      );
      if (!mounted) return;
      _showSnack(
        initial == null
            ? 'Porta criada com sucesso.'
            : 'Porta atualizada com sucesso.',
        color: Colors.green[700],
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack('Erro ao salvar porta: $error', color: Colors.red[700]);
    }
  }

  Future<void> _deleteDoor(Door door) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Excluir porta',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Deseja remover "${door.name}" do cadastro?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await widget.doorRepository.deleteById(door.id);
      if (!mounted) return;
      _showSnack('Porta removida com sucesso.', color: Colors.red[700]);
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack('Erro ao excluir porta: $error', color: Colors.red[700]);
    }
  }

  void _showSnack(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationNames = {
      for (final location in _locations) location.id: location.name,
    };

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.door_front_door_outlined, size: 22),
            SizedBox(width: 8),
            Text(
              'Portas',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_doors.length} cadastrada${_doors.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _openForm(),
        backgroundColor: Colors.cyanAccent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Nova porta'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : _errorMessage != null
              ? _DoorAdminErrorState(
                  message: _errorMessage!,
                  onRetry: _load,
                )
              : Column(
                  children: [
                    if (_locations.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: DropdownButtonFormField<String?>(
                          initialValue: _selectedLocationId,
                          dropdownColor: const Color(0xFF1E1E1E),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Filtrar por unidade',
                            labelStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: Colors.white10,
                            enabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Colors.white12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Colors.white30),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Todas as unidades'),
                            ),
                            ..._locations.map(
                              (location) => DropdownMenuItem<String?>(
                                value: location.id,
                                child: Text(location.name),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedLocationId = value);
                            _load();
                          },
                        ),
                      ),
                    Expanded(
                      child: _locations.isEmpty
                          ? const _DoorEmptyState(
                              icon: Icons.apartment_outlined,
                              title: 'Nenhuma unidade cadastrada',
                              description:
                                  'Cadastre uma unidade primeiro para então vincular portas a ela.',
                            )
                          : _doors.isEmpty
                              ? _DoorEmptyState(
                                  icon: Icons.door_front_door_outlined,
                                  title: _selectedLocationId == null
                                      ? 'Nenhuma porta cadastrada'
                                      : 'Nenhuma porta nesta unidade',
                                  description: _selectedLocationId == null
                                      ? 'Crie a primeira porta para organizar os acessos físicos.'
                                      : 'A unidade selecionada ainda não possui portas cadastradas.',
                                )
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView.separated(
                                    padding:
                                        const EdgeInsets.fromLTRB(16, 8, 16, 96),
                                    itemCount: _doors.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (_, index) {
                                      final door = _doors[index];
                                      final locationName =
                                          locationNames[door.locationId] ??
                                              'Unidade não encontrada';

                                      return Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1A1A1A),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border:
                                              Border.all(color: Colors.white12),
                                        ),
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          leading: Container(
                                            width: 46,
                                            height: 46,
                                            decoration: BoxDecoration(
                                              color:
                                                  Colors.orangeAccent.withValues(
                                                alpha: 0.15,
                                              ),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.orangeAccent,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.door_front_door,
                                              color: Colors.orangeAccent,
                                            ),
                                          ),
                                          title: Text(
                                            door.name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white10,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      999,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    locationName,
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  'ID: ${door.id}',
                                                  style: const TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'Editar porta',
                                                onPressed: () =>
                                                    _openForm(initial: door),
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  color: Colors.white70,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Excluir porta',
                                                onPressed: () =>
                                                    _deleteDoor(door),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.redAccent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                    ),
                  ],
                ),
    );
  }
}

class _DoorFormDialog extends StatefulWidget {
  const _DoorFormDialog({
    required this.initial,
    required this.locations,
  });

  final Door? initial;
  final List<Location> locations;

  @override
  State<_DoorFormDialog> createState() => _DoorFormDialogState();
}

class _DoorFormDialogState extends State<_DoorFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late String _selectedLocationId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _selectedLocationId = widget.locations
            .any((location) => location.id == widget.initial?.locationId)
        ? widget.initial!.locationId
        : widget.locations.first.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _DoorDraft(
        name: _nameController.text.trim(),
        locationId: _selectedLocationId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initial != null;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(
        isEditing ? 'Editar porta' : 'Nova porta',
        style: const TextStyle(color: Colors.white),
      ),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nome da porta',
                  labelStyle: TextStyle(color: Colors.white54),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return 'Informe o nome da porta.';
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedLocationId,
                dropdownColor: const Color(0xFF1E1E1E),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Unidade',
                  labelStyle: TextStyle(color: Colors.white54),
                ),
                items: widget.locations
                    .map(
                      (location) => DropdownMenuItem<String>(
                        value: location.id,
                        child: Text(location.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedLocationId = value);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancelar',
            style: TextStyle(color: Colors.white54),
          ),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
          child: Text(
            isEditing ? 'Salvar' : 'Criar',
            style: const TextStyle(color: Colors.black),
          ),
        ),
      ],
    );
  }
}

class _DoorDraft {
  const _DoorDraft({
    required this.name,
    required this.locationId,
  });

  final String name;
  final String locationId;
}

class _DoorEmptyState extends StatelessWidget {
  const _DoorEmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoorAdminErrorState extends StatelessWidget {
  const _DoorAdminErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: Colors.redAccent, size: 56),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../domain/entities/location.dart';
import '../../../domain/repositories/door_repository.dart';
import '../../../domain/repositories/location_repository.dart';
import '../../../domain/repositories/person_repository.dart';

class LocationManagementScreen extends StatefulWidget {
  const LocationManagementScreen({
    super.key,
    required this.locationRepository,
    required this.doorRepository,
    required this.personRepository,
  });

  final LocationRepository locationRepository;
  final DoorRepository doorRepository;
  final PersonRepository personRepository;

  @override
  State<LocationManagementScreen> createState() =>
      _LocationManagementScreenState();
}

class _LocationManagementScreenState extends State<LocationManagementScreen> {
  List<Location> _locations = const <Location>[];
  Map<String, int> _doorCountByLocation = const <String, int>{};
  Map<String, int> _personCountByLocation = const <String, int>{};
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
      final doors = await widget.doorRepository.findAll();
      final people = await widget.personRepository.findAll();

      final doorCounts = <String, int>{};
      for (final door in doors) {
        doorCounts.update(door.locationId, (count) => count + 1, ifAbsent: () => 1);
      }

      final personCounts = <String, int>{};
      for (final person in people) {
        for (final locationId in person.locationIds) {
          personCounts.update(locationId, (count) => count + 1, ifAbsent: () => 1);
        }
      }

      if (!mounted) return;
      setState(() {
        _locations = locations;
        _doorCountByLocation = doorCounts;
        _personCountByLocation = personCounts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Não foi possível carregar as unidades agora.';
        _loading = false;
      });
    }
  }

  Future<void> _openForm({Location? initial}) async {
    final draft = await showDialog<_LocationDraft>(
      context: context,
      builder: (_) => _LocationFormDialog(
        initial: initial,
        existingIds: _locations
            .map((location) => location.id)
            .where((id) => initial == null || id != initial.id)
            .toSet(),
      ),
    );

    if (draft == null) return;

    try {
      await widget.locationRepository.save(
        Location(
          id: draft.id,
          name: draft.name,
        ),
      );
      if (!mounted) return;
      _showSnack(
        initial == null
            ? 'Unidade criada com sucesso.'
            : 'Unidade atualizada com sucesso.',
        color: Colors.green[700],
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack('Erro ao salvar unidade: $error', color: Colors.red[700]);
    }
  }

  Future<void> _deleteLocation(Location location) async {
    final doorCount = _doorCountByLocation[location.id] ?? 0;
    final personCount = _personCountByLocation[location.id] ?? 0;

    if (doorCount > 0 || personCount > 0) {
      final parts = <String>[];
      if (doorCount > 0) {
        parts.add('$doorCount porta${doorCount == 1 ? '' : 's'}');
      }
      if (personCount > 0) {
        parts.add('$personCount pessoa${personCount == 1 ? '' : 's'}');
      }

      _showSnack(
        'Não é possível excluir "${location.name}" porque ela ainda possui ${parts.join(' e ')} vinculada${parts.length > 1 ? 's' : ''}.',
        color: Colors.orange[800],
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Excluir unidade',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Deseja remover "${location.name}" do cadastro?',
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
      await widget.locationRepository.deleteById(location.id);
      if (!mounted) return;
      _showSnack('Unidade removida com sucesso.', color: Colors.red[700]);
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack('Erro ao excluir unidade: $error', color: Colors.red[700]);
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.apartment, size: 22),
            SizedBox(width: 8),
            Text(
              'Unidades',
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
                  '${_locations.length} cadastrada${_locations.length == 1 ? '' : 's'}',
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
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Nova unidade'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : _errorMessage != null
              ? _AdminErrorState(
                  message: _errorMessage!,
                  onRetry: _load,
                )
              : _locations.isEmpty
                  ? const _AdminEmptyState(
                      icon: Icons.apartment_outlined,
                      title: 'Nenhuma unidade cadastrada',
                      description:
                          'Crie a primeira unidade para começar a organizar portas e acessos.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        itemCount: _locations.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, index) {
                          final location = _locations[index];
                          final doorCount = _doorCountByLocation[location.id] ?? 0;
                          final personCount =
                              _personCountByLocation[location.id] ?? 0;

                          return Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              leading: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: Colors.cyanAccent.withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.cyanAccent),
                                ),
                                child: const Icon(
                                  Icons.apartment,
                                  color: Colors.cyanAccent,
                                ),
                              ),
                              title: Text(
                                location.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ID estável: ${location.id}',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _StatChip(
                                          icon: Icons.door_front_door,
                                          label:
                                              '$doorCount porta${doorCount == 1 ? '' : 's'}',
                                        ),
                                        _StatChip(
                                          icon: Icons.people_outline,
                                          label:
                                              '$personCount pessoa${personCount == 1 ? '' : 's'}',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Editar unidade',
                                    onPressed: () => _openForm(initial: location),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Excluir unidade',
                                    onPressed: () => _deleteLocation(location),
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
    );
  }
}

class _LocationFormDialog extends StatefulWidget {
  const _LocationFormDialog({
    required this.initial,
    required this.existingIds,
  });

  final Location? initial;
  final Set<String> existingIds;

  @override
  State<_LocationFormDialog> createState() => _LocationFormDialogState();
}

class _LocationFormDialogState extends State<_LocationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _idController;
  late final bool _editing;
  bool _identifierTouched = false;

  @override
  void initState() {
    super.initState();
    _editing = widget.initial != null;
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _idController = TextEditingController(text: widget.initial?.id ?? '');
    _identifierTouched = _editing;
    _nameController.addListener(_syncIdentifierFromName);
  }

  void _syncIdentifierFromName() {
    if (_editing || _identifierTouched) return;
    final nextValue = _slugifyLocationId(_nameController.text);
    if (_idController.text == nextValue) return;
    _idController.value = TextEditingValue(
      text: nextValue,
      selection: TextSelection.collapsed(offset: nextValue.length),
    );
  }

  @override
  void dispose() {
    _nameController.removeListener(_syncIdentifierFromName);
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _LocationDraft(
        id: _idController.text.trim(),
        name: _nameController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(
        _editing ? 'Editar unidade' : 'Nova unidade',
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
                  labelText: 'Nome da unidade',
                  labelStyle: TextStyle(color: Colors.white54),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return 'Informe o nome da unidade.';
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _idController,
                readOnly: _editing,
                style: TextStyle(
                  color: _editing ? Colors.white54 : Colors.white,
                ),
                decoration: InputDecoration(
                  labelText: 'Identificador estável',
                  labelStyle: const TextStyle(color: Colors.white54),
                  helperText: _editing
                      ? 'O identificador não muda para preservar vínculos existentes.'
                      : 'Usado por pessoas e tablets como referência estável.',
                  helperStyle: const TextStyle(color: Colors.white38),
                ),
                onChanged: _editing
                    ? null
                    : (_) => setState(() => _identifierTouched = true),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return 'Informe o identificador.';
                  }
                  if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(trimmed)) {
                    return 'Use letras minúsculas, números e hífen.';
                  }
                  if (widget.existingIds.contains(trimmed)) {
                    return 'Este identificador já está em uso.';
                  }
                  return null;
                },
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
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
            _editing ? 'Salvar' : 'Criar',
            style: const TextStyle(color: Colors.black),
          ),
        ),
      ],
    );
  }
}

class _LocationDraft {
  const _LocationDraft({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

class _AdminEmptyState extends StatelessWidget {
  const _AdminEmptyState({
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

class _AdminErrorState extends StatelessWidget {
  const _AdminErrorState({
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

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

String _slugifyLocationId(String raw) {
  const replacements = <String, String>{
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };

  final buffer = StringBuffer();
  for (final rune in raw.trim().toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(replacements[char] ?? char);
  }

  return buffer
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

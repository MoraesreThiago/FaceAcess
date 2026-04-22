import 'package:flutter/material.dart';

import '../domain/entities/person.dart';
import '../domain/entities/user_role.dart';
import '../domain/repositories/door_repository.dart';
import '../domain/repositories/location_repository.dart';
import '../domain/repositories/person_repository.dart';
import '../infrastructure/firebase_database.dart';
import 'admin/doors/door_management_screen.dart';
import 'admin/locations/location_management_screen.dart';

/// Lista e remove pessoas cadastradas. A partir do PR #7 opera sobre o
/// [PersonRepository] (UUID-keyed) em vez do antigo `FaceDatabase`.
class PeopleListScreen extends StatefulWidget {
  final PersonRepository personRepository;
  final FirebaseDatabase firebaseDatabase;
  final LocationRepository locationRepository;
  final DoorRepository doorRepository;
  final bool showStructureManagement;
  const PeopleListScreen({
    super.key,
    required this.personRepository,
    required this.firebaseDatabase,
    required this.locationRepository,
    required this.doorRepository,
    required this.showStructureManagement,
  });

  @override
  State<PeopleListScreen> createState() => _PeopleListScreenState();
}

class _PeopleListScreenState extends State<PeopleListScreen> {
  List<Person> _people = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await widget.personRepository.findAll();
    if (mounted) {
      setState(() {
        _people = data;
        _loading = false;
      });
    }
  }

  Future<void> _deletePerson(Person person) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Confirmar exclusão',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Deseja remover "${person.name}" do sistema?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.personRepository.deleteById(person.id);
      try {
        await widget.firebaseDatabase.deletePerson(person.id);
      } catch (_) {}
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${person.name} removido com sucesso'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  Future<void> _openLocations() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocationManagementScreen(
          locationRepository: widget.locationRepository,
          doorRepository: widget.doorRepository,
          personRepository: widget.personRepository,
        ),
      ),
    );
  }

  Future<void> _openDoors() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DoorManagementScreen(
          locationRepository: widget.locationRepository,
          doorRepository: widget.doorRepository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchLower = _search.toLowerCase();
    final filtered = _people
        .where((p) =>
            p.name.toLowerCase().contains(searchLower) ||
            p.role.label.toLowerCase().contains(searchLower))
        .toList()
      ..sort((a, b) {
        // Sort by role priority then name
        final roleCmp = a.role.index.compareTo(b.role.index);
        if (roleCmp != 0) return roleCmp;
        return a.name.compareTo(b.name);
      });

    // Group by role
    final grouped = <UserRole, List<Person>>{};
    for (final person in filtered) {
      grouped.putIfAbsent(person.role, () => []).add(person);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.people, size: 22),
            SizedBox(width: 8),
            Text('Pessoas Cadastradas',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.showStructureManagement) ...[
            IconButton(
              tooltip: 'Gerenciar unidades',
              onPressed: _openLocations,
              icon: const Icon(Icons.apartment_outlined),
            ),
            IconButton(
              tooltip: 'Gerenciar portas',
              onPressed: _openDoors,
              icon: const Icon(Icons.door_front_door_outlined),
            ),
          ],
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
                  '${_people.length} cadastrado${_people.length != 1 ? 's' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Buscar por nome ou cargo…',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.white12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.white30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),

                // Summary chips
                if (_people.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: UserRole.values.map((role) {
                          final count =
                              _people.where((p) => p.role == role).length;
                          if (count == 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              avatar:
                                  Icon(role.icon, size: 14, color: role.color),
                              label: Text(
                                '${role.label}: $count',
                                style:
                                    TextStyle(color: role.color, fontSize: 12),
                              ),
                              backgroundColor: role.color.withOpacity(0.12),
                              side: BorderSide(
                                  color: role.color.withOpacity(0.3)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                // List
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.people_outline,
                                  color: Colors.white24, size: 64),
                              const SizedBox(height: 16),
                              Text(
                                _search.isEmpty
                                    ? 'Nenhuma pessoa cadastrada'
                                    : 'Nenhum resultado para "$_search"',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: grouped.length,
                          itemBuilder: (_, sectionIndex) {
                            final role = grouped.keys.elementAt(sectionIndex);
                            final people = grouped[role]!;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Section header
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Row(
                                    children: [
                                      Icon(role.icon,
                                          color: role.color, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        role.label.toUpperCase(),
                                        style: TextStyle(
                                          color: role.color,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Divider(
                                          color: role.color.withOpacity(0.3),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${people.length}',
                                        style: TextStyle(
                                          color: role.color.withOpacity(0.7),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // People cards
                                ...people.map((person) => _PersonCard(
                                      person: person,
                                      onDelete: () => _deletePerson(person),
                                    )),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

class _PersonCard extends StatelessWidget {
  final Person person;
  final VoidCallback onDelete;

  const _PersonCard({
    required this.person,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final role = person.role;
    final photoCount = person.embeddings.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: role.color.withOpacity(0.25)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: role.color.withOpacity(0.15),
            border: Border.all(color: role.color, width: 2),
          ),
          child: Icon(role.icon, color: role.color, size: 24),
        ),
        title: Text(
          person.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: role.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  role.label,
                  style: TextStyle(
                      color: role.color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.photo_library_outlined,
                  size: 13, color: Colors.white38),
              const SizedBox(width: 4),
              Text(
                '$photoCount fotos',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          tooltip: 'Remover pessoa',
          onPressed: onDelete,
        ),
      ),
    );
  }
}

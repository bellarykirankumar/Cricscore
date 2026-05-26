import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../main.dart';

class TournamentListScreen extends ConsumerStatefulWidget {
  const TournamentListScreen({super.key});
  @override ConsumerState<TournamentListScreen> createState() => _TournamentListState();
}

class _TournamentListState extends ConsumerState<TournamentListScreen> {
  List<Tournament> _list    = [];
  bool             _loading = true;
  bool             _showCreate = false;
  final _nameCtrl  = TextEditingController();
  String _format   = 'T20';
  int    _maxTeams = 8;
  bool   _saving   = false;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await TournamentApi.list().catchError((_) => <Tournament>[]);
    if (mounted) setState(() { _list = list; _loading = false; });
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await TournamentApi.create({
        'name': _nameCtrl.text.trim(), 'format': _format,
        'maxTeams': _maxTeams, 'status': 'upcoming',
      });
      _nameCtrl.clear();
      setState(() => _showCreate = false);
      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { setState(() => _saving = false); }
  }

  Future<void> _delete(Tournament t) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: const Text('Delete tournament?', style: TextStyle(color: AppColors.text)),
      content: Text('Delete "${t.name}"? This cannot be undone.',
        style: const TextStyle(color: AppColors.text2)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete', style: TextStyle(color: AppColors.wicket))),
      ],
    ));
    if (ok != true) return;
    await TournamentApi.update(t.id, {'status': 'deleted'});
    _load();
  }

  @override Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Tournaments'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => context.go('/'),
        ),
        actions: [
          if (user?.isAdmin == true)
            IconButton(
              icon: Icon(_showCreate ? Icons.close : Icons.add,
                color: AppColors.accent),
              onPressed: () => setState(() => _showCreate = !_showCreate),
            ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
        : RefreshIndicator(
            onRefresh: _load,
            color: AppColors.accent,
            child: ListView(children: [
              if (_showCreate && user?.isAdmin == true) _buildCreateForm(),
              ..._list.map((t) => AppCard(
                onTap: () => context.push('/tournament/${t.id}'),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.name, style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('${t.format} · ${t.teamCount}/${t.maxTeams} teams',
                      style: const TextStyle(color: AppColors.text2, fontSize: 13)),
                  ])),
                  StatusBadge(
                    label: t.isActive ? 'Active' : t.isCompleted ? 'Done' : 'Upcoming',
                    color: t.isActive ? AppColors.accent : t.isCompleted ? AppColors.text2 : AppColors.ball,
                  ),
                  if (user?.isAdmin == true) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _delete(t),
                      child: const Icon(Icons.delete_outline, color: AppColors.wicket, size: 20),
                    ),
                  ],
                ]),
              )),
              if (_list.isEmpty && !_showCreate)
                const Padding(padding: EdgeInsets.all(40),
                  child: Column(children: [
                    Text('🏆', style: TextStyle(fontSize: 40)),
                    SizedBox(height: 12),
                    Text('No tournaments yet', style: TextStyle(
                      color: AppColors.text, fontWeight: FontWeight.w700)),
                    SizedBox(height: 6),
                    Text('Tap + to create one',
                      style: TextStyle(color: AppColors.text2, fontSize: 13)),
                  ])),
              const SizedBox(height: 40),
            ]),
          ),
    );
  }

  Widget _buildCreateForm() {
    return AppCard(
      color: AppColors.bgCard,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Create tournament', style: TextStyle(
          fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 16)),
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(labelText: 'Tournament name',
            hintText: 'e.g. Summer League 2025'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Format', style: TextStyle(color: AppColors.text2, fontSize: 12)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _format,
              dropdownColor: AppColors.bgElevated,
              style: const TextStyle(color: AppColors.text),
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              items: ['T10','T20','ODI','Test','Gully'].map((f) =>
                DropdownMenuItem(value: f, child: Text(f))).toList(),
              onChanged: (v) => setState(() => _format = v ?? _format),
            ),
          ])),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Max teams', style: TextStyle(color: AppColors.text2, fontSize: 12)),
            const SizedBox(height: 6),
            TextFormField(
              initialValue: '$_maxTeams',
              style: const TextStyle(color: AppColors.text),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              onChanged: (v) => setState(() => _maxTeams = int.tryParse(v) ?? _maxTeams),
            ),
          ])),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: ElevatedButton(
            onPressed: _saving ? null : _create,
            child: _saving
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnAcc))
              : const Text('Create'),
          )),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton(
            onPressed: () => setState(() => _showCreate = false),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.text2,
              side: const BorderSide(color: AppColors.border),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text('Cancel'),
          )),
        ]),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../models/models.dart';
import '../../main.dart';
import '../../widgets/country_picker_sheet.dart';
import '../../widgets/location_picker_sheet.dart';

class TournamentListScreen extends ConsumerStatefulWidget {
  const TournamentListScreen({super.key});
  @override ConsumerState<TournamentListScreen> createState() => _TournamentListState();
}

class _TournamentListState extends ConsumerState<TournamentListScreen> {
  List<Tournament> _list      = [];
  Set<String>      _ownedIds  = {};
  String?          _userCountry;
  String?          _filterState;
  String?          _filterCity;
  bool             _loading   = true;
  bool             _showCreate = false;
  final _nameCtrl  = TextEditingController();
  String _format   = 'T20';
  int    _maxTeams = 8;
  bool   _saving   = false;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      TournamentApi.list(state: _filterState, city: _filterCity).catchError((_) => <Tournament>[]),
      AuthService.instance.getOwnedIds(),
      AuthService.instance.getCountry(),
    ]);
    if (mounted) setState(() {
      _userCountry   = results[2] as String?;
      final ownedIds = results[1] as Set<String>;
      final all      = results[0] as List<Tournament>;
      final user = ref.read(authProvider).value;
      _list = all.where((t) {
        if (user?.isAdmin == true) return true;           // admins see all
        if (user?.isScorerFor(t) == true) return true;   // invited scorers always see it
        if (_filterState != null || _filterCity != null) return true; // location filter applied server-side
        if (_userCountry == null) return true;
        if (t.country == _userCountry) return true;
        // Own untagged tournaments always visible.
        if (t.country == null &&
            (ownedIds.contains(t.id) || user?.canManage(t.createdBy) == true)) return true;
        return false;
      }).toList();
      _ownedIds = ownedIds;
      _loading  = false;
    });
  }

  Future<void> _pickLocation() async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LocationPickerSheet(
        country: _userCountry,
        initialState: _filterState,
      ),
    );
    if (result != null) {
      setState(() { _filterState = result.$1; _filterCity = result.$2; });
      _load();
    }
  }

  void _clearLocationFilter() {
    setState(() { _filterState = null; _filterCity = null; });
    _load();
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final user = ref.read(authProvider).value;

    // Ensure country is set — prompt if missing so new tournaments are always tagged.
    var country = await AuthService.instance.getCountry();
    if (country == null && mounted) {
      country = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const CountryPickerSheet(),
      );
      if (country == null) return; // user cancelled — abort creation
      await AuthService.instance.setCountry(country);
      setState(() => _userCountry = country);
    }

    setState(() => _saving = true);
    try {
      final created = await TournamentApi.create({
        'name': _nameCtrl.text.trim(), 'format': _format,
        'maxTeams': _maxTeams, 'status': 'upcoming',
        if (user != null) 'createdBy': user.sub,
        'country': country,
        if (_filterState != null) 'state': _filterState,
        if (_filterCity  != null) 'city':  _filterCity,
      });
      await AuthService.instance.claimOwnership(created.id);
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
        title: const Text('Leagues'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => context.go('/'),
        ),
        actions: [
          // Location filter
          IconButton(
            tooltip: _filterCity != null ? '$_filterCity (clear)' : 'Filter by location',
            icon: Icon(
              _filterState != null ? Icons.location_on : Icons.location_on_outlined,
              color: _filterState != null ? AppColors.accent : AppColors.text2,
            ),
            onPressed: _filterState != null ? _clearLocationFilter : _pickLocation,
          ),
          if (user != null) ...[
            // Wizard: full guided setup
            IconButton(
              tooltip: 'Setup wizard',
              icon: const Icon(Icons.auto_awesome, color: AppColors.accent),
              onPressed: () async {
                await context.push('/tournament/setup');
                _load();
              },
            ),
            // Quick create: inline form
            IconButton(
              tooltip: 'Quick create',
              icon: Icon(_showCreate ? Icons.close : Icons.add,
                color: AppColors.text2),
              onPressed: () => setState(() => _showCreate = !_showCreate),
            ),
          ],
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
        : RefreshIndicator(
            onRefresh: _load,
            color: AppColors.accent,
            child: ListView(children: [
              if (_filterState != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(children: [
                    const Icon(Icons.location_on, size: 14, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Text(
                      _filterCity != null
                        ? '$_filterCity · ${stateName(_filterState!)}'
                        : stateName(_filterState!),
                      style: const TextStyle(color: AppColors.accent, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _clearLocationFilter,
                      child: const Icon(Icons.close, size: 14, color: AppColors.text2),
                    ),
                  ]),
                ),
              if (_showCreate && user != null) _buildCreateForm(),
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
                  if (user?.canManage(t.createdBy) == true || _ownedIds.contains(t.id)) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _delete(t),
                      child: const Icon(Icons.delete_outline, color: AppColors.wicket, size: 20),
                    ),
                  ],
                ]),
              )),
              if (_list.isEmpty && !_showCreate)
                Padding(padding: const EdgeInsets.all(40),
                  child: Column(children: [
                    const Text('🏆', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 12),
                    const Text('No tournaments yet', style: TextStyle(
                      color: AppColors.text, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text('Use ✨ to set up with AI guidance,\nor + for a quick create.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.text2, fontSize: 13)),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Setup wizard'),
                      onPressed: () async {
                        await context.push('/tournament/setup');
                        _load();
                      },
                    ),
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
        const Text('Create league', style: TextStyle(
          fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 16)),
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(labelText: 'League name',
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
              items: ['T10','T20','ODI','Custom'].map((f) =>
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Cancel'),
          )),
        ]),
      ]),
    );
  }
}

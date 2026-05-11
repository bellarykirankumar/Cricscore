import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../main.dart';

class TeamRosterScreen extends ConsumerStatefulWidget {
  final String tournamentId, teamId;
  const TeamRosterScreen({super.key, required this.tournamentId, required this.teamId});
  @override ConsumerState<TeamRosterScreen> createState() => _TeamRosterState();
}

class _TeamRosterState extends ConsumerState<TeamRosterScreen> {
  Team?        _team;
  List<Player> _players  = [];
  bool         _loading  = true;
  bool         _showAdd  = false;
  bool         _saving   = false;

  final _nameCtrl  = TextEditingController();
  String _role     = 'all_rounder';
  String _bat      = 'right_hand';
  String _bowl     = '';
  String _jersey   = '';

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final t = await TournamentApi.get(widget.tournamentId);
      final teamData = (t.teams ?? []).firstWhere((team) => team.id == widget.teamId,
        orElse: () => Team(id: widget.teamId, name: 'Team', shortName: ''));
      final players = await PlayerApi.list(widget.teamId).catchError((_) => <Player>[]);
      if (mounted) setState(() { _team = teamData; _players = players; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPlayer() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await PlayerApi.create({
        'teamId':       widget.teamId,
        'name':         _nameCtrl.text.trim(),
        'role':         _role,
        'battingStyle': _bat,
        if (_bowl.isNotEmpty) 'bowlingStyle': _bowl,
        if (_jersey.isNotEmpty) 'jerseyNumber': int.tryParse(_jersey),
      });
      _nameCtrl.clear();
      setState(() { _jersey = ''; _showAdd = false; });
      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { setState(() => _saving = false); }
  }

  @override Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Column(children: [
          Text(_team?.name ?? 'Team'),
          Text('${_players.length} players', style: const TextStyle(
            fontSize: 12, color: AppColors.text2, fontWeight: FontWeight.w400)),
        ]),
        actions: [
          if (user?.isScorer == true)
            IconButton(
              icon: Icon(_showAdd ? Icons.close : Icons.person_add_outlined,
                color: AppColors.accent),
              onPressed: () => setState(() => _showAdd = !_showAdd),
            ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
        : RefreshIndicator(
            onRefresh: _load,
            color: AppColors.accent,
            child: ListView(children: [
              if (_showAdd && user?.isScorer == true) _buildAddForm(),

              if (_players.isEmpty && !_showAdd)
                Padding(padding: const EdgeInsets.all(40),
                  child: Column(children: [
                    const Text('👤', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 12),
                    const Text('No players yet', style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 16)),
                    const SizedBox(height: 6),
                    const Text('Tap + to add players',
                      style: TextStyle(color: AppColors.text2, fontSize: 13)),
                    if (user?.isScorer == true) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _showAdd = true),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add first player'),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent,
                          side: const BorderSide(color: AppColors.accent)),
                      ),
                    ],
                  ])),

              ...(_players.asMap().entries.map((e) => AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.accent.withOpacity(0.3))),
                    child: Center(child: Text(
                      e.value.jerseyNumber != null ? '#${e.value.jerseyNumber}' : '${e.key + 1}',
                      style: const TextStyle(
                        color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 13))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.value.name, style: const TextStyle(
                      fontWeight: FontWeight.w600, color: AppColors.text, fontSize: 15)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 4, children: [
                      _Tag(e.value.role.replaceAll('_', ' ')),
                      _Tag(e.value.battingStyle == 'right_hand' ? 'RHB' : 'LHB'),
                      if (e.value.bowlingStyle != null)
                        _Tag(e.value.bowlingStyle!.replaceAll('_', ' ')),
                    ]),
                  ])),
                ]),
              ))),
              const SizedBox(height: 40),
            ]),
          ),
    );
  }

  Widget _buildAddForm() {
    const roles   = [('Batsman','batsman'),('Bowler','bowler'),('All-rounder','all_rounder'),('WK','wicket_keeper')];
    const batOpts = [('Right hand','right_hand'),('Left hand','left_hand')];
    const bowlOpts = [
      ('Not a bowler',''), ('RA Fast','right_arm_fast'), ('RA Medium','right_arm_medium'),
      ('RA Off spin','right_arm_off_spin'), ('RA Leg spin','right_arm_leg_spin'),
      ('LA Fast','left_arm_fast'), ('LA Medium','left_arm_medium'), ('LA Slow','left_arm_slow'),
    ];

    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Add player', style: TextStyle(
        fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 16)),
      const SizedBox(height: 12),
      TextField(
        controller: _nameCtrl,
        style: const TextStyle(color: AppColors.text),
        decoration: const InputDecoration(labelText: 'Full name', hintText: 'e.g. Rohit Sharma'),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(
          value: _role, dropdownColor: AppColors.bgElevated,
          style: const TextStyle(color: AppColors.text, fontSize: 14),
          decoration: const InputDecoration(labelText: 'Role',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          items: roles.map((r) => DropdownMenuItem(value: r.$2, child: Text(r.$1))).toList(),
          onChanged: (v) => setState(() => _role = v ?? _role),
        )),
        const SizedBox(width: 8),
        Expanded(child: TextField(
          style: const TextStyle(color: AppColors.text),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Jersey #',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          onChanged: (v) => setState(() => _jersey = v),
        )),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(
          value: _bat, dropdownColor: AppColors.bgElevated,
          style: const TextStyle(color: AppColors.text, fontSize: 14),
          decoration: const InputDecoration(labelText: 'Batting',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          items: batOpts.map((r) => DropdownMenuItem(value: r.$2, child: Text(r.$1))).toList(),
          onChanged: (v) => setState(() => _bat = v ?? _bat),
        )),
        const SizedBox(width: 8),
        Expanded(child: DropdownButtonFormField<String>(
          value: _bowl, dropdownColor: AppColors.bgElevated,
          style: const TextStyle(color: AppColors.text, fontSize: 14),
          decoration: const InputDecoration(labelText: 'Bowling',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          items: bowlOpts.map((r) => DropdownMenuItem(value: r.$2, child: Text(r.$1))).toList(),
          onChanged: (v) => setState(() => _bowl = v ?? _bowl),
        )),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: ElevatedButton(
          onPressed: _saving ? null : _addPlayer,
          child: _saving ? const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnAcc))
            : const Text('Add player'),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton(
          onPressed: () => setState(() => _showAdd = false),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.text2,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: const Text('Cancel'),
        )),
      ]),
    ]));
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);
  @override Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.bgElevated, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border)),
      child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.text2)),
    );
  }
}

// Add teams getter to Tournament
extension TournamentTeams on Tournament {
  List<Team>? get teams => null; // Loaded separately via API
}

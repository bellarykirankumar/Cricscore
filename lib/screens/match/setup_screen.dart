import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../models/models.dart';
import '../../main.dart';
import '../../widgets/country_picker_sheet.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  int    _step      = 0; // 0=format, 1=team1, 2=team2, 3=toss
  bool   _saving    = false;
  String _format    = 'T20';
  late TextEditingController _oversCtrl;
  int    _overs     = 20;
  String _venue     = '';

  // Registered teams
  List<Team> _allTeams    = [];
  bool       _loadingTeams = false;

  // Team 1
  bool        _t1Registered = true;
  Team?       _t1Team;
  List<Player>_t1Roster     = [];
  Set<String> _t1Selected   = {};
  String      _t1Name       = '';
  List<String>_t1Players    = List.generate(11, (_) => '');

  // Team 2
  bool        _t2Registered = true;
  Team?       _t2Team;
  List<Player>_t2Roster     = [];
  Set<String> _t2Selected   = {};
  String      _t2Name       = '';
  List<String>_t2Players    = List.generate(11, (_) => '');

  // Toss
  bool _tossT1     = true;
  bool _tossBat    = true;

  static const _formats = [
    ('T10', 10), ('T20', 20), ('ODI', 50), ('Test', 90), ('Gully', 5),
  ];

  @override void initState() {
    super.initState();
    _oversCtrl = TextEditingController(text: '$_overs');
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    setState(() => _loadingTeams = true);
    try {
      final tours = await TournamentApi.list();
      final lists = await Future.wait(
        tours.map((t) => TournamentApi.listTeams(t.id).catchError((_) => <Team>[])));
      setState(() => _allTeams = lists.expand((l) => l).toList());
    } catch (_) {}
    finally { setState(() => _loadingTeams = false); }
  }

  Future<void> _selectTeam(Team team, bool isT1) async {
    final roster = await PlayerApi.list(team.id).catchError((_) => <Player>[]);
    // Start with empty selection — user must pick playing 11
    const sel = <String>{};
    setState(() {
      if (isT1) { _t1Team = team; _t1Roster = roster; _t1Selected = sel; }
      else      { _t2Team = team; _t2Roster = roster; _t2Selected = sel; }
    });
  }

  void _togglePlayer(String id, bool isT1) {
    final set = isT1 ? Set<String>.from(_t1Selected) : Set<String>.from(_t2Selected);
    if (set.contains(id)) { set.remove(id); }
    else if (set.length < 11) { set.add(id); }
    else { ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Maximum 11 players'))); return; }
    setState(() { if (isT1) _t1Selected = set; else _t2Selected = set; });
  }

  bool get _canProceed {
    if (_step == 0) return true;
    final isT1 = _step == 1;
    final registered = isT1 ? _t1Registered : _t2Registered;
    if (registered) {
      final team   = isT1 ? _t1Team : _t2Team;
      final sel    = isT1 ? _t1Selected : _t2Selected;
      final roster = isT1 ? _t1Roster : _t2Roster;
      // Must select exactly 11 (or all players if roster < 11)
      final required = roster.length < 11 ? roster.length : 11;
      return team != null && sel.length >= required;
    }
    final name = isT1 ? _t1Name : _t2Name;
    final pls  = isT1 ? _t1Players : _t2Players;
    return name.trim().isNotEmpty && pls.where((p) => p.trim().isNotEmpty).length >= 2;
  }

  List<Player> _makePlayers(List<String> names, String prefix) {
    return names.where((n) => n.trim().isNotEmpty).toList().asMap().entries.map((e) {
      final name = e.value.trim();
      return Player(
        id: '${prefix}_player_${e.key}', teamId: prefix,
        name: name, shortName: name.split(' ').map((w) => w[0]).join(''),
      );
    }).toList();
  }

  Future<void> _startMatch() async {
    final user = ref.read(authProvider).value;

    // Ensure country is set so every new match is tagged.
    var country = await AuthService.instance.getCountry();
    if (country == null && mounted) {
      country = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const CountryPickerSheet(),
      );
      if (country != null) await AuthService.instance.setCountry(country);
      // If still null (user cancelled), proceed without country — match stays untagged.
    }

    setState(() => _saving = true);
    try {
      Team team1, team2;

      if (_t1Registered && _t1Team != null) {
        team1 = _t1Team!.copyWith(players: _t1Roster.where((p) => _t1Selected.contains(p.id)).toList());
      } else {
        final s = _t1Name.trim().substring(0, _t1Name.trim().length.clamp(0, 3)).toUpperCase();
        team1 = Team(id: 'team1_${DateTime.now().millisecondsSinceEpoch}',
          name: _t1Name.trim(), shortName: s,
          players: _makePlayers(_t1Players, s));
      }

      if (_t2Registered && _t2Team != null) {
        team2 = _t2Team!.copyWith(players: _t2Roster.where((p) => _t2Selected.contains(p.id)).toList());
      } else {
        final s = _t2Name.trim().substring(0, _t2Name.trim().length.clamp(0, 3)).toUpperCase();
        team2 = Team(id: 'team2_${DateTime.now().millisecondsSinceEpoch}',
          name: _t2Name.trim(), shortName: s,
          players: _makePlayers(_t2Players, s));
      }

      final match = await MatchApi.create({
        'format': _format, 'oversPerInnings': _overs,
        if (_venue.trim().isNotEmpty) 'venue': _venue.trim(),
        'team1': team1.toJson(), 'team2': team2.toJson(),
        if (user != null) 'createdBy': user.sub,
        if (country != null) 'country': country,
      });
      await AuthService.instance.claimOwnership(match.id);
      await MatchApi.update(match.id, {'status': 'in_progress'});

      final tossWinTeam = _tossT1 ? team1 : team2;
      final battingTeamId = _tossBat ? tossWinTeam.id
        : (tossWinTeam.id == team1.id ? team2.id : team1.id);
      final bowlingTeamId = battingTeamId == team1.id ? team2.id : team1.id;

      await MatchApi.startInnings(match.id, {
        'battingTeamId': battingTeamId, 'bowlingTeamId': bowlingTeamId,
      });

      if (mounted) context.go('/scoring/${match.id}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _t1Label => _t1Registered ? (_t1Team?.name ?? 'Team 1') : (_t1Name.trim().isEmpty ? 'Team 1' : _t1Name.trim());
  String get _t2Label => _t2Registered ? (_t2Team?.name ?? 'Team 2') : (_t2Name.trim().isEmpty ? 'Team 2' : _t2Name.trim());

  @override Widget build(BuildContext context) {
    final titles = ['New match', _t1Label, _t2Label, 'Toss'];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => _step == 0 ? context.go('/') : setState(() => _step--),
        ),
        title: Column(children: [
          Text(titles[_step]),
          Text('Step ${_step + 1} of 4', style: const TextStyle(
            fontSize: 12, color: AppColors.text2, fontWeight: FontWeight.w400)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(children: List.generate(4, (i) => Container(
              width: 8, height: 8, margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i <= _step ? AppColors.accent : AppColors.bgElevated,
                shape: BoxShape.circle,
              ),
            ))),
          ),
        ],
      ),
      body: IndexedStack(index: _step, children: [
        _buildFormatStep(),
        _buildTeamStep(isT1: true),
        _buildTeamStep(isT1: false),
        _buildTossStep(),
      ]),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16,
          MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 8),
        child: _step < 3 ? ElevatedButton(
            onPressed: _canProceed ? () => setState(() => _step++) : null,
            child: Text(_step == 0 ? 'Next: Select Team 1 →'
              : _step == 1
                ? (_t1Registered
                  ? 'Next: Select Team 2 → (${_t1Selected.length}/11 selected)'
                  : 'Next: Select Team 2 →')
              : _step == 2
                ? (_t2Registered
                  ? 'Next: Toss → (${_t2Selected.length}/11 selected)'
                  : 'Next: Toss →')
              : 'Next: Toss →'),
          ) : ElevatedButton(
            onPressed: _saving ? null : _startMatch,
            child: _saving ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.textOnAcc))
              : const Text('Start match →'),
          ),
        ),
    );
  }

  Widget _buildFormatStep() {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
      const Text('Format', style: TextStyle(
        color: AppColors.text2, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: _formats.map((f) => ChoiceChip(
        label: Text(f.$1),
        selected: _format == f.$1,
        onSelected: (_) => setState(() { _format = f.$1; _overs = f.$2; _oversCtrl.text = '${f.$2}'; }),
        selectedColor: AppColors.accent.withOpacity(0.2),
        backgroundColor: AppColors.bgElevated,
        side: BorderSide(color: _format == f.$1 ? AppColors.accent : AppColors.border),
        labelStyle: TextStyle(
          color: _format == f.$1 ? AppColors.accent : AppColors.text2,
          fontWeight: FontWeight.w700,
        ),
      )).toList()),
      const SizedBox(height: 16),
      TextFormField(
        controller: _oversCtrl,
        style: const TextStyle(color: AppColors.text),
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Overs per innings'),
        onChanged: (v) => setState(() => _overs = int.tryParse(v) ?? _overs),
      ),
      const SizedBox(height: 12),
      TextFormField(
        style: const TextStyle(color: AppColors.text),
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Venue (optional)', hintText: 'e.g. Wankhede Stadium'),
        onChanged: (v) => setState(() => _venue = v),
        onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
      ),
    ]),
    );
  }

  Widget _buildTeamStep({required bool isT1}) {
    final registered = isT1 ? _t1Registered : _t2Registered;
    final selTeam    = isT1 ? _t1Team : _t2Team;
    final roster     = isT1 ? _t1Roster : _t2Roster;
    final selected   = isT1 ? _t1Selected : _t2Selected;
    final required   = roster.length < 11 ? roster.length : 11;

    return ListView(padding: const EdgeInsets.all(16), children: [
      // Toggle
      Container(
        decoration: BoxDecoration(
          color: AppColors.bgElevated, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(child: GestureDetector(
            onTap: () => setState(() { if (isT1) _t1Registered = true; else _t2Registered = true; }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: registered ? AppColors.accent.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: registered ? Border.all(color: AppColors.accent) : null,
              ),
              child: Text('📋 Registered', textAlign: TextAlign.center,
                style: TextStyle(color: registered ? AppColors.accent : AppColors.text2,
                  fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          )),
          Expanded(child: GestureDetector(
            onTap: () => setState(() { if (isT1) _t1Registered = false; else _t2Registered = false; }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: !registered ? AppColors.ball.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: !registered ? Border.all(color: AppColors.ball) : null,
              ),
              child: Text('✏️ Quick entry', textAlign: TextAlign.center,
                style: TextStyle(color: !registered ? AppColors.ball : AppColors.text2,
                  fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          )),
        ]),
      ),
      const SizedBox(height: 16),

      if (registered) ...[
        if (_loadingTeams)
          const Center(child: CircularProgressIndicator(color: AppColors.accent))
        else if (_allTeams.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border)),
            child: const Text('No registered teams yet. Switch to Quick entry.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text2)),
          )
        else ...[
          const Text('SELECT TEAM', style: TextStyle(
            color: AppColors.text2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          ..._allTeams.map((t) => GestureDetector(
            onTap: () => _selectTeam(t, isT1),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selTeam?.id == t.id ? AppColors.accent.withOpacity(0.1) : AppColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selTeam?.id == t.id ? AppColors.accent : AppColors.border,
                  width: selTeam?.id == t.id ? 1.5 : 1,
                ),
              ),
              child: Row(children: [
                TeamAvatar(shortName: t.shortName, size: 40),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                  Text('${t.players.length} players', style: const TextStyle(color: AppColors.text2, fontSize: 12)),
                ])),
                if (selTeam?.id == t.id)
                  const Icon(Icons.check_circle, color: AppColors.accent, size: 22),
              ]),
            ),
          )),
        ],

        // Playing 11 selector
        if (selTeam != null && roster.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Text('PLAYING 11', style: TextStyle(
              color: AppColors.text2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2))),
            Text('${selected.length}/$required', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: selected.length >= required ? AppColors.accent : AppColors.ball,
            )),
          ]),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border)),
            child: Column(children: roster.asMap().entries.map((e) {
              final p = e.value; final isSel = selected.contains(p.id);
              return ListTile(
                dense: true,
                leading: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: isSel ? AppColors.accent : AppColors.bgElevated,
                    shape: BoxShape.circle,
                  ),
                  child: Center(child: Text(
                    isSel ? '✓' : (p.jerseyNumber?.toString() ?? '${e.key + 1}'),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: isSel ? AppColors.textOnAcc : AppColors.text2),
                  )),
                ),
                title: Text(p.name, style: TextStyle(
                  color: isSel ? AppColors.accent : AppColors.text,
                  fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 14,
                )),
                subtitle: Text(p.role.replaceAll('_', ' '),
                  style: const TextStyle(color: AppColors.text2, fontSize: 11)),
                onTap: () => _togglePlayer(p.id, isT1),
                tileColor: isSel ? AppColors.accent.withOpacity(0.05) : null,
              );
            }).toList()),
          ),
        ],
      ] else ...[
        TextFormField(
          style: const TextStyle(color: AppColors.text),
          decoration: InputDecoration(
            labelText: isT1 ? 'Team 1 name' : 'Team 2 name',
            hintText: isT1 ? 'e.g. Mumbai XI' : 'e.g. Chennai Stars',
          ),
          onChanged: (v) => setState(() { if (isT1) _t1Name = v; else _t2Name = v; }),
        ),
        const SizedBox(height: 12),
        ...(isT1 ? _t1Players : _t2Players).asMap().entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Container(width: 32, height: 32, margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(color: AppColors.bgElevated, shape: BoxShape.circle),
              child: Center(child: Text('${e.key + 1}',
                style: const TextStyle(color: AppColors.text2, fontSize: 12, fontWeight: FontWeight.w700)))),
            Expanded(child: TextFormField(
              style: const TextStyle(color: AppColors.text),
              decoration: InputDecoration(hintText: 'Player ${e.key + 1}'),
              onChanged: (v) {
                final list = isT1 ? List<String>.from(_t1Players) : List<String>.from(_t2Players);
                list[e.key] = v;
                setState(() { if (isT1) _t1Players = list; else _t2Players = list; });
              },
            )),
          ]),
        )),
        TextButton.icon(
          onPressed: () => setState(() {
            if (isT1) _t1Players = [..._t1Players, '']; else _t2Players = [..._t2Players, ''];
          }),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add player'),
        ),
      ],
      const SizedBox(height: 80),
    ]);
  }

  Widget _buildTossStep() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Team badges
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        Column(children: [
          TeamAvatar(shortName: _t1Label.substring(0, _t1Label.length.clamp(0, 3)).toUpperCase(),
            color: AppColors.accent, size: 56),
          const SizedBox(height: 8),
          Text(_t1Label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
          Text('${_t1Registered ? _t1Selected.length : _t1Players.where((p) => p.trim().isNotEmpty).length} players',
            style: const TextStyle(color: AppColors.text2, fontSize: 12)),
        ]),
        const Text('vs', style: TextStyle(color: AppColors.text2, fontWeight: FontWeight.w700, fontSize: 18)),
        Column(children: [
          TeamAvatar(shortName: _t2Label.substring(0, _t2Label.length.clamp(0, 3)).toUpperCase(),
            color: AppColors.ball, size: 56),
          const SizedBox(height: 8),
          Text(_t2Label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
          Text('${_t2Registered ? _t2Selected.length : _t2Players.where((p) => p.trim().isNotEmpty).length} players',
            style: const TextStyle(color: AppColors.text2, fontSize: 12)),
        ]),
      ]),
      const SizedBox(height: 24),

      const Text('TOSS WON BY', style: TextStyle(
        color: AppColors.text2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: GestureDetector(
          onTap: () => setState(() => _tossT1 = true),
          child: _ToggleBtn(_t1Label, _tossT1, AppColors.accent),
        )),
        const SizedBox(width: 10),
        Expanded(child: GestureDetector(
          onTap: () => setState(() => _tossT1 = false),
          child: _ToggleBtn(_t2Label, !_tossT1, AppColors.ball),
        )),
      ]),
      const SizedBox(height: 16),

      const Text('ELECTED TO', style: TextStyle(
        color: AppColors.text2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: GestureDetector(
          onTap: () => setState(() => _tossBat = true),
          child: _ToggleBtn('🏏 Bat', _tossBat, AppColors.accent),
        )),
        const SizedBox(width: 10),
        Expanded(child: GestureDetector(
          onTap: () => setState(() => _tossBat = false),
          child: _ToggleBtn('🎳 Bowl', !_tossBat, AppColors.ball),
        )),
      ]),
      const SizedBox(height: 80),
    ]);
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  const _ToggleBtn(this.label, this.selected, this.color);

  @override Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.15) : AppColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? color : AppColors.border, width: selected ? 1.5 : 1),
      ),
      child: Text(label, textAlign: TextAlign.center, style: TextStyle(
        color: selected ? color : AppColors.text2,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
      )),
    );
  }
}

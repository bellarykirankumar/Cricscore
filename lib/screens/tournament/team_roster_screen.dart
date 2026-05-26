import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../models/models.dart';
import '../../main.dart';
import 'player_profile_screen.dart';

class TeamRosterScreen extends ConsumerStatefulWidget {
  final String tournamentId, teamId;
  const TeamRosterScreen({super.key, required this.tournamentId, required this.teamId});
  @override ConsumerState<TeamRosterScreen> createState() => _TeamRosterState();
}

class _TeamRosterState extends ConsumerState<TeamRosterScreen> {
  Team?        _team;
  List<Player> _players        = [];
  String?      _tournamentCreatedBy;
  String?      _userCountry;
  Set<String>  _ownedIds       = {};
  bool         _loading        = true;
  bool         _showAdd        = false;
  bool         _saving         = false;
  bool         _importing      = false;

  final _nameCtrl  = TextEditingController();
  String _role     = 'all_rounder';
  String _bat      = 'right_hand';
  String _bowl     = '';
  String _jersey   = '';

  @override void initState() { super.initState(); _loadAll(); }
  @override void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _loadAll() async {
    final results = await Future.wait([
      AuthService.instance.getCountry(),
      AuthService.instance.getOwnedIds(),
    ]);
    _userCountry = results[0] as String?;
    _ownedIds    = results[1] as Set<String>;
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final t = await TournamentApi.get(widget.tournamentId);
      final teamData = (t.teams ?? []).firstWhere((team) => team.id == widget.teamId,
        orElse: () => Team(id: widget.teamId, name: 'Team', shortName: ''));
      final players = await PlayerApi.list(widget.teamId).catchError((_) => <Player>[]);
      if (mounted) setState(() {
        _team = teamData;
        _tournamentCreatedBy = t.createdBy;
        _players = players;
        _loading = false;
      });
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
        if (_bowl.isNotEmpty)    'bowlingStyle': _bowl,
        if (_jersey.isNotEmpty)  'jerseyNumber': int.tryParse(_jersey),
        if (_userCountry != null) 'country': _userCountry,
      });
      _nameCtrl.clear();
      setState(() { _jersey = ''; _showAdd = false; });
      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { setState(() => _saving = false); }
  }

  // ── CSV bulk import ───────────────────────────────────────
  Future<void> _importCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    final content = String.fromCharCodes(bytes);
    final lines = content
        .split('\n')
        .map((l) => l.trim().replaceAll('\r', ''))
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return;

    // Skip header row when first row contains the word "name"
    final startIdx = lines.first.toLowerCase().contains('name') ? 1 : 0;
    final dataLines = lines.sublist(startIdx);

    if (dataLines.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No data rows found in CSV')));
      return;
    }

    setState(() => _importing = true);
    int success = 0, failed = 0;

    for (final line in dataLines) {
      final cols = line
          .split(',')
          .map((c) => c.trim().replaceAll('"', ''))
          .toList();
      if (cols.isEmpty || cols[0].isEmpty) continue;

      final name   = cols[0];
      final role   = cols.length > 1 && cols[1].isNotEmpty ? _normalizeRole(cols[1])  : 'all_rounder';
      final bat    = cols.length > 2 && cols[2].isNotEmpty ? _normalizeBat(cols[2])   : 'right_hand';
      final bowl   = cols.length > 3 && cols[3].isNotEmpty ? _normalizeBowl(cols[3])  : null;
      final jersey = cols.length > 4 ? int.tryParse(cols[4]) : null;

      try {
        await PlayerApi.create({
          'teamId':       widget.teamId,
          'name':         name,
          'role':         role,
          'battingStyle': bat,
          if (bowl != null && bowl.isNotEmpty) 'bowlingStyle': bowl,
          if (jersey != null) 'jerseyNumber': jersey,
          if (_userCountry != null) 'country': _userCountry,
        });
        success++;
      } catch (_) {
        failed++;
      }
    }

    setState(() => _importing = false);
    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failed == 0
          ? 'Imported $success player${success == 1 ? '' : 's'} ✓'
          : 'Imported $success, failed $failed'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  String _normalizeRole(String v) {
    final l = v.toLowerCase().trim().replaceAll(RegExp(r'[\s\-]+'), '_');
    const map = {
      'batsman': 'batsman',   'batter': 'batsman',
      'bowler': 'bowler',
      'all_rounder': 'all_rounder', 'allrounder': 'all_rounder',
      'wk': 'wicket_keeper',  'keeper': 'wicket_keeper',
      'wicket_keeper': 'wicket_keeper', 'wicketkeeper': 'wicket_keeper',
    };
    return map[l] ?? 'all_rounder';
  }

  String _normalizeBat(String v) =>
      v.toLowerCase().contains('left') ? 'left_hand' : 'right_hand';

  String? _normalizeBowl(String v) {
    if (v.isEmpty) return null;
    final l = v.toLowerCase().trim().replaceAll(RegExp(r'[\s\-]+'), '_');
    const map = {
      'right_arm_fast': 'right_arm_fast',   'ra_fast': 'right_arm_fast',
      'right_arm_medium': 'right_arm_medium','ra_medium': 'right_arm_medium',
      'right_arm_off_spin': 'right_arm_off_spin', 'ra_off_spin': 'right_arm_off_spin',
      'right_arm_leg_spin': 'right_arm_leg_spin', 'ra_leg_spin': 'right_arm_leg_spin',
      'left_arm_fast': 'left_arm_fast',     'la_fast': 'left_arm_fast',
      'left_arm_medium': 'left_arm_medium', 'la_medium': 'left_arm_medium',
      'left_arm_slow': 'left_arm_slow',     'la_slow': 'left_arm_slow',
    };
    return map[l];
  }

  // ── CSV template ──────────────────────────────────────────────
  void _downloadTemplate() {
    const template =
        'Name,Role,Batting Style,Bowling Style,Jersey Number\n'
        'Rohit Sharma,batsman,right_hand,right_arm_medium,45\n'
        'Virat Kohli,batsman,right_hand,,18\n'
        'Jasprit Bumrah,bowler,right_hand,right_arm_fast,93\n'
        'Ravindra Jadeja,all_rounder,left_hand,left_arm_slow,8\n'
        'MS Dhoni,wicket_keeper,right_hand,,7\n';

    Clipboard.setData(const ClipboardData(text: template));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('CSV template copied to clipboard — paste into Excel or Google Sheets'),
      duration: Duration(seconds: 4),
    ));
  }

  // ── Player registry search ────────────────────────────────────
  Future<void> _showPlayerSearch() async {
    if (_userCountry == null) return;
    final player = await showModalBottomSheet<Player>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlayerSearchSheet(country: _userCountry!, teamId: widget.teamId),
    );
    if (player != null) {
      // Player selected from registry — link them to this team.
      try {
        await PlayerApi.create({
          'teamId':       widget.teamId,
          'name':         player.name,
          'role':         player.role,
          'battingStyle': player.battingStyle,
          if (player.bowlingStyle != null) 'bowlingStyle': player.bowlingStyle,
          if (player.jerseyNumber != null) 'jerseyNumber': player.jerseyNumber,
          if (player.country != null)      'country': player.country,
        });
        await _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
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
          // CSV template + import — visible to tournament creator/admin only
          if (user != null &&
              (user.isAdmin || user.canManage(_tournamentCreatedBy) ||
               _ownedIds.contains(widget.tournamentId)))
            _importing
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent)),
                )
              : PopupMenuButton<String>(
                  icon: const Icon(Icons.upload_file_outlined, color: AppColors.accent),
                  color: AppColors.bgElevated,
                  onSelected: (v) {
                    if (v == 'import') _importCsv();
                    if (v == 'template') _downloadTemplate();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'template', child: Row(children: [
                      Icon(Icons.download_outlined, size: 18, color: AppColors.accent),
                      SizedBox(width: 10),
                      Text('Download template', style: TextStyle(color: AppColors.text)),
                    ])),
                    const PopupMenuItem(value: 'import', child: Row(children: [
                      Icon(Icons.upload_file_outlined, size: 18, color: AppColors.accent),
                      SizedBox(width: 10),
                      Text('Import from CSV', style: TextStyle(color: AppColors.text)),
                    ])),
                  ],
                ),
          if (user != null)
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
              if (_showAdd && user != null) _buildAddForm(),

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
                    if (user != null) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _showAdd = true),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add first player'),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent,
                          side: const BorderSide(color: AppColors.accent)),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _showPlayerSearch,
                        icon: const Icon(Icons.search, size: 16),
                        label: const Text('Search player registry'),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent,
                          side: const BorderSide(color: AppColors.accent)),
                      ),
                      if (user.isAdmin || user.canManage(_tournamentCreatedBy) ||
                          _ownedIds.contains(widget.tournamentId)) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _importing ? null : _importCsv,
                          icon: const Icon(Icons.upload_file_outlined, size: 16),
                          label: const Text('Import from CSV'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.text2,
                            side: const BorderSide(color: AppColors.border)),
                        ),
                      ],
                    ],
                  ])),

              ...(_players.asMap().entries.map((e) {
                final p = e.value;
                return AppCard(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => PlayerProfileScreen(player: p, teamId: widget.teamId),
                  )),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    // Avatar
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.accent.withOpacity(0.3))),
                      child: Center(child: Text(
                        p.jerseyNumber != null ? '#${p.jerseyNumber}' : '${e.key + 1}',
                        style: const TextStyle(
                          color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 13))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(p.name, style: const TextStyle(
                          fontWeight: FontWeight.w600, color: AppColors.text, fontSize: 15))),
                        if (p.playerCode != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentFaint,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.accent.withOpacity(0.3))),
                            child: Text(p.playerCode!,
                              style: const TextStyle(
                                color: AppColors.accent, fontSize: 10,
                                fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      Wrap(spacing: 4, children: [
                        _Tag(p.role.replaceAll('_', ' ')),
                        _Tag(p.battingStyle == 'right_hand' ? 'RHB' : 'LHB'),
                        if (p.bowlingStyle != null)
                          _Tag(p.bowlingStyle!.replaceAll('_', ' ')),
                        if (p.isClaimed) const _Tag('✓ Claimed', accent: true),
                      ]),
                    ])),
                    const Icon(Icons.chevron_right, color: AppColors.text3, size: 18),
                  ]),
                );
              })),
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
  final bool accent;
  const _Tag(this.label, {this.accent = false});
  @override Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accent ? AppColors.accentFaint : AppColors.bgElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent ? AppColors.accent.withOpacity(0.3) : AppColors.border)),
      child: Text(label, style: TextStyle(
        fontSize: 11, color: accent ? AppColors.accent : AppColors.text2)),
    );
  }
}

// ── Player Registry Search Sheet ──────────────────────────────
class _PlayerSearchSheet extends StatefulWidget {
  final String country, teamId;
  const _PlayerSearchSheet({required this.country, required this.teamId});
  @override State<_PlayerSearchSheet> createState() => _PlayerSearchSheetState();
}

class _PlayerSearchSheetState extends State<_PlayerSearchSheet> {
  final _ctrl = TextEditingController();
  List<Player> _results = [];
  bool _searching = false;

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _search(String q) async {
    if (q.length < 2) { setState(() => _results = []); return; }
    setState(() => _searching = true);
    try {
      final res = await PlayerApi.search(widget.country, q);
      if (mounted) setState(() => _results = res);
    } catch (_) {} finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(width: 40, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          const Text('Search Player Registry',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Search by name…',
                prefixIcon: const Icon(Icons.search, color: AppColors.text2),
                suffixIcon: _searching
                    ? const Padding(padding: EdgeInsets.all(12),
                        child: SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)))
                    : null,
              ),
              onChanged: _search,
            ),
          ),
          if (_results.isEmpty && _ctrl.text.length >= 2 && !_searching)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Text('No players found', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text('Add them manually using the + button',
                  style: TextStyle(color: AppColors.text2, fontSize: 13)),
              ]),
            ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final p = _results[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.accent.withOpacity(0.1),
                    child: Text(p.shortName.isNotEmpty ? p.shortName[0] : p.name[0],
                      style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                  ),
                  title: Text(p.name, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    [p.playerCode, p.role.replaceAll('_', ' ')].where((s) => s != null && s.isNotEmpty).join(' · '),
                    style: const TextStyle(color: AppColors.text2, fontSize: 12)),
                  trailing: TextButton(
                    onPressed: () => Navigator.pop(context, p),
                    child: const Text('Add', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                  ),
                );
              },
            ),
          ),
          SafeArea(child: TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel', style: TextStyle(color: AppColors.text2)),
          )),
        ]),
      ),
    );
  }
}

// Add teams getter to Tournament
extension TournamentTeams on Tournament {
  List<Team>? get teams => null; // Loaded separately via API
}

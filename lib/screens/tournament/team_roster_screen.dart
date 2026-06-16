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
  List<LeagueRegistration> _pool = [];
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
      final results = await Future.wait([
        TournamentApi.get(widget.tournamentId),
        TournamentApi.getTeam(widget.tournamentId, widget.teamId),
        PlayerApi.list(widget.teamId).catchError((_) => <Player>[]),
        TournamentApi.getRegistrations(widget.tournamentId, status: 'available')
            .catchError((_) => <LeagueRegistration>[]),
      ]);
      if (mounted) setState(() {
        _tournamentCreatedBy = (results[0] as Tournament).createdBy;
        _team               = results[1] as Team;
        _players            = results[2] as List<Player>;
        _pool               = results[3] as List<LeagueRegistration>;
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

  bool _canManageRoster(AuthUser? user) {
    if (user == null) return false;
    if (_team != null && user.isTeamCaptainOf(_team!)) return true;
    return user.isAdmin || user.canManage(_tournamentCreatedBy) ||
        _ownedIds.contains(widget.tournamentId);
  }

  bool _canAssignCaptain(AuthUser? user) {
    if (user == null) return false;
    return user.isAdmin || user.canManage(_tournamentCreatedBy) ||
        _ownedIds.contains(widget.tournamentId);
  }

  bool _canRequestCaptain(AuthUser? user) {
    if (user == null) return false;
    if (_canManageRoster(user)) return false; // already has access
    // No captain assigned yet (neither by ID nor email)
    return _team?.captainId == null && _team?.captainEmail == null;
  }

  Future<void> _requestCaptainRole(AuthUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Request Captain Role', style: TextStyle(
          color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
          'Request to become captain of ${_team?.name ?? 'this team'}?\n\n'
          'The league organizer will be notified and can approve or reject your request.',
          style: const TextStyle(color: AppColors.text2, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.text2))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Request')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await TournamentApi.requestCaptain(widget.tournamentId, widget.teamId, {
        'requestedBy':    user.sub,
        'requesterName':  user.name,
        'requesterEmail': user.email,
        'teamName':       _team?.name ?? '',
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Request sent — the league organizer will review it')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _showOrganizerCaptainSheet(AuthUser user) async {
    List<CaptainRequest> pending;
    List<JoinRequest> joinRequests;
    try {
      pending = await TournamentApi.getCaptainRequests(widget.tournamentId);
    } catch (_) {
      pending = [];
    }
    try {
      joinRequests = await TournamentApi.getJoinRequests(
          widget.tournamentId, widget.teamId, status: 'pending');
    } catch (_) {
      joinRequests = [];
    }
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrganizerCaptainSheet(
        tournamentId: widget.tournamentId,
        teamId: widget.teamId,
        teamName: _team?.name ?? 'Team',
        currentCaptainId: _team?.captainId,
        pendingRequests: pending.where((r) => r.teamId == widget.teamId).toList(),
        joinRequests: joinRequests,
        onDone: () async { await _load(); },
      ),
    );
  }

  Future<void> _showLeaguePool() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LeaguePoolSheet(
        tournamentId: widget.tournamentId,
        teamId: widget.teamId,
        teamName: _team?.name ?? 'Team',
        onAdded: () async { await _load(); },
      ),
    );
  }

  @override Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    final canManage = _canManageRoster(user);
    final canAssign = _canAssignCaptain(user);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Column(children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_team?.name ?? 'Team'),
            if (_team?.captainId != null || _team?.captainEmail != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6)),
                child: const Text('C', style: TextStyle(
                  color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ],
          ]),
          Text('${_players.length} players', style: const TextStyle(
            fontSize: 12, color: AppColors.text2, fontWeight: FontWeight.w400)),
        ]),
        actions: [
          if (canAssign)
            IconButton(
              icon: const Icon(Icons.manage_accounts_outlined, color: AppColors.text2),
              tooltip: 'Captain Management',
              onPressed: () => _showOrganizerCaptainSheet(user!),
            ),
          // CSV template + import — visible to roster managers only
          if (canManage)
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
          if (canManage)
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
              if (_showAdd && canManage) _buildAddForm(),

              // Player pool banner — shown to captains when players are waiting
              if (canManage && _pool.isNotEmpty)
                GestureDetector(
                  onTap: _showLeaguePool,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.ball.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.ball.withOpacity(0.4)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.ball.withOpacity(0.15),
                          shape: BoxShape.circle),
                        child: Center(child: Text('${_pool.length}',
                          style: const TextStyle(
                            color: AppColors.ball, fontWeight: FontWeight.w800, fontSize: 14))),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Players waiting to join',
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
                        Text('Tap to view the pool and add to your team',
                          style: TextStyle(color: AppColors.text2, fontSize: 12)),
                      ])),
                      const Icon(Icons.chevron_right, color: AppColors.ball, size: 18),
                    ]),
                  ),
                ),

              // Request captain banner (shown when no captain assigned and user is eligible)
              if (!canManage && _canRequestCaptain(user) && !_loading)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.shield_outlined, color: AppColors.accent, size: 22),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('No captain assigned yet',
                        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
                      const Text('Request to become this team\'s captain',
                        style: TextStyle(color: AppColors.text2, fontSize: 12)),
                    ])),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: user != null ? () => _requestCaptainRole(user) : null,
                      style: TextButton.styleFrom(
                        backgroundColor: AppColors.accent.withOpacity(0.12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text('Request', style: TextStyle(
                        color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ]),
                ),

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
                    if (canManage) ...[
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
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _showLeaguePool,
                        icon: const Icon(Icons.group_outlined, size: 16),
                        label: const Text('Browse league player pool'),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.ball,
                          side: const BorderSide(color: AppColors.ball)),
                      ),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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


// ── Organizer Captain Management Sheet ───────────────────────
class _OrganizerCaptainSheet extends StatefulWidget {
  final String tournamentId, teamId, teamName;
  final String? currentCaptainId;
  final List<CaptainRequest> pendingRequests;
  final List<JoinRequest> joinRequests;
  final VoidCallback onDone;
  const _OrganizerCaptainSheet({
    required this.tournamentId, required this.teamId, required this.teamName,
    this.currentCaptainId, required this.pendingRequests,
    required this.joinRequests, required this.onDone,
  });
  @override State<_OrganizerCaptainSheet> createState() => _OrganizerCaptainSheetState();
}

class _OrganizerCaptainSheetState extends State<_OrganizerCaptainSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _emailCtrl = TextEditingController();
  bool _assigning = false;
  String? _assignError;
  Map<String, bool> _responding = {};

  Map<String, bool> _respondingJoin = {};

  @override void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this,
      initialIndex: widget.joinRequests.isNotEmpty ? 0
        : widget.pendingRequests.isNotEmpty ? 1 : 2);
  }
  @override void dispose() { _tabs.dispose(); _emailCtrl.dispose(); super.dispose(); }

  Future<void> _respondJoin(JoinRequest req, String status) async {
    setState(() => _respondingJoin[req.id] = true);
    try {
      await TournamentApi.respondToJoinRequest(
          widget.tournamentId, widget.teamId, req.id, status);
      widget.onDone();
      if (mounted) setState(() => _respondingJoin.remove(req.id));
      if (mounted && status == 'approved') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${req.requesterName} added to roster ✓')));
      }
    } catch (e) {
      if (mounted) setState(() => _respondingJoin.remove(req.id));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')));
    }
  }

  Future<void> _respond(CaptainRequest req, String status) async {
    setState(() => _responding[req.id] = true);
    try {
      await TournamentApi.respondToCaptainRequest(widget.tournamentId, req.id, status);
      widget.onDone();
      if (mounted) setState(() => _responding.remove(req.id));
      if (mounted && status == 'approved') Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _responding.remove(req.id));
    }
  }

  Future<void> _assignByEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() { _assigning = true; _assignError = null; });
    try {
      await TournamentApi.assignCaptainByEmail(widget.tournamentId, widget.teamId, email);
      widget.onDone();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _assigning = false; _assignError = '$e'; });
    }
  }

  Future<void> _removeCaptain() async {
    setState(() { _assigning = true; _assignError = null; });
    try {
      await TournamentApi.updateTeam(widget.tournamentId, widget.teamId, {'captainId': null});
      widget.onDone();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _assigning = false; _assignError = '$e'; });
    }
  }

  @override Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(width: 40, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Captain Management', style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
                Text(widget.teamName, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
              ])),
              if (widget.currentCaptainId != null)
                TextButton.icon(
                  onPressed: _assigning ? null : _removeCaptain,
                  icon: const Icon(Icons.person_remove_outlined, size: 15, color: AppColors.wicket),
                  label: const Text('Remove', style: TextStyle(color: AppColors.wicket, fontSize: 12)),
                ),
            ]),
          ),
          TabBar(
            controller: _tabs,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.text2,
            indicatorColor: AppColors.accent,
            dividerColor: AppColors.border,
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: [
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Join Req.', style: TextStyle(fontSize: 12)),
                if (widget.joinRequests.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent, borderRadius: BorderRadius.circular(10)),
                    child: Text('${widget.joinRequests.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ],
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Captain', style: TextStyle(fontSize: 12)),
                if (widget.pendingRequests.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.wicket, borderRadius: BorderRadius.circular(10)),
                    child: Text('${widget.pendingRequests.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ],
              ])),
              const Tab(child: Text('Assign', style: TextStyle(fontSize: 12))),
            ],
          ),
          Expanded(child: TabBarView(
            controller: _tabs,
            children: [
              // ── Tab 0: Join Requests
              widget.joinRequests.isEmpty
                ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('🙋', style: TextStyle(fontSize: 36)),
                    SizedBox(height: 10),
                    Text('No join requests yet', style: TextStyle(
                      color: AppColors.text, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('Players registered for the league\ncan request to join this team',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.text2, fontSize: 13)),
                  ]))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemCount: widget.joinRequests.length,
                    itemBuilder: (_, i) {
                      final req = widget.joinRequests[i];
                      final loading = _respondingJoin[req.id] == true;
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.bgElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(children: [
                          CircleAvatar(
                            backgroundColor: AppColors.ball.withOpacity(0.12),
                            radius: 20,
                            child: Text(
                              req.requesterName.isNotEmpty ? req.requesterName[0].toUpperCase() : '?',
                              style: const TextStyle(color: AppColors.ball, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(req.requesterName, style: const TextStyle(
                              color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
                            Text(req.preferredRole.replaceAll('_', ' '), style: const TextStyle(
                              color: AppColors.text2, fontSize: 12)),
                          ])),
                          if (loading)
                            const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                          else ...[
                            IconButton(
                              icon: const Icon(Icons.check_circle_outline, color: AppColors.accent, size: 26),
                              tooltip: 'Approve',
                              onPressed: () => _respondJoin(req, 'approved'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel_outlined, color: AppColors.wicket, size: 26),
                              tooltip: 'Reject',
                              onPressed: () => _respondJoin(req, 'rejected'),
                            ),
                          ],
                        ]),
                      );
                    },
                  ),

              // ── Tab 1: Captain Requests
              widget.pendingRequests.isEmpty
                ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('🛡️', style: TextStyle(fontSize: 36)),
                    SizedBox(height: 10),
                    Text('No pending requests', style: TextStyle(
                      color: AppColors.text, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('Users can request the captain role\nfrom the team roster screen',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.text2, fontSize: 13)),
                  ]))
                : ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.all(16),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemCount: widget.pendingRequests.length,
                    itemBuilder: (_, i) {
                      final req = widget.pendingRequests[i];
                      final loading = _responding[req.id] == true;
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.bgElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(children: [
                          CircleAvatar(
                            backgroundColor: AppColors.accent.withOpacity(0.1),
                            radius: 20,
                            child: Text(
                              req.requesterName.isNotEmpty ? req.requesterName[0].toUpperCase() : '?',
                              style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(req.requesterName, style: const TextStyle(
                              color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
                            Text(req.requesterEmail, style: const TextStyle(
                              color: AppColors.text2, fontSize: 12)),
                          ])),
                          if (loading)
                            const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                          else ...[
                            IconButton(
                              icon: const Icon(Icons.check_circle_outline, color: AppColors.accent, size: 26),
                              tooltip: 'Approve',
                              onPressed: () => _respond(req, 'approved'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel_outlined, color: AppColors.wicket, size: 26),
                              tooltip: 'Reject',
                              onPressed: () => _respond(req, 'rejected'),
                            ),
                          ],
                        ]),
                      );
                    },
                  ),

              // ── Tab 2: Assign by Email
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Assign captain directly by email',
                    style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 6),
                  const Text(
                    'Enter the email address of the user you want to appoint as captain. '
                    'They must already have an account in the app.',
                    style: TextStyle(color: AppColors.text2, fontSize: 13)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: AppColors.text),
                    decoration: InputDecoration(
                      labelText: 'Email address',
                      hintText: 'captain@example.com',
                      errorText: _assignError,
                      prefixIcon: const Icon(Icons.email_outlined, color: AppColors.text2),
                    ),
                    onChanged: (_) => setState(() => _assignError = null),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _assigning ? null : _assignByEmail,
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                      child: _assigning
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnAcc))
                        : const Text('Assign Captain', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ),
            ],
          )),
          SafeArea(child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: AppColors.text2)))),
        ]),
      ),
    );
  }
}


// Add teams getter to Tournament
extension TournamentTeams on Tournament {
  List<Team>? get teams => null; // Loaded separately via API
}

// ── League Pool Sheet ─────────────────────────────────────────
// Captain browses all registered-but-available players and adds them directly
class _LeaguePoolSheet extends StatefulWidget {
  final String tournamentId, teamId, teamName;
  final VoidCallback onAdded;
  const _LeaguePoolSheet({
    required this.tournamentId, required this.teamId,
    required this.teamName, required this.onAdded,
  });
  @override State<_LeaguePoolSheet> createState() => _LeaguePoolSheetState();
}

class _LeaguePoolSheetState extends State<_LeaguePoolSheet> {
  List<LeagueRegistration> _pool = [];
  bool _loading = true;
  Set<String> _adding = {};

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final regs = await TournamentApi.getRegistrations(
          widget.tournamentId, status: 'available');
      if (mounted) setState(() { _pool = regs; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addToTeam(LeagueRegistration reg) async {
    setState(() => _adding.add(reg.userId));
    try {
      await PlayerApi.create({
        'teamId':       widget.teamId,
        'name':         reg.userName.isNotEmpty ? reg.userName : reg.userEmail,
        'role':         reg.preferredRole,
        'battingStyle': 'right_hand',
        'userId':       reg.userId,
        'userEmail':    reg.userEmail,
      });
      widget.onAdded();
      if (mounted) {
        setState(() {
          _adding.remove(reg.userId);
          _pool.removeWhere((r) => r.userId == reg.userId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${reg.userName} added to ${widget.teamName} ✓')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _adding.remove(reg.userId));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 12),
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4), child:
            Row(children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('League Player Pool', style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text)),
                SizedBox(height: 2),
                Text('Players registered for this league without a team',
                  style: TextStyle(color: AppColors.text2, fontSize: 12)),
              ])),
              IconButton(
                icon: const Icon(Icons.refresh_outlined, color: AppColors.text2),
                onPressed: _load,
              ),
            ]),
          ),
          const Divider(color: AppColors.border, height: 1),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : _pool.isEmpty
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('👥', style: TextStyle(fontSize: 36)),
                  SizedBox(height: 10),
                  Text('No available players', style: TextStyle(
                    color: AppColors.text, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('Players join the pool by registering\nfor this league',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.text2, fontSize: 13)),
                ]))
              : ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.all(16),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: _pool.length,
                  itemBuilder: (_, i) {
                    final reg = _pool[i];
                    final isAdding = _adding.contains(reg.userId);
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.bgElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border)),
                      child: Row(children: [
                        CircleAvatar(
                          backgroundColor: AppColors.ball.withOpacity(0.12),
                          radius: 22,
                          child: Text(
                            reg.userName.isNotEmpty ? reg.userName[0].toUpperCase() : '?',
                            style: const TextStyle(color: AppColors.ball, fontWeight: FontWeight.w700, fontSize: 16)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(reg.userName.isNotEmpty ? reg.userName : reg.userEmail,
                            style: const TextStyle(
                              color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
                          Text(reg.preferredRole.replaceAll('_', ' '),
                            style: const TextStyle(color: AppColors.text2, fontSize: 12)),
                          if (reg.bio.isNotEmpty)
                            Text(reg.bio, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.text2, fontSize: 11)),
                        ])),
                        const SizedBox(width: 8),
                        isAdding
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                          : TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: AppColors.accent.withOpacity(0.1),
                                foregroundColor: AppColors.accent,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _addToTeam(reg),
                              child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                      ]),
                    );
                  },
                ),
          ),
          SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: AppColors.text2)),
            ),
          )),
        ]),
      ),
    );
  }
}

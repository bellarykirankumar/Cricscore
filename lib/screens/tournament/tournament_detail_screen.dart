import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../models/models.dart';
import '../../main.dart';

class TournamentDetailScreen extends ConsumerStatefulWidget {
  final String tournamentId;
  const TournamentDetailScreen({super.key, required this.tournamentId});
  @override ConsumerState<TournamentDetailScreen> createState() => _TournamentDetailState();
}

class _TournamentDetailState extends ConsumerState<TournamentDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Tournament?        _tournament;
  List<Team>         _teams       = [];
  List<Fixture>      _fixtures    = [];
  List<Map<String, dynamic>> _standings = [];
  bool               _loading     = true;
  bool               _isLocalOwner = false;

  @override void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }
  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        TournamentApi.get(widget.tournamentId),
        TournamentApi.listTeams(widget.tournamentId).catchError((_) => <Team>[]),
        TournamentApi.getFixtures(widget.tournamentId).catchError((_) => <Fixture>[]),
        TournamentApi.getStandings(widget.tournamentId).catchError((_) => <Map<String, dynamic>>[]),
      ]);

      final teams = results[1] as List<Team>;
      // Load player counts
      final teamsWithPlayers = await Future.wait(teams.map((t) async {
        final players = await PlayerApi.list(t.id).catchError((_) => <Player>[]);
        return t.copyWith(players: players);
      }));

      if (!mounted) return;
      final rawFixtures = results[2] as List<Fixture>;
      final matchIds = rawFixtures.map((f) => f.matchId).whereType<String>().toSet();
      final byStatus = await MatchApi.loadMatchStatusesForIds(matchIds);
      final fixturesOpen = TournamentApi.fixturesExcludingFinishedMatches(rawFixtures, byStatus);
      final isOwner = await AuthService.instance.isLocalOwner(widget.tournamentId);
      setState(() {
        _tournament   = results[0] as Tournament;
        _teams        = teamsWithPlayers;
        _fixtures     = fixturesOpen;
        _standings    = results[3] as List<Map<String, dynamic>>;
        _isLocalOwner = isOwner;
        _loading      = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showManageScorers(Tournament t) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24,
            MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('Manage Scorers', style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 4),
            const Text('Add users who can score matches in this tournament',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text2, fontSize: 13)),
            const SizedBox(height: 16),
            if (t.scorerIds.isNotEmpty) ...[
              ...t.scorerIds.map((id) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline, color: AppColors.accent),
                title: Text(id, style: const TextStyle(color: AppColors.text, fontSize: 13)),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: AppColors.wicket, size: 20),
                  onPressed: () async {
                    final updated = List<String>.from(t.scorerIds)..remove(id);
                    await TournamentApi.update(t.id, {'scorerIds': updated});
                    if (mounted) { Navigator.pop(ctx); _load(); }
                  },
                ),
              )),
              const Divider(color: AppColors.border),
            ],
            Row(children: [
              Expanded(child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'scorer@example.com',
                  prefixIcon: Icon(Icons.email_outlined,
                    color: AppColors.text2, size: 20),
                ),
              )),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(72, 52),
                ),
                onPressed: () async {
                  final email = ctrl.text.trim().toLowerCase();
                  if (email.isEmpty || !email.contains('@')) return;
                  if (t.scorerIds.contains(email)) {
                    Navigator.pop(ctx);
                    return;
                  }
                  final updated = [...t.scorerIds, email];
                  await TournamentApi.update(t.id, {'scorerIds': updated});
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                        'Scorer added. If they\'re not registered yet, '
                        'they\'ll get access once they sign up with this email.'),
                      duration: Duration(seconds: 4),
                    ));
                    _load();
                  }
                },
                child: const Text('Add'),
              ),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  @override Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    if (_loading) return const LoadingScreen();
    if (_tournament == null) return ErrorScreen(message: 'Tournament not found', onRetry: _load);

    final t = _tournament!;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            floating: true, snap: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 20),
              onPressed: () => context.go('/'),
            ),
            title: Column(children: [
              Text(t.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text('${t.format} · ${_teams.length} teams', style: const TextStyle(
                fontSize: 12, color: AppColors.text2, fontWeight: FontWeight.w400)),
            ]),
            actions: [
              if (user?.canManage(t.createdBy) == true || _isLocalOwner)
                IconButton(
                  icon: const Icon(Icons.manage_accounts_outlined, color: AppColors.text2),
                  tooltip: 'Manage scorers',
                  onPressed: () => _showManageScorers(t),
                ),
              Container(
                margin: const EdgeInsets.only(right: 16),
                child: StatusBadge(
                  label: t.isActive ? 'Active' : t.isUpcoming ? 'Upcoming' : 'Done',
                  color: t.isActive ? AppColors.accent : t.isUpcoming ? AppColors.ball : AppColors.text2,
                ),
              ),
            ],
            bottom: TabBar(controller: _tabs, tabs: const [
              Tab(text: 'Teams'), Tab(text: 'Fixtures'), Tab(text: 'Standings'),
            ]),
          ),
        ],
        body: TabBarView(controller: _tabs, children: [
          _TeamsTab(teams: _teams, tournamentId: widget.tournamentId, user: user,
            onRefresh: _load, tournament: t, fixtures: _fixtures, isOwner: _isLocalOwner),
          _FixturesTab(fixtures: _fixtures, teams: _teams, tournament: t, tournamentId: widget.tournamentId,
            user: user, onRefresh: _load, isOwner: _isLocalOwner),
          _StandingsTab(standings: _standings),
        ]),
      ),
    );
  }
}

// ── Teams Tab ─────────────────────────────────────────────────
class _TeamsTab extends StatefulWidget {
  final List<Team> teams;
  final String tournamentId;
  final AuthUser? user;
  final Future<void> Function() onRefresh;
  final Tournament tournament;
  final List<Fixture> fixtures;
  final bool isOwner;

  const _TeamsTab({
    required this.teams, required this.tournamentId, required this.user,
    required this.onRefresh, required this.tournament, required this.fixtures,
    required this.isOwner,
  });

  @override State<_TeamsTab> createState() => _TeamsTabState();
}

class _TeamsTabState extends State<_TeamsTab> {
  bool   _showAdd = false;
  bool   _saving  = false;
  String _name    = '';
  String _short   = '';

  Future<void> _addTeam() async {
    if (_name.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await TournamentApi.addTeam(widget.tournamentId, {
        'name': _name.trim(),
        'shortName': _short.trim().isEmpty
          ? _name.trim().substring(0, _name.trim().length.clamp(0, 3)).toUpperCase()
          : _short.trim().toUpperCase(),
        if (widget.user != null) 'createdBy': widget.user!.sub,
      });
      setState(() { _name = ''; _short = ''; _showAdd = false; });
      widget.onRefresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { setState(() => _saving = false); }
  }

  Future<void> _genFixtures() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: const Text('Generate fixtures?', style: TextStyle(color: AppColors.text)),
      content: Text('Generate round-robin fixtures for ${widget.teams.length} teams?',
        style: const TextStyle(color: AppColors.text2)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true),
          child: const Text('Generate', style: TextStyle(color: AppColors.accent))),
      ],
    ));
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await TournamentApi.genFixtures(widget.tournamentId);
      widget.onRefresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { setState(() => _saving = false); }
  }

  @override Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: AppColors.accent,
      child: ListView(children: [
        if (widget.user?.canManage(widget.tournament.createdBy) == true || widget.isOwner)
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              Expanded(child: ElevatedButton.icon(
                onPressed: () => setState(() => _showAdd = !_showAdd),
                icon: Icon(_showAdd ? Icons.close : Icons.add, size: 18),
                label: Text(_showAdd ? 'Cancel' : 'Add team'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _showAdd ? AppColors.bgElevated : AppColors.accent,
                  foregroundColor: _showAdd ? AppColors.text2 : AppColors.textOnAcc,
                ),
              )),
            ])),

        if (_showAdd && (widget.user?.canManage(widget.tournament.createdBy) == true || widget.isOwner))
          AppCard(child: Column(children: [
            TextField(
              style: const TextStyle(color: AppColors.text),
              decoration: const InputDecoration(labelText: 'Team name', hintText: 'e.g. Mumbai XI'),
              onChanged: (v) => setState(() => _name = v),
            ),
            const SizedBox(height: 8),
            TextField(
              style: const TextStyle(color: AppColors.text),
              decoration: const InputDecoration(labelText: 'Short name (3 letters)', hintText: 'MUM'),
              maxLength: 3,
              onChanged: (v) => setState(() => _short = v.toUpperCase()),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _saving ? null : _addTeam,
              child: _saving ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnAcc))
                : const Text('Add team'),
            ),
          ])),

        ...widget.teams.map((t) => AppCard(
          onTap: () => context.push('/tournament/${widget.tournamentId}/team/${t.id}'),
          child: Row(children: [
            TeamAvatar(shortName: t.shortName),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 15)),
              Text('${t.players.length} players', style: const TextStyle(color: AppColors.text2, fontSize: 13)),
            ])),
            const Text('Roster →', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
          ]),
        )),

        if (widget.teams.length >= 2 && widget.fixtures.isEmpty &&
            (widget.user?.canManage(widget.tournament.createdBy) == true || widget.isOwner))
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _genFixtures,
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text('Generate round-robin (${widget.teams.length} teams)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.ball.withOpacity(0.15),
                foregroundColor: AppColors.ball,
              ),
            )),

        if (widget.teams.isEmpty && !_showAdd)
          const Padding(padding: EdgeInsets.all(32),
            child: Column(children: [
              Text('👥', style: TextStyle(fontSize: 36)),
              SizedBox(height: 10),
              Text('No teams yet', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
              SizedBox(height: 6),
              Text('Add teams above', style: TextStyle(color: AppColors.text2, fontSize: 13)),
            ])),
        const SizedBox(height: 40),
      ]),
    );
  }
}

String _fmtScheduled(String s) {
  try {
    final dt = DateTime.parse(s).toLocal();
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2,'0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '${dt.day} ${months[dt.month-1]} · $h:$m $ampm';
  } catch (_) { return s; }
}

// ── Fixtures Tab ──────────────────────────────────────────────
class _FixturesTab extends StatefulWidget {
  final List<Fixture> fixtures;
  final List<Team> teams;
  final Tournament tournament;
  final String tournamentId;
  final AuthUser? user;
  final Future<void> Function() onRefresh;
  final bool isOwner;

  const _FixturesTab({
    required this.fixtures, required this.teams, required this.tournament, required this.tournamentId,
    required this.user, required this.onRefresh, required this.isOwner,
  });
  @override State<_FixturesTab> createState() => _FixturesTabState();
}

class _FixturesTabState extends State<_FixturesTab> {
  String?    _starting;
  Fixture?   _tossFixture;
  bool       _tossHome   = true;
  bool       _tossBat    = true;
  List<Player> _homeRoster = [];
  List<Player> _awayRoster = [];
  Set<String>  _homeSel  = {};
  Set<String>  _awaySel  = {};
  // Create fixture state
  bool         _showCreateFixture = false;
  String?      _newHomeTeamId;
  String?      _newAwayTeamId;
  DateTime?    _newDate;
  TimeOfDay?   _newTime;
  bool         _savingFixture = false;


  Future<void> _saveFixture() async {
    if (_newHomeTeamId == null || _newAwayTeamId == null) return;
    if (_newHomeTeamId == _newAwayTeamId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Teams must be different')));
      return;
    }
    if (widget.teams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Teams not loaded — please wait and try again')));
      return;
    }
    final home = widget.teams.firstWhere((t) => t.id == _newHomeTeamId, orElse: () => Team(id: '', name: '', shortName: '', players: []));
    final away = widget.teams.firstWhere((t) => t.id == _newAwayTeamId, orElse: () => Team(id: '', name: '', shortName: '', players: []));
    if (home.id.isEmpty || away.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selected team not found — please refresh and try again')));
      return;
    }
    setState(() => _savingFixture = true);
    try {
      String? scheduled;
      if (_newDate != null) {
        final t = _newTime ?? const TimeOfDay(hour: 10, minute: 0);
        final dt = DateTime(_newDate!.year, _newDate!.month, _newDate!.day, t.hour, t.minute);
        scheduled = dt.toIso8601String();
      }
      await TournamentApi.addFixture(widget.tournamentId, {
        'homeTeamId': home.id, 'homeTeamName': home.name,
        'awayTeamId': away.id, 'awayTeamName': away.name,
        if (scheduled != null) 'scheduledDate': scheduled,
      });
      setState(() { _showCreateFixture = false; _newHomeTeamId = null; _newAwayTeamId = null; _newDate = null; _newTime = null; });
      widget.onRefresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      setState(() => _savingFixture = false);
    }
  }

  Future<void> _openToss(Fixture f) async {
    setState(() => _starting = f.id);
    try {
      final results = await Future.wait([
        PlayerApi.list(f.homeTeamId).catchError((_) => <Player>[]),
        PlayerApi.list(f.awayTeamId).catchError((_) => <Player>[]),
      ]);
      final home = results[0];
      final away = results[1];
      setState(() {
        _homeRoster = home; _awayRoster = away;
        _homeSel = home.take(11).map((p) => p.id).toSet();
        _awaySel = away.take(11).map((p) => p.id).toSet();
        _tossFixture = f;
      });
    } finally { setState(() => _starting = null); }
  }

  Future<void> _startMatch() async {
    final f = _tossFixture;
    if (f == null) return;
    setState(() => _starting = f.id);
    try {
      final team1 = Team(
        id: f.homeTeamId, name: f.homeTeamName,
        shortName: f.homeTeamName.substring(0, f.homeTeamName.length.clamp(0, 3)).toUpperCase(),
        players: _homeRoster.where((p) => _homeSel.contains(p.id)).toList(),
      );
      final team2 = Team(
        id: f.awayTeamId, name: f.awayTeamName,
        shortName: f.awayTeamName.substring(0, f.awayTeamName.length.clamp(0, 3)).toUpperCase(),
        players: _awayRoster.where((p) => _awaySel.contains(p.id)).toList(),
      );

      final ovs = widget.tournament.format == 'T10' ? 10
        : widget.tournament.format == 'ODI' ? 50 : 20;

      final match = await MatchApi.create({
        'tournamentId': widget.tournamentId,
        'format': widget.tournament.format, 'oversPerInnings': ovs,
        'team1': team1.toJson(), 'team2': team2.toJson(),
        if (widget.user != null) 'createdBy': widget.user!.sub,
      });
      await AuthService.instance.claimOwnership(match.id);
      await MatchApi.update(match.id, {'status': 'in_progress'});

      final tossTeam = _tossHome ? team1 : team2;
      final battingId = _tossBat ? tossTeam.id
        : (tossTeam.id == team1.id ? team2.id : team1.id);
      final bowlingId = battingId == team1.id ? team2.id : team1.id;

      await MatchApi.startInnings(match.id, {'battingTeamId': battingId, 'bowlingTeamId': bowlingId});

      setState(() => _tossFixture = null);
      widget.onRefresh();
      if (mounted) context.push('/scoring/${match.id}');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { setState(() => _starting = null); }
  }

  void _togglePlayer(String id, bool isHome) {
    final set = isHome ? Set<String>.from(_homeSel) : Set<String>.from(_awaySel);
    if (set.contains(id)) { set.remove(id); }
    else if (set.length < 11) { set.add(id); }
    else { ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Max 11 players'))); return; }
    setState(() { if (isHome) _homeSel = set; else _awaySel = set; });
  }

  @override Widget build(BuildContext context) {
    final rounds = widget.fixtures.map((f) => f.round).toSet().toList()..sort();

    return Stack(children: [
      RefreshIndicator(
        onRefresh: widget.onRefresh,
        color: AppColors.accent,
        child: ListView(children: [
          // Admin: create fixture button (shown even when list is empty)
          if (widget.user?.canManage(widget.tournament.createdBy) == true || widget.isOwner)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _showCreateFixture = !_showCreateFixture),
                icon: Icon(_showCreateFixture ? Icons.close : Icons.add, size: 18),
                label: Text(_showCreateFixture ? 'Cancel' : 'Create fixture'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _showCreateFixture ? AppColors.bgElevated : AppColors.ball,
                  foregroundColor: _showCreateFixture ? AppColors.text2 : AppColors.textOnAcc,
                ),
              ),
            ),

          if (_showCreateFixture && (widget.user?.canManage(widget.tournament.createdBy) == true || widget.isOwner))
            AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('New fixture', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 12),
              // Home team dropdown
              DropdownButtonFormField<String>(
                value: _newHomeTeamId,
                dropdownColor: AppColors.bgCard,
                style: const TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  labelText: 'Home team',
                  labelStyle: const TextStyle(color: AppColors.text2),
                  filled: true, fillColor: AppColors.bgElevated,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                ),
                items: widget.teams.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                onChanged: (v) => setState(() => _newHomeTeamId = v),
              ),
              const SizedBox(height: 10),
              // Away team dropdown
              DropdownButtonFormField<String>(
                value: _newAwayTeamId,
                dropdownColor: AppColors.bgCard,
                style: const TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  labelText: 'Away team',
                  labelStyle: const TextStyle(color: AppColors.text2),
                  filled: true, fillColor: AppColors.bgElevated,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                ),
                items: widget.teams.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                onChanged: (v) => setState(() => _newAwayTeamId = v),
              ),
              const SizedBox(height: 10),
              // Date picker
              GestureDetector(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _newDate ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (ctx, child) => Theme(
                      data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.accent)),
                      child: child!,
                    ),
                  );
                  if (d != null) setState(() => _newDate = d);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today, color: AppColors.text2, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      _newDate == null ? 'Select date' : '${_newDate!.day}/${_newDate!.month}/${_newDate!.year}',
                      style: TextStyle(color: _newDate == null ? AppColors.text2 : AppColors.text),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              // Time picker
              GestureDetector(
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _newTime ?? const TimeOfDay(hour: 10, minute: 0),
                    builder: (ctx, child) => Theme(
                      data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.accent)),
                      child: child!,
                    ),
                  );
                  if (t != null) setState(() => _newTime = t);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(children: [
                    const Icon(Icons.access_time, color: AppColors.text2, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      _newTime == null ? 'Select time' : _newTime!.format(context),
                      style: TextStyle(color: _newTime == null ? AppColors.text2 : AppColors.text),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity, height: 46,
                child: ElevatedButton(
                  onPressed: (_savingFixture || _newHomeTeamId == null || _newAwayTeamId == null) ? null : _saveFixture,
                  child: _savingFixture
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnAcc))
                    : const Text('Create fixture'),
                ),
              ),
            ])),

          if (widget.fixtures.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('🗓', style: TextStyle(fontSize: 40)),
                SizedBox(height: 12),
                Text('No fixtures yet', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                SizedBox(height: 6),
                Text('Add teams and generate round-robin', style: TextStyle(color: AppColors.text2, fontSize: 13)),
              ]),
            ),

          ...rounds.expand((round) => [
            SectionHeader(title: 'Round $round'),
            ...widget.fixtures.where((f) => f.round == round).map((f) => AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f.homeTeamName, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                    const Text('vs', style: TextStyle(color: AppColors.text2, fontSize: 12)),
                    Text(f.awayTeamName, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                    if (f.scheduledDate != null) ...[
                      const SizedBox(height: 4),
                      Text('📅 ${_fmtScheduled(f.scheduledDate!)}', style: const TextStyle(color: AppColors.ball, fontSize: 12)),
                    ],
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    StatusBadge(
                      label: f.status == 'completed' ? '✓ Done' : f.matchId != null ? 'Live' : 'Scheduled',
                      color: f.status == 'completed' ? AppColors.accent : f.matchId != null ? AppColors.wicket : AppColors.text2,
                    ),
                    if ((widget.user?.canManage(widget.tournament.createdBy) == true || widget.isOwner) && f.status != 'completed') ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () async {
                          final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                            backgroundColor: AppColors.bgCard,
                            title: const Text('Delete fixture?', style: TextStyle(color: AppColors.text)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete', style: TextStyle(color: AppColors.wicket))),
                            ],
                          ));
                          if (ok == true) {
                            await TournamentApi.deleteFixture(widget.tournamentId, f.id);
                            widget.onRefresh();
                          }
                        },
                        child: const Icon(Icons.close, color: AppColors.wicket, size: 18),
                      ),
                    ],
                  ]),
                ]),
                if (f.status != 'completed') ...[
                  const SizedBox(height: 10),
                  if (f.matchId != null)
                    OutlinedButton(
                      onPressed: () => context.push('/scoring/${f.matchId}'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.ball,
                        side: const BorderSide(color: AppColors.ball),
                        minimumSize: const Size(double.infinity, 40),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: const Text('Resume scoring →'),
                    )
                  else if (widget.user?.isScorerFor(widget.tournament) == true || widget.isOwner)
                    ElevatedButton(
                      onPressed: _starting == f.id ? null : () => _openToss(f),
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 40),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: _starting == f.id
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnAcc))
                        : const Text('🏏 Start match'),
                    ),
                ],
              ]),
            )),
          ]),
          const SizedBox(height: 40),
        ]),
      ),

      // Toss modal
      if (_tossFixture != null)
        _TossModal(
          fixture: _tossFixture!,
          homeRoster: _homeRoster, awayRoster: _awayRoster,
          homeSel: _homeSel, awaySel: _awaySel,
          tossHome: _tossHome, tossBat: _tossBat,
          starting: _starting == _tossFixture!.id,
          onTossHome: (v) => setState(() => _tossHome = v),
          onTossBat:  (v) => setState(() => _tossBat = v),
          onToggle:   _togglePlayer,
          onStart:    _startMatch,
          onCancel:   () => setState(() => _tossFixture = null),
        ),
    ]);
  }
}

class _TossModal extends StatelessWidget {
  final Fixture fixture;
  final List<Player> homeRoster, awayRoster;
  final Set<String> homeSel, awaySel;
  final bool tossHome, tossBat, starting;
  final void Function(bool) onTossHome, onTossBat;
  final void Function(String, bool) onToggle;
  final VoidCallback onStart, onCancel;

  const _TossModal({
    required this.fixture, required this.homeRoster, required this.awayRoster,
    required this.homeSel, required this.awaySel, required this.tossHome,
    required this.tossBat, required this.starting,
    required this.onTossHome, required this.onTossBat,
    required this.onToggle, required this.onStart, required this.onCancel,
  });

  @override Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          decoration: const BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            Text('🏏 ${fixture.homeTeamName} vs ${fixture.awayTeamName}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 16),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [
              _TossRow('Toss won by',
                fixture.homeTeamName, fixture.awayTeamName, tossHome,
                onTossHome),
              const SizedBox(height: 12),
              _TossRow('Elected to', '🏏 Bat', '🎳 Bowl', tossBat, onTossBat),
              const SizedBox(height: 16),
              for (final entry in [
                (true,  fixture.homeTeamName, homeRoster, homeSel),
                (false, fixture.awayTeamName, awayRoster, awaySel),
              ]) if (entry.$3.isNotEmpty) ...[
                Row(children: [
                  Expanded(child: Text(entry.$2, style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.text))),
                  Text('${entry.$4.length}/11', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: entry.$4.length == 11 ? AppColors.accent : AppColors.ball)),
                ]),
                const SizedBox(height: 6),
                ...entry.$3.asMap().entries.map((e) {
                  final p = e.value; final isSel = entry.$4.contains(p.id);
                  return ListTile(
                    dense: true,
                    leading: Container(width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: isSel ? AppColors.accent : AppColors.bgElevated,
                        shape: BoxShape.circle),
                      child: Center(child: Text(isSel ? '✓' : '${e.key + 1}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: isSel ? AppColors.textOnAcc : AppColors.text2)))),
                    title: Text(p.name, style: TextStyle(
                      color: isSel ? AppColors.accent : AppColors.text,
                      fontWeight: isSel ? FontWeight.w600 : FontWeight.w400, fontSize: 14)),
                    onTap: () => onToggle(p.id, entry.$1),
                    tileColor: isSel ? AppColors.accentFaint : null,
                  );
                }),
                const SizedBox(height: 12),
              ],
            ]))),
            Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              ElevatedButton(
                onPressed: starting ? null : onStart,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: starting
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.textOnAcc))
                  : const Text('Start match →'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.text2,
                  side: const BorderSide(color: AppColors.border),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Cancel'),
              ),
            ])),
          ]),
        ),
      ),
    );
  }
}

class _TossRow extends StatelessWidget {
  final String label, opt1, opt2;
  final bool val;
  final void Function(bool) onChanged;
  const _TossRow(this.label, this.opt1, this.opt2, this.val, this.onChanged);

  @override Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(
        color: AppColors.text2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: GestureDetector(
          onTap: () => onChanged(true),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: val ? AppColors.accent.withOpacity(0.15) : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: val ? AppColors.accent : AppColors.border, width: val ? 1.5 : 1)),
            child: Text(opt1, textAlign: TextAlign.center, style: TextStyle(
              color: val ? AppColors.accent : AppColors.text2,
              fontWeight: val ? FontWeight.w700 : FontWeight.w400, fontSize: 14)),
          ),
        )),
        const SizedBox(width: 10),
        Expanded(child: GestureDetector(
          onTap: () => onChanged(false),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: !val ? AppColors.ball.withOpacity(0.15) : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: !val ? AppColors.ball : AppColors.border, width: !val ? 1.5 : 1)),
            child: Text(opt2, textAlign: TextAlign.center, style: TextStyle(
              color: !val ? AppColors.ball : AppColors.text2,
              fontWeight: !val ? FontWeight.w700 : FontWeight.w400, fontSize: 14)),
          ),
        )),
      ]),
    ]);
  }
}

// ── Standings Tab ─────────────────────────────────────────────
class _StandingsTab extends StatelessWidget {
  final List<Map<String, dynamic>> standings;
  const _StandingsTab({required this.standings});

  @override Widget build(BuildContext context) {
    if (standings.isEmpty) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('📊', style: TextStyle(fontSize: 40)),
      SizedBox(height: 12),
      Text('No standings yet', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
      SizedBox(height: 6),
      Text('Standings update as matches complete', style: TextStyle(color: AppColors.text2, fontSize: 13)),
    ]));

    return ListView(padding: const EdgeInsets.all(12), children: [
      Table(
        columnWidths: const {
          0: FixedColumnWidth(30),
          1: FlexColumnWidth(3),
          2: FlexColumnWidth(1), 3: FlexColumnWidth(1),
          4: FlexColumnWidth(1), 5: FlexColumnWidth(1), 6: FlexColumnWidth(1.5),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            children: ['#','Team','P','W','L','Pts','NRR'].map((h) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(h, style: const TextStyle(
                color: AppColors.text2, fontSize: 12, fontWeight: FontWeight.w700)),
            )).toList(),
          ),
          ...standings.asMap().entries.map((e) {
            final i = e.key; final s = e.value;
            return TableRow(
              decoration: BoxDecoration(
                color: i < 2 ? AppColors.accent.withOpacity(0.04) : null,
                border: const Border(bottom: BorderSide(color: AppColors.borderDim))),
              children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Text('${i+1}', style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13,
                    color: i < 2 ? AppColors.accent : AppColors.text2))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Text(s['teamName'] as String? ?? '—', style: const TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.text, fontSize: 13))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Text('${s['played'] ?? 0}', style: const TextStyle(color: AppColors.text2, fontSize: 13))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Text('${s['won'] ?? 0}', style: const TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w600))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Text('${s['lost'] ?? 0}', style: const TextStyle(color: AppColors.wicket, fontSize: 13))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Text('${s['points'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 13))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Text(((s['nrr'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(3),
                    style: const TextStyle(color: AppColors.text2, fontSize: 12))),
              ],
            );
          }),
        ],
      ),
    ]);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../main.dart';
import 'fixture_toss_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<CricMatch>  _live       = [];
  List<CricMatch>  _recent     = [];
  List<Tournament> _tours      = [];
  List<Map<String, dynamic>> _todayFixtures = [];
  bool             _loading    = true;

  @override void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _checkAuthAndLoad();
  }

  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _checkAuthAndLoad() async {
    final auth = ref.read(authProvider);
    if (auth.value == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) context.go('/login'); });
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        MatchApi.live().catchError((_) => <CricMatch>[]),
        MatchApi.list().catchError((_) => <CricMatch>[]),
        TournamentApi.list().catchError((_) => <Tournament>[]),
        TournamentApi.getAllFixtures().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      final now = DateTime.now();
      final allFix = results[3] as List<Map<String, dynamic>>;
      setState(() {
        _live   = (results[0] as List<CricMatch>).where((m) =>
          m.status == 'in_progress' || m.status == 'innings_break').toList();
        _recent = (results[1] as List<CricMatch>).where((m) =>
          m.status == 'completed').take(10).toList();
        _tours  = (results[2] as List<Tournament>).where((t) =>
          t.status != 'completed' && t.status != 'deleted' && t.status != 'archived').toList();
        _todayFixtures = allFix.where((e) {
          final raw = (e['fixture'] as Fixture).scheduledDate;
          if (raw == null) return false;
          try {
            final local = DateTime.parse(raw).toLocal();
            return local.year == now.year && local.month == now.month && local.day == now.day;
          } catch (_) { return false; }
        }).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _endMatch(String matchId) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: const Text('End match?', style: TextStyle(color: AppColors.text)),
      content: const Text('This will mark the match as complete.',
        style: TextStyle(color: AppColors.text2)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: AppColors.text2))),
        TextButton(onPressed: () => Navigator.pop(context, true),
          child: const Text('End', style: TextStyle(color: AppColors.wicket))),
      ],
    ));
    if (ok != true) return;
    await MatchApi.update(matchId, {'status': 'completed'});
    _load();
  }

  @override Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.value;

    if (user == null && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/login'));
      return const LoadingScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            floating: true, snap: true,
            backgroundColor: AppColors.bgCard,
            elevation: 0,
            title: Row(children: [
              const Text('🏏', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('CricScore', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                )),
                if (user != null) Text(
                  'Welcome, ${user.name}',
                  style: const TextStyle(fontSize: 11, color: AppColors.text2),
                ),
              ]),
              const Spacer(),
              if (user?.isAdmin == true)
                IconButton(
                  icon: const Icon(Icons.settings_outlined, color: AppColors.ball),
                  onPressed: () => _showAdminDialog(),
                ),
              IconButton(
                icon: const Icon(Icons.logout_outlined, color: AppColors.text2),
                onPressed: () async {
                  await ref.read(authProvider.notifier).signOut();
                  if (mounted) context.go('/login');
                },
              ),
            ]),
            bottom: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Home'),
                Tab(text: 'Tournaments'),
                Tab(text: 'Results'),
              ],
            ),
          ),
        ],
        body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : TabBarView(controller: _tabs, children: [
              _HomeTab(live: _live, tours: _tours,
                todayFixtures: _todayFixtures,
                onRefresh: _load, onEndMatch: _endMatch, user: user),
              _TournamentsTab(tours: _tours, onRefresh: _load, user: user),
              _ResultsTab(recent: _recent, onRefresh: _load),
            ]),
      ),
      floatingActionButton: null,
    );
  }

  void _showAdminDialog() {
    showModalBottomSheet(context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Admin', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.people_outline, color: AppColors.accent),
            title: const Text('User roles', style: TextStyle(color: AppColors.text)),
            subtitle: const Text('Manage via AWS Cognito Console',
              style: TextStyle(color: AppColors.text2, fontSize: 12)),
            onTap: () => Navigator.pop(context),
          ),
          const Divider(color: AppColors.border),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined, color: AppColors.accent),
            title: const Text('Import players', style: TextStyle(color: AppColors.text)),
            subtitle: const Text('Upload CSV or Excel file',
              style: TextStyle(color: AppColors.text2, fontSize: 12)),
            onTap: () { Navigator.pop(context); context.push('/tournaments'); },
          ),
        ]),
      ),
    );
  }
}

String _formatTime(String dateStr) {
  try {
    final dt = DateTime.parse(dateStr).toLocal();
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  } catch (_) { return dateStr; }
}

bool _isTodayMillis(int millis) {
  if (millis <= 0) return false;
  final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  final now = DateTime.now();
  return dt.year == now.year && dt.month == now.month && dt.day == now.day;
}

// ── Home Tab ──────────────────────────────────────────────────
class _HomeTab extends StatelessWidget {
  final List<CricMatch> live;
  final List<Tournament> tours;
  final List<Map<String, dynamic>> todayFixtures;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String) onEndMatch;
  final AuthUser? user;

  const _HomeTab({
    required this.live, required this.tours,
    required this.todayFixtures,
    required this.onRefresh, required this.onEndMatch, required this.user,
  });

  @override Widget build(BuildContext context) {
    final liveToday = live.where((m) => _isTodayMillis(m.createdAt)).toList();

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      child: ListView(children: [
        // Live matches today
        if (liveToday.isNotEmpty) ...[
          const SectionHeader(title: 'Live matches today'),
          ...liveToday.map((m) => _LiveMatchCard(match: m, onEndMatch: onEndMatch, user: user)),
        ],

        // Today's fixtures
        if (todayFixtures.isNotEmpty) ...[
          const SectionHeader(title: "Today's fixtures"),
          ...todayFixtures.map((entry) {
            final f = entry['fixture'] as Fixture;
            final t = entry['tournament'] as Tournament;
            final hasMatch = f.matchId != null;
            return AppCard(
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${f.homeTeamName} vs ${f.awayTeamName}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(t.name, style: const TextStyle(color: AppColors.text2, fontSize: 12)),
                  if (f.scheduledDate != null) ...[
                    const SizedBox(height: 2),
                    Text('🕐 ${_formatTime(f.scheduledDate!)}',
                      style: const TextStyle(color: AppColors.ball, fontSize: 12)),
                  ],
                ])),
                if (hasMatch)
                  GestureDetector(
                    onTap: () => context.push('/scoring/${f.matchId}').then((_) => onRefresh()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.accent.withOpacity(0.4)),
                      ),
                      child: const Text('Resume', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => showTossSheet(context, f, t, onRefresh),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.four.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.four.withOpacity(0.4)),
                      ),
                      child: const Text('Start', style: TextStyle(color: AppColors.four, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
              ]),
            );
          }),
        ],

        // Active tournaments
        if (tours.isNotEmpty) ...[
          const SectionHeader(title: 'Active tournaments'),
          ...tours.map((t) => AppCard(
            onTap: () => context.push('/tournament/${t.id}').then((_) => onRefresh()),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.name, style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 15)),
                const SizedBox(height: 4),
                Text('${t.teamCount} teams · ${t.format}',
                  style: const TextStyle(color: AppColors.text2, fontSize: 13)),
              ])),
              StatusBadge(
                label: t.isActive ? 'Active' : 'Upcoming',
                color: t.isActive ? AppColors.accent : AppColors.ball,
              ),
            ]),
          )),
        ],

        if (liveToday.isEmpty && todayFixtures.isEmpty && tours.isEmpty)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Column(children: [
              Text('🏟️', style: TextStyle(fontSize: 48)),
              SizedBox(height: 16),
              Text('No matches yet', style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
              SizedBox(height: 8),
              Text('Start a match or create a tournament',
                style: TextStyle(color: AppColors.text2)),
            ]),
          ),

        // Quick actions
        if (user?.isScorer == true) ...[
          const SectionHeader(title: 'Quick actions'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: _QuickAction(
                icon: Icons.sports_cricket,
                label: 'New match',
                color: AppColors.accent,
                onTap: () => context.push('/setup').then((_) => onRefresh()),
              )),
              const SizedBox(width: 10),
              Expanded(child: _QuickAction(
                icon: Icons.emoji_events_outlined,
                label: 'Tournaments',
                color: AppColors.ball,
                onTap: () => context.push('/tournaments').then((_) => onRefresh()),
              )),
            ]),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 80),
      ]),
    );
  }
}

class _LiveMatchCard extends StatelessWidget {
  final CricMatch match;
  final Future<void> Function(String) onEndMatch;
  final AuthUser? user;

  const _LiveMatchCard({required this.match, required this.onEndMatch, required this.user});

  @override Widget build(BuildContext context) {
    final inn = match.innings?.where((i) => i.status == 'in_progress').firstOrNull;
    final batting = match.team1?.id == inn?.battingTeamId ? match.team1 : match.team2;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/scoring/${match.id}'),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const LiveBadge(),
                const Spacer(),
                if (user?.isScorer == true) ...[
                  _ActionBtn('Score', AppColors.accent,
                    () => context.push('/scoring/${match.id}')),
                  const SizedBox(width: 8),
                  _ActionBtn('End', AppColors.wicket, () => onEndMatch(match.id)),
                ],
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text(
                  '${match.team1?.name ?? '—'} vs ${match.team2?.name ?? '—'}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 15),
                )),
                Text(match.format, style: const TextStyle(color: AppColors.ball, fontSize: 13)),
              ]),
              if (inn != null && batting != null) ...[
                const SizedBox(height: 8),
                Text('${batting.name} batting',
                  style: const TextStyle(color: AppColors.text2, fontSize: 12)),
                const SizedBox(height: 4),
                Text(scoreFmt(inn.totalRuns, inn.totalWickets),
                  style: const TextStyle(
                    fontSize: 40, fontWeight: FontWeight.w800,
                    letterSpacing: -1.5, color: AppColors.text,
                  )),
                Text('${ballsToOvers(inn.totalBalls)} ov · CRR ${inn.currentRunRate.toStringAsFixed(1)}',
                  style: const TextStyle(color: AppColors.text2, fontSize: 13)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(this.label, this.color, this.onTap);

  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label, style: TextStyle(
          color: color, fontSize: 13, fontWeight: FontWeight.w700,
        )),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon, required this.label,
    required this.color, required this.onTap,
  });

  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(
            color: color, fontWeight: FontWeight.w700, fontSize: 13,
          )),
        ]),
      ),
    );
  }
}

// ── Tournaments Tab ───────────────────────────────────────────
class _TournamentsTab extends StatelessWidget {
  final List<Tournament> tours;
  final Future<void> Function() onRefresh;
  final AuthUser? user;

  const _TournamentsTab({required this.tours, required this.onRefresh, required this.user});

  @override Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      child: ListView(children: [
        if (user?.isAdmin == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ElevatedButton.icon(
              onPressed: () => context.push('/tournaments'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Manage tournaments'),
            ),
          ),
        ...tours.map((t) => AppCard(
          onTap: () => context.push('/tournament/${t.id}').then((_) => onRefresh()),
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
          ]),
        )),
        if (tours.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Column(children: [
              Text('🏆', style: TextStyle(fontSize: 40)),
              SizedBox(height: 12),
              Text('No tournaments yet', style: TextStyle(
                color: AppColors.text, fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text('Create one from the Tournaments screen',
                style: TextStyle(color: AppColors.text2, fontSize: 13)),
            ]),
          ),
        const SizedBox(height: 80),
      ]),
    );
  }
}

// ── Results Tab ────────────────────────────────────────────────
class _ResultsTab extends StatelessWidget {
  final List<CricMatch> recent;
  final Future<void> Function() onRefresh;
  const _ResultsTab({required this.recent, required this.onRefresh});

  @override Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      child: ListView(children: [
        const SectionHeader(title: 'Recent results'),
        ...recent.map((m) => AppCard(
          onTap: () => context.push('/scorecard/${m.id}'),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${m.team1?.name ?? '—'} vs ${m.team2?.name ?? '—'}',
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
              if (m.result != null) ...[
                const SizedBox(height: 4),
                Text(m.result!['description'] as String? ?? '',
                  style: const TextStyle(color: AppColors.accent, fontSize: 13)),
              ],
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(m.format, style: const TextStyle(color: AppColors.ball, fontSize: 13)),
            ]),
          ]),
        )),
        if (recent.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Column(children: [
              Text('📋', style: TextStyle(fontSize: 40)),
              SizedBox(height: 12),
              Text('No recent results', style: TextStyle(
                color: AppColors.text, fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text('Completed matches will appear here',
                style: TextStyle(color: AppColors.text2, fontSize: 13)),
            ]),
          ),
        const SizedBox(height: 80),
      ]),
    );
  }
}

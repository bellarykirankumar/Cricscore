import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/geo_service.dart';
import '../../models/models.dart';
import '../../main.dart';
import '../../widgets/country_picker_sheet.dart';
import '../support/support_chat_screen.dart';
import '../match/camera_buffer_screen.dart';
import '../quick_score/quick_score_screen.dart';
import '../feedback/feedback_screen.dart';
import 'fixture_toss_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int              _selectedIndex = 0;
  String?          _userCountry;
  Set<String>      _ownedIds   = {};
  List<CricMatch>  _live       = [];
  List<CricMatch>  _recent     = [];
  List<Tournament> _tours      = [];
  List<Map<String, dynamic>> _todayFixtures = [];
  List<Map<String, dynamic>> _allFixtures   = [];
  bool             _loading    = true;

  @override void initState() {
    super.initState();
    _checkAuthAndLoad();
  }

  Future<void> _checkAuthAndLoad() async {
    final auth = ref.read(authProvider);
    if (auth.value == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) context.go('/login'); });
      return;
    }
    final detected = await GeoService.detectCountry();
    if (detected != null && countryName(detected) != detected) {
      await AuthService.instance.setCountry(detected);
      if (mounted) setState(() => _userCountry = detected);
    } else {
      _userCountry = await AuthService.instance.getCountry();
      if (_userCountry == null && mounted) {
        String? picked;
        while (picked == null) {
          picked = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            isDismissible: false,
            builder: (_) => const CountryPickerSheet(),
          );
        }
        await AuthService.instance.setCountry(picked);
        if (mounted) setState(() => _userCountry = picked);
      }
    }
    if (mounted) await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final phase1 = await Future.wait([
        MatchApi.live().catchError((_) => <CricMatch>[]),
        MatchApi.list().catchError((_) => <CricMatch>[]),
        TournamentApi.list().catchError((_) => <Tournament>[]),
        AuthService.instance.getOwnedIds(),
      ]);
      if (!mounted) return;

      final storedOwnedIds = phase1[3] as Set<String>;
      final user           = ref.read(authProvider).value;

      final backendConfirmed = <String>{};
      if (user?.sub != null) {
        for (final t in phase1[2] as List<Tournament>) {
          if (t.createdBy == user!.sub) backendConfirmed.add(t.id);
        }
        for (final m in phase1[0] as List<CricMatch>) {
          if (m.createdBy == user!.sub) backendConfirmed.add(m.id);
        }
        for (final m in phase1[1] as List<CricMatch>) {
          if (m.createdBy == user!.sub) backendConfirmed.add(m.id);
        }
        if (backendConfirmed.isNotEmpty) {
          AuthService.instance.mergeOwnedIds(backendConfirmed);
        }
      }
      final ownedIds = {...storedOwnedIds, ...backendConfirmed};

      final tours = (phase1[2] as List<Tournament>).where((t) =>
        t.status != 'completed' && t.status != 'deleted' && t.status != 'archived')
        .where((t) {
          if (user?.isAdmin == true) return true;
          if (user?.isScorerFor(t) == true) return true;
          if (_userCountry == null) return true;
          if (t.country == _userCountry) return true;
          if (t.country == null &&
              (ownedIds.contains(t.id) || user?.canManage(t.createdBy) == true)) return true;
          return false;
        })
        .toList();
      final tourIds = tours.map((t) => t.id).toSet();

      final allFix = await TournamentApi
        .getAllFixtures(allowedTourIds: tourIds.isEmpty ? null : tourIds)
        .catchError((_) => <Map<String, dynamic>>[]);
      if (!mounted) return;

      final now = DateTime.now();
      setState(() {
        bool matchVisible(CricMatch m) {
          if (user?.isAdmin == true) return true;
          if (_userCountry == null) return true;
          if (m.tournamentId != null) return tourIds.contains(m.tournamentId);
          if (m.country == _userCountry) return true;
          if (m.country == null &&
              (ownedIds.contains(m.id) || user?.canManage(m.createdBy) == true)) return true;
          return false;
        }
        _ownedIds = ownedIds;
        _tours    = tours;
        _live     = (phase1[0] as List<CricMatch>)
          .where((m) => m.status == 'in_progress' || m.status == 'innings_break')
          .where(matchVisible)
          .toList();
        _recent   = (phase1[1] as List<CricMatch>)
          .where((m) => m.status == 'completed')
          .where(matchVisible)
          .take(10)
          .toList();
        _todayFixtures = allFix.where((e) {
          final raw = (e['fixture'] as Fixture).scheduledDate;
          if (raw == null) return false;
          try {
            final local = DateTime.parse(raw).toLocal();
            return local.year == now.year && local.month == now.month && local.day == now.day;
          } catch (_) { return false; }
        }).toList();
        _allFixtures = allFix;
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
    ref.listen<AsyncValue<AuthUser?>>(authProvider, (_, next) {
      if (next.value == null && mounted) context.go('/login');
    });

    final auth = ref.watch(authProvider);
    final user = auth.value;

    if (user == null && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/login'));
      return const LoadingScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      drawer: _AppDrawer(user: user, userCountry: _userCountry,
          onRefresh: _load,
          onOpenCamera: () => setState(() => _selectedIndex = 3)),
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        leading: Builder(builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu, color: AppColors.text2),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        )),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('🏏', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('CricScore', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.accent)),
            if (user != null) Text('Welcome, ${user.name}',
              style: const TextStyle(fontSize: 11, color: AppColors.text2)),
          ]),
        ]),
        actions: [
          if (user?.isAdmin == true)
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: AppColors.ball),
              onPressed: () => _showAdminDialog(),
            ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
        : IndexedStack(
            index: _selectedIndex,
            children: [
              _HomeTab(live: _live, recent: _recent, tours: _tours,
                todayFixtures: _todayFixtures, allFixtures: _allFixtures,
                onRefresh: _load, onEndMatch: _endMatch, user: user,
                ownedIds: _ownedIds),
              _TournamentsTab(tours: _tours, onRefresh: _load, user: user),
              _TeamsTab(tours: _tours, onRefresh: _load),
              // Hidden camera tab — kept alive in IndexedStack so buffering
              // continues while user scores. Accessible from drawer.
              CameraBufferScreen(onBack: () => setState(() => _selectedIndex = 0)),
            ],
          ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) {
          if (i == 3) {
            context.push('/setup').then((_) => _load());
          } else {
            setState(() => _selectedIndex = i);
          }
        },
        backgroundColor: AppColors.bgCard,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.text2,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.emoji_events_outlined),
            activeIcon: Icon(Icons.emoji_events),
            label: 'Leagues',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group_outlined),
            activeIcon: Icon(Icons.group),
            label: 'Teams',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            activeIcon: Icon(Icons.add_circle),
            label: 'New Match',
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Delete account?', style: TextStyle(color: AppColors.text)),
        content: const Text(
          'This permanently deletes your account and all your data. This action cannot be undone.',
          style: TextStyle(color: AppColors.text2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.text2))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteAccount();
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.wicket))),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    setState(() => _loading = true);
    try {
      await ref.read(authProvider.notifier).deleteAccount();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete account: $e')));
      }
    }
  }

  void _showAdminDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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
      ),
    );
  }
}

// ── Welcome Card (shown to new users with no matches) ─────────
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override Widget build(BuildContext context) {
    const features = [
      ('🏏', 'Ball-by-ball scoring', 'Live AI commentary on every delivery'),
      ('🏆', 'Leagues', 'Create leagues, knockouts & round-robins'),
      ('👥', 'Team management', 'Rosters, player stats & country registry'),
      ('📋', 'Scoring Sheet', 'Quick tally without any setup — open from the menu'),
      ('🤖', 'AI Support', 'Ask anything about the app — instant answers'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🎉 Welcome to CricScore!', style: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
        const SizedBox(height: 6),
        const Text('Here\'s what you can do:', style: TextStyle(
          color: AppColors.text2, fontSize: 13)),
        const SizedBox(height: 16),
        ...features.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.$1, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.$2, style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.text)),
                Text(f.$3, style: const TextStyle(
                  fontSize: 12, color: AppColors.text2)),
              ])),
          ]),
        )),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.accentFaint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withOpacity(0.2)),
          ),
          child: const Row(children: [
            Icon(Icons.arrow_downward, color: AppColors.accent, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text(
              'Tap New Match below to start scoring, or open the ☰ menu to explore.',
              style: TextStyle(color: AppColors.accent, fontSize: 13,
                fontWeight: FontWeight.w600))),
          ]),
        ),
      ]),
    );
  }
}

// ── App Drawer ────────────────────────────────────────────────
class _AppDrawer extends ConsumerWidget {
  final AuthUser? user;
  final String? userCountry;
  final VoidCallback onRefresh;
  final VoidCallback onOpenCamera;

  const _AppDrawer({this.user, this.userCountry, required this.onRefresh, required this.onOpenCamera});

  @override Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      backgroundColor: AppColors.bg,
      child: SafeArea(
        child: Column(children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            color: AppColors.bgCard,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.account_circle_outlined,
                size: 48, color: AppColors.accent),
              const SizedBox(height: 10),
              Text(user?.name ?? '',
                style: const TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w800, color: AppColors.text)),
              Text(user?.email ?? '',
                style: const TextStyle(fontSize: 12, color: AppColors.text2)),
              if (userCountry != null) ...[
                const SizedBox(height: 4),
                Text('${countryFlag(userCountry!)} ${countryName(userCountry!)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.text2)),
              ],
            ]),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(child: ListView(padding: EdgeInsets.zero, children: [
            _tile(context, Icons.videocam_outlined, 'Camera Mode',
              'Use this device as a clip camera', () {
                Navigator.pop(context);
                onOpenCamera();
              }),
            _tile(context, Icons.sports_cricket_outlined, 'Scoring Sheet',
              'Quick match tally — no setup needed', () {
                Navigator.pop(context);
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const QuickScoreScreen()));
              }),
            _tile(context, Icons.support_agent_outlined, 'AI Support',
              'Chat with our AI assistant', () {
                Navigator.pop(context);
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SupportChatScreen()));
              }),
            _tile(context, Icons.lightbulb_outline, 'Feedback & Suggestions',
              'Share ideas or report issues', () {
                Navigator.pop(context);
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FeedbackScreen()));
              }),
            const Divider(color: AppColors.border),
            _tile(context, Icons.logout_outlined, 'Sign out', '', () async {
              Navigator.pop(context);
              await ref.read(authProvider.notifier).signOut();
              if (context.mounted) context.go('/login');
            }, color: AppColors.text2),
            _tile(context, Icons.delete_outline, 'Delete account', '', () {
              Navigator.pop(context);
              // Find the HomeScreen state to call _confirmDeleteAccount
              final homeState = context.findAncestorStateOfType<_HomeScreenState>();
              homeState?._confirmDeleteAccount();
            }, color: AppColors.wicket),
          ])),
        ]),
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title,
      String subtitle, VoidCallback onTap, {Color? color}) {
    final c = color ?? AppColors.accent;
    return ListTile(
      leading: Icon(icon, color: c),
      title: Text(title, style: TextStyle(
        color: AppColors.text, fontWeight: FontWeight.w600)),
      subtitle: subtitle.isNotEmpty
          ? Text(subtitle, style: const TextStyle(
              color: AppColors.text2, fontSize: 12))
          : null,
      onTap: onTap,
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

// ── Strip Card ────────────────────────────────────────────────
// Cards with a coloured left-edge status strip (inspired by CricClubs).
class _StripCard extends StatelessWidget {
  final Widget child;
  final Color stripColor;
  final String stripLabel;
  final VoidCallback? onTap;
  final Color? borderColor;

  const _StripCard({
    required this.child,
    required this.stripColor,
    required this.stripLabel,
    this.onTap,
    this.borderColor,
  });

  @override Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.cardGradTop, AppColors.cardGradBot],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Left status strip
              Container(
                width: 22,
                color: stripColor,
                child: Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      stripLabel,
                      style: const TextStyle(
                        fontSize: 8, fontWeight: FontWeight.w900,
                        color: Colors.white, letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: child,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Home Tab ──────────────────────────────────────────────────
class _HomeTab extends StatelessWidget {
  final List<CricMatch> live, recent;
  final List<Tournament> tours;
  final List<Map<String, dynamic>> todayFixtures;
  final List<Map<String, dynamic>> allFixtures;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String) onEndMatch;
  final AuthUser? user;
  final Set<String> ownedIds;

  const _HomeTab({
    required this.live, required this.recent, required this.tours,
    required this.todayFixtures, required this.allFixtures,
    required this.onRefresh, required this.onEndMatch, required this.user,
    required this.ownedIds,
  });

  @override Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      child: ListView(children: [
        // Live matches
        if (live.isNotEmpty) ...[
          const SectionHeader(title: 'Live now'),
          ...live.map((m) => _LiveMatchCard(
            match: m, onEndMatch: onEndMatch, user: user, ownedIds: ownedIds)),
        ],

        // Today's fixtures
        if (todayFixtures.isNotEmpty) ...[
          const SectionHeader(title: "Today's fixtures"),
          ...todayFixtures.map((entry) {
            final f = entry['fixture'] as Fixture;
            final t = entry['tournament'] as Tournament;
            final hasMatch = f.matchId != null;
            return _StripCard(
              stripColor: AppColors.four,
              stripLabel: 'TODAY',
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
                _ActionBtn(
                  label: hasMatch ? 'Resume' : 'Start',
                  color: hasMatch ? AppColors.accent : AppColors.four,
                  onTap: hasMatch
                    ? () => context.push('/scoring/${f.matchId}').then((_) => onRefresh())
                    : () => showTossSheet(context, f, t, onRefresh),
                ),
              ]),
            );
          }),
        ],

        // Active tournaments
        if (tours.isNotEmpty) ...[
          const SectionHeader(title: 'Leagues'),
          ...tours.map((t) => _StripCard(
            stripColor: t.isActive ? AppColors.accent : AppColors.ball,
            stripLabel: t.isActive ? 'ACTIVE' : 'SOON',
            onTap: () => context.push('/tournament/${t.id}').then((_) => onRefresh()),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.name, style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 15)),
                const SizedBox(height: 4),
                Text('${t.teamCount} teams · ${t.format}',
                  style: const TextStyle(color: AppColors.text2, fontSize: 13)),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.text3, size: 20),
            ]),
          )),
        ],

        // Recent results
        if (recent.isNotEmpty) ...[
          const SectionHeader(title: 'Recent results'),
          ...recent.map((m) => _StripCard(
            stripColor: AppColors.text3,
            stripLabel: 'DONE',
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
                const SizedBox(height: 4),
                const Icon(Icons.chevron_right, color: AppColors.text3, size: 20),
              ]),
            ]),
          )),
        ],

        if (live.isEmpty && tours.isEmpty && recent.isEmpty)
          const _WelcomeCard(),
        const SizedBox(height: 100),
      ]),
    );
  }
}

// ── Live Match Card ───────────────────────────────────────────
class _LiveMatchCard extends StatelessWidget {
  final CricMatch match;
  final Future<void> Function(String) onEndMatch;
  final AuthUser? user;
  final Set<String> ownedIds;

  const _LiveMatchCard({
    required this.match, required this.onEndMatch,
    required this.user, required this.ownedIds,
  });

  @override Widget build(BuildContext context) {
    final inn = match.innings?.where((i) => i.status == 'in_progress').firstOrNull;
    final batting = match.team1?.id == inn?.battingTeamId ? match.team1 : match.team2;

    return _StripCard(
      stripColor: AppColors.wicket,
      stripLabel: 'LIVE',
      borderColor: AppColors.accent.withOpacity(0.35),
      onTap: () => context.push('/scoring/${match.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const LiveBadge(),
          const Spacer(),
          if (user?.isScorer == true)
            _ActionBtn(label: 'Score', color: AppColors.accent,
              onTap: () => context.push('/scoring/${match.id}')),
          if (user?.canManage(match.createdBy) == true || ownedIds.contains(match.id)) ...[
            const SizedBox(width: 8),
            _ActionBtn(label: 'End', color: AppColors.wicket,
              onTap: () => onEndMatch(match.id)),
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
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.color, required this.onTap});

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
        if (user != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ElevatedButton.icon(
              onPressed: () => context.push('/tournaments'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create League'),
            ),
          ),
        const SizedBox(height: 8),
        ...tours.map((t) => _StripCard(
          stripColor: t.isActive ? AppColors.accent : t.isCompleted ? AppColors.text3 : AppColors.ball,
          stripLabel: t.isActive ? 'ACTIVE' : t.isCompleted ? 'DONE' : 'SOON',
          onTap: () => context.push('/tournament/${t.id}').then((_) => onRefresh()),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 15)),
              const SizedBox(height: 4),
              Text('${t.format} · ${t.teamCount}/${t.maxTeams} teams',
                style: const TextStyle(color: AppColors.text2, fontSize: 13)),
            ])),
            const Icon(Icons.chevron_right, color: AppColors.text3, size: 20),
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
              Text('Create one from the Leagues screen',
                style: TextStyle(color: AppColors.text2, fontSize: 13)),
            ]),
          ),
        const SizedBox(height: 80),
      ]),
    );
  }
}

// ── Teams Tab ─────────────────────────────────────────────────
class _TeamsTab extends StatelessWidget {
  final List<Tournament> tours;
  final Future<void> Function() onRefresh;
  const _TeamsTab({required this.tours, required this.onRefresh});

  @override Widget build(BuildContext context) {
    return ListView(children: [
      const SectionHeader(title: 'Teams by tournament'),
      ...tours.map((t) => _StripCard(
        stripColor: AppColors.accent,
        stripLabel: 'TEAM',
        onTap: () => context.push('/tournament/${t.id}').then((_) => onRefresh()),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.name, style: const TextStyle(
              fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 15)),
            const SizedBox(height: 4),
            Text('${t.teamCount} teams registered',
              style: const TextStyle(color: AppColors.text2, fontSize: 13)),
          ])),
          const Icon(Icons.chevron_right, color: AppColors.text3, size: 20),
        ]),
      )),
      if (tours.isEmpty)
        const Padding(
          padding: EdgeInsets.all(40),
          child: Column(children: [
            Text('👥', style: TextStyle(fontSize: 40)),
            SizedBox(height: 12),
            Text('No teams yet', style: TextStyle(
              color: AppColors.text, fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text('Create a tournament first to add teams',
              style: TextStyle(color: AppColors.text2, fontSize: 13)),
          ]),
        ),
      const SizedBox(height: 80),
    ]);
  }
}

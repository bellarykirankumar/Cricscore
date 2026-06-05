import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../main.dart';
import '../../widgets/country_picker_sheet.dart';

// ── Player Profile Screen ─────────────────────────────────────
// Shows career stats, player details, and optional claim button.
class PlayerProfileScreen extends ConsumerStatefulWidget {
  final Player player;
  final String teamId;

  const PlayerProfileScreen({
    super.key,
    required this.player,
    required this.teamId,
  });

  @override ConsumerState<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends ConsumerState<PlayerProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map<String, dynamic> _stats = {};
  bool _loadingStats = true;
  bool _claiming = false;

  @override void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadStats();
  }

  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _loadStats() async {
    final stats = await PlayerApi.getStats(widget.player.id);
    if (mounted) setState(() { _stats = stats; _loadingStats = false; });
  }

  Future<void> _claim() async {
    final user = ref.read(authProvider).value;
    if (user == null) return;
    setState(() => _claiming = true);
    try {
      await PlayerApi.claim(widget.teamId, widget.player.id, user.sub);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile claimed! This is now your player record.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override Widget build(BuildContext context) {
    final p = widget.player;
    final user = ref.watch(authProvider).value;
    final canClaim = user != null && !p.isClaimed;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(p.name),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.text2,
          tabs: const [Tab(text: 'Profile'), Tab(text: 'Stats')],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _buildProfile(p, user, canClaim),
        _buildStats(p),
      ]),
    );
  }

  // ── Profile Tab ───────────────────────────────────────────────
  Widget _buildProfile(Player p, dynamic user, bool canClaim) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Avatar + name header
      Center(child: Column(children: [
        const SizedBox(height: 8),
        // Avatar (initials for now; photoUrl support ready when S3 is wired)
        Container(
          width: 88, height: 88,
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.accent.withOpacity(0.4), width: 2),
          ),
          child: Center(child: Text(
            p.shortName.isNotEmpty
                ? p.shortName.substring(0, p.shortName.length.clamp(0, 2))
                : p.name.substring(0, 1),
            style: const TextStyle(
              color: AppColors.accent, fontSize: 28, fontWeight: FontWeight.w800),
          )),
        ),
        const SizedBox(height: 12),
        Text(p.name, style: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
        const SizedBox(height: 6),
        // playerCode + country
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (p.playerCode != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accentFaint,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.accent.withOpacity(0.4))),
              child: Text(p.playerCode!,
                style: const TextStyle(
                  color: AppColors.accent, fontSize: 12,
                  fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ),
            const SizedBox(width: 8),
          ],
          if (p.country != null)
            Text('${countryFlag(p.country!)} ${countryName(p.country!)}',
              style: const TextStyle(color: AppColors.text2, fontSize: 13)),
        ]),
        if (p.isClaimed) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0x157C3AED),
              borderRadius: BorderRadius.circular(6)),
            child: const Text('✓ Claimed profile',
              style: TextStyle(color: Color(0xFF7C3AED), fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ])),

      const SizedBox(height: 24),

      // Bio (if set)
      if (p.bio != null && p.bio!.isNotEmpty) ...[
        Text(p.bio!, textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.text2, fontSize: 14, height: 1.5)),
        const SizedBox(height: 20),
      ],

      // Details grid
      _DetailSection(title: 'Player Details', rows: [
        ('Role',            p.role.replaceAll('_', ' ').capitalize()),
        ('Batting',         p.battingStyle == 'right_hand' ? 'Right hand' : 'Left hand'),
        if (p.bowlingStyle != null)
          ('Bowling',       p.bowlingStyle!.replaceAll('_', ' ').capitalize()),
        if (p.jerseyNumber != null)
          ('Jersey',        '#${p.jerseyNumber}'),
      ]),

      const SizedBox(height: 24),

      // Claim button
      if (canClaim)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.accent.withOpacity(0.3))),
          child: Column(children: [
            const Text('Is this you?',
              style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 6),
            const Text(
              'Claim this profile to link your account. Stats will appear under your name across all tournaments.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text2, fontSize: 13, height: 1.4)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _claiming ? null : _claim,
                child: _claiming
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnAcc))
                    : const Text('This is me — claim profile'),
              ),
            ),
          ]),
        ),

      const SizedBox(height: 32),
    ]);
  }

  // ── Stats Tab ─────────────────────────────────────────────────
  Widget _buildStats(Player p) {
    if (_loadingStats) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    if (_stats.isEmpty || (_stats['matches'] ?? 0) == 0) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('📊', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        const Text('No stats yet', style: TextStyle(
          color: AppColors.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('${p.name.split(' ').first}\'s career stats will appear here after matches are scored',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.text2, fontSize: 13)),
      ]));
    }

    final s = _stats;
    final matches    = (s['matches']      as num?)?.toInt() ?? 0;
    final innings    = (s['innings']      as num?)?.toInt() ?? 0;
    final runs       = (s['runsScored']   as num?)?.toInt() ?? 0;
    final balls      = (s['ballsFaced']   as num?)?.toInt() ?? 0;
    final fours      = (s['fours']        as num?)?.toInt() ?? 0;
    final sixes      = (s['sixes']        as num?)?.toInt() ?? 0;
    final fifties    = (s['fifties']      as num?)?.toInt() ?? 0;
    final hundreds   = (s['hundreds']     as num?)?.toInt() ?? 0;
    final wkts       = (s['wicketsTaken'] as num?)?.toInt() ?? 0;
    final ballsBwld  = (s['ballsBowled']  as num?)?.toInt() ?? 0;
    final runsCon    = (s['runsConceded'] as num?)?.toInt() ?? 0;

    final avg  = innings > 0 ? (runs / innings).toStringAsFixed(1) : '—';
    final sr   = balls  > 0 ? ((runs / balls) * 100).toStringAsFixed(1) : '—';
    final overs = '${ballsBwld ~/ 6}.${ballsBwld % 6}';
    final econ = ballsBwld > 0 ? ((runsCon / ballsBwld) * 6).toStringAsFixed(2) : '—';
    final bAvg = wkts > 0 ? (runsCon / wkts).toStringAsFixed(1) : '—';

    return ListView(padding: const EdgeInsets.all(16), children: [
      // Career summary strip
      Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border)),
        child: Row(children: [
          _StatChip('Matches', '$matches'),
          _StatChip('Innings', '$innings'),
          _StatChip('Wickets', '$wkts'),
        ]),
      ),
      const SizedBox(height: 16),

      // Batting
      _DetailSection(title: 'Batting', rows: [
        ('Runs',         '$runs'),
        ('Average',      avg),
        ('Strike Rate',  sr),
        ('Balls Faced',  '$balls'),
        ('50s / 100s',   '$fifties / $hundreds'),
        ('4s / 6s',      '$fours / $sixes'),
      ]),
      const SizedBox(height: 16),

      // Bowling (only show if they bowled)
      if (ballsBwld > 0)
        _DetailSection(title: 'Bowling', rows: [
          ('Wickets',    '$wkts'),
          ('Overs',      overs),
          ('Runs',       '$runsCon'),
          ('Economy',    econ),
          ('Average',    bAvg),
        ]),

      const SizedBox(height: 32),
    ]);
  }
}

// ── Detail Section ────────────────────────────────────────────
class _DetailSection extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _DetailSection({required this.title, required this.rows});

  @override Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(title.toUpperCase(),
            style: const TextStyle(
              color: AppColors.text2, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        ),
        const Divider(height: 1, color: AppColors.border),
        ...rows.map((r) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(children: [
            Text(r.$1, style: const TextStyle(color: AppColors.text2, fontSize: 14)),
            const Spacer(),
            Text(r.$2, style: const TextStyle(
              color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
        )),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  const _StatChip(this.label, this.value);
  @override Widget build(BuildContext context) {
    return Expanded(child: Column(children: [
      Text(value, style: const TextStyle(
        color: AppColors.accent, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 12)),
    ]));
  }
}

extension on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

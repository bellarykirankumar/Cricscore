import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../widgets/clip_player_widget.dart';
import 'commentary_screen.dart';
import 'highlights_gallery_screen.dart';

class ScorecardScreen extends StatefulWidget {
  final String matchId;
  const ScorecardScreen({super.key, required this.matchId});
  @override State<ScorecardScreen> createState() => _ScorecardScreenState();
}

class _ScorecardScreenState extends State<ScorecardScreen>
    with SingleTickerProviderStateMixin {
  CricMatch? _match;
  bool       _loading = true;
  late TabController _tabs;
  int _inningsIdx = 0;

  @override void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _load();
  }

  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    final m = await MatchApi.get(widget.matchId);
    if (mounted) setState(() { _match = m; _loading = false; });
  }

  String _getName(String? id) {
    if (id == null) return '—';
    final all = [...(_match?.team1?.players ?? []), ...(_match?.team2?.players ?? [])];
    return all.firstWhere((p) => p.id == id,
      orElse: () => Player(id: id, teamId: '', name: id.replaceAll(RegExp(r'_\d+$'), '').replaceAll('_', ' '), shortName: '')).name;
  }

  String _dismissalStr(Map<String, dynamic>? d) {
    if (d == null) return 'not out';
    final bow = _getName(d['bowlerId'] as String?);
    final fie = _getName(d['fielderId'] as String?);
    switch (d['type']) {
      case 'bowled':       return 'b $bow';
      case 'caught':       return fie.isNotEmpty ? 'c $fie b $bow' : 'c & b $bow';
      case 'lbw':          return 'lbw b $bow';
      case 'run_out':      return fie.isNotEmpty ? 'run out ($fie)' : 'run out';
      case 'stumped':      return 'st $fie b $bow';
      case 'retired_hurt': return 'retired hurt';
      default:             return (d['type'] as String?)?.replaceAll('_', ' ') ?? 'out';
    }
  }

  @override Widget build(BuildContext context) {
    if (_loading) return const LoadingScreen();
    if (_match == null) return ErrorScreen(message: 'Match not found', onRetry: _load);

    final m = _match!;
    final inn = m.innings?[_inningsIdx];
    final battingTeam  = [m.team1, m.team2].firstWhere((t) => t?.id == inn?.battingTeamId, orElse: () => null);
    final bowlingTeam  = [m.team1, m.team2].firstWhere((t) => t?.id == inn?.bowlingTeamId, orElse: () => null);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => m.status == 'in_progress'
            ? context.go('/scoring/${m.id}') : context.go('/'),
        ),
        title: Text('${m.team1?.shortName} vs ${m.team2?.shortName}'),
        actions: [
          // Highlights gallery — shown once any clips exist (loaded lazily inside screen)
          IconButton(
            icon: const Icon(Icons.video_collection_outlined, color: AppColors.accent),
            tooltip: 'Highlights',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HighlightsGalleryScreen(
                matchId: widget.matchId,
                matchTitle: '${m.team1?.shortName} vs ${m.team2?.shortName}',
              ),
            )),
          ),
          if (m.status == 'in_progress')
            TextButton(
              onPressed: () => context.go('/scoring/${m.id}'),
              child: const Text('Score', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Batting'), Tab(text: 'Bowling'),
            Tab(text: 'FoW'), Tab(text: 'Phases'),
            Tab(text: 'Commentary'),
          ],
        ),
      ),
      body: Column(children: [
        // Result banner
        if (m.result != null)
          Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            color: AppColors.accentFaint,
            child: Text(m.result!['description'] as String? ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 15)),
          ),

        // Innings switcher
        if ((m.innings?.length ?? 0) > 1)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: m.innings!.asMap().entries.map((e) {
              final i = e.key; final inn = e.value;
              final team = [m.team1, m.team2].firstWhere((t) => t?.id == inn.battingTeamId, orElse: () => null);
              return Expanded(child: GestureDetector(
                onTap: () => setState(() => _inningsIdx = i),
                child: Container(
                  margin: EdgeInsets.only(right: i == 0 ? 6 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _inningsIdx == i ? AppColors.accent.withOpacity(0.1) : AppColors.bgCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _inningsIdx == i ? AppColors.accent : AppColors.border),
                  ),
                  child: Column(children: [
                    Text(team?.shortName ?? 'Inn ${i+1}', style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _inningsIdx == i ? AppColors.accent : AppColors.text2,
                    )),
                    Text(scoreFmt(inn.totalRuns, inn.totalWickets),
                      style: TextStyle(fontSize: 12,
                        color: _inningsIdx == i ? AppColors.accent : AppColors.text2)),
                  ]),
                ),
              ));
            }).toList()),
          ),

        // Score summary
        if (inn != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            color: AppColors.bgCard,
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(battingTeam?.name ?? '—',
                  style: const TextStyle(color: AppColors.text2, fontSize: 12)),
                Text(scoreFmt(inn.totalRuns, inn.totalWickets), style: const TextStyle(
                  fontSize: 36, fontWeight: FontWeight.w800,
                  letterSpacing: -1.5, color: AppColors.text)),
                Text('${ballsToOvers(inn.totalBalls)} ov · ${inn.extras?['total'] ?? 0} extras',
                  style: const TextStyle(color: AppColors.text2, fontSize: 13)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (inn.target != null) ...[
                  const Text('Target', style: TextStyle(color: AppColors.text2, fontSize: 12)),
                  Text('${inn.target}', style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ball)),
                ],
                Text(inn.status == 'in_progress' ? '● Live' : 'Completed',
                  style: TextStyle(
                    color: inn.status == 'in_progress' ? AppColors.wicket : AppColors.accent,
                    fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ]),
          ),

        // Tabs
        Expanded(child: TabBarView(controller: _tabs, children: [
          _BattingTab(inn: inn, getName: _getName, dismissalStr: _dismissalStr),
          _BowlingTab(inn: inn, getName: _getName, bowlingTeam: bowlingTeam),
          _FoWTab(inn: inn, getName: _getName, dismissalStr: _dismissalStr),
          _PhasesTab(inn: inn),
          _CommentaryTab(matchId: widget.matchId, inningsNumber: _inningsIdx + 1),
        ])),
      ]),
    );
  }
}

class _BattingTab extends StatelessWidget {
  final Innings? inn;
  final String Function(String?) getName;
  final String Function(Map<String, dynamic>?) dismissalStr;

  const _BattingTab({required this.inn, required this.getName, required this.dismissalStr});

  @override Widget build(BuildContext context) {
    if (inn == null) return const SizedBox();
    return ListView(padding: const EdgeInsets.all(12), children: [
      Table(
        columnWidths: const {
          0: FlexColumnWidth(3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1),
          3: FlexColumnWidth(0.8), 4: FlexColumnWidth(0.8), 5: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            children: ['Batter','R','B','4s','6s','SR'].map((h) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Text(h, style: const TextStyle(
                color: AppColors.text2, fontSize: 12, fontWeight: FontWeight.w700)),
            )).toList(),
          ),
          ...inn!.battingOrder.where((id) => inn!.batsmanStats.containsKey(id)).map((id) {
            final b = inn!.batsmanStats[id]!;
            return TableRow(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.borderDim))),
              children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(getName(id), style: const TextStyle(
                      color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(b.isOut ? dismissalStr(b.dismissal) : b.didNotBat ? 'did not bat' : 'not out',
                      style: const TextStyle(color: AppColors.text2, fontSize: 11)),
                  ])),
                Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Text('${b.runsScored}', style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15,
                    color: b.runsScored >= 100 ? AppColors.ball
                      : b.runsScored >= 50 ? AppColors.accent : AppColors.text))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Text('${b.ballsFaced}', style: const TextStyle(color: AppColors.text2, fontSize: 13))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Text('${b.fours}', style: const TextStyle(color: AppColors.four, fontSize: 13))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Text('${b.sixes}', style: const TextStyle(color: AppColors.six, fontSize: 13))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Text(b.strikeRate.toStringAsFixed(0), style: const TextStyle(color: AppColors.text2, fontSize: 13))),
              ],
            );
          }),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('Extras: ${inn!.extras?['total'] ?? 0} '
          '(nb ${inn!.extras?['noBalls'] ?? 0}, '
          'wd ${inn!.extras?['wides'] ?? 0}, '
          'lb ${inn!.extras?['legByes'] ?? 0}, '
          'b ${inn!.extras?['byes'] ?? 0})',
          style: const TextStyle(color: AppColors.text2, fontSize: 13)),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.text)),
        Text('${scoreFmt(inn!.totalRuns, inn!.totalWickets)} (${ballsToOvers(inn!.totalBalls)} ov)',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.text)),
      ]),
    ]);
  }
}

class _BowlingTab extends StatelessWidget {
  final Innings? inn;
  final String Function(String?) getName;
  final Team? bowlingTeam;

  const _BowlingTab({required this.inn, required this.getName, required this.bowlingTeam});

  @override Widget build(BuildContext context) {
    if (inn == null) return const SizedBox();
    final bowlers = inn!.bowlerStats.values.toList()
      ..sort((a, b) => b.legalDeliveries.compareTo(a.legalDeliveries));

    return ListView(padding: const EdgeInsets.all(12), children: [
      if (bowlingTeam != null)
        Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Text(bowlingTeam!.name, style: const TextStyle(color: AppColors.text2, fontSize: 13))),
      Table(
        columnWidths: const {
          0: FlexColumnWidth(3), 1: FlexColumnWidth(0.8), 2: FlexColumnWidth(0.8),
          3: FlexColumnWidth(0.8), 4: FlexColumnWidth(0.8), 5: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            children: ['Bowler','O','M','R','W','Eco'].map((h) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Text(h, style: const TextStyle(
                color: AppColors.text2, fontSize: 12, fontWeight: FontWeight.w700)),
            )).toList(),
          ),
          ...bowlers.map((b) => TableRow(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderDim))),
            children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(getName(b.playerId), style: const TextStyle(
                  color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13))),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(b.oversBowled, style: const TextStyle(color: AppColors.text2, fontSize: 13))),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text('${b.maidenOvers}', style: const TextStyle(color: AppColors.text2, fontSize: 13))),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text('${b.runsConceded}', style: const TextStyle(color: AppColors.text2, fontSize: 13))),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text('${b.wicketsTaken}', style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13,
                  color: b.wicketsTaken > 0 ? AppColors.accent : AppColors.text))),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(b.economy.toStringAsFixed(1), style: TextStyle(
                  color: b.economy < 7 ? AppColors.accent : AppColors.wicket, fontSize: 13))),
            ],
          )),
        ],
      ),
    ]);
  }
}

class _FoWTab extends StatelessWidget {
  final Innings? inn;
  final String Function(String?) getName;
  final String Function(Map<String, dynamic>?) dismissalStr;

  const _FoWTab({required this.inn, required this.getName, required this.dismissalStr});

  @override Widget build(BuildContext context) {
    final fow = inn?.fallOfWickets ?? [];
    if (fow.isEmpty) return const Center(
      child: Text('No wickets yet', style: TextStyle(color: AppColors.text2)));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: fow.length,
      itemBuilder: (_, i) {
        final f = fow[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Container(width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColors.wicketFaint, shape: BoxShape.circle,
                border: Border.all(color: AppColors.wicket.withOpacity(0.4))),
              child: Center(child: Text('${f['wicketNumber'] ?? i+1}',
                style: const TextStyle(color: AppColors.wicket, fontWeight: FontWeight.w800, fontSize: 13)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(getName(f['batsmanId'] as String?),
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
              Text(dismissalStr(f['dismissal'] as Map<String, dynamic>?),
                style: const TextStyle(color: AppColors.text2, fontSize: 12)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${f['score'] ?? 0}', style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.wicket, fontSize: 15)),
              Text('Ov ${f['overNumber']}.${f['ballNumber']}',
                style: const TextStyle(color: AppColors.text2, fontSize: 11)),
            ]),
          ]),
        );
      },
    );
  }
}

class _PhasesTab extends StatelessWidget {
  final Innings? inn;
  const _PhasesTab({required this.inn});

  @override Widget build(BuildContext context) {
    if (inn == null) return const SizedBox();
    final dels = inn!.deliveries ?? [];
    final total = inn!.totalRuns == 0 ? 1 : inn!.totalRuns;

    Map<String, dynamic> phase(int from, int to) {
      final d = dels.where((x) => x.overNumber >= from && x.overNumber < to && x.isLegalDelivery).toList();
      return {
        'runs':    d.fold(0, (s, x) => s + x.runsTotal),
        'wickets': d.where((x) => x.isWicket).length,
        'balls':   d.length,
      };
    }

    final phases = [
      ('Powerplay', 'Ov 1–6',   phase(0, 6),  AppColors.accent),
      ('Middle',    'Ov 7–15',  phase(6, 15), AppColors.ball),
      ('Death',     'Ov 16–20', phase(15, 20),AppColors.wicket),
    ];

    return ListView(padding: const EdgeInsets.all(12), children: phases.map((p) {
      final runs    = p.$3['runs'] as int;
      final wickets = p.$3['wickets'] as int;
      final balls   = p.$3['balls'] as int;
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgCard, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.$1, style: TextStyle(fontWeight: FontWeight.w700, color: p.$4, fontSize: 15)),
              Text(p.$2, style: const TextStyle(color: AppColors.text2, fontSize: 12)),
            ])),
            Text('$runs/$wickets', style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.w800, color: p.$4)),
          ]),
          const Divider(height: 16, color: AppColors.border),
          Row(children: [
            _PhStat('Balls',    '$balls'),
            _PhStat('Run rate', balls > 0 ? ((runs / balls) * 6).toStringAsFixed(1) : '0.0'),
            _PhStat('% runs',   '${((runs / total) * 100).toStringAsFixed(0)}%'),
          ]),
        ]),
      );
    }).toList());
  }
}

class _PhStat extends StatelessWidget {
  final String label, value;
  const _PhStat(this.label, this.value);

  @override Widget build(BuildContext context) {
    return Expanded(child: Column(children: [
      Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 12)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 15)),
    ]));
  }
}

// ── Commentary Tab ────────────────────────────────────────────
class _CommentaryTab extends StatefulWidget {
  final String matchId;
  final int inningsNumber;
  const _CommentaryTab({required this.matchId, required this.inningsNumber});
  @override State<_CommentaryTab> createState() => _CommentaryTabState();
}

class _CommentaryTabState extends State<_CommentaryTab> {
  Map<String, MatchClip> _clips = {};

  @override void initState() {
    super.initState();
    _loadClips();
  }

  @override void didUpdateWidget(_CommentaryTab old) {
    super.didUpdateWidget(old);
    if (old.inningsNumber != widget.inningsNumber) _loadClips();
  }

  Future<void> _loadClips() async {
    try {
      final clips = await ClipApi.list(widget.matchId,
          inningsNumber: widget.inningsNumber);
      final map = <String, MatchClip>{};
      for (final c in clips) {
        if (c.event.contains('_pre') || c.event.contains('_post')) continue;
        map['${c.inningsNumber}_${c.over}_${c.ball}'] = c;
      }
      if (mounted) setState(() => _clips = map);
    } catch (_) {}
  }

  MatchClip? _clipFor(CommentaryEntry e) =>
      _clips['${e.innings}_${e.over}_${e.ball - 1}'];

  @override Widget build(BuildContext context) {
    final entries = CommentaryStore.get(widget.matchId)
        .where((e) => e.innings == widget.inningsNumber)
        .toList();

    if (entries.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🎙️', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 12),
        const Text('No commentary available',
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Commentary is recorded live during scoring',
          style: TextStyle(color: AppColors.text2, fontSize: 13)),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Open full commentary'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accent,
            side: const BorderSide(color: AppColors.accent),
          ),
          onPressed: () => context.push('/commentary/${widget.matchId}'),
        ),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (_, i) => CommentaryRow(
        entry: entries[i],
        clip: _clipFor(entries[i]),
      ),
    );
  }
}

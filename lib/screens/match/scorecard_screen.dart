import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
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
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
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
              onPressed: () => context.canPop() ? context.pop() : context.go('/scoring/${m.id}'),
              child: const Text('Score', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Batting'), Tab(text: 'Bowling'),
            Tab(text: 'FoW'), Tab(text: 'Charts'),
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
          _ChartsTab(inn: inn),
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

// ── Charts Tab ────────────────────────────────────────────────
class _ChartsTab extends StatelessWidget {
  final Innings? inn;
  const _ChartsTab({required this.inn});

  @override Widget build(BuildContext context) {
    if (inn == null || (inn!.deliveries?.isEmpty ?? true)) {
      return const Center(child: Text('No data yet', style: TextStyle(color: AppColors.text2)));
    }
    final dels = inn!.deliveries!;

    // ── Per-over data ──────────────────────────────────────────
    final maxOver = dels.map((d) => d.overNumber).fold(0, (a, b) => a > b ? a : b);
    final overRuns    = List<int>.filled(maxOver + 1, 0);
    final overWickets = List<int>.filled(maxOver + 1, 0);
    for (final d in dels) {
      overRuns[d.overNumber]    += d.runsTotal;
      if (d.isWicket) overWickets[d.overNumber]++;
    }

    // Cumulative worm
    final worm = <double>[];
    double cum = 0;
    for (int i = 0; i <= maxOver; i++) { cum += overRuns[i]; worm.add(cum); }

    // ── Partnerships (derived from FoW) ────────────────────────
    final fow = inn!.fallOfWickets ?? [];
    final partnerships = <(int, String)>[];
    int prevRuns = 0;
    for (final w in fow) {
      final r = (w['runs'] as num?)?.toInt() ?? 0;
      final wkt = (w['wicketNumber'] as num?)?.toInt() ?? 0;
      partnerships.add((r - prevRuns, 'Wkt $wkt'));
      prevRuns = r;
    }
    final lastP = inn!.totalRuns - prevRuns;
    if (lastP > 0) partnerships.add((lastP, 'Wkt ${fow.length + 1}'));

    // ── Scoring breakdown (dots/1s/2s/3s/4s/6s) ───────────────
    final legalDels = dels.where((d) => d.isLegalDelivery).toList();
    final dots  = legalDels.where((d) => d.runsBatsman == 0).length;
    final ones  = legalDels.where((d) => d.runsBatsman == 1).length;
    final twos  = legalDels.where((d) => d.runsBatsman == 2).length;
    final threes= legalDels.where((d) => d.runsBatsman == 3).length;
    final fours = legalDels.where((d) => d.runsBatsman == 4).length;
    final sixes = legalDels.where((d) => d.runsBatsman == 6).length;
    final totalL = legalDels.length == 0 ? 1 : legalDels.length;

    // ── Bowler economy ────────────────────────────────────────
    final bowlers = inn!.bowlerStats.values.toList()
      ..sort((a, b) => b.runsConceded.compareTo(a.runsConceded));

    return ListView(padding: const EdgeInsets.all(12), children: [

      // 1. Over by Over
      _chartCard('Over by Over', SizedBox(height: 180, child: BarChart(
        BarChartData(
          maxY: (overRuns.fold(0, (a, b) => a > b ? a : b) + 4).toDouble(),
          gridData: FlGridData(show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: AppColors.border, strokeWidth: 0.5)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24,
              getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(color: AppColors.text2, fontSize: 9)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 18,
              getTitlesWidget: (v, _) => v.toInt() % 5 == 0
                ? Text('${v.toInt()}', style: const TextStyle(color: AppColors.text2, fontSize: 9))
                : const SizedBox())),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barGroups: List.generate(maxOver + 1, (i) => BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: overRuns[i].toDouble(),
              color: overWickets[i] > 0 ? AppColors.wicket : AppColors.accent,
              width: maxOver > 15 ? 6 : 10,
              borderRadius: BorderRadius.circular(3),
            ),
          ])),
          barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (g, _, r, __) {
              final w = overWickets[g.x];
              return BarTooltipItem('Ov ${g.x}\n${r.toY.toInt()} runs${w > 0 ? '\n$w wkt' : ''}',
                const TextStyle(color: Colors.white, fontSize: 11));
            },
          )),
        ),
      ))),

      const SizedBox(height: 12),

      // 2. Worm Chart
      _chartCard('Worm Chart', SizedBox(height: 180, child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: AppColors.border, strokeWidth: 0.5)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30,
              getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(color: AppColors.text2, fontSize: 9)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 18,
              getTitlesWidget: (v, _) => v.toInt() % 5 == 0
                ? Text('${v.toInt()}', style: const TextStyle(color: AppColors.text2, fontSize: 9))
                : const SizedBox())),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [LineChartBarData(
            spots: worm.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
            isCurved: true, color: AppColors.accent, barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: AppColors.accent.withOpacity(0.1)),
          )],
        ),
      ))),

      const SizedBox(height: 12),

      // 3. Scoring Breakdown
      _chartCard('Scoring Breakdown', SizedBox(height: 180, child: Row(children: [
        Expanded(child: PieChart(PieChartData(
          sectionsSpace: 2, centerSpaceRadius: 36,
          sections: [
            if (dots  > 0) PieChartSectionData(value: dots.toDouble(),   color: AppColors.text2,   title: '', radius: 28),
            if (ones  > 0) PieChartSectionData(value: ones.toDouble(),   color: AppColors.accent,  title: '', radius: 28),
            if (twos  > 0) PieChartSectionData(value: twos.toDouble(),   color: Colors.teal,       title: '', radius: 28),
            if (threes> 0) PieChartSectionData(value: threes.toDouble(), color: Colors.purple,     title: '', radius: 28),
            if (fours > 0) PieChartSectionData(value: fours.toDouble(),  color: AppColors.ball,    title: '', radius: 28),
            if (sixes > 0) PieChartSectionData(value: sixes.toDouble(),  color: AppColors.wicket,  title: '', radius: 28),
          ],
        ))),
        const SizedBox(width: 12),
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _legend(AppColors.text2,  'Dots  $dots  (${(dots/totalL*100).toStringAsFixed(0)}%)'),
          _legend(AppColors.accent, '1s    $ones  (${(ones/totalL*100).toStringAsFixed(0)}%)'),
          _legend(Colors.teal,      '2s    $twos  (${(twos/totalL*100).toStringAsFixed(0)}%)'),
          _legend(Colors.purple,    '3s    $threes'),
          _legend(AppColors.ball,   '4s    $fours'),
          _legend(AppColors.wicket, '6s    $sixes'),
        ]),
      ]))),

      const SizedBox(height: 12),

      // 4. Partnership Chart
      if (partnerships.isNotEmpty)
        _chartCard('Partnerships', SizedBox(height: 30.0 * partnerships.length + 24, child: BarChart(
          BarChartData(
            maxY: partnerships.map((p) => p.$1).fold(0, (a, b) => a > b ? a : b).toDouble() + 10,
            gridData: FlGridData(show: true, drawHorizontalLine: false,
              getDrawingVerticalLine: (_) => FlLine(color: AppColors.border, strokeWidth: 0.5)),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40,
                getTitlesWidget: (v, m) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= partnerships.length) return const SizedBox();
                  return Text(partnerships[idx].$2, style: const TextStyle(color: AppColors.text2, fontSize: 9));
                })),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 18,
                getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(color: AppColors.text2, fontSize: 9)))),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            barGroups: partnerships.asMap().entries.map((e) => BarChartGroupData(
              x: e.key, barsSpace: 4,
              barRods: [BarChartRodData(
                toY: e.value.$1.toDouble(),
                color: AppColors.accent, width: 16,
                borderRadius: BorderRadius.circular(4),
              )],
            )).toList(),
            barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (g, _, r, __) => BarTooltipItem(
                '${partnerships[g.x].$2}\n${r.toY.toInt()} runs',
                const TextStyle(color: Colors.white, fontSize: 11)),
            )),
          ),
        ))),

      if (partnerships.isNotEmpty) const SizedBox(height: 12),

      // 5. Bowler Economy
      if (bowlers.isNotEmpty)
        _chartCard('Bowler Economy', Column(children: bowlers.map((b) {
          final overs = b.legalDeliveries / 6;
          final economy = overs > 0 ? b.runsConceded / overs : 0.0;
          final maxEco = 15.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 80, child: Text(b.playerId.length > 10 ? b.playerId.substring(0, 10) : b.playerId,
                style: const TextStyle(color: AppColors.text2, fontSize: 11), overflow: TextOverflow.ellipsis)),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (economy / maxEco).clamp(0.0, 1.0),
                  backgroundColor: AppColors.border,
                  color: economy > 10 ? AppColors.wicket : economy > 7 ? AppColors.ball : AppColors.accent,
                  minHeight: 14,
                ),
              )),
              const SizedBox(width: 8),
              Text('${economy.toStringAsFixed(1)} eco\n${b.wicketsTaken}w',
                style: const TextStyle(color: AppColors.text, fontSize: 10),
                textAlign: TextAlign.right),
            ]),
          );
        }).toList())),

      const SizedBox(height: 12),

      // 6. Phases summary (compact, below charts)
      _chartCard('Phase Summary', Column(children: [
        _phaseRow('Powerplay', 'Ov 1–6',   dels, 0,  6,  inn!.totalRuns, AppColors.accent),
        const Divider(height: 1, color: AppColors.border),
        _phaseRow('Middle',    'Ov 7–15',  dels, 6,  15, inn!.totalRuns, AppColors.ball),
        const Divider(height: 1, color: AppColors.border),
        _phaseRow('Death',     'Ov 16–20', dels, 15, 20, inn!.totalRuns, AppColors.wicket),
      ])),

      const SizedBox(height: 24),
    ]);
  }

  Widget _chartCard(String title, Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.bgCard, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(
        color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13)),
      const SizedBox(height: 12),
      child,
    ]),
  );

  Widget _legend(Color color, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 11)),
    ]),
  );

  Widget _phaseRow(String name, String range, List<Delivery> dels, int from, int to, int total, Color color) {
    final d = dels.where((x) => x.overNumber >= from && x.overNumber < to && x.isLegalDelivery).toList();
    final runs = d.fold(0, (s, x) => s + x.runsTotal);
    final wkts = d.where((x) => x.isWicket).length;
    final balls = d.length;
    final rr = balls > 0 ? ((runs / balls) * 6).toStringAsFixed(1) : '0.0';
    final pct = total > 0 ? '${((runs / total) * 100).toStringAsFixed(0)}%' : '0%';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          Text(range, style: const TextStyle(color: AppColors.text2, fontSize: 11)),
        ])),
        Text('$runs/$wkts', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$rr RR', style: const TextStyle(color: AppColors.text2, fontSize: 11)),
          Text(pct, style: const TextStyle(color: AppColors.text2, fontSize: 11)),
        ]),
      ]),
    );
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

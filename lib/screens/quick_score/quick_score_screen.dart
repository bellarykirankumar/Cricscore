import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

// ── Ball ──────────────────────────────────────────────────────

enum _Extra { none, wide, noBall }

class _Ball {
  final int runs;
  final bool isWicket;
  final _Extra extra;

  const _Ball({this.runs = 0, this.isWicket = false, this.extra = _Extra.none});

  bool get isLegal => extra == _Extra.none;

  String get label {
    if (isWicket) return 'W';
    switch (extra) {
      case _Extra.wide:   return runs == 1 ? 'Wd' : 'Wd+${runs - 1}';
      case _Extra.noBall: return runs == 1 ? 'Nb' : 'Nb+${runs - 1}';
      case _Extra.none:   return '$runs';
    }
  }

  Color get color {
    if (isWicket)              return AppColors.wicket;
    if (extra != _Extra.none)  return Colors.purple;
    if (runs == 4)             return AppColors.accent;
    if (runs == 6)             return AppColors.ball;
    return AppColors.text2;
  }
}

// ── Over ─────────────────────────────────────────────────────

class _Over {
  final TextEditingController bowler = TextEditingController();
  final List<_Ball> balls = [];
  bool expanded = false;

  int get runs       => balls.fold(0, (s, b) => s + b.runs);
  int get wickets    => balls.where((b) => b.isWicket).length;
  int get legalBalls => balls.where((b) => b.isLegal).length;
  bool get isComplete => legalBalls >= 6;

  void dispose() => bowler.dispose();
}

// ── Innings ───────────────────────────────────────────────────

class _Innings {
  final String teamName;
  final int totalOvers;
  final List<_Over> overs;

  _Innings({required this.teamName, required this.totalOvers})
      : overs = List.generate(totalOvers, (_) => _Over());

  int get totalRuns    => overs.fold(0, (s, o) => s + o.runs);
  int get totalWickets => overs.fold(0, (s, o) => s + o.wickets);
  int get ballsBowled  => overs.fold(0, (s, o) => s + o.legalBalls);

  double get runRate {
    if (ballsBowled == 0) return 0;
    return (totalRuns * 6.0) / ballsBowled;
  }

  void dispose() { for (final o in overs) o.dispose(); }
}

// ─────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────

class QuickScoreScreen extends StatefulWidget {
  const QuickScoreScreen({super.key});
  @override State<QuickScoreScreen> createState() => _QuickScoreScreenState();
}

class _QuickScoreScreenState extends State<QuickScoreScreen>
    with SingleTickerProviderStateMixin {
  bool _setupDone = false;
  final _team1Ctrl = TextEditingController();
  final _team2Ctrl = TextEditingController();
  int _overs = 10;

  late _Innings _inn1;
  late _Innings _inn2;
  late TabController _tabCtrl;

  // Tracks which over is waiting for extra-runs selection: 'wide' | 'noBall' | null
  String? _pendingExtra;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _team1Ctrl.dispose();
    _team2Ctrl.dispose();
    if (_setupDone) { _inn1.dispose(); _inn2.dispose(); }
    _tabCtrl.dispose();
    super.dispose();
  }

  void _startMatch() {
    final t1 = _team1Ctrl.text.trim().isEmpty ? 'Team 1' : _team1Ctrl.text.trim();
    final t2 = _team2Ctrl.text.trim().isEmpty ? 'Team 2' : _team2Ctrl.text.trim();
    setState(() {
      _inn1 = _Innings(teamName: t1, totalOvers: _overs);
      _inn2 = _Innings(teamName: t2, totalOvers: _overs);
      _setupDone = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Scoring Sheet'),
        actions: [
          if (_setupDone)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'New match',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Reset scoring sheet?'),
                    content: const Text(
                      'All scores entered so far will be lost. This cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.wicket),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  setState(() {
                    _inn1.dispose(); _inn2.dispose();
                    _setupDone = false;
                    _pendingExtra = null;
                  });
                }
              },
            ),
        ],
      ),
      body: _setupDone ? _scoreBody() : _setupBody(),
    );
  }

  // ── Setup ──────────────────────────────────────────────────

  Widget _setupBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Match Setup', style: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
        const SizedBox(height: 24),
        _label('Team 1 (batting first)'),
        const SizedBox(height: 8),
        TextField(controller: _team1Ctrl,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(hintText: 'e.g. Eagles')),
        const SizedBox(height: 16),
        _label('Team 2'),
        const SizedBox(height: 8),
        TextField(controller: _team2Ctrl,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(hintText: 'e.g. Warriors')),
        const SizedBox(height: 24),
        _label('Number of overs'),
        const SizedBox(height: 12),
        _overSelector(),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(onPressed: _startMatch,
            child: const Text('Start Scoring')),
        ),
      ]),
    );
  }

  Widget _label(String t) => Text(t, style: const TextStyle(
    fontSize: 12, fontWeight: FontWeight.w700,
    color: AppColors.text2, letterSpacing: 1.0));

  Widget _overSelector() {
    const options = [5, 6, 8, 10, 12, 15, 20, 25, 50];
    return Wrap(spacing: 10, runSpacing: 10, children: options.map((o) {
      final sel = _overs == o;
      return GestureDetector(
        onTap: () => setState(() => _overs = o),
        child: Container(
          width: 56, height: 44,
          decoration: BoxDecoration(
            color: sel ? AppColors.accent : AppColors.bgElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? AppColors.accent : AppColors.border),
          ),
          child: Center(child: Text('$o', style: TextStyle(
            fontWeight: FontWeight.w700,
            color: sel ? AppColors.textOnAcc : AppColors.text,
          ))),
        ),
      );
    }).toList());
  }

  // ── Score body ─────────────────────────────────────────────

  Widget _scoreBody() {
    return Column(children: [
      _summaryBar(),
      TabBar(
        controller: _tabCtrl,
        onTap: (_) => setState(() => _pendingExtra = null),
        tabs: [
          Tab(text: '1st Inn · ${_inn1.teamName}'),
          Tab(text: '2nd Inn · ${_inn2.teamName}'),
        ],
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.text2,
        indicatorColor: AppColors.accent,
        dividerColor: AppColors.border,
      ),
      Expanded(child: TabBarView(
        controller: _tabCtrl,
        children: [_inningsSheet(_inn1), _inningsSheet(_inn2)],
      )),
    ]);
  }

  Widget _summaryBar() {
    final r1 = _inn1.totalRuns;
    final w1 = _inn1.totalWickets;
    final r2 = _inn2.totalRuns;
    final w2 = _inn2.totalWickets;
    final diff = r2 - r1;
    String result = '';
    if (r2 > 0 || w2 > 0) {
      if (diff > 0)      result = '${_inn2.teamName} lead by $diff';
      else if (diff < 0) result = '${_inn1.teamName} lead by ${-diff}';
      else               result = 'Scores level';
    }
    return Container(
      color: AppColors.bgElevated,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(children: [
        Expanded(child: _scoreChip(_inn1.teamName, r1, w1)),
        if (result.isNotEmpty)
          Flexible(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(result, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppColors.text2,
                fontWeight: FontWeight.w600)),
          )),
        Expanded(child: _scoreChip(_inn2.teamName, r2, w2,
            align: CrossAxisAlignment.end)),
      ]),
    );
  }

  Widget _scoreChip(String team, int runs, int wickets,
      {CrossAxisAlignment align = CrossAxisAlignment.start}) =>
      Column(crossAxisAlignment: align, children: [
        Text(team, style: const TextStyle(
          fontSize: 11, color: AppColors.text2, fontWeight: FontWeight.w600)),
        Text('$runs/$wickets', style: const TextStyle(
          fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.text)),
      ]);

  // ── Innings sheet ──────────────────────────────────────────

  Widget _inningsSheet(_Innings inn) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: inn.overs.length + 1,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.borderDim),
      itemBuilder: (_, i) {
        if (i == inn.overs.length) return _totalsRow(inn);
        return _overTile(inn, i);
      },
    );
  }

  Widget _overTile(_Innings inn, int i) {
    final over = inn.overs[i];
    return Column(children: [
      InkWell(
        onTap: () => setState(() {
          over.expanded = !over.expanded;
          _pendingExtra = null;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: over.isComplete
                    ? AppColors.accent.withOpacity(0.12)
                    : AppColors.bgElevated,
                shape: BoxShape.circle,
              ),
              child: Center(child: Text('${i + 1}', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: over.isComplete ? AppColors.accent : AppColors.text2))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: over.bowler,
                style: const TextStyle(fontSize: 14, color: AppColors.text),
                decoration: const InputDecoration(
                  hintText: 'Bowler name',
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (over.balls.isNotEmpty)
              Flexible(
                child: Wrap(spacing: 3, runSpacing: 3,
                  children: over.balls.map((b) => _miniPip(b)).toList()),
              ),
            const SizedBox(width: 6),
            Text(over.balls.isNotEmpty ? '${over.runs}' : '',
              style: const TextStyle(fontSize: 15,
                fontWeight: FontWeight.w800, color: AppColors.text)),
            const SizedBox(width: 4),
            Icon(over.expanded ? Icons.expand_less : Icons.expand_more,
              color: AppColors.text3, size: 20),
          ]),
        ),
      ),
      if (over.expanded) _ballPanel(inn, over),
    ]);
  }

  Widget _miniPip(_Ball b) => Container(
    width: 20, height: 20,
    decoration: BoxDecoration(
      color: b.color.withOpacity(0.15),
      shape: BoxShape.circle,
      border: Border.all(color: b.color.withOpacity(0.4)),
    ),
    child: Center(child: Text(b.label, style: TextStyle(
      fontSize: 8, fontWeight: FontWeight.w800, color: b.color))),
  );

  Widget _ballPanel(_Innings inn, _Over over) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Ball pip row
        if (over.balls.isNotEmpty) ...[
          const Text('BALLS', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: AppColors.text3, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Wrap(spacing: 5, runSpacing: 5, children: [
            ...over.balls.asMap().entries.map((e) => GestureDetector(
              onLongPress: () => setState(() {
                over.balls.removeAt(e.key);
                _pendingExtra = null;
              }),
              child: _pip(e.value, size: 34),
            )),
            ...List.generate((6 - over.legalBalls).clamp(0, 6), (_) =>
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                  color: AppColors.bgElevated,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),
        ],

        // Extra runs picker (shown after tapping Wd or Nb)
        if (_pendingExtra != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.purple.withOpacity(0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _pendingExtra == 'wide'
                    ? 'WIDE — how many extra runs?'
                    : 'NO BALL — how many extra runs off the bat?',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: Colors.purple, letterSpacing: 0.5)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8,
                children: _extraRunOptions(_pendingExtra!).map((opt) =>
                  GestureDetector(
                    onTap: () => setState(() {
                      over.balls.add(opt);
                      _pendingExtra = null;
                    }),
                    child: Container(
                      width: 60, height: 44,
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.purple.withOpacity(0.4)),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(opt.label, style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800,
                            color: Colors.purple)),
                          Text('${opt.runs} run${opt.runs != 1 ? "s" : ""}',
                            style: TextStyle(fontSize: 9,
                              color: Colors.purple.withOpacity(0.8))),
                        ]),
                    ),
                  ),
                ).toList(),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => setState(() => _pendingExtra = null),
                child: const Text('Cancel', style: TextStyle(
                  fontSize: 12, color: AppColors.text3)),
              ),
            ]),
          ),
          const SizedBox(height: 14),
        ],

        // Outcome buttons
        if (_pendingExtra == null) ...[
          const Text('TAP TO ADD', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: AppColors.text3, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            // Legal balls (disabled when over complete)
            ...[
              const _Ball(runs: 0),
              const _Ball(runs: 1),
              const _Ball(runs: 2),
              const _Ball(runs: 3),
              const _Ball(runs: 4),
              const _Ball(runs: 6),
              const _Ball(isWicket: true),
            ].map((b) {
              final disabled = over.isComplete;
              return GestureDetector(
                onTap: disabled ? null : () => setState(() => over.balls.add(b)),
                child: Opacity(opacity: disabled ? 0.35 : 1.0,
                  child: _outcomeBtn(b)),
              );
            }),
            // Wide — locked once over is complete
            GestureDetector(
              onTap: over.isComplete ? null : () => setState(() => _pendingExtra = 'wide'),
              child: Opacity(opacity: over.isComplete ? 0.35 : 1.0,
                child: _outcomeBtn(const _Ball(runs: 1, extra: _Extra.wide))),
            ),
            // No Ball — locked once over is complete
            GestureDetector(
              onTap: over.isComplete ? null : () => setState(() => _pendingExtra = 'noBall'),
              child: Opacity(opacity: over.isComplete ? 0.35 : 1.0,
                child: _outcomeBtn(const _Ball(runs: 1, extra: _Extra.noBall))),
            ),
          ]),
          if (over.balls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: const Text('Long-press a ball to remove it',
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
            ),
        ],
      ]),
    );
  }

  List<_Ball> _extraRunOptions(String type) {
    if (type == 'wide') {
      return [
        const _Ball(runs: 1, extra: _Extra.wide),              // Wd
        const _Ball(runs: 3, extra: _Extra.wide),              // Wd+2
        const _Ball(runs: 4, extra: _Extra.wide),              // Wd+3
        const _Ball(runs: 5, extra: _Extra.wide),              // Wd+4
      ];
    } else {
      // No ball: bat runs 0,1,2,3,4,6 (all +1 for the no ball penalty)
      return [
        const _Ball(runs: 1, extra: _Extra.noBall), // Nb (no bat runs)
        const _Ball(runs: 2, extra: _Extra.noBall), // Nb+1
        const _Ball(runs: 3, extra: _Extra.noBall), // Nb+2
        const _Ball(runs: 4, extra: _Extra.noBall), // Nb+3
        const _Ball(runs: 5, extra: _Extra.noBall), // Nb+4
        const _Ball(runs: 7, extra: _Extra.noBall), // Nb+6
      ];
    }
  }

  Widget _pip(_Ball b, {double size = 28}) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      color: b.color.withOpacity(0.15),
      shape: BoxShape.circle,
      border: Border.all(color: b.color.withOpacity(0.5)),
    ),
    child: Center(child: Text(b.label, style: TextStyle(
      fontSize: size * 0.28, fontWeight: FontWeight.w800, color: b.color))),
  );

  Widget _outcomeBtn(_Ball b) {
    final sub = _btnSubLabel(b);
    return Container(
      width: 52, height: 44,
      decoration: BoxDecoration(
        color: b.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: b.color.withOpacity(0.4)),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(b.label, style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w800, color: b.color)),
        Text(sub, style: TextStyle(fontSize: 9, color: b.color.withOpacity(0.8))),
      ]),
    );
  }

  String _btnSubLabel(_Ball b) {
    if (b.isWicket)                    return 'out';
    if (b.extra == _Extra.wide)        return 'wide';
    if (b.extra == _Extra.noBall)      return 'no ball';
    if (b.runs == 4)                   return 'four';
    if (b.runs == 6)                   return 'six';
    if (b.runs == 0)                   return 'dot';
    return 'run${b.runs != 1 ? "s" : ""}';
  }

  Widget _totalsRow(_Innings inn) {
    return Container(
      color: AppColors.bgElevated,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        const Expanded(child: Text('TOTAL', style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w800,
          color: AppColors.text, letterSpacing: 0.8))),
        Text('${inn.totalRuns}/${inn.totalWickets}',
          style: const TextStyle(fontSize: 20,
            fontWeight: FontWeight.w900, color: AppColors.accent)),
        const SizedBox(width: 16),
        Text('RR: ${inn.runRate.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 13,
            color: AppColors.text2, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

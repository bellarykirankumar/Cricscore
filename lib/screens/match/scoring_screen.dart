import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/clip_ws_service.dart';
import '../../models/models.dart';
import '../../utils/cricket_utils.dart';
import 'commentary_screen.dart';
import 'camera_buffer_screen.dart';

class ScoringScreen extends ConsumerStatefulWidget {
  final String matchId;
  const ScoringScreen({super.key, required this.matchId});
  @override ConsumerState<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends ConsumerState<ScoringScreen> {
  CricMatch? _match;
  Innings?   _innings;
  bool       _loading   = true;
  bool       _saving    = false;
  String?    _extra;
  bool       _showDismissal = false;
  String?    _pickerMode;
  bool       _pendingBowlerChange = false;
  int        _rawBallCount = 0;

  // Wicket context — set before showing new_batsman picker
  bool       _wicketOverComplete     = false;
  bool?      _runOutStrikerDismissed;
  bool       _pendingStrikerConfirm  = false;

  // Tracks all dismissed player IDs for this innings — authoritative filter for picker
  final Set<String> _dismissedIds = {};

  // Voice scoring
  final SpeechToText _speech = SpeechToText();
  bool   _speechAvailable = false;
  bool   _isListening     = false;
  String _voiceText       = '';

  @override void initState() {
    super.initState();
    _loadMatch();
    _initSpeech();
    // Connect WebSocket so clip triggers can be sent immediately on wicket/boundary
    ClipWsService.instance.connect(widget.matchId);
  }

  @override void dispose() {
    _speech.stop();
    ClipWsService.instance.disconnect();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (e) => setState(() => _isListening = false),
    );
    setState(() {});
  }

  Future<void> _startListening() async {
    if (!_speechAvailable || _isListening) return;
    setState(() { _isListening = true; _voiceText = ''; });
    await _speech.listen(
      onResult: (result) {
        setState(() => _voiceText = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          _processVoiceCommand(result.recognizedWords);
          _stopListening();
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 2),
        localeId: 'en_US',
      ),
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() { _isListening = false; _voiceText = ''; });
  }

  void _processVoiceCommand(String text) {
    final t = text.toLowerCase().trim();

    // Wicket
    if (t.contains('out') || t.contains('wicket') || t == 'w') {
      HapticFeedback.mediumImpact();
      _handleBall(0, 'wicket');
      return;
    }
    // Wide
    if (t.contains('wide')) {
      setState(() => _extra = 'wide');
      Future.microtask(_showWidePicker);
      return;
    }
    // No ball
    if (t.contains('no ball') || t.contains('no-ball') || t.contains('no bal')) {
      setState(() => _extra = 'no_ball');
      Future.microtask(_showNoBallPicker);
      return;
    }
    // Leg bye
    if (t.contains('leg bye') || t.contains('leg-bye') || t.contains('legbye')) {
      setState(() => _extra = 'leg_bye');
      Future.microtask(_showByePicker);
      return;
    }
    // Bye
    if (t.contains('bye')) {
      setState(() => _extra = 'bye');
      Future.microtask(_showByePicker);
      return;
    }

    // Runs
    int? runs;
    if (t.contains('dot') || t.contains('zero') || t.contains('no run') || t == '0' || t == 'golden') {
      runs = 0;
    } else if (t == 'one' || t == '1' || t.contains('single')) {
      runs = 1;
    } else if (t == 'two' || t == '2' || t.contains('double') || t.contains('couple')) {
      runs = 2;
    } else if (t == 'three' || t == '3' || t.contains('triple')) {
      runs = 3;
    } else if (t.contains('four') || t == '4' || t.contains('boundary') || t.contains('fore')) {
      runs = 4;
    } else if (t == 'five' || t == '5') {
      runs = 5;
    } else if (t.contains('six') || t == '6' || t.contains('sixer') || t.contains('maximum') || t.contains('max')) {
      runs = 6;
    }

    if (runs != null) {
      HapticFeedback.lightImpact();
      _handleBall(runs, runs == 0 ? 'dot' : runs == 4 ? 'four' : runs == 6 ? 'six' : 'run');
    } else {
      // Unrecognised — brief feedback
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Not recognised: "$text"\nTry: dot, one, four, six, wide, wicket…'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _loadMatch() async {
    setState(() => _loading = true);
    try {
      final m = await MatchApi.get(widget.matchId);
      final allInnings = m.innings ?? [];
      allInnings.sort((a, b) => b.inningsNumber.compareTo(a.inningsNumber));
      final active = allInnings.firstWhere(
        (i) => i.status == 'in_progress',
        orElse: () => allInnings.first,
      );
      final full = await MatchApi.getInnings(widget.matchId, active.inningsNumber);
      _rawBallCount = full.deliveries?.length ?? 0;
      // Restore player IDs from the last delivery if the API returned nulls
      Innings resolved = full;
      final dels = full.deliveries;
      if (full.currentStrikerId == null && dels != null && dels.isNotEmpty) {
        final last = dels.last;
        resolved = Innings.copyWith(full,
          currentStrikerId:    full.currentStrikerId    ?? last.batsmanId,
          currentNonStrikerId: full.currentNonStrikerId ?? last.nonStrikerId,
          currentBowlerId:     full.currentBowlerId     ?? last.bowlerId,
        );
      }
      // Rebuild dismissed set from server data on load/reload
      _dismissedIds
        ..clear()
        ..addAll(resolved.batsmanStats.entries
            .where((e) => e.value.isOut).map((e) => e.key));
      setState(() { _match = m; _innings = resolved; _loading = false; });
      // Only show picker for what's actually missing
      if (resolved.currentStrikerId == null) {
        setState(() => _pickerMode = 'striker');
      } else if (resolved.currentNonStrikerId == null) {
        setState(() => _pickerMode = 'non_striker');
      } else if (resolved.currentBowlerId == null) {
        setState(() => _pickerMode = 'bowler');
      } else {
        setState(() => _pickerMode = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
        setState(() => _loading = false);
      }
    }
  }

  List<Player> get _allPlayers => [...(_match?.team1?.players ?? []), ...(_match?.team2?.players ?? [])];

  String _getName(String? id) {
    if (id == null) return '—';
    return _allPlayers.firstWhere((p) => p.id == id,
      orElse: () => Player(id: id, teamId: '', name: id, shortName: id)).name;
  }

  Team? get _battingTeam => _match?.team1?.id == _innings?.battingTeamId ? _match?.team1 : _match?.team2;
  Team? get _bowlingTeam => _match?.team1?.id == _innings?.bowlingTeamId ? _match?.team1 : _match?.team2;

  List<Player> get _availBatters {
    final inn = _innings;
    if (inn == null) return [];
    return (_battingTeam?.players ?? []).where((p) {
      if (p.id == inn.currentStrikerId || p.id == inn.currentNonStrikerId) return false;
      if (_dismissedIds.contains(p.id)) return false;
      final s = inn.batsmanStats[p.id];
      if (s != null && s.isOut) return false;
      return true;
    }).toList();
  }

  List<Player> get _availBowlers {
    final inn = _innings;
    final match = _match;
    if (inn == null || match == null) return [];
    return (_bowlingTeam?.players ?? []).where((p) {
      if (p.id == inn.currentBowlerId) return false;
      final quota = _maxOvers(match.format, match.oversPerInnings);
      if (quota == null) return true;
      final s = inn.bowlerStats[p.id];
      return s == null || (s.legalDeliveries ~/ 6) < quota;
    }).toList();
  }

  int? _maxOvers(String format, int total) => CricketUtils.bowlerQuota(format, total);

  void _onPickPlayer(Player player) {
    final inn = _innings;
    if (inn == null) return;
    HapticFeedback.selectionClick();
    if (_pickerMode == 'new_batsman') {
      final newInn = (inn.currentStrikerId == null)
          ? Innings.copyWith(inn, currentStrikerId: player.id)
          : Innings.copyWith(inn, currentNonStrikerId: player.id);
      setState(() => _innings = newInn);

      if (_runOutStrikerDismissed != null && !_wicketOverComplete) {
        // Mid-over run out: ask who's on strike before resuming
        Future.delayed(const Duration(milliseconds: 200),
            () { if (mounted) setState(() => _pickerMode = 'striker_confirm'); });
        return;
      }
      if (_pendingBowlerChange) {
        // Last ball wicket (normal or run out): close over → new bowler → striker confirm
        setState(() { _pendingBowlerChange = false; _pendingStrikerConfirm = true; _pickerMode = null; });
        Future.delayed(const Duration(milliseconds: 300),
            () { if (mounted) setState(() => _pickerMode = 'new_bowler'); });
        return;
      }
    } else if (_pickerMode == 'run_out_who') {
      // This mode is handled by a custom widget — not a player picker
      // (see _RunOutWhoWidget below); this branch won't be reached
      return;
    } else if (_pickerMode == 'striker') {
      setState(() => _innings = Innings.copyWith(inn, currentStrikerId: player.id));
      if (inn.currentNonStrikerId == null) { setState(() => _pickerMode = 'non_striker'); return; }
      if (inn.currentBowlerId == null)     { setState(() => _pickerMode = 'bowler'); return; }
    } else if (_pickerMode == 'non_striker') {
      setState(() => _innings = Innings.copyWith(inn, currentNonStrikerId: player.id));
      if (inn.currentBowlerId == null) { setState(() => _pickerMode = 'bowler'); return; }
    } else if (_pickerMode == 'bowler' || _pickerMode == 'new_bowler') {
      setState(() => _innings = Innings.copyWith(inn, currentBowlerId: player.id));
      if (_pendingStrikerConfirm) {
        setState(() { _pendingStrikerConfirm = false; _pickerMode = 'striker_confirm'; });
        return;
      }
    }
    setState(() => _pickerMode = null);
  }

  void _handleBall(int runs, String type) {
    final inn = _innings;
    if (inn == null) return;
    // Block scoring while any picker or confirmation is active
    if (_pickerMode != null) return;
    if (_showDismissal) return;
    if (inn.currentStrikerId == null || inn.currentNonStrikerId == null || inn.currentBowlerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select players first')));
      setState(() => _pickerMode = 'striker');
      return;
    }
    if (type == 'wicket') { setState(() => _showDismissal = true); return; }
    _submitDelivery(runs, false);
  }

  void _showWidePicker() {
    showModalBottomSheet(
      context: context, backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Wide — additional runs?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 6),
          const Text('1 penalty run already counted. Select overthrow runs if any.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.text2, fontSize: 13)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [0, 1, 2, 3, 4].map((r) => GestureDetector(
              onTap: () { final e = _extra; Navigator.pop(context); setState(() => _extra = null); _submitDeliveryWithExtra(r, false, e); },
              child: Container(
                width: 58, height: 58,
                decoration: BoxDecoration(
                  color: r == 4 ? AppColors.four.withOpacity(0.15) : AppColors.bgElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: r == 4 ? AppColors.four : AppColors.border),
                ),
                child: Center(child: Text(r == 0 ? 'Wd' : 'Wd+$r',
                  style: TextStyle(fontSize: r == 0 ? 13 : 11, fontWeight: FontWeight.w800,
                    color: r == 4 ? AppColors.four : AppColors.ball))),
              ),
            )).toList(),
          ),
        ]),
      ),
    );
  }

  void _showNoBallPicker() {
    showModalBottomSheet(
      context: context, backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('No Ball — runs off bat?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 6),
          const Text('1 penalty run already counted. Select additional runs scored.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.text2, fontSize: 13)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [0, 1, 2, 3, 4, 6].map((r) => GestureDetector(
              onTap: () { final e = _extra; Navigator.pop(context); setState(() => _extra = null); _submitDeliveryWithExtra(r, false, e); },
              child: Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: r == 4 ? AppColors.four.withOpacity(0.15) : r == 6 ? AppColors.six.withOpacity(0.15) : AppColors.bgElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: r == 4 ? AppColors.four : r == 6 ? AppColors.six : AppColors.border),
                ),
                child: Center(child: Text(r == 0 ? 'Nb' : 'Nb+$r',
                  style: TextStyle(fontSize: r == 0 ? 13 : 11, fontWeight: FontWeight.w800,
                    color: r == 4 ? AppColors.four : r == 6 ? AppColors.six : AppColors.ball))),
              ),
            )).toList(),
          ),
        ]),
      ),
    );
  }

  void _showByePicker() {
    final isLegBye = _extra == 'leg_bye';
    showModalBottomSheet(
      context: context, backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(isLegBye ? 'Leg Bye — how many?' : 'Bye — how many?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 6),
          const Text('Runs credited as extras, not to batsman.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.text2, fontSize: 13)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [1, 2, 3, 4].map((r) => GestureDetector(
              onTap: () { final e = _extra; Navigator.pop(context); setState(() => _extra = null); _submitDeliveryWithExtra(r, false, e); },
              child: Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: r == 4 ? AppColors.four.withOpacity(0.15) : AppColors.bgElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: r == 4 ? AppColors.four : AppColors.border),
                ),
                child: Center(child: Text('$r', style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800,
                  color: r == 4 ? AppColors.four : AppColors.text))),
              ),
            )).toList(),
          ),
        ]),
      ),
    );
  }


  // ── Local-first delivery submission ───────────────────────────
  // All state transitions (rotation, over-end, wicket) are computed
  // locally before the API call. The server response is used only to
  // update stats/totals — never to drive currentStrikerId/NonStrikerId.
  Future<void> _submitDeliveryWithExtra(int runs, bool isWicket, String? extraType, [String? dismissalType, String? fielderId]) async {
    final match = _match;
    final inn = _innings;
    if (match == null || inn == null) return;
    if (_pickerMode != null) return; // picker active — ignore accidental taps
    if (inn.currentStrikerId == null || inn.currentNonStrikerId == null || inn.currentBowlerId == null) return;

    setState(() { _saving = true; _showDismissal = false; _extra = null; });
    HapticFeedback.lightImpact();

    final extra     = extraType;
    final isLegal   = extra != 'wide' && extra != 'no_ball';
    final runsBat   = (extra == 'wide' || extra == 'leg_bye' || extra == 'bye') ? 0 : runs;
    final runsExt   = extra == 'no_ball' ? (1 + runs) : extra == 'wide' ? (1 + runs)
                      : (extra == 'bye' || extra == 'leg_bye') ? runs : 0;
    final runsTotal = extra == 'no_ball' ? (1 + runs) : extra == 'wide' ? (1 + runs) : runs;

    // ── Snapshot names/positions BEFORE any state change ──────────
    final strikerName = _getName(inn.currentStrikerId);
    final bowlerName  = _getName(inn.currentBowlerId);
    final overNum     = inn.totalBalls ~/ 6;
    final ballNum     = (inn.totalBalls % 6) + 1;

    // ── 1. Compute next state LOCALLY — server never drives UI ────
    // Build new delivery record
    final newDelivery = Delivery(
      overNumber:      overNum,
      ballNumber:      inn.totalBalls % 6,
      batsmanId:       inn.currentStrikerId ?? '',
      nonStrikerId:    inn.currentNonStrikerId ?? '',
      bowlerId:        inn.currentBowlerId ?? '',
      runsBatsman:     runsBat,
      runsExtras:      runsExt,
      runsTotal:       runsTotal,
      isWicket:        isWicket,
      isLegalDelivery: isLegal,
      extraType:       extra,
    );

    // Build updated totals locally
    final newTotalBalls   = inn.totalBalls + (isLegal ? 1 : 0);
    final newTotalRuns    = inn.totalRuns + runsTotal;
    final newTotalWickets = inn.totalWickets + (isWicket ? 1 : 0);
    final newDeliveries   = <Delivery>[...(inn.deliveries ?? []), newDelivery];

    // ── Update batsman & bowler stats locally ─────────────────────
    // Deep-copy existing stats maps
    final newBatsmanStats = Map<String, BatsmanStats>.from(inn.batsmanStats);
    final newBowlerStats  = Map<String, BowlerStats>.from(inn.bowlerStats);

    final strikerId = inn.currentStrikerId ?? '';
    final bowlerId  = inn.currentBowlerId  ?? '';

    // Ensure striker entry exists
    if (strikerId.isNotEmpty && !newBatsmanStats.containsKey(strikerId)) {
      newBatsmanStats[strikerId] = const BatsmanStats(
        playerId: '', runsScored: 0, ballsFaced: 0,
        fours: 0, sixes: 0, strikeRate: 0, isOut: false, didNotBat: false,
      );
    }
    // Ensure non-striker entry exists so they appear in scorecard
    final nonStrikerId = inn.currentNonStrikerId ?? '';
    if (nonStrikerId.isNotEmpty && !newBatsmanStats.containsKey(nonStrikerId)) {
      newBatsmanStats[nonStrikerId] = const BatsmanStats(
        playerId: '', runsScored: 0, ballsFaced: 0,
        fours: 0, sixes: 0, strikeRate: 0, isOut: false, didNotBat: false,
      );
    }
    if (strikerId.isNotEmpty) {
      final old = newBatsmanStats[strikerId]!;
      final newBalls = old.ballsFaced + (isLegal ? 1 : 0);
      final newRuns  = old.runsScored + runsBat;
      newBatsmanStats[strikerId] = BatsmanStats(
        playerId:   strikerId,
        runsScored: newRuns,
        ballsFaced: newBalls,
        fours:      old.fours + (runsBat == 4 && extra == null ? 1 : 0),
        sixes:      old.sixes + (runsBat == 6 ? 1 : 0),
        strikeRate: newBalls > 0 ? (newRuns / newBalls * 100).roundToDouble() : 0,
        isOut:      isWicket ? true : old.isOut,
        didNotBat:  false,
      );
    }
    // Ensure bowler entry exists
    if (bowlerId.isNotEmpty && !newBowlerStats.containsKey(bowlerId)) {
      newBowlerStats[bowlerId] = BowlerStats(
        playerId: bowlerId, legalDeliveries: 0, runsConceded: 0,
        wicketsTaken: 0, maidenOvers: 0, wides: 0, noBalls: 0, economy: 0,
      );
    }
    if (bowlerId.isNotEmpty) {
      final old = newBowlerStats[bowlerId]!;
      final newLegal = old.legalDeliveries + (isLegal ? 1 : 0);
      final newRuns  = old.runsConceded + runsTotal;
      newBowlerStats[bowlerId] = BowlerStats(
        playerId:        bowlerId,
        legalDeliveries: newLegal,
        runsConceded:    newRuns,
        wicketsTaken:    old.wicketsTaken + (isWicket ? 1 : 0),
        maidenOvers:     old.maidenOvers,
        wides:           old.wides + (extra == 'wide' ? 1 : 0),
        noBalls:         old.noBalls + (extra == 'no_ball' ? 1 : 0),
        economy:         newLegal > 0
            ? double.parse((newRuns / (newLegal / 6)).toStringAsFixed(2))
            : 0,
      );
    }

    // Determine next striker/non-striker purely from local rules:
    //   - Odd batsman runs → rotate
    //   - Wicket → new batsman will be picked, keep non-striker
    //   - End of over (after this legal ball) → swap (handled after setState)
    String? nextStriker    = inn.currentStrikerId;
    String? nextNonStriker = inn.currentNonStrikerId;

    if (!isWicket && isLegal && runsBat.isOdd) {
      // Rotate on odd batsman runs
      nextStriker    = inn.currentNonStrikerId;
      nextNonStriker = inn.currentStrikerId;
    }

    // Check if this legal ball completes the over
    final overComplete = isLegal && (newTotalBalls % 6 == 0);
    if (overComplete && !isWicket) {
      // End-of-over swap (non-striker faces next over)
      final tmp  = nextStriker;
      nextStriker    = nextNonStriker;
      nextNonStriker = tmp;
    }

    // Track dismissed player — for run_out we don't know who yet; resolved in picker
    if (isWicket && dismissalType != 'run_out') {
      _dismissedIds.add(inn.currentStrikerId ?? '');
    }

    // Apply local state immediately — UI responds without waiting for network
    // Compute local innings state — all placement logic here, never from server
    bool clearS = false, clearNS = false;
    String? localStriker, localNonStriker;

    if (!isWicket) {
      localStriker    = nextStriker;
      localNonStriker = nextNonStriker;
    } else if (dismissalType == 'run_out') {
      // Run out: keep current positions — picker will resolve who's out
      localStriker    = inn.currentStrikerId;
      localNonStriker = inn.currentNonStrikerId;
    } else if (overComplete) {
      // Normal wicket, last ball of over:
      // → non-striker walks to striker end for next over
      // → new batsman comes in at non-striker end (to be picked)
      localStriker = inn.currentNonStrikerId;
      clearNS      = true;
    } else {
      // Normal wicket, mid-over (balls 1–5):
      // → striker is out, new batsman faces next ball (striker end, to be picked)
      // → non-striker stays unchanged
      clearS          = true;
      localNonStriker = inn.currentNonStrikerId;
    }

    final localInn = Innings.copyWith(inn,
      totalRuns:           newTotalRuns,
      totalBalls:          newTotalBalls,
      totalWickets:        newTotalWickets,
      currentStrikerId:    localStriker,
      currentNonStrikerId: localNonStriker,
      clearStriker:        clearS,
      clearNonStriker:     clearNS,
      deliveries:          newDeliveries,
      batsmanStats:        newBatsmanStats,
      bowlerStats:         newBowlerStats,
    );
    setState(() { _innings = localInn; _rawBallCount++; });

    // ── 2. Commentary placeholder (immediate) ─────────────────────
    final placeholder = CommentaryEntry(
      innings: inn.inningsNumber, over: overNum, ball: ballNum,
      batsman: strikerName, bowler: bowlerName,
      runs: runsTotal, extra: extra,
      isWicket: isWicket, dismissal: dismissalType, text: '',
    );
    CommentaryStore.addOrUpdate(widget.matchId, placeholder);
    if (mounted) setState(() {});

    // ── 3. Clip trigger (fire-and-forget) ─────────────────────────
    final clipEvent = isWicket ? 'wicket' : runsBat == 6 ? 'six' : runsBat == 4 ? 'four' : null;
    if (clipEvent != null) {
      ClipWsService.instance.sendClipTrigger(
        matchId: widget.matchId, inningsNumber: inn.inningsNumber,
        over: overNum, ball: ballNum - 1, event: clipEvent,
      );
    }

    // ── 4. AI Commentary (fire-and-forget, never blocks next ball) ─
    AiApi.generateCommentary({
      'bowler': bowlerName, 'batsman': strikerName,
      'runs': runsTotal,
      if (extra != null) 'extra': extra,
      'isWicket': isWicket,
      if (isWicket && dismissalType != null) 'dismissal': dismissalType,
      'over': overNum, 'ball': ballNum,
      'teamRuns': newTotalRuns, 'teamWickets': newTotalWickets,
      if (localInn.target != null) 'target': localInn.target,
    }).then((text) {
      if (text.isNotEmpty && mounted) {
        CommentaryStore.addOrUpdate(widget.matchId, CommentaryEntry(
          innings: inn.inningsNumber, over: overNum, ball: ballNum,
          batsman: strikerName, bowler: bowlerName,
          runs: runsTotal, extra: extra,
          isWicket: isWicket, dismissal: dismissalType, text: text,
        ));
        setState(() {});
      }
    }).catchError((_) {});

    // ── 5. Send to backend async (best-effort, never blocks UI) ───
    MatchApi.recordDelivery(widget.matchId, inn.inningsNumber, {
      'batsmanId':       inn.currentStrikerId,
      'nonStrikerId':    inn.currentNonStrikerId,
      'bowlerId':        inn.currentBowlerId,
      'runsBatsman':     runsBat,
      'runsExtras':      runsExt,
      'runsTotal':       runsTotal,
      if (extra != null) 'extraType': extra,
      'isWicket':        isWicket,
      'isLegalDelivery': isLegal,
      'rawBallNumber':   _rawBallCount - 1,
      if (isWicket && dismissalType != null) 'dismissal': {
        'type': dismissalType, 'batsmanId': inn.currentStrikerId,
        'bowlerId': inn.currentBowlerId,
        if (fielderId != null) 'fielderId': fielderId,
      },
    }).catchError((e) {
      // Log silently — local state is already correct
      debugPrint('Delivery sync failed: $e');
    });

    // ── 6. Post-ball UI transitions ────────────────────────────────
    try {
      if (isWicket) {
        if (newTotalWickets >= 10) { await _handleInningsEnd(localInn); return; }
        if (isLegal && newTotalBalls >= match.oversPerInnings * 6) {
          await _handleInningsEnd(localInn); return;
        }
        // Store wicket context for the picker to use
        _wicketOverComplete    = overComplete;
        _runOutStrikerDismissed = null;
        _pendingStrikerConfirm  = false;

        if (dismissalType == 'run_out') {
          // For run out at end of over, flag bowler change now so picker chain picks it up
          if (overComplete) _pendingBowlerChange = true;
          Future.delayed(const Duration(milliseconds: 300),
              () { if (mounted) setState(() => _pickerMode = 'run_out_who'); });
        } else {
          // Normal dismissal — striker is always out
          if (overComplete) {
            setState(() { _pendingBowlerChange = true; _pickerMode = 'new_batsman'; });
          } else {
            Future.delayed(const Duration(milliseconds: 300),
                () { if (mounted) setState(() => _pickerMode = 'new_batsman'); });
          }
        }
        return;
      }

      if (isLegal) {
        if (newTotalBalls >= match.oversPerInnings * 6) {
          await _handleInningsEnd(localInn); return;
        }
        if (overComplete) {
          // Set pickerMode immediately so scoring buttons are blocked before the
          // delayed sheet appears — prevents accidental scoring between deliveries
          setState(() => _pickerMode = 'new_bowler');
        }
      }

      if (localInn.target != null && newTotalRuns >= localInn.target!) {
        await _handleInningsEnd(localInn);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitDelivery(int runs, bool isWicket, [String? dismissalType, String? fielderId]) =>
      _submitDeliveryWithExtra(runs, isWicket, _extra, dismissalType, fielderId);

  void _swapEnds() {
    final inn = _innings;
    if (inn == null) return;
    setState(() => _innings = Innings.copyWith(inn,
      currentStrikerId: inn.currentNonStrikerId,
      currentNonStrikerId: inn.currentStrikerId,
    ));
  }

  // ── Camera device sheet ───────────────────────────────────────
  // Shows the match ID so the camera person can join, with a button
  // to open the camera buffer screen on this same device.
  void _showCameraSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          const Text('📹 Video Clips', style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text)),
          const SizedBox(height: 8),
          const Text(
            'Open this match on the camera device and enter the Match ID below.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.text2, fontSize: 13, height: 1.4)),
          const SizedBox(height: 16),
          // Match ID display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border)),
            child: Column(children: [
              const Text('Match ID', style: TextStyle(
                color: AppColors.text2, fontSize: 11, fontWeight: FontWeight.w600,
                letterSpacing: 0.8)),
              const SizedBox(height: 6),
              Text(widget.matchId, style: const TextStyle(
                color: AppColors.accent, fontSize: 14,
                fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ]),
          ),
          const SizedBox(height: 16),
          // Open camera screen on this device
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            icon: const Icon(Icons.videocam_outlined),
            label: const Text('Use this device as camera'),
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CameraBufferScreen(matchId: widget.matchId),
              ));
            },
          )),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: AppColors.text2)),
          ),
        ]),
      ),
    );
  }

  Future<void> _handleInningsEnd(Innings cur) async {
    try {
      final isSecond = cur.inningsNumber == 2;
      await MatchApi.update(widget.matchId, {'status': isSecond ? 'completed' : 'innings_break'});

      // ── Career stats: accumulate this innings into each player's record ──
      final statsBatch = <Map<String, dynamic>>[];
      cur.batsmanStats.forEach((playerId, bat) {
        if (bat.ballsFaced > 0 || bat.runsScored > 0) {
          statsBatch.add({
            'playerId': playerId,
            'batting': {
              'runsScored': bat.runsScored,
              'ballsFaced': bat.ballsFaced,
              'fours':      bat.fours,
              'sixes':      bat.sixes,
            },
          });
        }
      });
      cur.bowlerStats.forEach((playerId, bowl) {
        if (bowl.legalDeliveries > 0) {
          final idx = statsBatch.indexWhere((e) => e['playerId'] == playerId);
          final bowlMap = {
            'wicketsTaken':    bowl.wicketsTaken,
            'legalDeliveries': bowl.legalDeliveries,
            'runsConceded':    bowl.runsConceded,
          };
          if (idx >= 0) {
            statsBatch[idx]['bowling'] = bowlMap;
          } else {
            statsBatch.add({'playerId': playerId, 'bowling': bowlMap});
          }
        }
      });
      // Fire-and-forget — don't block innings flow on stats update.
      PlayerApi.batchUpdateStats(statsBatch).catchError((_) {});

      // Store innings summary for the commentary separator
      final overs = '${cur.totalBalls ~/ 6}.${cur.totalBalls % 6}';
      final innings1Summary =
          '${_battingTeam?.shortName ?? 'Inn 1'}: ${cur.totalRuns}/${cur.totalWickets} (${overs} ov)';
      CommentaryStore.setInningsSummary(widget.matchId, cur.inningsNumber, innings1Summary);
      if (!isSecond) {
        // Store target string (keyed at 0 for use by separator)
        final target = cur.totalRuns + 1;
        CommentaryStore.setInningsSummary(widget.matchId, 0,
            '${_bowlingTeam?.shortName ?? 'Inn 2'} need $target to win');
      }

      if (!isSecond) {
        final battingTeamName = _battingTeam?.name ?? 'Team';
        final bowlingTeamName = _bowlingTeam?.name ?? 'Team';
        if (mounted) {
          await showModalBottomSheet(
            context: context, isDismissible: false, enableDrag: false,
            backgroundColor: AppColors.bgCard,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            builder: (_) => _InningsBreakSheet(
              innings: cur, battingTeamName: battingTeamName,
              bowlingTeamName: bowlingTeamName, onContinue: () => Navigator.pop(context),
            ),
          );
        }
        await MatchApi.startInnings(widget.matchId, {
          'battingTeamId': cur.bowlingTeamId, 'bowlingTeamId': cur.battingTeamId,
        });
        await _loadMatch();
        _dismissedIds.clear();
        setState(() { _rawBallCount = 0; _pickerMode = 'striker'; });
      } else {
        final m = await MatchApi.get(widget.matchId);
        final resultStr = _calcResult(cur, m);
        if (resultStr.isNotEmpty) {
          await MatchApi.update(widget.matchId, {'result': {'description': resultStr}});
        }
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => _MatchResultScreen(
              matchId: widget.matchId, result: resultStr,
              innings1: m.innings?.firstWhere((i) => i.inningsNumber == 1, orElse: () => cur),
              innings2: cur, team1: m.team1, team2: m.team2,
            ),
          ));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String _calcResult(Innings cur, CricMatch m) {
    final inn1 = m.innings?.firstWhere((i) => i.inningsNumber == 1, orElse: () => cur);
    final inn2 = m.innings?.firstWhere((i) => i.inningsNumber == 2, orElse: () => cur);
    if (inn1 == null || inn2 == null) return 'Match complete';
    final battingFirst  = m.team1?.id == inn1.battingTeamId ? m.team1 : m.team2;
    final battingSecond = m.team1?.id == inn2.battingTeamId ? m.team1 : m.team2;
    final target = inn2.target ?? (inn1.totalRuns + 1);
    if (inn2.totalRuns >= target) {
      final wkts = 10 - inn2.totalWickets;
      return '🏆 ${battingSecond?.name} won by $wkts wicket${wkts != 1 ? "s" : ""}';
    }
    final margin = inn1.totalRuns - inn2.totalRuns;
    if (margin > 0) return '🏆 ${battingFirst?.name} won by $margin run${margin != 1 ? "s" : ""}';
    return '🤝 Match tied!';
  }

  Future<void> _handleUndo() async {
    final inn = _innings;
    if (inn == null) return;
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: const Text('Undo last ball?', style: TextStyle(color: AppColors.text)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: AppColors.text2))),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Undo', style: TextStyle(color: AppColors.wicket))),
      ],
    ));
    if (ok != true) return;
    if (_rawBallCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to undo')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final lastRecordedIndex = _rawBallCount - 1;
      dynamic r;
      try {
        r = await MatchApi.undoDelivery(
          widget.matchId,
          inn.inningsNumber,
          rawBallNumber: lastRecordedIndex,
        );
      } on ApiException catch (e) {
        if (e.statusCode == 400) {
          r = await MatchApi.undoDelivery(widget.matchId, inn.inningsNumber);
        } else {
          rethrow;
        }
      }
      _rawBallCount = (_rawBallCount - 1).clamp(0, 9999);
      if (r is Map<String, dynamic> && r['innings'] is Map<String, dynamic>) {
        setState(() => _innings = Innings.fromJson(r['innings'] as Map<String, dynamic>));
      } else {
        await _loadMatch();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override Widget build(BuildContext context) {
    if (_loading) return const LoadingScreen();
    if (_match == null || _innings == null) return ErrorScreen(message: 'Match not found', onRetry: _loadMatch);

    final inn = _innings!;
    final match = _match!;

    final allDels = inn.deliveries ?? [];
    final curOverNum = inn.totalBalls ~/ 6;
    final curOverDels = allDels.where((d) => d.overNumber == curOverNum).toList();

    final strikerStats = inn.currentStrikerId != null ? inn.batsmanStats[inn.currentStrikerId] : null;
    final bowlerStats  = inn.currentBowlerId  != null ? inn.bowlerStats[inn.currentBowlerId]   : null;
    final quota = _maxOvers(match.format, match.oversPerInnings);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          // Score Header
          Container(
            color: AppColors.bgCard,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(children: [
              Row(children: [
                IconButton(icon: const Icon(Icons.arrow_back_ios, size: 20, color: AppColors.text2), onPressed: () => context.go('/')),
                Expanded(child: Column(children: [
                  Text('${_battingTeam?.shortName ?? "—"} vs ${_bowlingTeam?.shortName ?? "—"}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                  Text('${match.format} · Inn ${inn.inningsNumber}${_saving ? " · saving..." : ""}',
                    style: const TextStyle(color: AppColors.accent, fontSize: 12)),
                ])),
                IconButton(icon: const Icon(Icons.assignment_outlined, color: AppColors.text2),
                  onPressed: () => context.push('/scorecard/${widget.matchId}')),
                IconButton(
                  tooltip: 'Camera device',
                  icon: const Icon(Icons.videocam_outlined, color: AppColors.text2),
                  onPressed: () => _showCameraSheet(),
                ),
                IconButton(
                  tooltip: 'Commentary',
                  icon: Stack(clipBehavior: Clip.none, children: [
                    const Icon(Icons.mic_none_outlined, color: AppColors.text2),
                    if (CommentaryStore.get(widget.matchId).isNotEmpty)
                      Positioned(top: -2, right: -2, child: Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                      )),
                  ]),
                  onPressed: () => context.push(
                    '/commentary/${widget.matchId}?title=${Uri.encodeComponent('${_battingTeam?.shortName ?? ''} vs ${_bowlingTeam?.shortName ?? ''}')}',
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                      backgroundColor: AppColors.bgCard,
                      title: const Text('End match?', style: TextStyle(color: AppColors.text)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('End', style: TextStyle(color: AppColors.wicket))),
                      ],
                    ));
                    if (ok == true) {
                      await MatchApi.update(widget.matchId, {'status': 'completed'});
                      if (mounted) context.go('/scorecard/${widget.matchId}');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.wicketFaint, borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.wicket.withOpacity(0.4))),
                    child: const Text('End', style: TextStyle(color: AppColors.wicket, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_battingTeam?.name ?? '—', style: const TextStyle(color: AppColors.text2, fontSize: 12)),
                  Text(scoreFmt(inn.totalRuns, inn.totalWickets), style: const TextStyle(
                    fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -2, color: AppColors.text)),
                  Text('${ballsToOvers(inn.totalBalls)} ov · CRR ${inn.currentRunRate.toStringAsFixed(2)}',
                    style: const TextStyle(color: AppColors.text2, fontSize: 13)),
                ])),
                if (inn.target != null)
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text('Target', style: TextStyle(color: AppColors.text2, fontSize: 12)),
                    Text('${inn.target}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ball)),
                    Text('Need ${(inn.target! - inn.totalRuns).clamp(0, 9999)} · RRR ${inn.requiredRunRate?.toStringAsFixed(1) ?? "—"}',
                      style: const TextStyle(color: AppColors.ball, fontSize: 12)),
                  ])
                else
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text('Projected', style: TextStyle(color: AppColors.text2, fontSize: 12)),
                    Text(
                      '${CricketUtils.projectedScore(inn.totalRuns, inn.totalBalls, match.oversPerInnings * 6)}',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.accent),
                    ),
                  ]),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Text('Ov ${curOverNum + 1}: ', style: const TextStyle(color: AppColors.text2, fontSize: 12)),
                ...curOverDels.map((d) => BallPip(
                  label: d.isWicket ? 'W' : d.extraType == 'wide' ? 'Wd' : d.extraType == 'no_ball' ? 'Nb' : d.runsBatsman == 0 ? '•' : '${d.runsBatsman}',
                  isWicket: d.isWicket, isExtra: d.extraType != null,
                  isFour: d.runsBatsman == 4, isSix: d.runsBatsman == 6,
                )),
                if (curOverDels.isEmpty) const Text('—', style: TextStyle(color: AppColors.text3, fontSize: 13)),
              ]),
            ]),
          ),

          // Batsmen & Bowler
          Expanded(child: SingleChildScrollView(child: Column(children: [
            Container(
              color: AppColors.bgCard, margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: () => setState(() => _pickerMode = 'striker'),
                    child: Row(children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_getName(inn.currentStrikerId) + (inn.currentStrikerId == null ? ' (tap)' : ' *'),
                        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text, fontSize: 15))),
                      Text('${strikerStats?.runsScored ?? 0}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text)),
                      Text(' (${strikerStats?.ballsFaced ?? 0}b)', style: const TextStyle(color: AppColors.text2, fontSize: 13)),
                    ]),
                  )),
                  GestureDetector(
                    onTap: _swapEnds,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.swap_vert, color: AppColors.accent.withOpacity(0.7), size: 22),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => setState(() => _pickerMode = 'non_striker'),
                  child: Opacity(opacity: 0.7, child: Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(border: Border.all(color: AppColors.text2), shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_getName(inn.currentNonStrikerId), style: const TextStyle(color: AppColors.text, fontSize: 15))),
                    Text('${inn.batsmanStats[inn.currentNonStrikerId]?.runsScored ?? "—"}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text)),
                    Text(' (${inn.batsmanStats[inn.currentNonStrikerId]?.ballsFaced ?? 0}b)', style: const TextStyle(color: AppColors.text2, fontSize: 13)),
                  ])),
                ),
                const Divider(height: 20, color: AppColors.border),
                GestureDetector(
                  onTap: () => setState(() => _pickerMode = 'new_bowler'),
                  child: Row(children: [
                    const Icon(Icons.sports_cricket, size: 16, color: AppColors.text2),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      _getName(inn.currentBowlerId) + (quota != null && bowlerStats != null ? '  (${quota - (bowlerStats.legalDeliveries ~/ 6)} ov left)' : ''),
                      style: const TextStyle(color: AppColors.text2, fontSize: 13))),
                    Text(bowlerStats != null
                      ? '${bowlerStats.oversBowled}-${bowlerStats.maidenOvers}-${bowlerStats.runsConceded}-${bowlerStats.wicketsTaken}'
                      : '—', style: const TextStyle(color: AppColors.text2, fontSize: 13)),
                  ]),
                ),
              ]),
            ),

            // Extras bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                for (final e in [('Wide', 'wide'), ('No Ball', 'no_ball'), ('Leg Bye', 'leg_bye'), ('Bye', 'bye')])
                  Expanded(child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        if (_extra == e.$2) { setState(() => _extra = null); return; }
                        setState(() => _extra = e.$2);
                        if (e.$2 == 'no_ball') { Future.microtask(_showNoBallPicker); }
                        else if (e.$2 == 'wide') { Future.microtask(_showWidePicker); }
                        else if (e.$2 == 'bye' || e.$2 == 'leg_bye') { Future.microtask(_showByePicker); }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _extra == e.$2 ? AppColors.ball.withOpacity(0.2) : AppColors.bgElevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _extra == e.$2 ? AppColors.ball : AppColors.border),
                        ),
                        child: Text(e.$1, textAlign: TextAlign.center, style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: _extra == e.$2 ? AppColors.ball : AppColors.text2)),
                      ),
                    ),
                  )),
              ]),
            ),

            // Voice + Undo row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(children: [
                // Mic button
                if (_speechAvailable) GestureDetector(
                  onTap: _saving ? null : (_isListening ? _stopListening : _startListening),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: _isListening ? AppColors.accent.withOpacity(0.15) : AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isListening ? AppColors.accent : AppColors.border,
                        width: _isListening ? 1.5 : 1,
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        size: 16,
                        color: _isListening ? AppColors.accent : AppColors.text2,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isListening
                          ? (_voiceText.isEmpty ? 'Listening…' : _voiceText)
                          : 'Voice',
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: _isListening ? AppColors.accent : AppColors.text2,
                        ),
                      ),
                    ]),
                  ),
                ),
                const Spacer(),
                // Undo button
                GestureDetector(
                  onTap: _saving ? null : _handleUndo,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.undo_rounded, size: 16,
                        color: _saving ? AppColors.text3 : AppColors.text2),
                      const SizedBox(width: 5),
                      Text('Undo', style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: _saving ? AppColors.text3 : AppColors.text2)),
                    ]),
                  ),
                ),
              ]),
            ),

            // Run buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: GridView.count(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4, mainAxisSpacing: 10, crossAxisSpacing: 10,
                children: [
                  _RunBtn('•', 0, 'dot', AppColors.bgElevated, AppColors.text2),
                  _RunBtn('1', 1, 'run', AppColors.bgElevated, AppColors.text),
                  _RunBtn('2', 2, 'run', AppColors.bgElevated, AppColors.text),
                  _RunBtn('3', 3, 'run', AppColors.bgElevated, AppColors.text),
                  _RunBtn('4', 4, 'four', AppColors.four.withOpacity(0.12), AppColors.four),
                  _RunBtn('5', 5, 'run', AppColors.bgElevated, AppColors.text),
                  _RunBtn('6', 6, 'six', AppColors.six.withOpacity(0.12), AppColors.six),
                  _RunBtn('W', 0, 'wicket', AppColors.wicketFaint, AppColors.wicket),
                ].asMap().entries.map((e) {
                  final btn = e.value;
                  return GestureDetector(
                    onTap: _saving ? null : () => _handleBall(btn.runs, btn.type),
                    child: Container(
                      decoration: BoxDecoration(color: btn.bg, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: btn.fg.withOpacity(0.3))),
                      child: Center(
                        child: Text(btn.label, style: TextStyle(fontSize: btn.label == 'W' ? 24 : 28,
                          fontWeight: FontWeight.w800, color: btn.fg)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
          ]))),
        ]),
      ),

      bottomSheet: _showDismissal ? _DismissalSheet(
        batsmanName: _getName(inn.currentStrikerId),
        fielders: _bowlingTeam?.players ?? [],
        onSelect: (type, fielderId) => _submitDelivery(0, true, type, fielderId),
        onCancel: () => setState(() => _showDismissal = false),
      ) : _pickerMode == 'run_out_who' ? _RunOutWhoSheet(
        striker:    _getName(inn.currentStrikerId),
        nonStriker: _getName(inn.currentNonStrikerId),
        onSelect: (strikerOut) {
          final outId      = strikerOut ? inn.currentStrikerId    : inn.currentNonStrikerId;
          final survivorId = strikerOut ? inn.currentNonStrikerId : inn.currentStrikerId;
          if (outId != null) _dismissedIds.add(outId);
          setState(() {
            _runOutStrikerDismissed = strikerOut;
            // Survivor stays, dismissed slot becomes null for new batsman
            _innings = Innings.copyWith(inn,
              currentStrikerId:    strikerOut ? null     : survivorId,
              currentNonStrikerId: strikerOut ? survivorId : null,
              clearStriker:        strikerOut,
              clearNonStriker:     !strikerOut,
            );
            _pickerMode = 'new_batsman';
          });
        },
      ) : _pickerMode == 'striker_confirm' ? _StrikerConfirmSheet(
        strikerName: _getName(inn.currentStrikerId),
        onConfirm: (isCorrect) {
          setState(() {
            if (!isCorrect) {
              // Swap striker and non-striker
              _innings = Innings.copyWith(inn,
                currentStrikerId:    inn.currentNonStrikerId,
                currentNonStrikerId: inn.currentStrikerId,
              );
            }
            _runOutStrikerDismissed = null;
            _pickerMode = null;
          });
        },
      ) : _pickerMode != null ? _PlayerPickerSheet(
        title: _pickerTitle,
        players: _pickerMode == 'bowler' || _pickerMode == 'new_bowler' ? _availBowlers : _availBatters,
        innings: inn,
        isBowler: _pickerMode == 'bowler' || _pickerMode == 'new_bowler',
        quota: quota,
        onSelect: _onPickPlayer,
        onCancel: (_pickerMode == 'new_bowler' || _pickerMode == 'bowler') ? () => setState(() => _pickerMode = null) : null,
      ) : null,
    );
  }

  String get _pickerTitle {
    switch (_pickerMode) {
      case 'striker':     return 'Select opening batsman';
      case 'non_striker': return 'Select non-striker';
      case 'bowler':      return 'Select opening bowler';
      case 'new_batsman':
        final inn = _innings;
        if (inn?.currentStrikerId == null) return 'New batsman — will face next ball';
        return 'New batsman — comes in at non-striker end';
      default:            return 'Over ${(_innings?.totalBalls ?? 0) ~/ 6} — Select bowler';
    }
  }
}

// ── Run Out — Who Was Out? ─────────────────────────────────────
class _RunOutWhoSheet extends StatelessWidget {
  final String striker, nonStriker;
  final void Function(bool strikerOut) onSelect;
  const _RunOutWhoSheet({required this.striker, required this.nonStriker, required this.onSelect});

  @override Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('RUN OUT — WHO WAS OUT?', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w800,
          color: AppColors.text2, letterSpacing: 1.2)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _btn(striker, true)),
          const SizedBox(width: 12),
          Expanded(child: _btn(nonStriker, false)),
        ]),
      ]),
    );
  }

  Widget _btn(String name, bool isStriker) => GestureDetector(
    onTap: () => onSelect(isStriker),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.wicketFaint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.wicket.withOpacity(0.4)),
      ),
      child: Column(children: [
        Text(name, style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text)),
        const SizedBox(height: 4),
        Text(isStriker ? 'Striker' : 'Non-striker',
          style: const TextStyle(fontSize: 11, color: AppColors.text2)),
      ]),
    ),
  );
}

// ── Striker confirmation (shown after bowler selected on over-end wicket) ──
class _StrikerConfirmSheet extends StatelessWidget {
  final String strikerName;
  final void Function(bool isCorrect) onConfirm;
  const _StrikerConfirmSheet({required this.strikerName, required this.onConfirm});

  @override Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🏏', style: TextStyle(fontSize: 28)),
        const SizedBox(height: 12),
        RichText(text: TextSpan(
          style: const TextStyle(fontSize: 17, color: AppColors.text, height: 1.4),
          children: [
            const TextSpan(text: 'Is '),
            TextSpan(text: strikerName,
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent)),
            const TextSpan(text: ' on strike?'),
          ],
        )),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: _btn('Yes', true, AppColors.accent, AppColors.accentFaint)),
          const SizedBox(width: 12),
          Expanded(child: _btn('No, swap', false, AppColors.text2, AppColors.bgElevated)),
        ]),
      ]),
    );
  }

  Widget _btn(String label, bool confirm, Color fg, Color bg) => GestureDetector(
    onTap: () => onConfirm(confirm),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withOpacity(0.4)),
      ),
      child: Center(child: Text(label, style: TextStyle(
        fontSize: 15, fontWeight: FontWeight.w800, color: fg))),
    ),
  );
}

class _RunBtn {
  final String label, type;
  final int runs;
  final Color bg, fg;
  const _RunBtn(this.label, this.runs, this.type, this.bg, this.fg);
}

class _DismissalSheet extends StatefulWidget {
  final String batsmanName;
  final List<Player> fielders;
  final void Function(String type, String? fielderId) onSelect;
  final VoidCallback onCancel;

  const _DismissalSheet({required this.batsmanName, required this.fielders, required this.onSelect, required this.onCancel});

  @override State<_DismissalSheet> createState() => _DismissalSheetState();
}

class _DismissalSheetState extends State<_DismissalSheet> {
  String? _selectedType;

  static const _types = [
    ('Bowled',       'bowled',       false),
    ('Caught',       'caught',       true),
    ('LBW',          'lbw',          false),
    ('Run Out',      'run_out',      true),
    ('Stumped',      'stumped',      true),
    ('Hit Wicket',   'hit_wicket',   false),
    ('Retired Hurt', 'retired_hurt', false),
  ];


  @override Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            _selectedType == null ? 'How was ${widget.batsmanName} out?' : 'Select fielder',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
        ),
        if (_selectedType == null) ...[
          ..._types.map((t) => ListTile(
            dense: true,
            leading: Icon(t.$3 ? Icons.person_outline : Icons.sports_cricket_outlined, color: AppColors.text2, size: 18),
            title: Text(t.$1, style: const TextStyle(color: AppColors.text, fontSize: 15)),
            trailing: t.$3 ? const Text('+ fielder', style: TextStyle(color: AppColors.text2, fontSize: 11)) : null,
            onTap: () {
              if (t.$3) { setState(() => _selectedType = t.$2); }
              else { widget.onSelect(t.$2, null); }
            },
          )),
        ] else ...[
          Flexible(child: ListView(shrinkWrap: true, children: [
            ListTile(
              dense: true,
              leading: const Icon(Icons.person_off_outlined, color: AppColors.text2, size: 18),
              title: const Text('Unknown / Skip', style: TextStyle(color: AppColors.text2, fontSize: 14)),
              onTap: () => widget.onSelect(_selectedType!, null),
            ),
            const Divider(color: AppColors.border, height: 1),
            ...widget.fielders.map((p) => ListTile(
              dense: true,
              leading: Container(width: 28, height: 28,
                decoration: BoxDecoration(color: AppColors.bgElevated, shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border)),
                child: Center(child: Text(p.jerseyNumber != null ? '${p.jerseyNumber}' : p.name[0],
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.text2)))),
              title: Text(p.name, style: const TextStyle(color: AppColors.text, fontSize: 14)),
              onTap: () => widget.onSelect(_selectedType!, p.id),
            )),
          ])),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: OutlinedButton(
            onPressed: _selectedType != null ? () => setState(() => _selectedType = null) : widget.onCancel,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.text2,
              side: const BorderSide(color: AppColors.border),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(_selectedType != null ? '← Back' : 'Cancel'),
          ),
        ),
      ]),
    );
  }
}

class _PlayerPickerSheet extends StatelessWidget {
  final String title;
  final List<Player> players;
  final Innings innings;
  final bool isBowler;
  final int? quota;
  final void Function(Player) onSelect;
  final VoidCallback? onCancel;

  const _PlayerPickerSheet({required this.title, required this.players, required this.innings,
    required this.isBowler, this.quota, required this.onSelect, this.onCancel});

  @override Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text))),
        if (isBowler && quota != null)
          Text('Max $quota overs per bowler', style: const TextStyle(color: AppColors.ball, fontSize: 12)),
        Flexible(child: players.isEmpty
          ? const Padding(padding: EdgeInsets.all(24),
              child: Text('No eligible players', style: TextStyle(color: AppColors.text2)))
          : ListView.builder(
              shrinkWrap: true, itemCount: players.length,
              itemBuilder: (_, i) {
                final p = players[i];
                final bs = innings.batsmanStats[p.id];
                final ws = innings.bowlerStats[p.id];
                return ListTile(
                  leading: Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: AppColors.bgElevated, shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border)),
                    child: Center(child: Text('${i + 1}', style: const TextStyle(
                      color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 13)))),
                  title: Text(p.name, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                  trailing: isBowler && ws != null
                    ? Text('${ws.oversBowled} ov · ${ws.runsConceded}r', style: const TextStyle(color: AppColors.text2, fontSize: 12))
                    : !isBowler && bs != null
                      ? Text('${bs.runsScored} (${bs.ballsFaced}b)', style: const TextStyle(color: AppColors.text2, fontSize: 12))
                      : Text(isBowler ? '${quota ?? "∞"} ov left' : 'yet to bat', style: const TextStyle(color: AppColors.accent, fontSize: 12)),
                  onTap: () => onSelect(p),
                );
              },
            ),
        ),
        if (onCancel != null) Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.text2,
              side: const BorderSide(color: AppColors.border),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Cancel'),
          ),
        ),
      ]),
    );
  }
}

class _InningsBreakSheet extends StatelessWidget {
  final Innings innings;
  final String battingTeamName, bowlingTeamName;
  final VoidCallback onContinue;

  const _InningsBreakSheet({required this.innings, required this.battingTeamName,
    required this.bowlingTeamName, required this.onContinue});

  @override Widget build(BuildContext context) {
    final target = innings.totalRuns + 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        const Text('🏏 Innings Break', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border)),
          child: Column(children: [
            Text(battingTeamName, style: const TextStyle(color: AppColors.text2, fontSize: 13)),
            const SizedBox(height: 4),
            Text(scoreFmt(innings.totalRuns, innings.totalWickets), style: const TextStyle(
              fontSize: 48, fontWeight: FontWeight.w800, letterSpacing: -2, color: AppColors.text)),
            Text('${ballsToOvers(innings.totalBalls)} overs', style: const TextStyle(color: AppColors.text2, fontSize: 14)),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.accent.withOpacity(0.3))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('🎯 ', style: TextStyle(fontSize: 20)),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bowlingTeamName, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 15)),
              Text('need $target runs to win', style: const TextStyle(color: AppColors.text2, fontSize: 13)),
            ]),
          ]),
        ),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, height: 52,
          child: ElevatedButton(onPressed: onContinue,
            child: const Text('Start 2nd Innings →', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
      ]),
    );
  }
}

class _MatchResultScreen extends StatefulWidget {
  final String matchId, result;
  final Innings? innings1, innings2;
  final Team? team1, team2;

  const _MatchResultScreen({required this.matchId, required this.result,
    this.innings1, this.innings2, this.team1, this.team2});

  @override State<_MatchResultScreen> createState() => _MatchResultScreenState();
}

class _MatchResultScreenState extends State<_MatchResultScreen> {
  String? _motmPlayerId;
  bool    _motmSaved = false;

  Innings?  get innings1 => widget.innings1;
  Innings?  get innings2 => widget.innings2;
  Team?     get team1    => widget.team1;
  Team?     get team2    => widget.team2;

  String _teamName(String? id) {
    if (id == null) return '—';
    if (id == team1?.id) return team1?.name ?? '—';
    if (id == team2?.id) return team2?.name ?? '—';
    return '—';
  }

  String _playerName(String? id) {
    if (id == null) return '—';
    final all = [...(team1?.players ?? []), ...(team2?.players ?? [])];
    return all.firstWhere((p) => p.id == id,
        orElse: () => Player(id: id, teamId: '', name: id, shortName: id)).name;
  }

  // Top performers from both innings — suggest top 3
  List<({String id, String name, String perf, int score})> get _suggestions {
    final list = <({String id, String name, String perf, int score})>[];
    for (final inn in [innings1, innings2]) {
      if (inn == null) continue;
      // Top batsman
      inn.batsmanStats.forEach((id, s) {
        if (s.runsScored > 0) {
          list.add((id: id, name: _playerName(id),
            perf: '${s.runsScored} runs (${s.ballsFaced}b)', score: s.runsScored * 10));
        }
      });
      // Top bowler
      inn.bowlerStats.forEach((id, s) {
        if (s.wicketsTaken > 0) {
          list.add((id: id, name: _playerName(id),
            perf: '${s.wicketsTaken}/${s.runsConceded} (${s.oversBowled} ov)',
            score: s.wicketsTaken * 25 + (30 - s.runsConceded).clamp(0, 30)));
        }
      });
    }
    list.sort((a, b) => b.score.compareTo(a.score));
    // Deduplicate by id, keep top 3
    final seen = <String>{};
    return list.where((e) => seen.add(e.id)).take(3).toList();
  }

  Future<void> _saveMotm(String playerId) async {
    setState(() => _motmPlayerId = playerId);
    try {
      await MatchApi.update(widget.matchId, {'manOfTheMatch': playerId});
      setState(() => _motmSaved = true);
    } catch (_) {}
  }

  @override Widget build(BuildContext context) {
    final isWin = widget.result.contains('won');
    final isTie = widget.result.contains('tied');
    final suggestions = _suggestions;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(child: Column(children: [
        Container(
          width: double.infinity, padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: isWin ? AppColors.accent.withOpacity(0.1) : isTie ? AppColors.ball.withOpacity(0.1) : AppColors.bgCard,
            border: Border(bottom: BorderSide(color: isWin ? AppColors.accent : isTie ? AppColors.ball : AppColors.border))),
          child: Column(children: [
            Text(isWin ? '🏆' : isTie ? '🤝' : '🏏', style: const TextStyle(fontSize: 64)),
            const SizedBox(height: 12),
            Text(widget.result.replaceAll('🏆 ', '').replaceAll('🤝 ', ''), textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                color: isWin ? AppColors.accent : isTie ? AppColors.ball : AppColors.text)),
          ]),
        ),
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          if (innings1 != null) _InningsSummaryCard(innings: innings1!, teamName: _teamName(innings1!.battingTeamId), label: '1st Innings'),
          if (innings2 != null) _InningsSummaryCard(innings: innings2!, teamName: _teamName(innings2!.battingTeamId), label: '2nd Innings'),
          const SizedBox(height: 8),

          // ── Man of the Match ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _motmPlayerId != null ? AppColors.ball : AppColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('⭐', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                const Expanded(child: Text('Man of the Match',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
                if (_motmSaved) const Icon(Icons.check_circle, color: Colors.green, size: 18),
              ]),
              if (_motmPlayerId != null) ...[
                const SizedBox(height: 6),
                Text(_playerName(_motmPlayerId),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ball)),
              ],
              if (!_motmSaved) ...[
                const SizedBox(height: 12),
                if (suggestions.isEmpty)
                  const Text('No stats available — score some balls first',
                    style: TextStyle(color: AppColors.text2, fontSize: 13))
                else ...[
                  const Text('SUGGESTED', style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.text2, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  ...suggestions.map((s) => GestureDetector(
                    onTap: () => _saveMotm(s.id),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _motmPlayerId == s.id ? AppColors.ball.withOpacity(0.1) : AppColors.bgElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _motmPlayerId == s.id ? AppColors.ball : AppColors.border,
                          width: _motmPlayerId == s.id ? 1.5 : 1,
                        ),
                      ),
                      child: Row(children: [
                        const Text('🏏', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.name, style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.text)),
                          Text(s.perf, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                        ])),
                        if (_motmPlayerId == s.id)
                          const Icon(Icons.star, color: AppColors.ball, size: 20),
                      ]),
                    ),
                  )),
                ],
                const SizedBox(height: 4),
                const Text('Tap to select · saved against the match',
                  style: TextStyle(fontSize: 11, color: AppColors.text3)),
              ],
            ]),
          ),
          const SizedBox(height: 8),
        ])),
        Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          SizedBox(width: double.infinity, height: 52,
            child: ElevatedButton.icon(
              onPressed: () => context.go('/scorecard/${widget.matchId}'),
              icon: const Icon(Icons.assignment_outlined, size: 18),
              label: const Text('Full scorecard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, height: 48,
            child: OutlinedButton(
              onPressed: () => context.go('/?t=${DateTime.now().millisecondsSinceEpoch}'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.text2,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Back to home'))),
        ])),
      ])),
    );
  }
}

class _InningsSummaryCard extends StatelessWidget {
  final Innings innings;
  final String teamName, label;
  const _InningsSummaryCard({required this.innings, required this.teamName, required this.label});

  @override Widget build(BuildContext context) {
    final topBatsman = innings.batsmanStats.values.where((b) => !b.didNotBat)
      .fold<BatsmanStats?>(null, (best, b) => best == null || b.runsScored > best.runsScored ? b : best);
    final topBowler = innings.bowlerStats.values
      .fold<BowlerStats?>(null, (best, b) => best == null || b.wicketsTaken > best.wicketsTaken ||
        (b.wicketsTaken == best.wicketsTaken && b.runsConceded < best.runsConceded) ? b : best);

    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 12, fontWeight: FontWeight.w600)),
            Text(teamName, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 16)),
          ])),
          Text(scoreFmt(innings.totalRuns, innings.totalWickets), style: const TextStyle(
            fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1, color: AppColors.text)),
        ]),
        Text('${ballsToOvers(innings.totalBalls)} overs · CRR ${innings.currentRunRate.toStringAsFixed(1)}',
          style: const TextStyle(color: AppColors.text2, fontSize: 13)),
        if (topBatsman != null || topBowler != null) ...[
          const Divider(height: 16, color: AppColors.border),
          if (topBatsman != null) Text('🏏 Top scorer: ${topBatsman.runsScored} (${topBatsman.ballsFaced}b)',
            style: const TextStyle(color: AppColors.accent, fontSize: 13)),
          if (topBowler != null) Text('🎳 Best bowler: ${topBowler.wicketsTaken}/${topBowler.runsConceded} (${topBowler.oversBowled} ov)',
            style: const TextStyle(color: AppColors.ball, fontSize: 13)),
        ],
      ]),
    );
  }
}

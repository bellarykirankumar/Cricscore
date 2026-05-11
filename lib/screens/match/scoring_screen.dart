import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';

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

  @override void initState() { super.initState(); _loadMatch(); }

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
      final s = inn.batsmanStats[p.id];
      return (s == null || !s.isOut) && p.id != inn.currentStrikerId && p.id != inn.currentNonStrikerId;
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

  int? _maxOvers(String format, int total) {
    if (format == 'Test') return null;
    if (format == 'T20') return 4;
    if (format == 'T10') return 2;
    if (format == 'ODI') return 10;
    return (total / 5).floor().clamp(1, 999);
  }

  void _onPickPlayer(Player player) {
    final inn = _innings;
    if (inn == null) return;
    HapticFeedback.selectionClick();
    if (_pickerMode == 'striker' || _pickerMode == 'new_batsman') {
      setState(() => _innings = Innings.copyWith(inn, currentStrikerId: player.id));
      if (_pickerMode == 'striker' && inn.currentNonStrikerId == null) {
        setState(() => _pickerMode = 'non_striker'); return;
      }
      if (_pickerMode == 'striker' && inn.currentBowlerId == null) {
        setState(() => _pickerMode = 'bowler'); return;
      }
      if (_pickerMode == 'new_batsman' && _pendingBowlerChange) {
        setState(() { _pendingBowlerChange = false; _pickerMode = null; });
        Future.delayed(const Duration(milliseconds: 300), () => setState(() => _pickerMode = 'new_bowler'));
        return;
      }
    } else if (_pickerMode == 'non_striker') {
      setState(() => _innings = Innings.copyWith(inn, currentNonStrikerId: player.id));
      if (inn.currentBowlerId == null) { setState(() => _pickerMode = 'bowler'); return; }
    } else if (_pickerMode == 'bowler' || _pickerMode == 'new_bowler') {
      setState(() => _innings = Innings.copyWith(inn, currentBowlerId: player.id));
    }
    setState(() => _pickerMode = null);
  }

  void _handleBall(int runs, String type) {
    final inn = _innings;
    if (inn == null) return;
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


  Future<void> _submitDeliveryWithExtra(int runs, bool isWicket, String? extraType, [String? dismissalType, String? fielderId]) async {
    final match = _match;
    final inn = _innings;
    if (match == null || inn == null) return;
    if (inn.currentStrikerId == null || inn.currentNonStrikerId == null || inn.currentBowlerId == null) return;

    setState(() { _saving = true; _showDismissal = false; });
    HapticFeedback.lightImpact();

    final extra = extraType;
    final isLegal = extra != 'wide' && extra != 'no_ball';
    final runsBat = (extra == 'wide' || extra == 'leg_bye' || extra == 'bye') ? 0 : runs;
    final runsExt = extra == 'no_ball' ? (1 + runs) : extra == 'wide' ? (1 + runs)
      : extra == 'bye' || extra == 'leg_bye' ? runs : 0;
    final runsTotal = extra == 'no_ball' ? (1 + runs) : extra == 'wide' ? (1 + runs) : runs;

    try {
      final result = await MatchApi.recordDelivery(widget.matchId, inn.inningsNumber, {
        'batsmanId':       inn.currentStrikerId,
        'nonStrikerId':    inn.currentNonStrikerId,
        'bowlerId':        inn.currentBowlerId,
        'runsBatsman':     runsBat,
        'runsExtras':      runsExt,
        'runsTotal':       runsTotal,
        if (extra != null) 'extraType': extra,
        'isWicket':        isWicket,
        'isLegalDelivery': isLegal,
        'rawBallNumber':   _rawBallCount,
        if (isWicket && dismissalType != null) 'dismissal': {
          'type': dismissalType, 'batsmanId': inn.currentStrikerId, 'bowlerId': inn.currentBowlerId,
          if (fielderId != null) 'fielderId': fielderId,
        },
      });

      _rawBallCount++;
      final rawInn = Innings.fromJson(result['innings'] as Map<String, dynamic>? ?? {});
      final updInn = Innings.copyWith(rawInn,
        currentStrikerId: rawInn.currentStrikerId ?? inn.currentStrikerId,
        currentNonStrikerId: rawInn.currentNonStrikerId ?? inn.currentNonStrikerId,
        currentBowlerId: rawInn.currentBowlerId ?? inn.currentBowlerId,
      );

      // Use API deliveries if returned, otherwise keep existing + build one locally
      final apiDels = updInn.deliveries ?? [];
      final existingDels = inn.deliveries ?? [];
      final mergedDels = apiDels.isNotEmpty ? apiDels : [
        ...existingDels,
        Delivery(
          overNumber: inn.totalBalls ~/ 6,
          ballNumber: inn.totalBalls % 6,
          batsmanId: inn.currentStrikerId ?? '',
          nonStrikerId: inn.currentNonStrikerId ?? '',
          bowlerId: inn.currentBowlerId ?? '',
          runsBatsman: runsBat,
          runsExtras: runsExt,
          runsTotal: runsTotal,
          isWicket: isWicket,
          isLegalDelivery: isLegal,
          extraType: extra,
        ),
      ];
      if (isLegal && !isWicket && runsBat.isOdd) {
        setState(() => _innings = Innings.copyWith(updInn,
          currentStrikerId: inn.currentNonStrikerId,
          currentNonStrikerId: inn.currentStrikerId,
          deliveries: mergedDels,
        ));
      } else {
        setState(() => _innings = Innings.copyWith(updInn,
          deliveries: mergedDels,
        ));
      }

      if (isLegal) {
        final nb = updInn.totalBalls;
        if (nb >= match.oversPerInnings * 6) { await _handleInningsEnd(updInn); return; }
        if (nb % 6 == 0) {
          _swapEnds();
          Future.delayed(const Duration(milliseconds: 300), () => setState(() => _pickerMode = 'new_bowler'));
        }
      }

      if (updInn.target != null && updInn.totalRuns >= updInn.target!) {
        await _handleInningsEnd(updInn);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitDelivery(int runs, bool isWicket, [String? dismissalType, String? fielderId]) async {
    final match = _match;
    final inn = _innings;
    if (match == null || inn == null) return;
    if (inn.currentStrikerId == null || inn.currentNonStrikerId == null || inn.currentBowlerId == null) return;

    setState(() { _saving = true; _showDismissal = false; });
    HapticFeedback.lightImpact();

    final extra = _extra;
    final isLegal = extra != 'wide' && extra != 'no_ball';
    final runsBat = (extra == 'wide' || extra == 'leg_bye' || extra == 'bye') ? 0 : runs;
    final runsExt = extra == 'no_ball' ? (1 + runs) : extra == 'wide' ? (1 + runs)
      : extra == 'bye' || extra == 'leg_bye' ? runs : 0;
    final runsTotal = extra == 'no_ball' ? (1 + runs) : extra == 'wide' ? (1 + runs) : runs;

    try {
      final result = await MatchApi.recordDelivery(widget.matchId, inn.inningsNumber, {
        'batsmanId':       inn.currentStrikerId,
        'nonStrikerId':    inn.currentNonStrikerId,
        'bowlerId':        inn.currentBowlerId,
        'runsBatsman':     runsBat,
        'runsExtras':      runsExt,
        'runsTotal':       runsTotal,
        if (extra != null) 'extraType': extra,
        'isWicket':        isWicket,
        'isLegalDelivery': isLegal,
        'rawBallNumber':   _rawBallCount,
        if (isWicket && dismissalType != null) 'dismissal': {
          'type': dismissalType, 'batsmanId': inn.currentStrikerId, 'bowlerId': inn.currentBowlerId,
          if (fielderId != null) 'fielderId': fielderId,
        },
      });

      _rawBallCount++;
      final rawInn = Innings.fromJson(result['innings'] as Map<String, dynamic>? ?? {});
      // Preserve current player IDs if API returns null
      final updInn = Innings.copyWith(rawInn,
        currentStrikerId: rawInn.currentStrikerId ?? inn.currentStrikerId,
        currentNonStrikerId: rawInn.currentNonStrikerId ?? inn.currentNonStrikerId,
        currentBowlerId: rawInn.currentBowlerId ?? inn.currentBowlerId,
      );

      // Use API deliveries if returned, otherwise keep existing + build one locally
      final apiDels = updInn.deliveries ?? [];
      final existingDels = inn.deliveries ?? [];
      final mergedDels = apiDels.isNotEmpty ? apiDels : [
        ...existingDels,
        Delivery(
          overNumber: inn.totalBalls ~/ 6,
          ballNumber: inn.totalBalls % 6,
          batsmanId: inn.currentStrikerId ?? '',
          nonStrikerId: inn.currentNonStrikerId ?? '',
          bowlerId: inn.currentBowlerId ?? '',
          runsBatsman: runsBat,
          runsExtras: runsExt,
          runsTotal: runsTotal,
          isWicket: isWicket,
          isLegalDelivery: isLegal,
          extraType: extra,
        ),
      ];
      if (isLegal && !isWicket && runsBat.isOdd) {
        setState(() => _innings = Innings.copyWith(updInn,
          currentStrikerId: inn.currentNonStrikerId,
          currentNonStrikerId: inn.currentStrikerId,
          deliveries: mergedDels,
        ));
      } else {
        setState(() => _innings = Innings.copyWith(updInn,
          deliveries: mergedDels,
        ));
      }
      setState(() => _extra = null);

      if (isWicket) {
        if (updInn.totalWickets >= 10) { await _handleInningsEnd(updInn); return; }
        final nb = updInn.totalBalls;
        final isInningsOver = isLegal && nb >= match.oversPerInnings * 6;
        if (isInningsOver) { await _handleInningsEnd(updInn); return; }
        final overDone = isLegal && nb % 6 == 0;
        if (overDone) {
          _swapEnds();
          setState(() { _pendingBowlerChange = true; _pickerMode = 'new_batsman'; });
        } else {
          Future.delayed(const Duration(milliseconds: 300), () => setState(() => _pickerMode = 'new_batsman'));
        }
        return;
      }

      if (isLegal) {
        final nb = updInn.totalBalls;
        if (nb >= match.oversPerInnings * 6) { await _handleInningsEnd(updInn); return; }
        if (nb % 6 == 0) {
          _swapEnds();
          Future.delayed(const Duration(milliseconds: 300), () => setState(() => _pickerMode = 'new_bowler'));
        }
      }

      if (updInn.target != null && updInn.totalRuns >= updInn.target!) {
        await _handleInningsEnd(updInn);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _swapEnds() {
    final inn = _innings;
    if (inn == null) return;
    setState(() => _innings = Innings.copyWith(inn,
      currentStrikerId: inn.currentNonStrikerId,
      currentNonStrikerId: inn.currentStrikerId,
    ));
  }

  void _swapBatters() {
    final inn = _innings;
    if (inn == null) return;
    if (inn.currentStrikerId == null || inn.currentNonStrikerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select both batters before swapping')),
      );
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _innings = Innings.copyWith(
        inn,
        currentStrikerId: inn.currentNonStrikerId,
        currentNonStrikerId: inn.currentStrikerId,
      );
      _pickerMode = null;
    });
  }

  String? _missingPlayerPicker(Innings inn) {
    if (inn.currentStrikerId == null) return 'striker';
    if (inn.currentNonStrikerId == null) return 'non_striker';
    if (inn.currentBowlerId == null) return 'bowler';
    return null;
  }

  String? _stringField(Map<String, dynamic>? data, String key) {
    final value = data?[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  Innings _resolveUndoInnings(Innings previous, Map<String, dynamic> response) {
    final updated = Innings.fromJson(response['innings'] as Map<String, dynamic>);
    final undoneRaw = response['undone'];
    final undone = undoneRaw is Map<String, dynamic> ? undoneRaw : null;
    final currentDeliveries = previous.deliveries ?? const <Delivery>[];
    final apiDeliveries = updated.deliveries;
    final resolvedDeliveries = apiDeliveries != null && apiDeliveries.isNotEmpty
        ? apiDeliveries
        : currentDeliveries.isEmpty
            ? null
            : currentDeliveries.take(currentDeliveries.length - 1).toList();
    final lastRemaining = resolvedDeliveries == null || resolvedDeliveries.isEmpty
        ? null
        : resolvedDeliveries.last;

    return Innings.copyWith(
      updated,
      currentStrikerId: _stringField(undone, 'batsmanId') ??
          updated.currentStrikerId ??
          lastRemaining?.batsmanId ??
          previous.currentStrikerId,
      currentNonStrikerId: _stringField(undone, 'nonStrikerId') ??
          updated.currentNonStrikerId ??
          lastRemaining?.nonStrikerId ??
          previous.currentNonStrikerId,
      currentBowlerId: _stringField(undone, 'bowlerId') ??
          updated.currentBowlerId ??
          lastRemaining?.bowlerId ??
          previous.currentBowlerId,
      deliveries: resolvedDeliveries,
    );
  }

  Future<void> _handleInningsEnd(Innings cur) async {
    try {
      final isSecond = cur.inningsNumber == 2;
      await MatchApi.update(widget.matchId, {'status': isSecond ? 'completed' : 'innings_break'});

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
        final resolved = _resolveUndoInnings(inn, r);
        setState(() {
          _innings = resolved;
          _pickerMode = _missingPlayerPicker(resolved);
        });
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
                    Text('${inn.projectedScore ?? 0}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.accent)),
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
                GestureDetector(
                  onTap: () => setState(() => _pickerMode = 'striker'),
                  child: Row(children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_getName(inn.currentStrikerId) + (inn.currentStrikerId == null ? ' (tap)' : ' *'),
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text, fontSize: 15))),
                    Text('${strikerStats?.runsScored ?? 0}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text)),
                    Text(' (${strikerStats?.ballsFaced ?? 0}b)', style: const TextStyle(color: AppColors.text2, fontSize: 13)),
                  ]),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _saving ? null : _swapBatters,
                    icon: const Icon(Icons.swap_vert, size: 16),
                    label: const Text('Swap batters'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
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

            // Run buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                    onLongPress: btn.type == 'dot' ? () => _handleUndo() : null,
                    child: Container(
                      decoration: BoxDecoration(color: btn.bg, borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: btn.fg.withOpacity(0.3))),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(btn.label, style: TextStyle(fontSize: btn.label == 'W' ? 24 : 28,
                          fontWeight: FontWeight.w800, color: btn.fg)),
                        if (btn.type == 'dot') Text('hold=undo', style: TextStyle(fontSize: 9, color: btn.fg.withOpacity(0.5))),
                      ]),
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
      case 'new_batsman': return 'Select new batsman';
      default:            return 'Over ${(_innings?.totalBalls ?? 0) ~/ 6} — Select bowler';
    }
  }
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

  bool get _needsFielder => _selectedType == 'caught' || _selectedType == 'run_out' || _selectedType == 'stumped';

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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
          decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(16),
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
          decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(16),
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

class _MatchResultScreen extends StatelessWidget {
  final String matchId, result;
  final Innings? innings1, innings2;
  final Team? team1, team2;

  const _MatchResultScreen({required this.matchId, required this.result,
    this.innings1, this.innings2, this.team1, this.team2});

  String _teamName(String? id) {
    if (id == null) return '—';
    if (id == team1?.id) return team1?.name ?? '—';
    if (id == team2?.id) return team2?.name ?? '—';
    return '—';
  }

  @override Widget build(BuildContext context) {
    final isWin = result.contains('won');
    final isTie = result.contains('tied');
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
            Text(result.replaceAll('🏆 ', '').replaceAll('🤝 ', ''), textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                color: isWin ? AppColors.accent : isTie ? AppColors.ball : AppColors.text)),
          ]),
        ),
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          if (innings1 != null) _InningsSummaryCard(innings: innings1!, teamName: _teamName(innings1!.battingTeamId), label: '1st Innings'),
          if (innings2 != null) _InningsSummaryCard(innings: innings2!, teamName: _teamName(innings2!.battingTeamId), label: '2nd Innings'),
        ])),
        Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          SizedBox(width: double.infinity, height: 52,
            child: ElevatedButton.icon(
              onPressed: () => context.go('/scorecard/$matchId'),
              icon: const Icon(Icons.assignment_outlined, size: 18),
              label: const Text('Full scorecard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, height: 48,
            child: OutlinedButton(
              onPressed: () => context.go('/?t=${DateTime.now().millisecondsSinceEpoch}'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.text2,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
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
      decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(16),
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

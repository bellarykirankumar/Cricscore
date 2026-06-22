import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';

/// Opens the same toss + playing XI + start flow used on the tournament
/// fixtures tab, for a fixture launched from the home screen.
Future<void> showTossSheet(
  BuildContext context,
  Fixture fixture,
  Tournament tournament,
  Future<void> Function() onRefresh,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _FixtureTossSheet(
      parentContext: context,
      sheetContext: sheetContext,
      fixture: fixture,
      tournament: tournament,
      onRefresh: onRefresh,
    ),
  );
}

class _FixtureTossSheet extends StatefulWidget {
  final BuildContext parentContext;
  final BuildContext sheetContext;
  final Fixture fixture;
  final Tournament tournament;
  final Future<void> Function() onRefresh;

  const _FixtureTossSheet({
    required this.parentContext,
    required this.sheetContext,
    required this.fixture,
    required this.tournament,
    required this.onRefresh,
  });

  @override
  State<_FixtureTossSheet> createState() => _FixtureTossSheetState();
}

class _FixtureTossSheetState extends State<_FixtureTossSheet> {
  bool _loading = true;
  bool _starting = false;
  bool _tossHome = true;
  bool _tossBat = true;
  List<Player> _homeRoster = [];
  List<Player> _awayRoster = [];
  Set<String> _homeSel = {};
  Set<String> _awaySel = {};

  @override
  void initState() {
    super.initState();
    _loadRosters();
  }

  Future<void> _loadRosters() async {
    try {
      final results = await Future.wait([
        PlayerApi.list(widget.fixture.homeTeamId).catchError((_) => <Player>[]),
        PlayerApi.list(widget.fixture.awayTeamId).catchError((_) => <Player>[]),
      ]);
      final home = results[0];
      final away = results[1];
      if (!mounted) return;
      setState(() {
        _homeRoster = home;
        _awayRoster = away;
        _homeSel = home.take(11).map((p) => p.id).toSet();
        _awaySel = away.take(11).map((p) => p.id).toSet();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _togglePlayer(String id, bool isHome) {
    final set = isHome ? Set<String>.from(_homeSel) : Set<String>.from(_awaySel);
    if (set.contains(id)) {
      set.remove(id);
    } else if (set.length < 11) {
      set.add(id);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Max 11 players')),
      );
      return;
    }
    setState(() {
      if (isHome) {
        _homeSel = set;
      } else {
        _awaySel = set;
      }
    });
  }

  int _oversForTournament() {
    final fmt = widget.tournament.format;
    if (fmt == 'T10') return 10;
    if (fmt == 'ODI') return 50;
    return 20;
  }

  Future<void> _startMatch() async {
    final f = widget.fixture;
    if (_homeSel.isEmpty || _awaySel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one player per side')),
      );
      return;
    }
    setState(() => _starting = true);
    try {
      final team1 = Team(
        id: f.homeTeamId,
        name: f.homeTeamName,
        shortName: f.homeTeamName.substring(0, f.homeTeamName.length.clamp(0, 3)).toUpperCase(),
        players: _homeRoster.where((p) => _homeSel.contains(p.id)).toList(),
      );
      final team2 = Team(
        id: f.awayTeamId,
        name: f.awayTeamName,
        shortName: f.awayTeamName.substring(0, f.awayTeamName.length.clamp(0, 3)).toUpperCase(),
        players: _awayRoster.where((p) => _awaySel.contains(p.id)).toList(),
      );

      final match = await MatchApi.create({
        'tournamentId': widget.tournament.id,
        'format': widget.tournament.format,
        'oversPerInnings': _oversForTournament(),
        'team1': team1.toJson(),
        'team2': team2.toJson(),
      });
      await MatchApi.update(match.id, {'status': 'in_progress'});

      final tossTeam = _tossHome ? team1 : team2;
      final battingId = _tossBat
          ? tossTeam.id
          : (tossTeam.id == team1.id ? team2.id : team1.id);
      final bowlingId = battingId == team1.id ? team2.id : team1.id;

      await MatchApi.startInnings(match.id, {
        'battingTeamId': battingId,
        'bowlingTeamId': bowlingId,
      });

      if (widget.sheetContext.mounted) {
        Navigator.of(widget.sheetContext).pop();
      }
      await widget.onRefresh();
      if (widget.parentContext.mounted) {
        widget.parentContext.go('/scoring/${match.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fixture;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: const BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    '🏏 ${f.homeTeamName} vs ${f.awayTeamName}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          _TossRow(
                            'Toss won by',
                            f.homeTeamName,
                            f.awayTeamName,
                            _tossHome,
                            (v) => setState(() => _tossHome = v),
                          ),
                          const SizedBox(height: 12),
                          _TossRow(
                            'Elected to',
                            '🏏 Bat',
                            '🎳 Bowl',
                            _tossBat,
                            (v) => setState(() => _tossBat = v),
                          ),
                          const SizedBox(height: 16),
                          for (final entry in [
                            (true, f.homeTeamName, _homeRoster, _homeSel),
                            (false, f.awayTeamName, _awayRoster, _awaySel),
                          ])
                            if (entry.$3.isNotEmpty) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry.$2,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${entry.$4.length}/11',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: entry.$4.length == 11 ? AppColors.accent : AppColors.ball,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ...entry.$3.asMap().entries.map((e) {
                                final p = e.value;
                                final isSel = entry.$4.contains(p.id);
                                return ListTile(
                                  dense: true,
                                  leading: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: isSel ? AppColors.accent : AppColors.bgElevated,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        isSel ? '✓' : '${e.key + 1}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: isSel ? AppColors.textOnAcc : AppColors.text2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    p.name,
                                    style: TextStyle(
                                      color: isSel ? AppColors.accent : AppColors.text,
                                      fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                                      fontSize: 14,
                                    ),
                                  ),
                                  onTap: () => _togglePlayer(p.id, entry.$1),
                                  tileColor: isSel ? AppColors.accentFaint : null,
                                );
                              }),
                              const SizedBox(height: 12),
                            ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        ElevatedButton(
                          onPressed: _starting ? null : _startMatch,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _starting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppColors.textOnAcc,
                                  ),
                                )
                              : const Text('Start match →'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _starting ? null : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.text2,
                            side: const BorderSide(color: AppColors.border),
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TossRow extends StatelessWidget {
  final String label;
  final String opt1;
  final String opt2;
  final bool val;
  final void Function(bool) onChanged;

  const _TossRow(this.label, this.opt1, this.opt2, this.val, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.text2,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: val ? AppColors.accent.withOpacity(0.15) : AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: val ? AppColors.accent : AppColors.border,
                      width: val ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    opt1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: val ? AppColors.accent : AppColors.text2,
                      fontWeight: val ? FontWeight.w700 : FontWeight.w400,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: !val ? AppColors.ball.withOpacity(0.15) : AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: !val ? AppColors.ball : AppColors.border,
                      width: !val ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    opt2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: !val ? AppColors.ball : AppColors.text2,
                      fontWeight: !val ? FontWeight.w700 : FontWeight.w400,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

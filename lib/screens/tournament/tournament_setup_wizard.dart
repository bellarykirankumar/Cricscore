import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../models/models.dart';
import '../../main.dart';

// ── Data model for wizard state ────────────────────────────────
class _WizardState {
  String name            = '';
  String format          = 'T20';
  String tournamentType  = 'league_finals';
  int    numTeams        = 8;
  List<String> teamNames = [];
  DateTime? startDate;
  Set<String> playDays   = {'saturday', 'sunday'};
  int    matchesPerDay   = 2;
  TimeOfDay startTime    = const TimeOfDay(hour: 9, minute: 0);
  List<Map<String, dynamic>> generatedFixtures = [];
}

class TournamentSetupWizard extends ConsumerStatefulWidget {
  const TournamentSetupWizard({super.key});
  @override ConsumerState<TournamentSetupWizard> createState() => _TournamentSetupWizardState();
}

class _TournamentSetupWizardState extends ConsumerState<TournamentSetupWizard> {
  final _state   = _WizardState();
  int    _step   = 0; // 0=AI/Basics, 1=Schedule, 2=Teams, 3=Fixtures, 4=Done
  bool   _aiLoading   = false;
  bool   _schedLoading = false;
  bool   _saving  = false;
  String? _error;
  String? _aiSuccess;

  final _aiCtrl   = TextEditingController();
  final _nameCtrl = TextEditingController();

  static const _steps = ['Basics', 'Schedule', 'Teams', 'Fixtures', 'Launch'];

  @override void dispose() {
    _aiCtrl.dispose(); _nameCtrl.dispose(); super.dispose();
  }

  // ── AI: parse description ──────────────────────────────────
  Future<void> _parseWithAI() async {
    final desc = _aiCtrl.text.trim();
    if (desc.isEmpty) return;
    setState(() { _aiLoading = true; _error = null; _aiSuccess = null; });
    try {
      final result = await AiApi.parseTournamentDescription(desc);
      final filled = <String>[];
      setState(() {
        if (result['name'] != null && (result['name'] as String).isNotEmpty) {
          _state.name = result['name'] as String;
          _nameCtrl.text = _state.name;
          filled.add('name');
        }
        if (result['format'] != null) {
          _state.format = result['format'] as String;
          filled.add(_state.format);
        }
        if (result['tournamentType'] != null) {
          _state.tournamentType = result['tournamentType'] as String;
        }
        if (result['numTeams'] != null) {
          _state.numTeams = (result['numTeams'] as num).toInt();
          filled.add('${_state.numTeams} teams');
        }
        if (result['teamNames'] is List) {
          final names = (result['teamNames'] as List).map((n) => n.toString()).where((n) => n.isNotEmpty).toList();
          if (names.isNotEmpty) _state.teamNames = names;
        }
        if (result['startDate'] != null) {
          try {
            _state.startDate = DateTime.parse(result['startDate'] as String);
            filled.add('start date');
          } catch (_) {}
        }
        if (result['playDays'] is List) {
          final days = (result['playDays'] as List).map((d) => d.toString()).toSet();
          if (days.isNotEmpty) {
            _state.playDays = days;
            filled.add(days.map((d) => d[0].toUpperCase() + d.substring(1)).join(' & '));
          }
        }
        if (result['matchesPerDay'] != null) {
          _state.matchesPerDay = (result['matchesPerDay'] as num).toInt();
          filled.add('${_state.matchesPerDay}/day');
        }
        if (result['startTime'] != null) {
          try {
            final parts = (result['startTime'] as String).split(':');
            _state.startTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
          } catch (_) {}
        }

        // Auto-generate a name if AI didn't provide one
        if (_state.name.isEmpty) {
          _state.name = '${_state.format} Tournament';
          _nameCtrl.text = _state.name;
        }

        _aiSuccess = filled.isEmpty
          ? 'Filled: format and schedule defaults'
          : 'Filled: ${filled.join(', ')} — check below and tap Next';
      });

      // Always advance to next step after AI parse
      _goToStep(1);

    } catch (e) {
      setState(() => _error = 'AI error: $e');
    } finally {
      setState(() => _aiLoading = false);
    }
  }

  // ── AI: suggest team names ─────────────────────────────────
  Future<void> _suggestTeamNames() async {
    setState(() { _aiLoading = true; _error = null; });
    try {
      final names = await AiApi.suggestTeamNames(
        count: _state.numTeams,
        existing: _state.teamNames,
      );
      setState(() {
        // Merge: keep existing non-empty names, fill rest with suggestions
        final merged = List<String>.filled(_state.numTeams, '');
        for (int i = 0; i < _state.teamNames.length && i < merged.length; i++) {
          merged[i] = _state.teamNames[i];
        }
        int si = 0;
        for (int i = 0; i < merged.length; i++) {
          if (merged[i].isEmpty && si < names.length) {
            merged[i] = names[si++];
          }
        }
        _state.teamNames = merged;
      });
    } catch (e) {
      setState(() => _error = 'Could not load suggestions: $e');
    } finally {
      setState(() => _aiLoading = false);
    }
  }

  // ── AI: generate schedule ──────────────────────────────────
  Future<void> _generateSchedule() async {
    setState(() { _schedLoading = true; _error = null; });
    try {
      final fixtures = await AiApi.generateSchedule({
        'numTeams': _state.numTeams,
        'teamNames': _state.teamNames.where((n) => n.isNotEmpty).toList(),
        'tournamentType': _state.tournamentType,
        'format': _state.format,
        'startDate': _state.startDate!.toIso8601String().substring(0, 10),
        'playDays': _state.playDays.toList(),
        'matchesPerDay': _state.matchesPerDay,
        'startTime': '${_state.startTime.hour.toString().padLeft(2,'0')}:${_state.startTime.minute.toString().padLeft(2,'0')}',
      });
      setState(() => _state.generatedFixtures = fixtures);
    } catch (e) {
      setState(() => _error = 'Schedule error: $e');
    } finally {
      setState(() => _schedLoading = false);
    }
  }

  // ── Create tournament + teams + fixtures ───────────────────
  Future<void> _launchTournament() async {
    if (_state.name.trim().isEmpty) return;
    setState(() { _saving = true; _error = null; });
    try {
      final user = ref.read(authProvider).value;
      final country = await AuthService.instance.getCountry();

      // 1. Create tournament
      final tournament = await TournamentApi.create({
        'name': _state.name.trim(),
        'format': _state.format,
        'maxTeams': _state.numTeams,
        'status': 'upcoming',
        if (user != null) 'createdBy': user.sub,
        if (country != null) 'country': country,
      });
      await AuthService.instance.claimOwnership(tournament.id);

      // 2. Create teams
      final teamIds = <String, String>{}; // name → id
      for (final name in _state.teamNames.where((n) => n.isNotEmpty)) {
        final short = name.length >= 3 ? name.substring(0, 3).toUpperCase() : name.toUpperCase();
        final team = await TournamentApi.addTeam(tournament.id, {
          'name': name, 'shortName': short,
          if (user != null) 'createdBy': user.sub,
        });
        teamIds[name] = team.id;
      }

      // 3. Create fixtures
      for (final f in _state.generatedFixtures) {
        final home = f['homeTeam'] as String? ?? '';
        final away = f['awayTeam'] as String? ?? '';
        final homeId = teamIds[home];
        final awayId = teamIds[away];
        if (homeId == null || awayId == null) continue;

        String? scheduled;
        if (f['date'] != null && f['time'] != null) {
          try {
            final d = DateTime.parse(f['date'] as String);
            final parts = (f['time'] as String).split(':');
            final dt = DateTime(d.year, d.month, d.day, int.parse(parts[0]), int.parse(parts[1]));
            scheduled = dt.toIso8601String();
          } catch (_) {}
        }
        await TournamentApi.addFixture(tournament.id, {
          'homeTeamId': homeId, 'homeTeamName': home,
          'awayTeamId': awayId, 'awayTeamName': away,
          if (scheduled != null) 'scheduledDate': scheduled,
          if (f['round'] != null) 'round': f['round'],
          if (f['stage'] != null) 'stage': f['stage'],
        });
      }

      // Done — navigate to tournament
      if (mounted) context.go('/tournament/${tournament.id}');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _goToStep(int s) {
    HapticFeedback.selectionClick();
    setState(() { _step = s; _error = null; });
    if (s == 3 && _state.generatedFixtures.isEmpty && _state.startDate != null) {
      _generateSchedule();
    }
  }

  bool get _step0Valid => _state.name.trim().isNotEmpty;
  bool get _step1Valid => _state.startDate != null && _state.playDays.isNotEmpty;
  bool get _step2Valid => _state.numTeams >= 2;
  bool get _step3Valid => _state.generatedFixtures.isNotEmpty;

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close, size: 22),
          onPressed: () => context.go('/tournaments'),
        ),
        title: const Text('New Tournament'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: _StepBar(steps: _steps, current: _step, onTap: (i) {
            if (i < _step) _goToStep(i);
          }),
        ),
      ),
      body: SafeArea(
        child: Column(children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: AppColors.wicketFaint,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(_error!, style: const TextStyle(color: AppColors.wicket, fontSize: 13)),
            ),
          Expanded(child: _buildStep()),
          _buildNavBar(),
        ]),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _Step0Basics(state: _state, nameCtrl: _nameCtrl, aiCtrl: _aiCtrl,
          aiLoading: _aiLoading, onParseAI: _parseWithAI, aiSuccess: _aiSuccess,
          onChanged: () => setState(() {}));
      case 1: return _Step1Schedule(state: _state, onChanged: () => setState(() {}));
      case 2: return _Step2Teams(state: _state, aiLoading: _aiLoading,
          onSuggest: _suggestTeamNames, onChanged: () => setState(() {}));
      case 3: return _Step3Fixtures(state: _state, loading: _schedLoading,
          onRegenerate: _generateSchedule, onChanged: () => setState(() {}));
      case 4: return _Step4Launch(state: _state, saving: _saving, onLaunch: _launchTournament);
      default: return const SizedBox();
    }
  }

  Widget _buildNavBar() {
    final canNext = switch (_step) {
      0 => _step0Valid,
      1 => _step1Valid,
      2 => _step2Valid,
      3 => _step3Valid,
      4 => true,   // launch step is always enabled
      _ => false,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        if (_step > 0) OutlinedButton(
          onPressed: () => _goToStep(_step - 1),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text2,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size(80, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('← Back'),
        ),
        if (_step > 0) const SizedBox(width: 12),
        Expanded(child: ElevatedButton(
          onPressed: canNext && !_aiLoading && !_schedLoading && !_saving
            ? () {
                if (_step < 4) _goToStep(_step + 1);
                else _launchTournament();
              }
            : null,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _schedLoading || _saving
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnAcc))
            : Text(_step == 3 ? 'Next: Review →' : _step == 4 ? '🚀 Launch Tournament' : 'Next →',
                style: const TextStyle(fontWeight: FontWeight.w700)),
        )),
      ]),
    );
  }
}

// ── Step Progress Bar ─────────────────────────────────────────
class _StepBar extends StatelessWidget {
  final List<String> steps;
  final int current;
  final void Function(int) onTap;
  const _StepBar({required this.steps, required this.current, required this.onTap});

  @override Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(children: steps.asMap().entries.map((e) {
        final i = e.key; final label = e.value;
        final done = i < current; final active = i == current;
        return Expanded(child: GestureDetector(
          onTap: () => onTap(i),
          child: Row(children: [
            if (i > 0) Expanded(child: Container(height: 1,
              color: done ? AppColors.accent : AppColors.border)),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppColors.accent : done ? AppColors.accent.withOpacity(0.4) : AppColors.bgElevated,
                  border: Border.all(color: active ? AppColors.accent : done ? AppColors.accent.withOpacity(0.4) : AppColors.border),
                ),
                child: Center(child: done
                  ? const Icon(Icons.check, size: 12, color: AppColors.textOnAcc)
                  : Text('${i+1}', style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: active ? AppColors.textOnAcc : AppColors.text3))),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(
                fontSize: 9, fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: active ? AppColors.accent : AppColors.text3)),
            ]),
          ]),
        ));
      }).toList()),
    );
  }
}

// ── Step 0: Basics + AI prompt ────────────────────────────────
class _Step0Basics extends StatelessWidget {
  final _WizardState state;
  final TextEditingController nameCtrl, aiCtrl;
  final bool aiLoading;
  final String? aiSuccess;
  final VoidCallback onParseAI, onChanged;
  const _Step0Basics({required this.state, required this.nameCtrl, required this.aiCtrl,
    required this.aiLoading, required this.onParseAI, required this.onChanged,
    this.aiSuccess});

  static const _formats = ['T10', 'T20', 'ODI', 'Test', 'Gully'];
  static const _types = [
    ('league',         '🏅 League only',          'All play all, ranked by points'),
    ('league_finals',  '🏆 League + Finals',       'League stage then top 4 → semis + final'),
    ('knockout',       '⚡ Knockout',              'Direct elimination bracket'),
    ('group_knockout', '🌍 Group Stage + Knockout', 'Groups then top 2 per group advance'),
  ];

  @override Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      // AI prompt
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppColors.accent.withOpacity(0.1), AppColors.bgCard]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accent.withOpacity(0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('✨', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            const Text('Describe your tournament', style: TextStyle(
              fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 15)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
              child: const Text('AI', style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('Let AI fill in the details automatically',
            style: TextStyle(color: AppColors.text2, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: aiCtrl,
            style: const TextStyle(color: AppColors.text, fontSize: 14),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'e.g. "8 team T20 tournament in Bangalore, starting next Saturday, 2 games per weekend for 5 weeks"',
              hintStyle: const TextStyle(color: AppColors.text3, fontSize: 13),
              filled: true, fillColor: AppColors.bgElevated,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: aiLoading ? null : onParseAI,
              icon: aiLoading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnAcc))
                : const Icon(Icons.auto_awesome, size: 16),
              label: Text(aiLoading ? 'Setting up…' : 'Set up with AI'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ),
          if (aiSuccess != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.accent.withOpacity(0.4)),
              ),
              child: Row(children: [
                const Text('✓ ', style: TextStyle(color: AppColors.accent, fontSize: 13)),
                Expanded(child: Text(aiSuccess!,
                  style: const TextStyle(color: AppColors.accent, fontSize: 12))),
              ]),
            ),
          ],
        ]),
      ),

      const SizedBox(height: 24),
      const _SectionLabel('OR FILL MANUALLY'),
      const SizedBox(height: 12),

      // Name
      TextField(
        controller: nameCtrl,
        style: const TextStyle(color: AppColors.text),
        decoration: const InputDecoration(
          labelText: 'Tournament name *',
          hintText: 'e.g. Bangalore T20 Cup 2026',
        ),
        onChanged: (v) { state.name = v; onChanged(); },
      ),
      const SizedBox(height: 20),

      // Format
      const Text('Format', style: TextStyle(color: AppColors.text2, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: _formats.map((f) => GestureDetector(
        onTap: () { state.format = f; onChanged(); },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: state.format == f ? AppColors.accent.withOpacity(0.15) : AppColors.bgElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: state.format == f ? AppColors.accent : AppColors.border,
              width: state.format == f ? 1.5 : 1),
          ),
          child: Text(f, style: TextStyle(
            fontWeight: state.format == f ? FontWeight.w700 : FontWeight.w400,
            color: state.format == f ? AppColors.accent : AppColors.text2, fontSize: 14)),
        ),
      )).toList()),
      const SizedBox(height: 20),

      // Tournament type
      const Text('Tournament type', style: TextStyle(color: AppColors.text2, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      ..._types.map((t) => GestureDetector(
        onTap: () { state.tournamentType = t.$1; onChanged(); },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: state.tournamentType == t.$1 ? AppColors.accent.withOpacity(0.08) : AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: state.tournamentType == t.$1 ? AppColors.accent : AppColors.border,
              width: state.tournamentType == t.$1 ? 1.5 : 1),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.$2, style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14,
                color: state.tournamentType == t.$1 ? AppColors.accent : AppColors.text)),
              const SizedBox(height: 2),
              Text(t.$3, style: const TextStyle(color: AppColors.text2, fontSize: 12)),
            ])),
            if (state.tournamentType == t.$1)
              const Icon(Icons.check_circle, color: AppColors.accent, size: 20),
          ]),
        ),
      )),
    ]);
  }
}

// ── Step 1: Schedule ──────────────────────────────────────────
class _Step1Schedule extends StatelessWidget {
  final _WizardState state;
  final VoidCallback onChanged;
  const _Step1Schedule({required this.state, required this.onChanged});

  String _fmtDate(DateTime? d) {
    if (d == null) return 'Pick a date';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month-1]} ${d.year}';
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? "AM" : "PM"}';
  }

  @override Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      const _SectionLabel('WHEN DOES IT START?'),
      const SizedBox(height: 12),

      // Start date
      _PickerTile(
        icon: Icons.calendar_today_outlined,
        label: 'Start date',
        value: _fmtDate(state.startDate),
        hasValue: state.startDate != null,
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: state.startDate ?? DateTime.now().add(const Duration(days: 7)),
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            builder: (ctx, child) => Theme(
              data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.accent)),
              child: child!),
          );
          if (d != null) { state.startDate = d; onChanged(); }
        },
      ),
      const SizedBox(height: 12),

      // Play days
      const _SectionLabel('PLAY ON WEEKENDS'),
      const SizedBox(height: 10),
      Row(children: [
        for (final day in [('saturday', 'Saturday'), ('sunday', 'Sunday')])
          Expanded(child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                if (state.playDays.contains(day.$1)) {
                  if (state.playDays.length > 1) state.playDays.remove(day.$1);
                } else {
                  state.playDays.add(day.$1);
                }
                onChanged();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: state.playDays.contains(day.$1) ? AppColors.accent.withOpacity(0.12) : AppColors.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: state.playDays.contains(day.$1) ? AppColors.accent : AppColors.border,
                    width: state.playDays.contains(day.$1) ? 1.5 : 1),
                ),
                child: Column(children: [
                  Text(day.$2.substring(0, 3).toUpperCase(),
                    style: TextStyle(fontSize: 11, color: state.playDays.contains(day.$1) ? AppColors.accent : AppColors.text3)),
                  const SizedBox(height: 4),
                  Icon(state.playDays.contains(day.$1) ? Icons.check_box : Icons.check_box_outline_blank,
                    color: state.playDays.contains(day.$1) ? AppColors.accent : AppColors.text3, size: 20),
                ]),
              ),
            ),
          )),
      ]),
      const SizedBox(height: 20),

      // Matches per day
      const _SectionLabel('MATCHES PER DAY'),
      const SizedBox(height: 10),
      Row(children: [1, 2, 3, 4].map((n) => Expanded(child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () { state.matchesPerDay = n; onChanged(); },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: state.matchesPerDay == n ? AppColors.ball.withOpacity(0.12) : AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: state.matchesPerDay == n ? AppColors.ball : AppColors.border,
                width: state.matchesPerDay == n ? 1.5 : 1),
            ),
            child: Text('$n', textAlign: TextAlign.center, style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w800,
              color: state.matchesPerDay == n ? AppColors.ball : AppColors.text2)),
          ),
        ),
      ))).toList()),
      const SizedBox(height: 20),

      // Start time
      const _SectionLabel('FIRST MATCH START TIME'),
      const SizedBox(height: 10),
      _PickerTile(
        icon: Icons.access_time_outlined,
        label: 'Start time',
        value: _fmtTime(state.startTime),
        hasValue: true,
        onTap: () async {
          final t = await showTimePicker(
            context: context,
            initialTime: state.startTime,
            builder: (ctx, child) => Theme(
              data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.accent)),
              child: child!),
          );
          if (t != null) { state.startTime = t; onChanged(); }
        },
      ),

      const SizedBox(height: 24),
      // Summary chip
      if (state.startDate != null)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgCard, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border)),
          child: Row(children: [
            const Text('📅', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text(
              'Matches on ${state.playDays.map((d) => d[0].toUpperCase() + d.substring(1)).join(" & ")}, '
              '${state.matchesPerDay} per day, starting ${_fmtDate(state.startDate)} at ${_fmtTime(state.startTime)}',
              style: const TextStyle(color: AppColors.text2, fontSize: 13))),
          ]),
        ),
    ]);
  }
}

// ── Step 2: Teams ─────────────────────────────────────────────
class _Step2Teams extends StatefulWidget {
  final _WizardState state;
  final bool aiLoading;
  final VoidCallback onSuggest, onChanged;
  const _Step2Teams({required this.state, required this.aiLoading,
    required this.onSuggest, required this.onChanged});
  @override State<_Step2Teams> createState() => _Step2TeamsState();
}

class _Step2TeamsState extends State<_Step2Teams> {
  late List<TextEditingController> _ctrls;

  @override void initState() {
    super.initState();
    _rebuild();
  }

  void _rebuild() {
    final n = widget.state.numTeams;
    while (widget.state.teamNames.length < n) widget.state.teamNames.add('');
    _ctrls = List.generate(n, (i) => TextEditingController(text: widget.state.teamNames[i]));
  }

  @override void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  void _setNumTeams(int n) {
    setState(() {
      widget.state.numTeams = n;
      while (widget.state.teamNames.length < n) widget.state.teamNames.add('');
      widget.state.teamNames = widget.state.teamNames.sublist(0, n);
      for (final c in _ctrls) c.dispose();
      _ctrls = List.generate(n, (i) => TextEditingController(text: widget.state.teamNames[i]));
    });
    widget.onChanged();
  }

  @override Widget build(BuildContext context) {
    // Sync AI-filled names into controllers
    for (int i = 0; i < _ctrls.length && i < widget.state.teamNames.length; i++) {
      if (_ctrls[i].text != widget.state.teamNames[i]) {
        _ctrls[i].text = widget.state.teamNames[i];
      }
    }

    return ListView(padding: const EdgeInsets.all(20), children: [
      const _SectionLabel('NUMBER OF TEAMS'),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [4, 6, 8, 10, 12, 16].map((n) => GestureDetector(
        onTap: () => _setNumTeams(n),
        child: Container(
          width: 60, height: 44,
          decoration: BoxDecoration(
            color: widget.state.numTeams == n ? AppColors.accent.withOpacity(0.15) : AppColors.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.state.numTeams == n ? AppColors.accent : AppColors.border,
              width: widget.state.numTeams == n ? 1.5 : 1),
          ),
          child: Center(child: Text('$n', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700,
            color: widget.state.numTeams == n ? AppColors.accent : AppColors.text2))),
        ),
      )).toList()),
      const SizedBox(height: 24),

      Row(children: [
        const Expanded(child: _SectionLabel('TEAM NAMES')),
        GestureDetector(
          onTap: widget.aiLoading ? null : () { widget.onSuggest(); setState(() {}); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.accent.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              widget.aiLoading
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                : const Icon(Icons.auto_awesome, size: 14, color: AppColors.accent),
              const SizedBox(width: 4),
              const Text('Suggest names', style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 10),

      ...List.generate(widget.state.numTeams, (i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: _ctrls[i],
          style: const TextStyle(color: AppColors.text),
          decoration: InputDecoration(
            labelText: 'Team ${i + 1}',
            hintText: 'Team name',
            prefixIcon: Container(
              width: 32, alignment: Alignment.center,
              child: Text('${i+1}', style: const TextStyle(
                color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 13))),
          ),
          onChanged: (v) {
            widget.state.teamNames[i] = v;
            widget.onChanged();
          },
        ),
      )),
    ]);
  }
}

// ── Step 3: Fixture Preview ───────────────────────────────────
class _Step3Fixtures extends StatelessWidget {
  final _WizardState state;
  final bool loading;
  final VoidCallback onRegenerate, onChanged;
  const _Step3Fixtures({required this.state, required this.loading,
    required this.onRegenerate, required this.onChanged});

  String _fmtDate(String? d) {
    if (d == null) return '—';
    try {
      final dt = DateTime.parse(d);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day} ${months[dt.month-1]}';
    } catch (_) { return d; }
  }

  @override Widget build(BuildContext context) {
    if (loading) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(color: AppColors.accent),
      SizedBox(height: 16),
      Text('AI is scheduling your fixtures…', style: TextStyle(color: AppColors.text2)),
    ]));

    final fixtures = state.generatedFixtures;
    final byStage = <String, List<Map<String, dynamic>>>{};
    for (final f in fixtures) {
      final stage = f['stage'] as String? ?? 'league';
      byStage.putIfAbsent(stage, () => []).add(f);
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('${fixtures.length} fixtures generated',
          style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15))),
        GestureDetector(
          onTap: onRegenerate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.bgCard, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.refresh, size: 14, color: AppColors.text2),
              SizedBox(width: 4),
              Text('Regenerate', style: TextStyle(color: AppColors.text2, fontSize: 12)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 12),

      ...byStage.entries.map((entry) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            entry.key.toUpperCase().replaceAll('_', ' '),
            style: const TextStyle(color: AppColors.accent, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 1)),
        ),
        ...entry.value.map((f) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bgCard, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Container(
              width: 48,
              child: Column(children: [
                Text(_fmtDate(f['date'] as String?),
                  style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                Text(f['time'] as String? ?? '', style: const TextStyle(color: AppColors.text2, fontSize: 10)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f['homeTeam'] as String? ?? 'TBD',
                style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
              const Text('vs', style: TextStyle(color: AppColors.text2, fontSize: 11)),
              Text(f['awayTeam'] as String? ?? 'TBD',
                style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
            ])),
            Text('R${f['round'] ?? ''}',
              style: const TextStyle(color: AppColors.text3, fontSize: 11)),
          ]),
        )),
      ])),
    ]);
  }
}

// ── Step 4: Launch review ─────────────────────────────────────
class _Step4Launch extends StatelessWidget {
  final _WizardState state;
  final bool saving;
  final VoidCallback onLaunch;
  const _Step4Launch({required this.state, required this.saving, required this.onLaunch});

  @override Widget build(BuildContext context) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final d = state.startDate;
    final dateStr = d != null ? '${d.day} ${months[d.month-1]} ${d.year}' : '—';

    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('🏏', style: TextStyle(fontSize: 56), textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Text(state.name.isEmpty ? 'Unnamed Tournament' : state.name,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text)),
      const SizedBox(height: 24),

      _ReviewRow('Format', state.format),
      _ReviewRow('Type', state.tournamentType.replaceAll('_', ' + ')),
      _ReviewRow('Teams', '${state.numTeams} teams'),
      _ReviewRow('Start date', dateStr),
      _ReviewRow('Play days', state.playDays.map((d) => d[0].toUpperCase() + d.substring(1)).join(' & ')),
      _ReviewRow('Matches/day', '${state.matchesPerDay}'),
      _ReviewRow('Fixtures', '${state.generatedFixtures.length} scheduled'),

      const SizedBox(height: 20),
      if (state.teamNames.where((n) => n.isNotEmpty).isNotEmpty) ...[
        const _SectionLabel('TEAMS'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8,
          children: state.teamNames.where((n) => n.isNotEmpty).map((n) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.bgCard, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border)),
            child: Text(n, style: const TextStyle(color: AppColors.text, fontSize: 13)),
          )).toList()),
        const SizedBox(height: 24),
      ],

      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withOpacity(0.3))),
        child: const Text(
          '✓ Tapping Launch will create the tournament, all teams, and schedule all fixtures immediately.',
          style: TextStyle(color: AppColors.text2, fontSize: 13), textAlign: TextAlign.center),
      ),
    ]);
  }
}

class _ReviewRow extends StatelessWidget {
  final String label, value;
  const _ReviewRow(this.label, this.value);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 14))),
      Text(value, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
    ]),
  );
}

// ── Shared widgets ────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override Widget build(BuildContext context) => Text(text,
    style: const TextStyle(color: AppColors.text2, fontSize: 11,
      fontWeight: FontWeight.w700, letterSpacing: 1));
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final bool hasValue;
  final VoidCallback onTap;
  const _PickerTile({required this.icon, required this.label,
    required this.value, required this.hasValue, required this.onTap});

  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.bgCard, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasValue ? AppColors.accent.withOpacity(0.4) : AppColors.border)),
      child: Row(children: [
        Icon(icon, color: hasValue ? AppColors.accent : AppColors.text2, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 11)),
          Text(value, style: TextStyle(
            color: hasValue ? AppColors.text : AppColors.text2,
            fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400, fontSize: 15)),
        ])),
        const Icon(Icons.chevron_right, color: AppColors.text3, size: 20),
      ]),
    ),
  );
}

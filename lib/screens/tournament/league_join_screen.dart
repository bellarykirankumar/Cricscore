import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../main.dart';

class LeagueJoinScreen extends ConsumerStatefulWidget {
  final String tournamentId;
  const LeagueJoinScreen({super.key, required this.tournamentId});
  @override ConsumerState<LeagueJoinScreen> createState() => _LeagueJoinScreenState();
}

class _LeagueJoinScreenState extends ConsumerState<LeagueJoinScreen> {
  Tournament?          _tournament;
  LeagueRegistration?  _myRegistration;
  bool                 _loading  = true;
  bool                 _saving   = false;
  String               _role     = 'all_rounder';
  final _bioCtrl = TextEditingController();

  static const _roles = [
    ('all_rounder',    'All Rounder'),
    ('batsman',        'Batsman'),
    ('bowler',         'Bowler'),
    ('wicket_keeper',  'Wicket Keeper'),
  ];

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _bioCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = ref.read(authProvider).value;
      final results = await Future.wait([
        TournamentApi.get(widget.tournamentId),
        if (user != null)
          TournamentApi.getMyRegistration(widget.tournamentId, user.sub)
        else
          Future.value(null),
      ]);
      if (mounted) setState(() {
        _tournament     = results[0] as Tournament;
        _myRegistration = results.length > 1 ? results[1] as LeagueRegistration? : null;
        _loading        = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final user = ref.read(authProvider).value;
    if (user == null) {
      // Not logged in — go to login, then come back
      context.go('/login', extra: '/join/${widget.tournamentId}');
      return;
    }
    setState(() => _saving = true);
    try {
      final reg = await TournamentApi.registerToLeague(widget.tournamentId, {
        'userId':        user.sub,
        'userName':      user.name,
        'userEmail':     user.email,
        'preferredRole': _role,
        'bio':           _bioCtrl.text.trim(),
      });
      setState(() { _myRegistration = reg; _saving = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Registered! Captains can now find and add you to a team.')));
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override Widget build(BuildContext context) {
    if (_loading) return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
    );
    if (_tournament == null) return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/'))),
      body: const Center(child: Text('League not found', style: TextStyle(color: AppColors.text2))),
    );

    final t = _tournament!;
    final alreadyRegistered = _myRegistration != null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => context.go('/tournament/${widget.tournamentId}'),
        ),
        title: const Text('Join League'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // League info card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.sports_cricket, size: 14, color: AppColors.text2),
                const SizedBox(width: 4),
                Text('${t.format} · ${t.teamCount}/${t.maxTeams} teams',
                  style: const TextStyle(color: AppColors.text2, fontSize: 13)),
              ]),
              if (t.city != null || t.state != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: AppColors.text2),
                  const SizedBox(width: 4),
                  Text(
                    [if (t.city != null) t.city!, if (t.state != null) t.state!].join(' · '),
                    style: const TextStyle(color: AppColors.text2, fontSize: 13)),
                ]),
              ],
              const SizedBox(height: 12),
              StatusBadge(
                label: t.isActive ? 'Active' : t.isUpcoming ? 'Upcoming' : 'Completed',
                color: t.isActive ? AppColors.accent : t.isUpcoming ? AppColors.ball : AppColors.text2,
              ),
            ]),
          ),
          const SizedBox(height: 24),

          if (alreadyRegistered) ...[
            // Already registered
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _myRegistration!.isOnTeam
                  ? AppColors.accent.withOpacity(0.1)
                  : AppColors.ball.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _myRegistration!.isOnTeam ? AppColors.accent : AppColors.ball),
              ),
              child: Row(children: [
                Icon(
                  _myRegistration!.isOnTeam ? Icons.check_circle : Icons.how_to_reg,
                  color: _myRegistration!.isOnTeam ? AppColors.accent : AppColors.ball,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    _myRegistration!.isOnTeam ? "You're on a team!" : "You're registered!",
                    style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15,
                      color: _myRegistration!.isOnTeam ? AppColors.accent : AppColors.ball),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _myRegistration!.isOnTeam
                      ? 'You have been assigned to a team. Check the league page.'
                      : 'Waiting for a captain to add you to a team.',
                    style: const TextStyle(color: AppColors.text2, fontSize: 13)),
                ])),
              ]),
            ),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => context.go('/tournament/${widget.tournamentId}'),
              child: const Text('View League'),
            )),
          ] else ...[
            // Registration form
            const Text('Register as a Player', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 4),
            const Text("Tell captains who you are so they can add you to a team.",
              style: TextStyle(color: AppColors.text2, fontSize: 13)),
            const SizedBox(height: 20),

            // Role
            const Text('Your preferred role', style: TextStyle(
              color: AppColors.text2, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: _roles.map((r) {
              final selected = _role == r.$1;
              return GestureDetector(
                onTap: () => setState(() => _role = r.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accent : AppColors.bgCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: selected ? AppColors.accent : AppColors.border)),
                  child: Text(r.$2, style: TextStyle(
                    color: selected ? AppColors.textOnAcc : AppColors.text2,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    fontSize: 13)),
                ),
              );
            }).toList()),
            const SizedBox(height: 16),

            // Bio
            TextField(
              controller: _bioCtrl,
              maxLines: 3,
              style: const TextStyle(color: AppColors.text),
              decoration: const InputDecoration(
                labelText: 'Short bio (optional)',
                hintText: 'e.g. Right-arm medium pacer, 8 years playing exp.',
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _saving ? null : _register,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnAcc))
                : const Text('Register for this League',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            )),
          ],
        ]),
      ),
    );
  }
}

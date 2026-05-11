import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'models/models.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/new_password_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/match/setup_screen.dart';
import 'screens/match/scoring_screen.dart';
import 'screens/match/scorecard_screen.dart';
import 'screens/tournament/tournament_list_screen.dart';
import 'screens/tournament/tournament_detail_screen.dart';
import 'screens/tournament/team_roster_screen.dart';

// ── Auth State Provider ───────────────────────────────────────
final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<AuthUser?>>((ref) {
  return AuthNotifier();
});

class AuthNotifier extends StateNotifier<AsyncValue<AuthUser?>> {
  AuthNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  Future<void> _init() async {
    final user = await AuthService.instance.restoreSession();
    state = AsyncValue.data(user);
  }

  Future<void> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final user = await AuthService.instance.signIn(email, password);
      state = AsyncValue.data(user);
    } catch (e) {
      state = const AsyncValue.data(null);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await AuthService.instance.signOut();
    state = const AsyncValue.data(null);
  }

  void setUser(AuthUser user) => state = AsyncValue.data(user);
}

// ── Router ────────────────────────────────────────────────────
final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/',        builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/login',   builder: (_, __) => const LoginScreen()),
    GoRoute(
      path: '/new-password',
      builder: (_, state) => NewPasswordScreen(
        email: state.uri.queryParameters['email'] ?? ''),
    ),
    GoRoute(path: '/setup',   builder: (_, __) => const SetupScreen()),
    GoRoute(
      path: '/scoring/:matchId',
      builder: (_, state) => ScoringScreen(matchId: state.pathParameters['matchId']!),
    ),
    GoRoute(
      path: '/scorecard/:matchId',
      builder: (_, state) => ScorecardScreen(matchId: state.pathParameters['matchId']!),
    ),
    GoRoute(path: '/tournaments', builder: (_, __) => const TournamentListScreen()),
    GoRoute(
      path: '/tournament/:id',
      builder: (_, state) => TournamentDetailScreen(tournamentId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/tournament/:tournamentId/team/:teamId',
      builder: (_, state) => TeamRosterScreen(
        tournamentId: state.pathParameters['tournamentId']!,
        teamId: state.pathParameters['teamId']!,
      ),
    ),
  ],
);

// ── App Entry ─────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp, DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const ProviderScope(child: CricScoreApp()));
}

class CricScoreApp extends ConsumerWidget {
  const CricScoreApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'CricScore',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
      builder: (context, child) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: child!,
          ),
        );
      },
    );
  }
}

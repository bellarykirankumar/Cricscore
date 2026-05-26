# Frontend

Flutter app targeting iOS and Android. Minimum iOS deployment target: 13.0. Flutter SDK ≥ 3.19.0.

---

## Key dependencies

| Package | Version | Purpose |
|---|---|---|
| `flutter_riverpod` | ^2.5.1 | State management |
| `go_router` | ^13.2.0 | Declarative navigation |
| `http` | ^1.2.1 | REST API calls |
| `flutter_secure_storage` | ^9.0.0 | JWT token storage (iOS Keychain) |
| `shared_preferences` | ^2.2.3 | Country/user prefs |
| `camera` | ^0.10.5+9 | Rolling pre-buffer recording |
| `video_player` | ^2.9.1 | Clip playback |
| `web_socket_channel` | ^3.0.1 | WebSocket clip triggers |
| `speech_to_text` | ^7.4.0 | Voice scoring input |
| `image_picker` | ^1.0.7 | Photo library access |
| `fl_chart` | ^0.67.0 | Stats charts |
| `intl` | ^0.19.0 | Date formatting |
| `uuid` | ^4.4.0 | Client-side ID generation |
| `firebase_core` | ^3.6.0 | Firebase SDK initialisation |
| `firebase_crashlytics` | ^4.1.3 | Crash reporting (iOS + Android) |

---

## Navigation

Uses `GoRouter` with path-based routes. Defined in `lib/main.dart`.

```
/                       → HomeScreen (redirect based on auth)
/login                  → LoginScreen
/signup                 → SignupScreen
/new-password           → NewPasswordScreen

/home                   → HomeScreen (shell with bottom nav)
  /matches              → Match list tab
  /tournaments          → Tournament list tab
  /account              → Account tab

/scoring/:matchId       → ScoringScreen
/scorecard/:matchId     → ScorecardScreen
/commentary/:matchId    → CommentaryScreen (inside scorecard)
/highlights/:matchId    → HighlightsGalleryScreen

/tournament/:id         → TournamentDetailScreen (Teams/Fixtures/Standings tabs)
/tournament/:id/roster/:teamId    → TeamRosterScreen
/tournament/:id/player/:playerId  → PlayerProfileScreen
/tournament/setup       → TournamentSetupWizardScreen
```

Auth guard: `GoRouter` redirect checks for a valid JWT in `FlutterSecureStorage`. Unauthenticated users are redirected to `/login`.

---

## State management

Uses Riverpod with `StateNotifier` providers. No code generation (`riverpod_generator` not used — plain providers).

Key providers (defined in `lib/main.dart` and screen files):

| Provider | Type | Description |
|---|---|---|
| `authProvider` | `StateNotifierProvider<AuthNotifier, AuthUser?>` | Current logged-in user |
| `matchListProvider` | `FutureProvider<List<CricMatch>>` | Match list for home screen |
| `tournamentListProvider` | `FutureProvider<List<Tournament>>` | Tournaments filtered by country |

Most screens use `StatefulWidget` with manual state (not Riverpod) for local UI state like form inputs, loading flags, and pagination. Riverpod is mainly used for global auth state and shared data.

---

## Screens

### Auth screens (`lib/screens/auth/`)

- **LoginScreen** — email/password login via Cognito. Handles `NEW_PASSWORD_REQUIRED` challenge by redirecting to `NewPasswordScreen`.
- **SignupScreen** — email/password signup with email verification code step.
- **NewPasswordScreen** — forced password change for admin-created accounts.

### Home screen (`lib/screens/home/`)

- **HomeScreen** — `BottomNavigationBar` with 3 tabs: Matches, Tournaments, Account. Uses `IndexedStack` to preserve tab state.
- **FixtureTossSheet** — bottom sheet for recording toss result before a fixture match starts.

### Match screens (`lib/screens/match/`)

- **SetupScreen** — create a new match (select teams, format, overs, toss).
- **ScoringScreen** — primary scoring UI. Ball-by-ball tap interface.
  - Handles: runs (0–6), wide, no-ball, byes, leg-byes, wickets with dismissal type
  - Connects to `ClipWsService` on init, sends clip triggers on wickets/boundaries
  - Camera shortcut: bottom sheet → navigate to `CameraBufferScreen`
- **ScorecardScreen** — tabbed view: scorecard per innings + commentary tab.
  - AppBar 📹 button → `HighlightsGalleryScreen`
- **CommentaryScreen** — ball-by-ball log. Loads clips and shows `ClipPlayButton` inline when a clip exists for that delivery.
- **CameraBufferScreen** — rolling pre-buffer camera. Records 10s segments, keeps last 3 in memory (30s lookback). On clip trigger, records 5s post-roll then uploads segments to S3.
- **HighlightsGalleryScreen** — 3-tab grid (All / Wickets 🎯 / Boundaries). Shows `HighlightCard` per clip.

### Tournament screens (`lib/screens/tournament/`)

- **TournamentListScreen** — paginated list, filtered by user's country. Admin sees all.
- **TournamentDetailScreen** — 3 tabs: Teams, Fixtures, Standings.
  - Fixtures tab: shows toss button for owned tournaments, create fixture button.
- **TeamRosterScreen** — team squad with player rows. CSV import for admins/owners.
- **PlayerProfileScreen** — player career stats, batting/bowling breakdown.
- **TournamentSetupWizardScreen** — multi-step wizard: format → teams → schedule. AI-assisted team name suggestions and fixture generation.

### Support screen (`lib/screens/support/`)

- **SupportChatScreen** — AI-powered in-app support chat. Sends messages to `POST /support/chat` (Claude Haiku). Shows a 3-dot typing indicator while waiting, renders chat bubbles for user/assistant messages, and displays an escalation banner when the AI flags an issue for the team.

### Widgets (`lib/widgets/`)

- **ClipPlayButton** — compact `▶ Clip` button shown on commentary rows. Taps open `ClipPlayerScreen`.
- **ClipPlayerScreen** — full-screen `video_player` with scrubbing and tap-to-pause.
- **HighlightCard** — grid card with event emoji + over.ball label. Taps open `ClipPlayerScreen`.
- **CountryPickerSheet** — shown on first login. Stores country in `FlutterSecureStorage`.
- **SharedWidgets** — common UI components (loading spinners, error states, etc.).

---

## Utilities (`lib/utils/`)

### `cricket_utils.dart`
Pure stateless functions — no Flutter or network dependencies, making them trivially testable.

| Function | Description |
|---|---|
| `CricketUtils.bowlerQuota(format, overs)` | Max overs a bowler may bowl (null = unlimited for Test) |
| `CricketUtils.runRate(runs, balls)` | Current run rate (runs per over) |
| `CricketUtils.requiredRunRate(target, scored, ballsLeft)` | Required run rate for 2nd innings |
| `CricketUtils.oversDisplay(balls)` | Format ball count as "3.1" (3 overs 1 ball) |
| `CricketUtils.isLegal(extraType)` | Returns false for wide/no-ball (don't advance over count) |
| `CricketUtils.projectedScore(runs, balls, totalBalls)` | Projected final score at current rate |

---

## Auth flow

```
App launch
    │
    ▼
Firebase.initializeApp()   ← Crashlytics hooks installed here
    │
    ▼
FlutterSecureStorage.read('id_token')
    │
    ├─ token exists & valid ──► HomeScreen
    │
    ├─ token expired ──► AuthService.refreshToken()
    │                        │
    │                        ├─ success ──► HomeScreen
    │                        └─ fail    ──► LoginScreen
    │
    └─ no token ──► LoginScreen
```

Token storage keys:
- `id_token` — Cognito ID JWT (used for API auth)
- `access_token` — Cognito Access JWT
- `refresh_token` — Cognito Refresh token (30-day validity)
- `user_sub` — Cognito user UUID
- `user_email` — cached email
- `user_country` — user's country selection
- `is_admin` — cached admin flag (from Cognito custom:role claim)

---

## Ownership model

Who can edit/delete what is enforced in the UI (backend should also enforce, future work):

```dart
// AuthUser helpers
bool canManage(String? createdBy) => isAdmin || sub == createdBy;
bool isScorerFor(Tournament t) => t.scorerIds.contains(sub);
bool get isAdmin => role == 'admin';  // from Cognito custom:role
```

Tournament creators see full management controls. Invited scorers can score matches but cannot edit tournament settings or delete fixtures.

---

## Video clip system (Phase 2)

### Rolling pre-buffer
`CameraBufferScreen` uses the `camera` package to record continuously in 10s chunks. Up to 3 chunks are kept in memory (30s total). When a `ClipTriggerEvent` arrives via `ClipWsService.onTrigger`, the screen:
1. Stops buffering new chunks
2. Records a 5s post-roll segment
3. Uploads all segments to S3 using presigned PUT URLs from `ClipApi.presign()`
4. Saves metadata for the first (primary) segment via `ClipApi.save()`

### Clip matching in commentary
Clips are keyed as `"${innings}_${over}_${ball}"` where `ball` is 0-based (Lambdas and `MatchClip` are 0-based; `CommentaryEntry.ball` is 1-based).

```dart
// Correct matching in commentary_screen.dart
final key = '${e.innings}_${e.over}_${e.ball - 1}';
final clip = _clips[key];
```

### MatchClip model
Named `MatchClip` (not `Clip`) to avoid collision with Flutter's built-in `Clip` enum.

---

## Automated testing

Tests live in `test/` and run automatically on every push via GitHub Actions (`.github/workflows/ci.yml`).

```
test/
  widget_test.dart              — smoke test (runner sanity check)
  unit/
    models_test.dart            — AuthUser roles, Tournament status, BowlerStats,
                                  MatchClip, Delivery.fromJson (flat + legacy formats)
    cricket_utils_test.dart     — bowlerQuota, runRate, requiredRunRate,
                                  oversDisplay, isLegal, projectedScore
  widget/
    login_screen_test.dart      — form rendering, validation errors, password toggle
```

**Running locally:**
```bash
flutter test                  # all 64 tests (~1s)
flutter test test/unit/       # unit tests only (fastest)
```

**CI pipeline (GitHub Actions):**
1. `flutter pub get`
2. `flutter analyze --fatal-infos` — type errors + lint
3. `flutter test --dart-define=ENV=dev` — all tests

The pipeline runs on every push and pull request to `main`. A failing test blocks the commit from being considered clean.

---

## Known technical debt

| Item | Location | Notes |
|---|---|---|
| Dead duplicate files | `lib/auth/`, `lib/home/`, `lib/match/`, `lib/tournament/` | Old copies from before `lib/screens/` was created. Router ignores them. Safe to delete. |
| Backend ownership enforcement | All Lambda functions | Ownership is only checked in Flutter UI, not in Lambda. A malicious API call could bypass it. |
| No offline support | All screens | App requires network. No local caching or offline mode. |
| Video stitching | `camera_buffer_screen.dart` | Segments uploaded individually. No on-device stitching (FFmpeg removed). Server-side stitching not yet built. |
| Lambda code not in repo | `/tmp/cricscore-*/` | Lambda source should move to a `backend/` directory in this repo. |

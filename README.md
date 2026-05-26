# CricScore 🏏

AI-assisted cricket scoring platform — live match scoring, tournament management, team rosters, and video highlights. Available on iOS.

**App Store:** [CricScore on the App Store](https://apps.apple.com/us/app/randomcricscore/id6767393901)  
**Website:** [cricscore.randomappsstore.com](https://cricscore.randomappsstore.com)

---

## What it does

| Feature | Status |
|---|---|
| Live ball-by-ball scoring (T10 → Test) | ✅ |
| Tournament management (fixtures, standings) | ✅ |
| Team & player rosters, CSV bulk import | ✅ |
| Country-based tournament filtering | ✅ |
| Invite co-scorers by email | ✅ |
| Video highlight clips (wickets, fours, sixes) | ✅ |
| Commentary with inline clip playback | ✅ |
| Highlights gallery | ✅ |
| AI-assisted tournament setup & team names | ✅ |
| Android support | 🔜 |

---

## Tech stack

| Layer | Technology |
|---|---|
| Mobile | Flutter (Dart), Riverpod, GoRouter |
| Auth | AWS Cognito (raw HTTP, no Amplify) |
| Backend | AWS Lambda (Node.js 20) + API Gateway |
| Database | AWS DynamoDB (single-table design) |
| Video storage | AWS S3 + CloudFront |
| Real-time | AWS API Gateway WebSocket |
| AI features | Anthropic Claude API |

---

## Quick start

### Prerequisites
- Flutter SDK ≥ 3.19.0
- Xcode (iOS builds)
- AWS CLI configured (`aws configure`)
- An iPhone or iOS Simulator

### Run locally (dev backend)
```bash
cd cricscore_flutter
flutter pub get
flutter run                        # hits dev backend by default
```

### Run with prod backend
```bash
flutter run --dart-define=ENV=prod
```

### Build for App Store
```bash
flutter build ipa --dart-define=ENV=prod
# Then open Transporter and upload the .ipa
```

---

## Project structure

```
lib/
├── config.dart                  # Environment config (dev/prod URLs)
├── main.dart                    # App entry point, router
├── models/
│   └── models.dart              # All data models
├── services/
│   ├── auth_service.dart        # Cognito auth (login, signup, token refresh)
│   ├── api_service.dart         # All REST API calls
│   └── clip_ws_service.dart     # WebSocket for clip triggers
├── screens/
│   ├── auth/                    # Login, signup, new password
│   ├── home/                    # Home shell, fixture toss sheet
│   ├── match/                   # Scoring, scorecard, commentary, camera, highlights
│   └── tournament/              # List, detail, roster, player profile, setup wizard
├── widgets/
│   ├── clip_player_widget.dart  # Inline clip button + fullscreen player
│   ├── country_picker_sheet.dart
│   └── shared_widgets.dart
└── theme/
    └── app_theme.dart
```

---

## Documentation

| Doc | Description |
|---|---|
| [Architecture](docs/architecture.md) | System diagram, AWS infrastructure, data flow |
| [Backend](docs/backend.md) | Lambda functions, API endpoints, WebSocket |
| [Frontend](docs/frontend.md) | Flutter screens, navigation, state management |
| [Data Model](docs/data-model.md) | DynamoDB single-table design, all entity schemas |
| [Environments](docs/environments.md) | Dev/prod setup, deployment, App Store process |

---

## Environments

| | Dev | Prod |
|---|---|---|
| Run command | `flutter run` | `flutter build ipa --dart-define=ENV=prod` |
| DynamoDB | `CricScore-dev` | `CricScore-prod` |
| Cognito pool | `us-east-1_9H7UT8B1I` | `us-east-1_q5DAEOe9G` |
| REST API | `r78anm7dvb/dev` | `j6czhcdaz8/prod` |
| WebSocket | `2fziydn0oj/dev` | `gx2b5g04zb/prod` |

---

## Contact

Built by Bellary Kiran Kumar — [bellarykirankumar@gmail.com](mailto:bellarykirankumar@gmail.com)

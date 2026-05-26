# Environments

CricScore has two environments — **dev** and **prod** — with completely separate AWS resources (database, auth, storage, APIs).

---

## Environment config

All environment-specific values live in **`lib/config.dart`**. Never hardcode URLs in service files.

```dart
// lib/config.dart
const _env = String.fromEnvironment('ENV', defaultValue: 'dev');
const bool isProd = _env == 'prod';

const String apiBase   = isProd ? 'https://j6czhcdaz8.../prod' : 'https://r78anm7dvb.../dev';
const String wsUrl     = isProd ? 'wss://gx2b5g04zb.../prod'   : 'wss://2fziydn0oj.../dev';
const String cognitoPoolId   = isProd ? 'us-east-1_q5DAEOe9G' : 'us-east-1_9H7UT8B1I';
const String cognitoClientId = isProd ? '2kr2g7njtctpjr7tn7mk1rq3l5' : '126l3iutfb2a6qpf2jhapligsg';
```

---

## Running the app

### Dev (daily development)
```bash
flutter run
# or explicitly:
flutter run --dart-define=ENV=dev
```
Hits `CricScore-dev` DynamoDB, dev Cognito pool. Test accounts here won't appear in prod.

### Prod (testing prod backend locally)
```bash
flutter run --dart-define=ENV=prod
```
Hits `CricScore-prod`. Use carefully — this is real user data.

---

## Building for App Store

```bash
# 1. Bump version in pubspec.yaml
#    version: 1.0.5+19   ← increment both semver and build number

# 2. Build the IPA
flutter build ipa --dart-define=ENV=prod

# 3. Open Transporter
open /Applications/Transporter.app
# Drag in: build/ios/ipa/cricscore.ipa
# Click Deliver

# 4. Wait ~30 min, then check App Store Connect → TestFlight
```

### Version numbering
- Format: `MAJOR.MINOR.PATCH+BUILD`
- Example: `1.0.5+19` = version 1.0.5, build 19
- Build number must increase with every upload to App Store Connect
- Current: `1.0.4+18` (in pubspec.yaml)

---

## AWS resource reference

### Dev environment

| Resource | Name / ID |
|---|---|
| DynamoDB | `CricScore-dev` |
| S3 clips | `cricscore-clips-dev-115635400323` |
| Cognito pool | `us-east-1_9H7UT8B1I` |
| Cognito client | `126l3iutfb2a6qpf2jhapligsg` |
| REST API | `r78anm7dvb` → stage `dev` |
| WebSocket API | `2fziydn0oj` → stage `dev` |
| Lambda functions | `cricscore-*-dev` (×7) |

### Prod environment

| Resource | Name / ID |
|---|---|
| DynamoDB | `CricScore-prod` |
| S3 clips | `cricscore-clips-prod-115635400323` |
| Cognito pool | `us-east-1_q5DAEOe9G` |
| Cognito client | `2kr2g7njtctpjr7tn7mk1rq3l5` |
| REST API | `j6czhcdaz8` → stage `prod` |
| WebSocket API | `gx2b5g04zb` → stage `prod` |
| Lambda functions | `cricscore-*-prod` (×7) |

---

## Deploying backend changes

Lambda source is deployed independently of the Flutter app. When a Lambda needs a change:

```bash
# Edit the Lambda source in /tmp/cricscore-<domain>/
# Then zip and deploy:

cd /tmp/cricscore-match
zip -r function.zip .

# Deploy to dev first
aws lambda update-function-code \
  --function-name cricscore-match-dev \
  --zip-file fileb://function.zip

# Test thoroughly with flutter run (hits dev)

# Then deploy to prod
aws lambda update-function-code \
  --function-name cricscore-match-prod \
  --zip-file fileb://function.zip
```

> **Future improvement:** Move Lambda source into `backend/` in this repo and set up a deploy script or GitHub Actions to automate this.

---

## Deploying website changes

The website is a static S3 site behind CloudFront.

```bash
# Edit files in ~/cricscore-website/ or directly in /tmp/

# Upload to S3
aws s3 cp privacy.html s3://cricscore.randomappsstore.com/privacy.html --content-type "text/html"
aws s3 cp about.html   s3://cricscore.randomappsstore.com/about.html   --content-type "text/html"
aws s3 cp index.html   s3://cricscore.randomappsstore.com/index.html   --content-type "text/html"

# Invalidate CloudFront cache (changes live within ~60 seconds)
aws cloudfront create-invalidation \
  --distribution-id E1PILK3UT9S7HX \
  --paths "/*"
```

---

## Git workflow

```
main branch = source of truth

Feature/fix:
  1. Make changes (flutter run to test on dev)
  2. git add <specific files>
  3. git commit -m "description"
  4. git push origin main

App Store release:
  1. Bump version in pubspec.yaml
  2. git commit -m "Bump version to 1.0.5+19"
  3. git push origin main
  4. flutter build ipa --dart-define=ENV=prod
  5. Upload via Transporter
```

### What is / isn't in the repo

| In repo | Not in repo |
|---|---|
| All Flutter/Dart source | Lambda source (in `/tmp/` locally) |
| iOS project files | `build/` directory |
| pubspec.yaml + lock | `ios/Pods/` |
| .gitignore | `.dart_tool/` |
| docs/ | Secrets / API keys |

---

## TestFlight & App Store

- **Bundle ID:** `com.randomapps.cricscore` (set in Xcode / `ios/Runner.xcodeproj`)
- **Apple Team:** linked to `bellarykirankumar@gmail.com`
- **App Store Connect:** [App Store Connect](https://appstoreconnect.apple.com)
- **Current build:** 1.0.4 (18) — available on TestFlight

### Adding testers
- **Internal testers** (must be in Users & Access): Go to App Store Connect → Users and Access → add Apple ID → then add to TestFlight internal group
- **External testers** (any email): Create an External Testing group → add by email → requires one-time Beta App Review (~1 day)
- **Public link**: External group → Settings → Enable Public Link → share the URL

### Privacy policy URL (required by Apple)
`https://cricscore.randomappsstore.com/privacy.html`

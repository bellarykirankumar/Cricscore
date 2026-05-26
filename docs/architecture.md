# Architecture

## System overview

CricScore is a mobile-first cricket scoring platform with a serverless AWS backend. The iOS app communicates with two API layers — a REST API for data operations and a WebSocket API for real-time clip triggers.

```
┌──────────────────────────────────────────────────────────────────────┐
│                     iOS / Android App (Flutter)                      │
│                                                                      │
│  ┌──────────┐  ┌──────────────┐  ┌────────────────┐  ┌───────────┐  │
│  │   Auth   │  │  REST calls  │  │  WebSocket     │  │ Firebase  │  │
│  │(Cognito) │  │  (api_svc)   │  │ (clip trigger) │  │Crashlytics│  │
│  └────┬─────┘  └──────┬───────┘  └───────┬────────┘  └─────┬─────┘  │
└───────┼───────────────┼──────────────────┼────────────────┼─────────┘
        │               │                  │                │
        ▼               ▼                  ▼                ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐
│ AWS Cognito  │ │ API Gateway  │ │ API Gateway  │ │ Firebase Project │
│  User Pool   │ │ REST (HTTP)  │ │  WebSocket   │ │  cricscore-ffd4a │
└──────────────┘ └──────┬───────┘ └──────┬───────┘ └──────────────────┘
                        │                │
           ┌────────────┼──────────┐     │
           ▼            ▼          ▼     ▼
      ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
      │ Lambda  │ │ Lambda  │ │ Lambda  │ │ Lambda  │
      │  match  │ │tournam. │ │  clip   │ │   ws    │
      └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘
           │           │           │           │
      ┌────┴───────────┴───────────┘           │
      ▼                                        ▼
┌─────────────┐                        ┌─────────────┐
│  DynamoDB   │◄───────────────────────│  DynamoDB   │
│ CricScore-* │                        │ (conn store)│
└─────────────┘                        └─────────────┘

┌─────────────┐   ┌──────────────────┐
│  S3 Bucket  │   │   CloudFront     │
│(video clips)│──►│ (signed playUrls)│
└─────────────┘   └──────────────────┘

┌──────────────────────────────────────────────────┐
│              Monitoring (CloudWatch)             │
│  19 alarms → SNS → email bellarykirankumar@      │
│  Lambda errors/duration · API GW 5XX/latency ·  │
│  DynamoDB throttles                              │
└──────────────────────────────────────────────────┘
```

---

## Key design decisions

### 1. Serverless backend (Lambda + DynamoDB)
No servers to manage. Each Lambda function handles one domain (auth, match, tournament, player, clip, ws, ai). Pay-per-request on DynamoDB means near-zero cost at low volume.

### 2. Single-table DynamoDB design
All entities live in one table using composite keys (`PK` + `SK`) and a GSI. This enables efficient queries without joins. See [data-model.md](data-model.md) for full schema.

### 3. No Amplify
Cognito is called directly via raw HTTP (`cognito-idp` service endpoint). Avoids the 50MB+ Amplify dependency and gives full control over token handling and refresh logic.

### 4. WebSocket for clip triggers
When a scorer taps "wicket" or "boundary", a WebSocket message is sent to all camera devices connected to that match. The camera device records a rolling pre-buffer clip and uploads segments directly to S3 — no video passes through Lambda.

### 5. Rolling pre-buffer (no on-device FFmpeg)
The camera screen records 10s segments continuously, keeping the last 3 (30s lookback). On a clip trigger, it uploads the buffered segments individually to S3. FFmpeg was removed due to iOS CocoaPod compatibility issues. Stitching can be done server-side later.

### 6. Direct S3 upload via presigned URLs
The clip Lambda generates a presigned PUT URL. The device uploads directly to S3 — Lambda never touches the video bytes. This keeps Lambda fast and cheap.

---

## AWS infrastructure map

### Account
- **Account ID:** 115635400323
- **Region:** us-east-1

### API Gateway

| Name | Type | ID (dev) | ID (prod) |
|---|---|---|---|
| CricScore | REST | `r78anm7dvb` | `j6czhcdaz8` |
| cricscore-ws | WebSocket | `2fziydn0oj` | `gx2b5g04zb` |

### Lambda functions

| Function | Domain | Handler |
|---|---|---|
| `cricscore-auth-{env}` | Cognito user verification | `auth.handler` |
| `cricscore-match-{env}` | Match CRUD, innings, deliveries | `match.handler` |
| `cricscore-tournament-{env}` | Tournaments, fixtures, teams | `tournament.handler` |
| `cricscore-player-{env}` | Players, stats | `player.handler` |
| `cricscore-clip-{env}` | Presign URL, save/list clips | `handler.handler` |
| `cricscore-ws-{env}` | WebSocket connect/disconnect/trigger | `handler.handler` |
| `cricscore-ai-{env}` | Claude API: team names, schedule, commentary | `src/index.handler` |
| `cricscore-support-{env}` | AI support chat (Claude Haiku), escalation emails | `src/handler.handler` |

### DynamoDB

| Table | Purpose |
|---|---|
| `CricScore-dev` | Development data |
| `CricScore-prod` | Production data |

Both tables: `PK` (hash) + `SK` (range) + GSI1 (`GSI1PK` + `GSI1SK`). TTL attribute: `ttl`.

### Cognito

| Pool | ID | Client ID |
|---|---|---|
| `CricScore-dev` | `us-east-1_9H7UT8B1I` | `126l3iutfb2a6qpf2jhapligsg` |
| `CricScore-prod` | `us-east-1_q5DAEOe9G` | `2kr2g7njtctpjr7tn7mk1rq3l5` |

Auth flows: `USER_PASSWORD_AUTH`, `USER_SRP_AUTH`, `REFRESH_TOKEN_AUTH`.  
Token storage: `flutter_secure_storage` (iOS Keychain).

### S3

| Bucket | Purpose |
|---|---|
| `cricscore-clips-dev-115635400323` | Dev video segments |
| `cricscore-clips-prod-115635400323` | Prod video segments |
| `cricscore.randomappsstore.com` | Website (static HTML via CloudFront) |
| `cricscore-web-115635400323` | Legacy website bucket |

### IAM
Single execution role: `CricScoreLambdaRole` — used by all Lambda functions.

### Firebase
- **Project:** `cricscore-ffd4a` (Spark / free plan)
- **Services:** Crashlytics (iOS + Android)
- **Console:** https://console.firebase.google.com/project/cricscore-ffd4a/crashlytics

### Monitoring (CloudWatch + SNS)
- **SNS topic:** `cricscore-alerts` → subscription to `bellarykirankumar@gmail.com`
- **19 CloudWatch alarms** across all prod resources:
  - 8 × Lambda error alarms (one per function)
  - 8 × Lambda duration alarms (fires if any function exceeds 10 s)
  - 1 × API Gateway 5XX errors (≥3 in 60 s)
  - 1 × API Gateway high latency (avg >5 s over 5 min)
  - 1 × DynamoDB throttled requests

---

## Real-time clip flow

```
Scorer taps "Wicket" / "4" / "6"
          │
          ▼
  scoring_screen.dart
  ClipWsService.sendClipTrigger(matchId, inn, over, ball, event)
          │
          ▼ (WebSocket message: action=clipTrigger)
  API Gateway WebSocket  ──►  cricscore-ws Lambda
          │                        │
          │                   DynamoDB query:
          │                   WS_CONN rows for matchId
          │                        │
          │◄───── PostToConnection ─┘  (broadcasts to all connected cameras)
          │
          ▼ (camera device receives trigger)
  camera_buffer_screen.dart
  Records 5s post-roll → uploads segments to S3 via presigned URL
          │
          ▼
  ClipApi.presign() → cricscore-clip Lambda → S3 presigned PUT URL
  Device PUT to S3 directly
  ClipApi.save() → stores clip metadata in DynamoDB
```

---

## Website

Static site hosted on S3 + CloudFront. Deployed via AWS CLI.

- **URL:** https://cricscore.randomappsstore.com
- **CloudFront distribution:** `E1PILK3UT9S7HX`
- **Pages:** `index.html`, `about.html`, `privacy.html`
- **Deploy:** `aws s3 cp <file> s3://cricscore.randomappsstore.com/ && aws cloudfront create-invalidation --distribution-id E1PILK3UT9S7HX --paths "/*"`

# Backend

All backend logic runs on AWS Lambda (Node.js 20) behind API Gateway. No Express or framework — plain handler functions.

Lambda source lives at `/tmp/cricscore-<domain>/` locally (deployed directly, not in this repo). The Lambda code is deployed independently of the Flutter app.

---

## REST API endpoints

Base URL:
- **Dev:** `https://r78anm7dvb.execute-api.us-east-1.amazonaws.com/dev`
- **Prod:** `https://j6czhcdaz8.execute-api.us-east-1.amazonaws.com/prod`

All authenticated endpoints require an `Authorization: Bearer <idToken>` header. The Cognito ID token is refreshed automatically by `auth_service.dart` when it expires.

### Auth — `cricscore-auth-{env}`

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | _(Cognito direct)_ | No | Login — calls Cognito `InitiateAuth` directly |
| POST | _(Cognito direct)_ | No | Sign up, confirm sign up |

> Auth is handled directly against the Cognito endpoint, not through API Gateway. See `auth_service.dart`.

### Matches — `cricscore-match-{env}`

| Method | Path | Description |
|---|---|---|
| GET | `/matches` | List matches for current user |
| POST | `/matches` | Create a new match |
| GET | `/matches/{matchId}` | Get match detail |
| PUT | `/matches/{matchId}` | Update match (toss, result, etc.) |
| GET | `/matches/live` | Get live matches |
| POST | `/matches/{matchId}/innings` | Start a new innings |
| GET | `/matches/{matchId}/innings/{inningsNum}` | Get innings detail |
| POST | `/matches/{matchId}/innings/{inningsNum}/delivery` | Submit a delivery |
| POST | `/matches/{matchId}/innings/{inningsNum}/undo` | Undo last delivery |
| DELETE | `/matches/{matchId}/innings/{inningsNum}/undo` | Undo (alternate) |

### Tournaments — `cricscore-tournament-{env}`

| Method | Path | Description |
|---|---|---|
| GET | `/tournaments` | List tournaments (filtered by country) |
| POST | `/tournaments` | Create tournament |
| GET | `/tournaments/{tournamentId}` | Get tournament detail |
| PUT | `/tournaments/{tournamentId}` | Update tournament |
| GET | `/tournaments/{tournamentId}/fixtures` | List fixtures |
| POST | `/tournaments/{tournamentId}/fixtures` | Create fixture |
| POST | `/tournaments/{tournamentId}/fixtures/manual` | Create manual fixture |
| DELETE | `/tournaments/{tournamentId}/fixtures/{fixtureId}` | Delete fixture |
| GET | `/tournaments/{tournamentId}/standings` | Get points table |
| GET | `/tournaments/{tournamentId}/teams` | List teams |
| POST | `/tournaments/{tournamentId}/teams` | Add team |
| GET | `/tournaments/{tournamentId}/teams/{teamId}` | Get team |
| PUT | `/tournaments/{tournamentId}/teams/{teamId}` | Update team / roster |

### Players — `cricscore-player-{env}`

| Method | Path | Description |
|---|---|---|
| GET | `/players` | List players |
| POST | `/players` | Create player |
| GET | `/players/{playerId}` | Get player |
| PUT | `/players/{playerId}` | Update player |
| GET | `/players/{playerId}/stats` | Get player career stats |
| POST | `/players/{playerId}/claim` | Claim a player profile |
| GET | `/players/search` | Search players by name |
| POST | `/players/stats` | Batch update stats |
| POST | `/players/stats/batch` | Batch get stats |

### Video Clips — `cricscore-clip-{env}`

| Method | Path | Description |
|---|---|---|
| POST | `/clips/presign` | Get S3 presigned PUT URL for a new clip segment |
| POST | `/clips` | Save clip metadata to DynamoDB after upload |
| GET | `/clips?matchId=X` | List clips for a match (returns signed playUrls) |

**Presign request body:**
```json
{ "matchId": "abc", "inningsNumber": 1, "over": 3, "ball": 2, "event": "wicket" }
```
**Presign response:**
```json
{ "clipId": "uuid", "s3Key": "clips/abc/...", "uploadUrl": "https://s3.presigned..." }
```

**Save request body:**
```json
{
  "clipId": "uuid", "matchId": "abc", "s3Key": "clips/abc/...",
  "inningsNumber": 1, "over": 3, "ball": 2,
  "event": "wicket", "durationMs": 15000
}
```

### AI — `cricscore-ai-{env}`

Calls Anthropic Claude API. All endpoints require auth.

| Method | Path | Description |
|---|---|---|
| POST | `/ai/team-names` | Suggest team names for a tournament |
| POST | `/ai/schedule` | Generate a fixture schedule |
| POST | `/ai/tournament-setup` | AI-guided tournament configuration |
| POST | `/ai/commentary` | Generate commentary for a delivery |

---

## WebSocket API

Used for real-time clip triggers between scorer and camera devices.

**Dev:** `wss://2fziydn0oj.execute-api.us-east-1.amazonaws.com/dev`  
**Prod:** `wss://gx2b5g04zb.execute-api.us-east-1.amazonaws.com/prod`

Route selection: `$request.body.action`

### Routes

| Route key | Triggered by | Description |
|---|---|---|
| `$connect` | WebSocket connect | Stores connection ID in DynamoDB (TTL 12h) |
| `$disconnect` | WebSocket disconnect | Removes connection from DynamoDB |
| `joinMatch` | Client sends `{action:"joinMatch", matchId:"..."}` | Associates connection with a match |
| `clipTrigger` | Scorer sends trigger | Queries all connections for match, broadcasts to each |

### DynamoDB connection record
```
PK: WS_CONN
SK: CONN#<connectionId>
matchId: "abc123"
ttl: <unix timestamp + 12h>
```

### clipTrigger message format (sent by scorer)
```json
{
  "action": "clipTrigger",
  "matchId": "abc123",
  "inningsNumber": 1,
  "over": 3,
  "ball": 2,
  "event": "wicket"
}
```

### Broadcast payload (received by camera)
```json
{
  "type": "clipTrigger",
  "matchId": "abc123",
  "inningsNumber": 1,
  "over": 3,
  "ball": 2,
  "event": "wicket"
}
```

---

## Lambda environment variables

| Function | Variable | Dev value | Prod value |
|---|---|---|---|
| auth, match, tournament, player | `TABLE_NAME` | `CricScore-dev` | `CricScore-prod` |
| auth, match, tournament, player | `USER_POOL_ID` | `us-east-1_9H7UT8B1I` | `us-east-1_q5DAEOe9G` |
| auth, match, tournament, player | `ENV` | `dev` | `prod` |
| clip | `TABLE_NAME` | `CricScore-dev` | `CricScore-prod` |
| clip | `CLIP_BUCKET` | `cricscore-clips-dev-115635400323` | `cricscore-clips-prod-115635400323` |
| ws | `TABLE_NAME` | `CricScore-dev` | `CricScore-prod` |
| ai | `ANTHROPIC_API_KEY` | _(secret — same for both envs)_ | _(same)_ |

---

## Deploying Lambda changes

Lambda functions are deployed individually using the AWS CLI. There is no CI/CD pipeline yet — it's a manual deploy process:

```bash
# Example: redeploy the match Lambda
cd /tmp/cricscore-match
zip -r function.zip .
aws lambda update-function-code \
  --function-name cricscore-match-dev \
  --zip-file fileb://function.zip

# Same for prod
aws lambda update-function-code \
  --function-name cricscore-match-prod \
  --zip-file fileb://function.zip
```

> **Note:** Lambda source code is not currently in this repo. It should be moved to a `backend/` directory in a future cleanup.

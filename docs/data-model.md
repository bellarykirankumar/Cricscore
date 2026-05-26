# Data Model

CricScore uses a **DynamoDB single-table design** — all entities live in one table (`CricScore-dev` / `CricScore-prod`).

## Table structure

| Attribute | Type | Description |
|---|---|---|
| `PK` | String (Hash key) | Partition key |
| `SK` | String (Range key) | Sort key |
| `GSI1PK` | String | GSI partition key |
| `GSI1SK` | String | GSI sort key |
| `ttl` | Number | Unix timestamp for auto-expiry (WebSocket connections only) |

**GSI1** — `GSI1PK` (hash) + `GSI1SK` (range), `ProjectionType: ALL`

---

## Entity patterns

### Tournament

```
PK: TOURNAMENT#<tournamentId>
SK: TOURNAMENT

Attributes:
  tournamentId    String
  name            String
  format          String    // "T10" | "T20" | "ODI" | "Gully" | "Test"
  overs           Number
  createdBy       String    // Cognito user sub
  scorerIds       List<String>
  country         String?   // e.g. "IN", "AU"
  status          String    // "upcoming" | "ongoing" | "completed"
  createdAt       Number    // Unix ms
```

### Team (within tournament)

```
PK: TOURNAMENT#<tournamentId>
SK: TEAM#<teamId>

Attributes:
  teamId          String
  tournamentId    String
  name            String
  createdBy       String
  players         List<PlayerRef>   // [{playerId, name, jerseyNo, ...}]
```

### Fixture

```
PK: TOURNAMENT#<tournamentId>
SK: FIXTURE#<fixtureId>

Attributes:
  fixtureId       String
  tournamentId    String
  homeTeamId      String
  awayTeamId      String
  matchId         String?   // set when match is started
  scheduledAt     Number?
  status          String    // "scheduled" | "completed"
  result          String?
```

### Match

```
PK: MATCH#<matchId>
SK: MATCH

GSI1PK: MATCH_STATUS#<status>   // for live match queries
GSI1SK: MATCH#<matchId>

Attributes:
  matchId         String
  tournamentId    String?
  format          String
  overs           Number
  team1Id         String
  team2Id         String
  team1Name       String
  team2Name       String
  tossWinner      String?
  tossChoice      String?   // "bat" | "bowl"
  createdBy       String
  scorerIds       List<String>
  status          String    // "upcoming" | "live" | "completed"
  result          String?
  createdAt       Number
```

### Innings

```
PK: MATCH#<matchId>
SK: INN#<inningsNumber>          // e.g. INN#1, INN#2

Attributes:
  inningsNumber   Number          // 1 or 2
  battingTeamId   String
  bowlingTeamId   String
  runs            Number
  wickets         Number
  overs           Number          // completed overs
  balls           Number          // balls in current over
  extras          Map             // {wides, noBalls, byes, legByes}
  batters         List<BatterStat>
  bowlers         List<BowlerStat>
  status          String          // "ongoing" | "completed"
  result          String?
```

### Delivery

```
PK: MATCH#<matchId>
SK: INN#<inn>#OVR#<over>#BALL#<ball>
    // e.g. INN#1#OVR#03#BALL#04   (zero-padded)

Attributes:
  inningsNumber   Number
  over            Number          // 0-based
  ball            Number          // 1-based within over
  batsmanId       String
  batsmanName     String
  bowlerId        String
  bowlerName      String
  runs            Number          // runs off bat
  extras          Map?            // {type: "wide"|"noBall"|"bye"|"legBye", runs: 1}
  isWicket        Boolean
  wicket          Map?            // {type, batsmanId, fielderId?}
  totalRuns       Number          // runs + extras
  commentary      String?
```

### Player

```
PK: PLAYER#<playerId>
SK: PLAYER

GSI1PK: PLAYER_EMAIL#<email>    // for claim/lookup by email

Attributes:
  playerId        String
  name            String
  email           String?
  battingStyle    String?   // "Right-hand" | "Left-hand"
  bowlingStyle    String?   // "Right-arm Fast" | "Left-arm Spin" | etc.
  jerseyNo        Number?
  createdBy       String
  claimedBy       String?   // Cognito sub of the player's own account
```

### Player stats

```
PK: PLAYER#<playerId>
SK: STATS#<matchId>             // one record per match played

Attributes:
  matchId         String
  tournamentId    String?
  runsScored      Number
  ballsFaced      Number
  fours           Number
  sixes           Number
  wicketsTaken    Number
  runsConceded    Number
  oversBowled     Number
  catches         Number
  runouts         Number
  didBat          Boolean
  didBowl         Boolean
```

### Video clip

```
PK: MATCH#<matchId>
SK: CLIP#<pad(inn)>#<pad(over)>#<pad(ball)>#<clipId>
    // e.g. CLIP#01#03#02#uuid

Attributes:
  clipId          String
  matchId         String
  inningsNumber   Number
  over            Number    // 0-based
  ball            Number    // 0-based (note: CommentaryEntry.ball is 1-based)
  event           String    // "wicket" | "four" | "six" | "manual"
  s3Key           String
  durationMs      Number
  createdAt       Number
  // playUrl is generated on read (presigned CloudFront/S3 URL, not stored)
```

### WebSocket connection

```
PK: WS_CONN
SK: CONN#<connectionId>

Attributes:
  connectionId    String
  matchId         String    // set after joinMatch action
  ttl             Number    // Unix timestamp + 12 hours (DynamoDB auto-deletes)
```

---

## Query patterns

| Use case | Query |
|---|---|
| Get match | `PK = MATCH#<id>`, `SK = MATCH` |
| Get all innings for match | `PK = MATCH#<id>`, `SK begins_with INN#` |
| Get all deliveries in innings | `PK = MATCH#<id>`, `SK begins_with INN#<n>#OVR#` |
| Get all teams in tournament | `PK = TOURNAMENT#<id>`, `SK begins_with TEAM#` |
| Get all fixtures in tournament | `PK = TOURNAMENT#<id>`, `SK begins_with FIXTURE#` |
| Get live matches | GSI1: `GSI1PK = MATCH_STATUS#live` |
| Get player by email | GSI1: `GSI1PK = PLAYER_EMAIL#<email>` |
| Get clips for match | `PK = MATCH#<id>`, `SK begins_with CLIP#` |
| Get WebSocket connections for match | `PK = WS_CONN`, filter `matchId = <id>` |

---

## Dart models (lib/models/models.dart)

| Class | Maps to |
|---|---|
| `AuthUser` | Cognito token claims |
| `Tournament` | Tournament entity |
| `CricMatch` | Match entity |
| `Innings` | Innings entity |
| `Delivery` | Delivery entity |
| `Team` | Team entity |
| `Player` | Player entity |
| `PlayerStats` | Player stats entity |
| `Fixture` | Fixture entity |
| `MatchClip` | Video clip entity |
| `CommentaryEntry` | Derived from Delivery for display |

> **Note:** `MatchClip` is named with `Match` prefix to avoid collision with Flutter's built-in `Clip` enum (used in widget clipping).

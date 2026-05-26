// ─────────────────────────────────────────────────────────────
//  CricScore Flutter — Data Models
// ─────────────────────────────────────────────────────────────

// ── Auth ──────────────────────────────────────────────────────
class AuthUser {
  final String sub, email, name;
  final List<String> groups;

  const AuthUser({
    required this.sub, required this.email,
    required this.name, required this.groups,
  });

  bool get isAdmin  => groups.contains('admin');
  bool get isScorer => isAdmin || groups.contains('scorer');
  bool get isViewer => true;

  String get role => isAdmin ? 'admin' : isScorer ? 'scorer' : 'viewer';

  bool canManage(String? createdBy) => isAdmin || sub == createdBy;
  bool isScorerFor(Tournament t) =>
      isAdmin || t.createdBy == sub || isScorer ||
      t.scorerIds.contains(sub) || t.scorerIds.contains(email);

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
    sub:    j['sub']   as String,
    email:  j['email'] as String,
    name:   j['name']  as String? ?? j['email'] as String,
    groups: List<String>.from(j['cognito:groups'] as List? ?? []),
  );
}

// ── Tournament ────────────────────────────────────────────────
class Tournament {
  final String id, name, format, status;
  final int maxTeams, teamCount;
  final String? venue, startDate;
  final int createdAt;
  final String? createdBy;
  final List<String> scorerIds;
  final String? country;

  const Tournament({
    required this.id, required this.name, required this.format,
    required this.maxTeams, required this.teamCount, required this.status,
    this.venue, this.startDate, required this.createdAt,
    this.createdBy, this.scorerIds = const [], this.country,
  });

  bool get isActive    => status == 'in_progress';
  bool get isUpcoming  => status == 'upcoming';
  bool get isCompleted => status == 'completed';

  factory Tournament.fromJson(Map<String, dynamic> j) => Tournament(
    id:        j['id']        as String,
    name:      j['name']      as String,
    format:    j['format']    as String? ?? 'T20',
    maxTeams:  (j['maxTeams']  as num?)?.toInt() ?? 8,
    teamCount: (j['teamCount'] as num?)?.toInt() ?? 0,
    status:    j['status']    as String? ?? 'upcoming',
    venue:     j['venue']     as String?,
    startDate: j['startDate'] as String?,
    createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
    createdBy: j['createdBy'] as String?,
    scorerIds: List<String>.from(j['scorerIds'] as List? ?? []),
    country:   j['country']   as String?,
  );
}

// ── Team ──────────────────────────────────────────────────────
class Team {
  final String id, name, shortName;
  final String? tournamentId;
  final List<Player> players;

  final String? createdBy;

  const Team({
    required this.id, required this.name, required this.shortName,
    this.tournamentId, this.players = const [], this.createdBy,
  });

  Team copyWith({List<Player>? players}) => Team(
    id: id, name: name, shortName: shortName,
    tournamentId: tournamentId, createdBy: createdBy,
    players: players ?? this.players,
  );

  factory Team.fromJson(Map<String, dynamic> j) => Team(
    id:           j['id']           as String,
    name:         j['name']         as String,
    shortName:    j['shortName']    as String? ?? (j['name'] as String).substring(0, (j['name'] as String).length.clamp(0, 3)).toUpperCase(),
    tournamentId: j['tournamentId'] as String?,
    players:      (j['players']     as List?)?.map((p) => Player.fromJson(p as Map<String, dynamic>)).toList() ?? [],
    createdBy:    j['createdBy'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'shortName': shortName,
    if (tournamentId != null) 'tournamentId': tournamentId,
    if (createdBy != null) 'createdBy': createdBy,
    'players': players.map((p) => p.toJson()).toList(),
  };
}

// ── Player ────────────────────────────────────────────────────
class Player {
  final String id, teamId, name, shortName;
  final String role, battingStyle;
  final String? bowlingStyle;
  final int? jerseyNumber;
  // Registry fields
  final String? playerCode;  // e.g. "IN-000042"
  final String? country;     // ISO code e.g. "IN"
  final String? photoUrl;
  final String? bio;
  final String? claimedBy;   // userId of claiming account

  const Player({
    required this.id, required this.teamId,
    required this.name, required this.shortName,
    this.role = 'all_rounder', this.battingStyle = 'right_hand',
    this.bowlingStyle, this.jerseyNumber,
    this.playerCode, this.country, this.photoUrl, this.bio, this.claimedBy,
  });

  factory Player.fromJson(Map<String, dynamic> j) => Player(
    id:           j['id']           as String,
    teamId:       j['teamId']       as String? ?? '',
    name:         j['name']         as String,
    shortName:    j['shortName']    as String? ?? '',
    role:         j['role']         as String? ?? 'all_rounder',
    battingStyle: j['battingStyle'] as String? ?? 'right_hand',
    bowlingStyle: j['bowlingStyle'] as String?,
    jerseyNumber: (j['jerseyNumber'] as num?)?.toInt(),
    playerCode:   j['playerCode']   as String?,
    country:      j['country']      as String?,
    photoUrl:     j['photoUrl']     as String?,
    bio:          j['bio']          as String?,
    claimedBy:    j['claimedBy']    as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'teamId': teamId, 'name': name, 'shortName': shortName,
    'role': role, 'battingStyle': battingStyle,
    if (bowlingStyle != null)  'bowlingStyle': bowlingStyle,
    if (jerseyNumber != null)  'jerseyNumber': jerseyNumber,
    if (playerCode != null)    'playerCode':   playerCode,
    if (country != null)       'country':      country,
    if (photoUrl != null)      'photoUrl':     photoUrl,
    if (bio != null)           'bio':          bio,
    if (claimedBy != null)     'claimedBy':    claimedBy,
  };

  bool get isClaimed => claimedBy != null && claimedBy!.isNotEmpty;
}

// ── Fixture ───────────────────────────────────────────────────
class Fixture {
  final String id, homeTeamId, homeTeamName, awayTeamId, awayTeamName;
  final int round;
  final String status;
  final String? matchId, scheduledDate;

  const Fixture({
    required this.id, required this.homeTeamId, required this.homeTeamName,
    required this.awayTeamId, required this.awayTeamName,
    required this.round, required this.status,
    this.matchId, this.scheduledDate,
  });

  factory Fixture.fromJson(Map<String, dynamic> j) => Fixture(
    id:            j['id']           as String? ?? j['SK']         as String? ?? '',
    homeTeamId:    j['homeTeamId']   as String? ?? '',
    homeTeamName:  j['homeTeamName'] as String? ?? j['homeTeamId'] as String? ?? '',
    awayTeamId:    j['awayTeamId']   as String? ?? '',
    awayTeamName:  j['awayTeamName'] as String? ?? j['awayTeamId'] as String? ?? '',
    round:         (j['round']       as num?)?.toInt() ?? 1,
    status:        j['status']       as String? ?? 'scheduled',
    matchId:       j['matchId']      as String?,
    scheduledDate: j['scheduledDate'] as String?,
  );
}

// ── CricMatch ─────────────────────────────────────────────────
class CricMatch {
  final String id, format, status;
  final int oversPerInnings;
  final Team? team1, team2;
  final List<Innings>? innings;
  final Map<String, dynamic>? result;
  final String? tournamentId, venue, createdBy, country;
  final int createdAt;

  const CricMatch({
    required this.id, required this.format, required this.status,
    required this.oversPerInnings,
    this.team1, this.team2, this.innings, this.result,
    this.tournamentId, this.venue, this.createdBy, this.country,
    required this.createdAt,
  });

  factory CricMatch.fromJson(Map<String, dynamic> j) => CricMatch(
    id:              j['id']              as String,
    format:          j['format']          as String? ?? 'T20',
    status:          j['status']          as String? ?? 'not_started',
    oversPerInnings: (j['oversPerInnings'] as num?)?.toInt() ?? 20,
    team1:           j['team1'] != null ? Team.fromJson(j['team1'] as Map<String, dynamic>) : null,
    team2:           j['team2'] != null ? Team.fromJson(j['team2'] as Map<String, dynamic>) : null,
    innings:         (j['innings'] as List?)?.map((i) => Innings.fromJson(i as Map<String, dynamic>)).toList(),
    result:          j['result'] as Map<String, dynamic>?,
    tournamentId:    j['tournamentId'] as String?,
    venue:           j['venue'] as String?,
    createdBy:       j['createdBy'] as String?,
    country:         j['country'] as String?,
    createdAt:       (j['createdAt'] as num?)?.toInt() ?? 0,
  );
}

// ── Innings ───────────────────────────────────────────────────
class Innings {
  final String id, battingTeamId, bowlingTeamId;
  final int inningsNumber, totalRuns, totalWickets, totalBalls;
  final String status;
  final String? currentStrikerId, currentNonStrikerId, currentBowlerId;
  final Map<String, BatsmanStats> batsmanStats;
  final Map<String, BowlerStats> bowlerStats;
  final List<Delivery>? deliveries;
  final List<Map<String, dynamic>>? fallOfWickets;
  final List<String> battingOrder;
  final double currentRunRate;
  final double? requiredRunRate;
  final int? target, projectedScore;
  final Map<String, int>? extras;

  const Innings({
    required this.id, required this.battingTeamId, required this.bowlingTeamId,
    required this.inningsNumber, required this.totalRuns, required this.totalWickets,
    required this.totalBalls, required this.status,
    this.currentStrikerId, this.currentNonStrikerId, this.currentBowlerId,
    required this.batsmanStats, required this.bowlerStats,
    this.deliveries, this.fallOfWickets, required this.battingOrder,
    required this.currentRunRate, this.requiredRunRate,
    this.target, this.projectedScore, this.extras,
  });

  static Innings copyWith(Innings inn, {
    String? currentStrikerId, String? currentNonStrikerId, String? currentBowlerId,
    List<Delivery>? deliveries,
  }) => Innings(
    id: inn.id, battingTeamId: inn.battingTeamId, bowlingTeamId: inn.bowlingTeamId,
    inningsNumber: inn.inningsNumber, totalRuns: inn.totalRuns,
    totalWickets: inn.totalWickets, totalBalls: inn.totalBalls, status: inn.status,
    currentStrikerId:    currentStrikerId    ?? inn.currentStrikerId,
    currentNonStrikerId: currentNonStrikerId ?? inn.currentNonStrikerId,
    currentBowlerId:     currentBowlerId     ?? inn.currentBowlerId,
    batsmanStats: inn.batsmanStats, bowlerStats: inn.bowlerStats,
    deliveries:   deliveries ?? inn.deliveries,
    fallOfWickets: inn.fallOfWickets, battingOrder: inn.battingOrder,
    currentRunRate: inn.currentRunRate, requiredRunRate: inn.requiredRunRate,
    target: inn.target, projectedScore: inn.projectedScore, extras: inn.extras,
  );

  factory Innings.fromJson(Map<String, dynamic> j) {
    final bsRaw = j['batsmanStats'] as Map<String, dynamic>? ?? {};
    final wsRaw = j['bowlerStats']  as Map<String, dynamic>? ?? {};
    return Innings(
      id:              j['id']              as String? ?? '',
      battingTeamId:   j['battingTeamId']   as String? ?? '',
      bowlingTeamId:   j['bowlingTeamId']   as String? ?? '',
      inningsNumber:   (j['inningsNumber']  as num?)?.toInt() ?? 1,
      totalRuns:       (j['totalRuns']      as num?)?.toInt() ?? 0,
      totalWickets:    (j['totalWickets']   as num?)?.toInt() ?? 0,
      totalBalls:      (j['totalBalls']     as num?)?.toInt() ?? 0,
      status:          j['status']          as String? ?? 'not_started',
      currentStrikerId:    j['currentStrikerId']    as String?,
      currentNonStrikerId: j['currentNonStrikerId'] as String?,
      currentBowlerId:     j['currentBowlerId']     as String?,
      batsmanStats: bsRaw.map((k, v) =>
        MapEntry(k, BatsmanStats.fromJson(v as Map<String, dynamic>))),
      bowlerStats: wsRaw.map((k, v) =>
        MapEntry(k, BowlerStats.fromJson(v as Map<String, dynamic>))),
      deliveries: (j['deliveries'] as List?)?.map((d) =>
        Delivery.fromJson(d as Map<String, dynamic>)).toList(),
      fallOfWickets: (j['fallOfWickets'] as List?)?.cast<Map<String, dynamic>>(),
      battingOrder:   List<String>.from(j['battingOrder'] as List? ?? []),
      currentRunRate: (j['currentRunRate']  as num?)?.toDouble() ?? 0.0,
      requiredRunRate:(j['requiredRunRate'] as num?)?.toDouble(),
      target:         (j['target']         as num?)?.toInt(),
      projectedScore: (j['projectedScore'] as num?)?.toInt(),
      extras:         (j['extras']         as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, (v as num).toInt())),
    );
  }
}

// ── BatsmanStats ──────────────────────────────────────────────
class BatsmanStats {
  final String playerId;
  final int runsScored, ballsFaced, fours, sixes;
  final double strikeRate;
  final bool isOut, didNotBat;
  final Map<String, dynamic>? dismissal;

  const BatsmanStats({
    required this.playerId, required this.runsScored, required this.ballsFaced,
    required this.fours, required this.sixes, required this.strikeRate,
    required this.isOut, required this.didNotBat, this.dismissal,
  });

  factory BatsmanStats.fromJson(Map<String, dynamic> j) => BatsmanStats(
    playerId:   j['playerId']   as String? ?? '',
    runsScored: (j['runsScored']  as num?)?.toInt() ?? 0,
    ballsFaced: (j['ballsFaced']  as num?)?.toInt() ?? 0,
    fours:      (j['fours']       as num?)?.toInt() ?? 0,
    sixes:      (j['sixes']       as num?)?.toInt() ?? 0,
    strikeRate: (j['strikeRate']  as num?)?.toDouble() ?? 0.0,
    isOut:       j['isOut']      as bool? ?? false,
    didNotBat:   j['didNotBat']  as bool? ?? false,
    dismissal:   j['dismissal']  as Map<String, dynamic>?,
  );
}

// ── BowlerStats ───────────────────────────────────────────────
class BowlerStats {
  final String playerId;
  final int legalDeliveries, runsConceded, wicketsTaken, maidenOvers, wides, noBalls;
  final double economy;

  const BowlerStats({
    required this.playerId, required this.legalDeliveries,
    required this.runsConceded, required this.wicketsTaken,
    required this.maidenOvers, required this.wides, required this.noBalls,
    required this.economy,
  });

  String get oversBowled {
    final o = legalDeliveries ~/ 6;
    final b = legalDeliveries % 6;
    return '$o${b > 0 ? ".$b" : ""}';
  }

  factory BowlerStats.fromJson(Map<String, dynamic> j) => BowlerStats(
    playerId:        j['playerId']        as String? ?? '',
    legalDeliveries: (j['legalDeliveries'] as num?)?.toInt() ?? 0,
    runsConceded:    (j['runsConceded']    as num?)?.toInt() ?? 0,
    wicketsTaken:    (j['wicketsTaken']    as num?)?.toInt() ?? 0,
    maidenOvers:     (j['maidenOvers']     as num?)?.toInt() ?? 0,
    wides:           (j['wides']           as num?)?.toInt() ?? 0,
    noBalls:         (j['noBalls']         as num?)?.toInt() ?? 0,
    economy:         (j['economy']         as num?)?.toDouble() ?? 0.0,
  );
}

// ── Delivery ──────────────────────────────────────────────────
class Delivery {
  final int overNumber, ballNumber, runsBatsman, runsExtras, runsTotal;
  final bool isWicket, isLegalDelivery;
  final String? extraType;
  final String batsmanId, nonStrikerId, bowlerId;

  const Delivery({
    required this.overNumber, required this.ballNumber,
    required this.runsBatsman, required this.runsExtras, required this.runsTotal,
    required this.isWicket, required this.isLegalDelivery,
    this.extraType,
    required this.batsmanId, required this.nonStrikerId, required this.bowlerId,
  });

  factory Delivery.fromJson(Map<String, dynamic> j) => Delivery(
    overNumber:       (j['overNumber']       as num?)?.toInt() ?? 0,
    ballNumber:       (j['ballNumber']       as num?)?.toInt() ?? 0,
    runsBatsman:      (j['runsBatsman']      as num?)?.toInt() ??
                      (j['runs'] != null ? (j['runs']['batsman'] as num?)?.toInt() ?? 0 : 0),
    runsExtras:       (j['runsExtras']       as num?)?.toInt() ??
                      (j['runs'] != null ? (j['runs']['extras'] as num?)?.toInt() ?? 0 : 0),
    runsTotal:        (j['runsTotal']        as num?)?.toInt() ??
                      (j['runs'] != null ? (j['runs']['total'] as num?)?.toInt() ?? 0 : 0),
    isWicket:          j['isWicket']         as bool? ?? false,
    isLegalDelivery:   j['isLegalDelivery']  as bool? ?? true,
    extraType:         j['extraType'] as String? ??
                       ((j['extras'] as Map<String, dynamic>?)?['type'] as String?),
    batsmanId:         j['batsmanId']        as String? ?? '',
    nonStrikerId:      j['nonStrikerId']     as String? ?? '',
    bowlerId:          j['bowlerId']         as String? ?? '',
  );
}

// ── MatchClip ─────────────────────────────────────────────────
// A short video clip attached to a specific delivery.
class MatchClip {
  final String clipId, matchId, s3Key;
  final int inningsNumber, over, ball;
  final String event;   // 'wicket' | 'four' | 'six' | 'manual'
  final int durationMs;
  final int createdAt;
  final String? playUrl; // signed CloudFront / S3 URL (regenerated per fetch)

  const MatchClip({
    required this.clipId, required this.matchId, required this.s3Key,
    required this.inningsNumber, required this.over, required this.ball,
    required this.event, required this.durationMs, required this.createdAt,
    this.playUrl,
  });

  factory MatchClip.fromJson(Map<String, dynamic> j) => MatchClip(
    clipId:       j['clipId']       as String,
    matchId:      j['matchId']      as String,
    s3Key:        j['s3Key']        as String,
    inningsNumber:(j['inningsNumber'] as num?)?.toInt() ?? 1,
    over:         (j['over']         as num?)?.toInt() ?? 0,
    ball:         (j['ball']         as num?)?.toInt() ?? 0,
    event:         j['event']        as String? ?? 'manual',
    durationMs:   (j['durationMs']   as num?)?.toInt() ?? 0,
    createdAt:    (j['createdAt']    as num?)?.toInt() ?? 0,
    playUrl:       j['playUrl']      as String?,
  );

  String get eventEmoji {
    switch (event) {
      case 'wicket': return '🎯';
      case 'four':   return '4️⃣';
      case 'six':    return '6️⃣';
      default:       return '🎬';
    }
  }

  String get overDotBall => '$over.${ball + 1}';
}

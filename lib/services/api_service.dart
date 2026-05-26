import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/models.dart';
import 'auth_service.dart';
import '../config.dart' as config;

// ─────────────────────────────────────────────────────────────
//  CricScore API Service
//  Calls the existing AWS API Gateway endpoints
// ─────────────────────────────────────────────────────────────

const _baseUrl = config.apiBase;
const _storage = FlutterSecureStorage();

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class ApiService {
  static ApiService? _instance;
  static ApiService get instance => _instance ??= ApiService._();
  ApiService._();

  Future<Map<String, String>> _headers() async {
    await AuthService.instance.ensureFreshTokens();
    // Cognito User Pool authorizers on API Gateway expect the **ID token** in
    // `Authorization` (raw JWT, no "Bearer " — that prefix triggers SigV4 parsing).
    final id = (await _storage.read(key: 'id_token'))?.trim();
    if (id == null || id.isEmpty) {
      return {'Content-Type': 'application/json'};
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': id,
    };
  }

  Future<dynamic> _request(
    String method, String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    var uri = Uri.parse('$_baseUrl$path');
    if (query != null) uri = uri.replace(queryParameters: query);

    final headers = await _headers();
    http.Response res;

    switch (method) {
      case 'GET':
        res = await http.get(uri, headers: headers);
        break;
      case 'POST':
        res = await http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
        break;
      case 'PUT':
        res = await http.put(uri, headers: headers, body: jsonEncode(body ?? {}));
        break;
      case 'DELETE':
        res = await http.delete(uri, headers: headers);
        break;
      default:
        throw ApiException('Unknown method: $method');
    }

    if (res.statusCode >= 400) {
      Map<String, dynamic> err = {};
      try { err = jsonDecode(res.body) as Map<String, dynamic>; } catch (_) {}
      final fromJson = err['error'] as String? ?? err['message'] as String?;
      final trimmed = res.body.trim();
      final fromBody = (fromJson == null || fromJson.isEmpty) &&
              trimmed.isNotEmpty &&
              trimmed.length < 240 &&
              !trimmed.startsWith('<')
          ? trimmed
          : null;
      throw ApiException(
        fromJson ??
            fromBody ??
            'Request failed (HTTP ${res.statusCode})',
        res.statusCode,
      );
    }

    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }
}

// ── Match API ─────────────────────────────────────────────────
class MatchApi {
  static final _api = ApiService.instance;

  static Future<List<CricMatch>> live() async {
    final data = await _api._request('GET', '/matches/live') as List;
    return data.map((j) => CricMatch.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<List<CricMatch>> list() async {
    final data = await _api._request('GET', '/matches') as List;
    return data.map((j) => CricMatch.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<CricMatch> get(String matchId) async {
    final data = await _api._request('GET', '/matches/$matchId');
    return CricMatch.fromJson(data as Map<String, dynamic>);
  }

  static Future<CricMatch> create(Map<String, dynamic> payload) async {
    final data = await _api._request('POST', '/matches', body: payload);
    return CricMatch.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> update(String matchId, Map<String, dynamic> updates) async {
    await _api._request('PUT', '/matches/$matchId', body: updates);
  }

  static Future<Innings> getInnings(String matchId, int num) async {
    final data = await _api._request('GET', '/matches/$matchId/innings/$num');
    return Innings.fromJson(data as Map<String, dynamic>);
  }

  static Future<Map<String, dynamic>> startInnings(
      String matchId, Map<String, dynamic> payload) async {
    return await _api._request(
      'POST', '/matches/$matchId/innings', body: payload
    ) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> recordDelivery(
      String matchId, int inningsNum, Map<String, dynamic> payload) async {
    return await _api._request(
      'POST', '/matches/$matchId/innings/$inningsNum/delivery', body: payload
    ) as Map<String, dynamic>;
  }

  /// Undoes the last ball. When [rawBallNumber] is set, it should match the
  /// `rawBallNumber` last sent with [recordDelivery] for that delivery.
  static Future<dynamic> undoDelivery(
    String matchId,
    int inningsNum, {
    int? rawBallNumber,
  }) async {
    final body = <String, dynamic>{};
    if (rawBallNumber != null) {
      body['rawBallNumber'] = rawBallNumber;
    }
    return _api._request(
      'POST',
      '/matches/$matchId/innings/$inningsNum/undo',
      body: body,
    );
  }

  /// Backend may use different strings when a game is over.
  static bool isFinishedMatchStatus(String? status) {
    if (status == null || status.isEmpty) return false;
    switch (status.trim().toLowerCase()) {
      case 'completed':
      case 'complete':
      case 'ended':
      case 'finished':
      case 'closed':
        return true;
      default:
        return false;
    }
  }

  /// Resolves each [matchId] with [get] — needed because `GET /matches` often
  /// omits completed games, so list-based filtering never sees them.
  static Future<Map<String, String>> loadMatchStatusesForIds(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final out = <String, String>{};
    final list = ids.toList();
    const batchSize = 8;
    for (var i = 0; i < list.length; i += batchSize) {
      final end = math.min(i + batchSize, list.length);
      final chunk = list.sublist(i, end);
      final partial = await Future.wait(chunk.map((id) async {
        try {
          final m = await get(id);
          return <String, String>{id: m.status};
        } catch (_) {
          return <String, String>{};
        }
      }));
      for (final m in partial) {
        out.addAll(m);
      }
    }
    return out;
  }
}

// ── Tournament API ────────────────────────────────────────────
class TournamentApi {
  static final _api = ApiService.instance;

  static Future<List<Tournament>> list() async {
    final data = await _api._request('GET', '/tournaments') as List;
    return data
      .map((j) => Tournament.fromJson(j as Map<String, dynamic>))
      .where((t) => t.status != 'deleted' && t.status != 'archived')
      .toList();
  }

  static Future<Tournament> get(String id) async {
    final data = await _api._request('GET', '/tournaments/$id');
    return Tournament.fromJson(data as Map<String, dynamic>);
  }

  static Future<Tournament> create(Map<String, dynamic> payload) async {
    final data = await _api._request('POST', '/tournaments', body: payload);
    return Tournament.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> update(String id, Map<String, dynamic> updates) async {
    await _api._request('PUT', '/tournaments/$id', body: updates);
  }

  static Future<List<Team>> listTeams(String tournamentId) async {
    final data = await _api._request('GET', '/tournaments/$tournamentId/teams') as List;
    return data.map((j) => Team.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<Team> addTeam(String tournamentId, Map<String, dynamic> payload) async {
    final data = await _api._request(
      'POST', '/tournaments/$tournamentId/teams', body: payload
    );
    return Team.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> genFixtures(String tournamentId) async {
    await _api._request('POST', '/tournaments/$tournamentId/fixtures');
  }

  static Future<List<Fixture>> getFixtures(String tournamentId) async {
    final data = await _api._request('GET', '/tournaments/$tournamentId/fixtures') as List;
    return data.map((j) => Fixture.fromJson(j as Map<String, dynamic>)).toList();
  }

  /// Removes completed fixtures and fixtures whose linked match [status] is
  /// finished ([MatchApi.isFinishedMatchStatus]). [matchStatusById] comes from
  /// [MatchApi.loadMatchStatusesForIds].
  static List<Fixture> fixturesExcludingFinishedMatches(
    List<Fixture> fixtures,
    Map<String, String> matchStatusById,
  ) {
    return fixtures.where((f) {
      if (f.status == 'completed') return false;
      final mid = f.matchId;
      if (mid == null) return true;
      final st = matchStatusById[mid];
      if (MatchApi.isFinishedMatchStatus(st)) return false;
      return true;
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> getStandings(String tournamentId) async {
    final data = await _api._request('GET', '/tournaments/$tournamentId/standings') as List;
    return data.map((j) => j as Map<String, dynamic>).toList();
  }

  static Future<void> addFixture(String tournamentId, Map<String, dynamic> payload) async {
    await _api._request('POST', '/tournaments/$tournamentId/fixtures/manual', body: payload);
  }


  // Get fixtures that are not completed (including when the linked match has ended).
  // Pass [allowedTourIds] to restrict to specific tournaments (e.g. country-filtered).
  static Future<List<Map<String, dynamic>>> getAllFixtures({Set<String>? allowedTourIds}) async {
    try {
      final allTours = await list();
      final tours = allowedTourIds != null
          ? allTours.where((t) => allowedTourIds.contains(t.id)).toList()
          : allTours;
      print('[getAllFixtures] found ${tours.length} tournaments');
      final pending = <({Tournament t, Fixture f})>[];
      for (final t in tours) {
        print('[getAllFixtures] checking tournament: ${t.name} (${t.id})');
        try {
          final fixtures = await getFixtures(t.id);
          for (final f in fixtures) {
            if (f.status == 'completed') continue;
            pending.add((t: t, f: f));
          }
        } catch (e) {
          print('[getAllFixtures]   -> ERROR fetching fixtures for ${t.name}: $e');
        }
      }
      final matchIds = pending.map((e) => e.f.matchId).whereType<String>().toSet();
      final byStatus = await MatchApi.loadMatchStatusesForIds(matchIds);
      final all = <Map<String, dynamic>>[];
      for (final e in pending) {
        final f = e.f;
        final mid = f.matchId;
        if (mid != null && MatchApi.isFinishedMatchStatus(byStatus[mid])) continue;
        print('[getAllFixtures]   -> including: ${f.homeTeamName} vs ${f.awayTeamName}, scheduledDate=${f.scheduledDate}, status=${f.status}');
        all.add({'fixture': f, 'tournament': e.t});
      }
      all.sort((a, b) {
        final da = (a['fixture'] as Fixture).scheduledDate;
        final db = (b['fixture'] as Fixture).scheduledDate;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
      print('[getAllFixtures] returning ${all.length} total fixtures');
      return all;
    } catch (e) {
      print('[getAllFixtures] TOP-LEVEL ERROR: $e');
      return [];
    }
  }
  static Future<void> deleteFixture(String tournamentId, String fixtureId) async {
    await _api._request('DELETE', '/tournaments/$tournamentId/fixtures/$fixtureId');
  }
}

// ── Player API ────────────────────────────────────────────────
// ── AI Api ────────────────────────────────────────────────────
class AiApi {
  static final _api = ApiService.instance;

  /// Parse natural language into structured tournament setup data.
  static Future<Map<String, dynamic>> parseTournamentDescription(String description) async {
    final data = await _api._request('POST', '/ai/tournament-setup', body: {'description': description});
    return (data as Map<String, dynamic>?)?['result'] as Map<String, dynamic>? ?? {};
  }

  /// Generate a fixture schedule given constraints.
  static Future<List<Map<String, dynamic>>> generateSchedule(Map<String, dynamic> params) async {
    final data = await _api._request('POST', '/ai/schedule', body: params);
    final fixtures = (data as Map<String, dynamic>?)?['fixtures'] as List?;
    return fixtures?.map((f) => f as Map<String, dynamic>).toList() ?? [];
  }

  /// Generate ball-by-ball commentary for a single delivery.
  /// Returns empty string silently on any error — commentary is best-effort.
  static Future<String> generateCommentary(Map<String, dynamic> payload) async {
    try {
      final data = await _api._request('POST', '/ai/commentary', body: payload);
      return (data as Map<String, dynamic>?)?['commentary'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Suggest cricket team names based on location.
  static Future<List<String>> suggestTeamNames({String? location, int count = 8, List<String> existing = const []}) async {
    final data = await _api._request('POST', '/ai/team-names', body: {
      'count': count,
      if (location != null && location.isNotEmpty) 'location': location,
      if (existing.isNotEmpty) 'existingNames': existing,
    });
    final names = (data as Map<String, dynamic>?)?['names'] as List?;
    return names?.map((n) => n.toString()).toList() ?? [];
  }
}

class PlayerApi {
  static final _api = ApiService.instance;

  static Future<List<Player>> list(String teamId) async {
    final data = await _api._request('GET', '/players', query: {'teamId': teamId}) as List;
    return data.map((j) => Player.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<Player> create(Map<String, dynamic> payload) async {
    final data = await _api._request('POST', '/players', body: payload);
    return Player.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> update(String teamId, String playerId, Map<String, dynamic> updates) async {
    await _api._request('PUT', '/players/$playerId',
        query: {'teamId': teamId}, body: updates);
  }

  /// Search the country player registry by name.
  static Future<List<Player>> search(String country, String query) async {
    final data = await _api._request('GET', '/players/search',
        query: {'country': country, 'q': query}) as List;
    return data.map((j) => Player.fromJson(j as Map<String, dynamic>)).toList();
  }

  /// Get a single player by id (needs teamId for DynamoDB key).
  static Future<Player> getPlayer(String teamId, String playerId) async {
    final data = await _api._request('GET', '/players/$playerId',
        query: {'teamId': teamId});
    return Player.fromJson(data as Map<String, dynamic>);
  }

  /// Claim a player profile — links the player record to [userId].
  static Future<void> claim(String teamId, String playerId, String userId) async {
    await _api._request('POST', '/players/$playerId/claim',
        body: {'teamId': teamId, 'userId': userId});
  }

  /// Career stats for a player. Never throws — returns empty map on error.
  static Future<Map<String, dynamic>> getStats(String playerId) async {
    try {
      final data = await _api._request('GET', '/players/$playerId/stats');
      return (data as Map<String, dynamic>?) ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Batch update career stats at end of each innings.
  /// [players] = list of { playerId, batting?, bowling? } maps.
  static Future<void> batchUpdateStats(List<Map<String, dynamic>> players) async {
    if (players.isEmpty) return;
    try {
      await _api._request('POST', '/players/stats/batch',
          body: {'players': players});
    } catch (_) {}
  }
}

// ── Clip API ──────────────────────────────────────────────────
class ClipApi {
  static final _api = ApiService.instance;

  /// Step 1: get a presigned S3 PUT URL. The camera device uploads the MP4
  /// directly to S3 using this URL (no backend proxy needed).
  static Future<({String clipId, String s3Key, String uploadUrl})> presign({
    required String matchId,
    required int inningsNumber,
    required int over,
    required int ball,
    required String event, // 'wicket' | 'four' | 'six' | 'manual'
  }) async {
    final data = await _api._request('POST', '/clips/presign', body: {
      'matchId': matchId,
      'inningsNumber': inningsNumber,
      'over': over,
      'ball': ball,
      'event': event,
    }) as Map<String, dynamic>;
    return (
      clipId:    data['clipId']    as String,
      s3Key:     data['s3Key']     as String,
      uploadUrl: data['uploadUrl'] as String,
    );
  }

  /// Step 2: after upload completes, save the clip record to DynamoDB.
  static Future<MatchClip> save({
    required String matchId,
    required int inningsNumber,
    required int over,
    required int ball,
    required String event,
    required String s3Key,
    required int durationMs,
  }) async {
    final data = await _api._request('POST', '/clips', body: {
      'matchId': matchId,
      'inningsNumber': inningsNumber,
      'over': over,
      'ball': ball,
      'event': event,
      's3Key': s3Key,
      'durationMs': durationMs,
    }) as Map<String, dynamic>;
    return MatchClip.fromJson(data);
  }

  /// Fetch all clips for a match, optionally filtered to one innings.
  static Future<List<MatchClip>> list(String matchId, {int? inningsNumber}) async {
    final data = await _api._request('GET', '/clips', query: {
      'matchId': matchId,
      if (inningsNumber != null) 'inningsNumber': '$inningsNumber',
    }) as List;
    return data.map((j) => MatchClip.fromJson(j as Map<String, dynamic>)).toList();
  }
}

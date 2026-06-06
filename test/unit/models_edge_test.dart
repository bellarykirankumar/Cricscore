import 'package:flutter_test/flutter_test.dart';
import 'package:cricscore/models/models.dart';
import 'package:cricscore/utils/cricket_utils.dart';

void main() {
  // ── AuthUser edge cases ──────────────────────────────────────

  group('AuthUser — edge cases', () {
    test('multiple groups includes both admin and scorer', () {
      final u = AuthUser.fromJson({
        'sub': 's1', 'email': 'x@y.com', 'name': 'X',
        'cognito:groups': ['admin', 'scorer'],
      });
      expect(u.isAdmin,  isTrue);
      expect(u.isScorer, isTrue);
      expect(u.role,     equals('admin'));
    });

    test('empty name falls back to email', () {
      final u = AuthUser.fromJson({'sub': 's', 'email': 'a@b.com'});
      expect(u.name, equals('a@b.com'));
    });

    test('canManage returns true for own sub', () {
      final u = AuthUser(sub: 'u1', email: 'a@b.com', name: 'A', groups: []);
      expect(u.canManage('u1'), isTrue);
    });

    test('canManage returns false for other sub (non-admin)', () {
      final u = AuthUser(sub: 'u1', email: 'a@b.com', name: 'A', groups: []);
      expect(u.canManage('u2'), isFalse);
    });

    test('canManage returns true for admin on any sub', () {
      final u = AuthUser(sub: 'u1', email: 'a@b.com', name: 'A', groups: ['admin']);
      expect(u.canManage('u999'), isTrue);
    });

    test('isViewer is always true', () {
      final u = AuthUser(sub: 'u1', email: 'a@b.com', name: 'A', groups: []);
      expect(u.isViewer, isTrue);
    });
  });

  // ── Tournament edge cases ────────────────────────────────────

  group('Tournament — edge cases', () {
    test('unknown status is not active/upcoming/completed', () {
      final t = Tournament(
        id: 't', name: 'T', format: 'T20',
        maxTeams: 8, teamCount: 0, status: 'cancelled', createdAt: 0,
      );
      expect(t.isActive,    isFalse);
      expect(t.isUpcoming,  isFalse);
      expect(t.isCompleted, isFalse);
    });

    test('fromJson scorerIds parses list correctly', () {
      final t = Tournament.fromJson({
        'id': 't', 'name': 'T', 'createdAt': 0,
        'scorerIds': ['u1', 'u2'],
      });
      expect(t.scorerIds, equals(['u1', 'u2']));
    });

    test('isScorerFor: scorer by email', () {
      final t = Tournament(
        id: 't', name: 'T', format: 'T20',
        maxTeams: 8, teamCount: 0, status: 'upcoming', createdAt: 0,
        scorerIds: ['scorer@x.com'],
      );
      final u = AuthUser(sub: 'u1', email: 'scorer@x.com', name: 'S', groups: []);
      expect(u.isScorerFor(t), isTrue);
    });

    test('isScorerFor: creator can score their own tournament', () {
      final t = Tournament(
        id: 't', name: 'T', format: 'T20',
        maxTeams: 8, teamCount: 0, status: 'upcoming',
        createdAt: 0, createdBy: 'u1',
      );
      final u = AuthUser(sub: 'u1', email: 'a@b.com', name: 'A', groups: []);
      expect(u.isScorerFor(t), isTrue);
    });
  });

  // ── Team ─────────────────────────────────────────────────────

  group('Team.fromJson', () {
    test('shortName defaults to first 3 chars of name uppercased', () {
      final t = Team.fromJson({'id': 't1', 'name': 'warriors'});
      expect(t.shortName, equals('WAR'));
    });

    test('shortName truncated if name < 3 chars', () {
      final t = Team.fromJson({'id': 't1', 'name': 'XI'});
      expect(t.shortName, equals('XI'));
    });

    test('players list parsed from json', () {
      final t = Team.fromJson({
        'id': 't1', 'name': 'Team',
        'players': [
          {'id': 'p1', 'name': 'Alice', 'role': 'batsman'},
        ],
      });
      expect(t.players.length, equals(1));
      expect(t.players.first.name, equals('Alice'));
    });

    test('copyWith preserves other fields', () {
      final t = Team.fromJson({'id': 't1', 'name': 'Team'});
      final copy = t.copyWith(players: []);
      expect(copy.id,   equals('t1'));
      expect(copy.name, equals('Team'));
    });
  });

  // ── BowlerStats.oversBowled ──────────────────────────────────

  group('BowlerStats.oversBowled — edge cases', () {
    BowlerStats make(int legal) => BowlerStats(
      playerId: 'p', legalDeliveries: legal,
      runsConceded: 0, wicketsTaken: 0,
      maidenOvers: 0, wides: 0, noBalls: 0, economy: 0,
    );

    test('5 deliveries → "0.5"',  () => expect(make(5).oversBowled,  equals('0.5')));
    test('60 deliveries → "10"',  () => expect(make(60).oversBowled, equals('10')));
    test('61 deliveries → "10.1"', () => expect(make(61).oversBowled, equals('10.1')));
  });

  // ── MatchClip ────────────────────────────────────────────────

  group('MatchClip — edge cases', () {
    MatchClip make(String event) => MatchClip(
      clipId: 'c', matchId: 'm', s3Key: 'k',
      inningsNumber: 1, over: 0, ball: 0,
      event: event, durationMs: 3000, createdAt: 0,
    );

    test('unknown event → 🎬', () =>
        expect(make('unknown').eventEmoji, equals('🎬')));
    test('empty event string → 🎬', () =>
        expect(make('').eventEmoji, equals('🎬')));
    test('wicket emoji correct', () =>
        expect(make('wicket').eventEmoji, equals('🎯')));
  });

  // ── Delivery ─────────────────────────────────────────────────

  group('Delivery.fromJson — edge cases', () {
    test('isWicket true parses correctly', () {
      final d = Delivery.fromJson({
        'overNumber': 1, 'ballNumber': 2,
        'isWicket': true, 'isLegalDelivery': true,
        'batsmanId': 'b1', 'nonStrikerId': 'b2', 'bowlerId': 'w1',
      });
      expect(d.isWicket, isTrue);
    });

    test('no_ball extra parses extraType correctly', () {
      final d = Delivery.fromJson({
        'overNumber': 0, 'ballNumber': 0,
        'extras': {'type': 'no_ball', 'runs': 1},
        'batsmanId': '', 'nonStrikerId': '', 'bowlerId': '',
      });
      expect(d.extraType, equals('no_ball'));
      // isLegalDelivery is stored explicitly in JSON; CricketUtils.isLegal()
      // is the utility to derive legality from extraType
      expect(CricketUtils.isLegal(d.extraType), isFalse);
    });

    test('runsTotal defaults to 0 when missing', () {
      final d = Delivery.fromJson({
        'overNumber': 0, 'ballNumber': 0,
        'batsmanId': '', 'nonStrikerId': '', 'bowlerId': '',
      });
      expect(d.runsTotal, equals(0));
    });
  });
}

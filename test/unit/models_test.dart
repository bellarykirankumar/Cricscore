import 'package:flutter_test/flutter_test.dart';
import 'package:cricscore/models/models.dart';

void main() {
  // ── AuthUser ────────────────────────────────────────────────

  group('AuthUser roles', () {
    final admin = AuthUser(sub: 'u1', email: 'a@x.com', name: 'A',
        groups: ['admin']);
    final scorer = AuthUser(sub: 'u2', email: 'b@x.com', name: 'B',
        groups: ['scorer']);
    final viewer = AuthUser(sub: 'u3', email: 'c@x.com', name: 'C',
        groups: []);

    test('admin isAdmin/isScorer/isViewer', () {
      expect(admin.isAdmin,  isTrue);
      expect(admin.isScorer, isTrue);
      expect(admin.isViewer, isTrue);
      expect(admin.role,     equals('admin'));
    });

    test('scorer is not admin but is scorer', () {
      expect(scorer.isAdmin,  isFalse);
      expect(scorer.isScorer, isTrue);
      expect(scorer.role,     equals('scorer'));
    });

    test('viewer has no special permissions', () {
      expect(viewer.isAdmin,  isFalse);
      expect(viewer.isScorer, isFalse);
      expect(viewer.role,     equals('viewer'));
    });

    test('canManage: admin can manage anything', () {
      expect(admin.canManage('someone-else'), isTrue);
    });

    test('canManage: own resource', () {
      expect(viewer.canManage('u3'), isTrue);
    });

    test('canManage: other user resource', () {
      expect(viewer.canManage('u99'), isFalse);
    });

    test('fromJson parses groups correctly', () {
      final u = AuthUser.fromJson({
        'sub': 's1', 'email': 'x@y.com', 'name': 'X',
        'cognito:groups': ['admin', 'scorer'],
      });
      expect(u.isAdmin, isTrue);
      expect(u.groups, containsAll(['admin', 'scorer']));
    });

    test('fromJson falls back to email when name is missing', () {
      final u = AuthUser.fromJson({
        'sub': 's2', 'email': 'x@y.com',
      });
      expect(u.name, equals('x@y.com'));
      expect(u.groups, isEmpty);
    });
  });

  // ── Tournament ──────────────────────────────────────────────

  group('Tournament status', () {
    Tournament make(String status) => Tournament(
      id: 't1', name: 'Cup', format: 'T20',
      maxTeams: 8, teamCount: 4, status: status,
      createdAt: 0,
    );

    test('in_progress → isActive', () {
      expect(make('in_progress').isActive,    isTrue);
      expect(make('in_progress').isUpcoming,  isFalse);
      expect(make('in_progress').isCompleted, isFalse);
    });

    test('upcoming → isUpcoming', () {
      expect(make('upcoming').isUpcoming, isTrue);
      expect(make('upcoming').isActive,   isFalse);
    });

    test('completed → isCompleted', () {
      expect(make('completed').isCompleted, isTrue);
    });

    test('fromJson applies defaults for missing fields', () {
      final t = Tournament.fromJson({'id': 'x', 'name': 'T', 'createdAt': 0});
      expect(t.format,    equals('T20'));
      expect(t.maxTeams,  equals(8));
      expect(t.status,    equals('upcoming'));
      expect(t.scorerIds, isEmpty);
    });
  });

  // ── BowlerStats ─────────────────────────────────────────────

  group('BowlerStats.oversBowled', () {
    BowlerStats make(int legal) => BowlerStats(
      playerId: 'p1', legalDeliveries: legal,
      runsConceded: 0, wicketsTaken: 0,
      maidenOvers: 0, wides: 0, noBalls: 0, economy: 0,
    );

    test('0 deliveries → "0"', () => expect(make(0).oversBowled, equals('0')));
    test('6 deliveries → "1"', () => expect(make(6).oversBowled, equals('1')));
    test('7 deliveries → "1.1"', () => expect(make(7).oversBowled, equals('1.1')));
    test('12 deliveries → "2"', () => expect(make(12).oversBowled, equals('2')));
    test('13 deliveries → "2.1"', () => expect(make(13).oversBowled, equals('2.1')));
    test('23 deliveries → "3.5"', () => expect(make(23).oversBowled, equals('3.5')));
  });

  // ── MatchClip ───────────────────────────────────────────────

  group('MatchClip', () {
    MatchClip make({required String event, required int over, required int ball}) =>
        MatchClip(clipId: 'c1', matchId: 'm1', s3Key: 'k',
            inningsNumber: 1, over: over, ball: ball,
            event: event, durationMs: 5000, createdAt: 0);

    test('eventEmoji: wicket → 🎯', () =>
        expect(make(event: 'wicket', over: 1, ball: 0).eventEmoji, equals('🎯')));
    test('eventEmoji: four → 4️⃣', () =>
        expect(make(event: 'four', over: 1, ball: 0).eventEmoji, equals('4️⃣')));
    test('eventEmoji: six → 6️⃣', () =>
        expect(make(event: 'six', over: 1, ball: 0).eventEmoji, equals('6️⃣')));
    test('eventEmoji: manual → 🎬', () =>
        expect(make(event: 'manual', over: 1, ball: 0).eventEmoji, equals('🎬')));

    test('overDotBall: over=3 ball=2 → "3.3"', () =>
        expect(make(event: 'four', over: 3, ball: 2).overDotBall, equals('3.3')));
  });

  // ── Delivery.fromJson ────────────────────────────────────────

  group('Delivery.fromJson', () {
    test('parses new flat format', () {
      final d = Delivery.fromJson({
        'overNumber': 2, 'ballNumber': 3,
        'runsBatsman': 4, 'runsExtras': 0, 'runsTotal': 4,
        'isWicket': false, 'isLegalDelivery': true,
        'batsmanId': 'b1', 'nonStrikerId': 'b2', 'bowlerId': 'w1',
      });
      expect(d.runsBatsman, equals(4));
      expect(d.runsTotal,   equals(4));
      expect(d.isWicket,    isFalse);
    });

    test('parses legacy nested runs format', () {
      final d = Delivery.fromJson({
        'overNumber': 0, 'ballNumber': 0,
        'runs': {'batsman': 1, 'extras': 0, 'total': 1},
        'isWicket': false, 'isLegalDelivery': true,
        'batsmanId': 'b1', 'nonStrikerId': 'b2', 'bowlerId': 'w1',
      });
      expect(d.runsBatsman, equals(1));
      expect(d.runsTotal,   equals(1));
    });

    test('defaults isLegalDelivery to true when missing', () {
      final d = Delivery.fromJson({
        'overNumber': 0, 'ballNumber': 0,
        'batsmanId': '', 'nonStrikerId': '', 'bowlerId': '',
      });
      expect(d.isLegalDelivery, isTrue);
    });

    test('parses extraType from extras map', () {
      final d = Delivery.fromJson({
        'overNumber': 0, 'ballNumber': 0,
        'extras': {'type': 'wide', 'runs': 1},
        'batsmanId': '', 'nonStrikerId': '', 'bowlerId': '',
      });
      expect(d.extraType, equals('wide'));
    });
  });
}

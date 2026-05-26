import 'package:flutter_test/flutter_test.dart';
import 'package:cricscore/utils/cricket_utils.dart';

void main() {
  // ── bowlerQuota ─────────────────────────────────────────────

  group('CricketUtils.bowlerQuota', () {
    test('Test → null (unlimited)', () =>
        expect(CricketUtils.bowlerQuota('Test', 0), isNull));

    test('T20  → 4 overs max', () =>
        expect(CricketUtils.bowlerQuota('T20', 20), equals(4)));

    test('T10  → 2 overs max', () =>
        expect(CricketUtils.bowlerQuota('T10', 10), equals(2)));

    test('ODI  → 10 overs max', () =>
        expect(CricketUtils.bowlerQuota('ODI', 50), equals(10)));

    test('Custom 10-over → 2 (10÷5)', () =>
        expect(CricketUtils.bowlerQuota('Gully', 10), equals(2)));

    test('Custom 6-over  → 1 (⌊6÷5⌋, min 1)', () =>
        expect(CricketUtils.bowlerQuota('Gully', 6), equals(1)));

    test('Custom 25-over → 5 (25÷5)', () =>
        expect(CricketUtils.bowlerQuota('Custom', 25), equals(5)));
  });

  // ── runRate ─────────────────────────────────────────────────

  group('CricketUtils.runRate', () {
    test('0 balls → 0.0', () =>
        expect(CricketUtils.runRate(0, 0), equals(0.0)));

    test('36 runs in 36 balls → 6.0 (rr = 6)', () =>
        expect(CricketUtils.runRate(36, 36), closeTo(6.0, 0.001)));

    test('100 runs in 60 balls (10 overs) → 10.0', () =>
        expect(CricketUtils.runRate(100, 60), closeTo(10.0, 0.001)));

    test('partial over: 10 runs in 3 balls → 20.0', () =>
        expect(CricketUtils.runRate(10, 3), closeTo(20.0, 0.001)));
  });

  // ── requiredRunRate ─────────────────────────────────────────

  group('CricketUtils.requiredRunRate', () {
    test('0 balls remaining → infinity', () =>
        expect(CricketUtils.requiredRunRate(150, 100, 0),
            equals(double.infinity)));

    test('target already reached → 0.0', () =>
        expect(CricketUtils.requiredRunRate(100, 100, 12), equals(0.0)));

    test('need 60 off 30 balls (5 overs) → 12.0', () =>
        expect(CricketUtils.requiredRunRate(160, 100, 30),
            closeTo(12.0, 0.001)));

    test('need 6 off 6 balls (1 over) → 6.0', () =>
        expect(CricketUtils.requiredRunRate(106, 100, 6),
            closeTo(6.0, 0.001)));
  });

  // ── oversDisplay ────────────────────────────────────────────

  group('CricketUtils.oversDisplay', () {
    test('0 balls → "0.0"',  () => expect(CricketUtils.oversDisplay(0),  equals('0.0')));
    test('6 balls → "1.0"',  () => expect(CricketUtils.oversDisplay(6),  equals('1.0')));
    test('7 balls → "1.1"',  () => expect(CricketUtils.oversDisplay(7),  equals('1.1')));
    test('11 balls → "1.5"', () => expect(CricketUtils.oversDisplay(11), equals('1.5')));
    test('18 balls → "3.0"', () => expect(CricketUtils.oversDisplay(18), equals('3.0')));
    test('19 balls → "3.1"', () => expect(CricketUtils.oversDisplay(19), equals('3.1')));
    test('120 balls → "20.0"', () => expect(CricketUtils.oversDisplay(120), equals('20.0')));
  });

  // ── isLegal ─────────────────────────────────────────────────

  group('CricketUtils.isLegal', () {
    test('null extraType → legal', () =>
        expect(CricketUtils.isLegal(null), isTrue));
    test('wide → not legal', () =>
        expect(CricketUtils.isLegal('wide'), isFalse));
    test('no_ball → not legal', () =>
        expect(CricketUtils.isLegal('no_ball'), isFalse));
    test('bye → legal (counts as ball)', () =>
        expect(CricketUtils.isLegal('bye'), isTrue));
    test('leg_bye → legal', () =>
        expect(CricketUtils.isLegal('leg_bye'), isTrue));
  });

  // ── projectedScore ──────────────────────────────────────────

  group('CricketUtils.projectedScore', () {
    test('0 balls bowled → 0', () =>
        expect(CricketUtils.projectedScore(0, 0, 120), equals(0)));

    test('50 runs in 60 balls, 120 total → projected 100', () =>
        expect(CricketUtils.projectedScore(50, 60, 120), equals(100)));

    test('36 runs in 36 balls, 120 total → projected 120', () =>
        expect(CricketUtils.projectedScore(36, 36, 120), equals(120)));
  });
}

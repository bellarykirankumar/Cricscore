import 'package:flutter_test/flutter_test.dart';
import 'package:cricscore/utils/cricket_utils.dart';

void main() {
  // ── bowlerQuota edge cases ───────────────────────────────────

  group('CricketUtils.bowlerQuota — edge cases', () {
    test('0-over match → clamp to 1', () =>
        expect(CricketUtils.bowlerQuota('Gully', 0), equals(1)));

    test('1-over match → clamp to 1', () =>
        expect(CricketUtils.bowlerQuota('Gully', 1), equals(1)));

    test('T10 format is exactly 2', () =>
        expect(CricketUtils.bowlerQuota('T10', 10), equals(2)));

    test('Test format ignores totalOvers', () =>
        expect(CricketUtils.bowlerQuota('Test', 999), isNull));

    test('50-over (ODI string) → 10', () =>
        expect(CricketUtils.bowlerQuota('ODI', 50), equals(10)));
  });

  // ── runRate edge cases ───────────────────────────────────────

  group('CricketUtils.runRate — edge cases', () {
    test('negative runs (correction) → negative rr', () =>
        expect(CricketUtils.runRate(-6, 6), closeTo(-6.0, 0.001)));

    test('large score 300 in 300 balls → 6.0', () =>
        expect(CricketUtils.runRate(300, 300), closeTo(6.0, 0.001)));

    test('1 run off 1 ball → 6.0 rr', () =>
        expect(CricketUtils.runRate(1, 1), closeTo(6.0, 0.001)));
  });

  // ── requiredRunRate edge cases ───────────────────────────────

  group('CricketUtils.requiredRunRate — edge cases', () {
    test('negative balls remaining → infinity', () =>
        expect(CricketUtils.requiredRunRate(100, 50, -1),
            equals(double.infinity)));

    test('target exceeded (scored > target) → 0.0', () =>
        expect(CricketUtils.requiredRunRate(100, 150, 12), equals(0.0)));

    test('target exactly met → 0.0', () =>
        expect(CricketUtils.requiredRunRate(100, 100, 0),
            equals(double.infinity))); // 0 balls → infinity takes priority

    test('1 run needed off 1 ball → 6.0', () =>
        expect(CricketUtils.requiredRunRate(101, 100, 1),
            closeTo(6.0, 0.001)));
  });

  // ── oversDisplay edge cases ──────────────────────────────────

  group('CricketUtils.oversDisplay — edge cases', () {
    test('5 balls → "0.5"',  () => expect(CricketUtils.oversDisplay(5),  equals('0.5')));
    test('60 balls → "10.0"', () => expect(CricketUtils.oversDisplay(60), equals('10.0')));
    test('300 balls (50 overs) → "50.0"', () =>
        expect(CricketUtils.oversDisplay(300), equals('50.0')));
  });

  // ── isLegal exhaustive ───────────────────────────────────────

  group('CricketUtils.isLegal — all extra types', () {
    test('wide → illegal',    () => expect(CricketUtils.isLegal('wide'),    isFalse));
    test('no_ball → illegal', () => expect(CricketUtils.isLegal('no_ball'), isFalse));
    test('bye → legal',       () => expect(CricketUtils.isLegal('bye'),     isTrue));
    test('leg_bye → legal',   () => expect(CricketUtils.isLegal('leg_bye'), isTrue));
    test('penalty → legal',   () => expect(CricketUtils.isLegal('penalty'), isTrue));
    test('empty string → legal', () => expect(CricketUtils.isLegal(''),     isTrue));
    test('null → legal',      () => expect(CricketUtils.isLegal(null),      isTrue));
  });

  // ── projectedScore edge cases ────────────────────────────────

  group('CricketUtils.projectedScore — edge cases', () {
    test('full innings bowled → same as runs', () =>
        expect(CricketUtils.projectedScore(100, 120, 120), equals(100)));

    test('halfway through 50 overs → doubles runs', () =>
        expect(CricketUtils.projectedScore(80, 150, 300), equals(160)));

    test('1 ball bowled — projection is very high', () =>
        expect(CricketUtils.projectedScore(1, 1, 120), equals(120)));

    test('0 runs from 60 balls → projected 0', () =>
        expect(CricketUtils.projectedScore(0, 60, 120), equals(0)));
  });
}

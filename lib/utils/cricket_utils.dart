// ─────────────────────────────────────────────────────────────
//  CricScore — Pure cricket calculation utilities
//  All functions are stateless / side-effect-free so they are
//  trivially unit-testable without a widget or network.
// ─────────────────────────────────────────────────────────────

class CricketUtils {
  CricketUtils._(); // prevent instantiation

  /// Max overs a single bowler may bowl in an innings.
  static int? bowlerQuota(String format, int totalOvers) {
    switch (format) {
      case 'T20':  return 4;
      case 'T10':  return 2;
      case 'ODI':  return 10;
      default:
        // Custom: 1 bowler per 5 overs, minimum 1
        return (totalOvers / 5).floor().clamp(1, 999);
    }
  }

  /// Current run rate: runs scored per over bowled.
  static double runRate(int runs, int balls) {
    if (balls == 0) return 0.0;
    return (runs * 6.0) / balls;
  }

  /// Required run rate: runs needed per remaining over.
  /// Returns [double.infinity] if no balls remain.
  static double requiredRunRate(int target, int scored, int ballsRemaining) {
    if (ballsRemaining <= 0) return double.infinity;
    final needed = target - scored;
    if (needed <= 0) return 0.0;
    return (needed * 6.0) / ballsRemaining;
  }

  /// Format a ball count as overs-and-balls string: 19 balls → "3.1".
  static String oversDisplay(int balls) {
    final overs = balls ~/ 6;
    final rem   = balls % 6;
    return '$overs.$rem';
  }

  /// True if the delivery type counts as a legal delivery
  /// (advances the ball count in the over).
  static bool isLegal(String? extraType) =>
      extraType != 'wide' && extraType != 'no_ball';

  /// Projected score at end of innings using current run rate.
  static int projectedScore(int runs, int balls, int totalBalls) {
    if (balls == 0) return 0;
    return ((runs / balls) * totalBalls).round();
  }
}

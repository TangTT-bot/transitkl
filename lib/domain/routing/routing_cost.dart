/// Recommended journey ranking. Clock time remains separate from penalties.
final class RoutingCost implements Comparable<RoutingCost> {
  const RoutingCost({
    required this.elapsedSeconds,
    required this.transfers,
    required this.walkingSeconds,
    required this.generalizedSeconds,
  });

  final int elapsedSeconds;
  final int transfers;
  final int walkingSeconds;
  final int generalizedSeconds;

  /// Tied scores prefer fewer changes, less walking, then earlier arrival.
  @override
  int compareTo(RoutingCost other) {
    for (final (left, right) in [
      (generalizedSeconds, other.generalizedSeconds),
      (transfers, other.transfers),
      (walkingSeconds, other.walkingSeconds),
      (elapsedSeconds, other.elapsedSeconds),
    ]) {
      final comparison = left.compareTo(right);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  /// Equality also counts as dominance so zero-cost cycles are discarded.
  bool dominatesOrEquals(RoutingCost other) =>
      elapsedSeconds <= other.elapsedSeconds &&
      transfers <= other.transfers &&
      walkingSeconds <= other.walkingSeconds;
}

# ADR 0005: Treat convenience as a first-class routing objective

## Status

Implemented on 3 November 2026: multi-label modified Dijkstra, walking weighting,
and one search behaviour: Recommended, with no user-selectable routing profiles.

## Context

The mathematically fastest public-transport journey is not always the journey a
commuter prefers. A route that saves a few minutes may require changing lines,
walking through an interchange, waiting again, finding another platform, and
accepting more missed-connection risk.

The Putra Heights to Pasar Seni case demonstrated this. Raw GTFS timing made an
SPL-to-KJL journey through Masjid Jamek roughly nine minutes faster than staying
on KJL, but the direct journey is substantially easier to understand and use.
TransitKL's project objective is therefore not merely shortest elapsed time; it
is a practical, convenient journey recommendation.

## Decision

TransitKL will treat routing as a multi-criteria problem. Every search label
must distinguish at least:

- actual elapsed seconds;
- number of changes between vehicles;
- walking seconds and distance; and
- generalized inconvenience cost.

The default **Recommended** profile will optimize a generalized cost rather than
raw arrival time:

```text
recommended cost (seconds) = elapsed seconds
                           + 600 * vehicle changes
                           + walking seconds
```

The current transfer inconvenience is ten minutes per vehicle change. It is a
ranking penalty only and must never be added to the arrival time shown to the
user. Walking already contributes once to elapsed time; the additional walking
term makes it count twice in Recommended. These are configurable starting
weights, not parameters validated by a commuter study.

When generalized costs are equal, the deterministic tie-break
order is:

1. fewer vehicle changes;
2. less walking;
3. earlier actual arrival; and
4. stable route/service identifiers.

All app and command-line searches use Recommended's balanced generalized cost.
There is no Travel preference control. Fastest, Fewer transfers, and Least
walking were removed after product review to keep the interface focused on one
convenient recommendation. Time, transfers, and walking remain separate internal
criteria. This is a product design decision; commuter preferences can vary.

The modified Dijkstra algorithm retains a Pareto frontier of labels for each
`(stop, has boarded before, active vehicle run)` state. A label contains elapsed
seconds, changes, walking seconds, and a reference to its own predecessor label.
A candidate is discarded when an existing label is no worse on every criterion;
equal labels are also discarded to stop zero-cost cycles. There is no arbitrary
frontier-size cap that silently drops useful alternatives.

The priority queue uses Recommended's lexicographic ordering. All
increments are nonnegative. The first destination label removed from the queue
is the selected result within the six-hour horizon and this graph's static
timing model. A lower score at an intermediate station cannot erase an earlier
arrival that has more changes: it may be needed to catch a scheduled connection.

Walking clears the active run, so reboarding counts as changing vehicles.
Different scheduled trip instances on the same line also count as a transfer;
continuing on the same trip through a dwell does not.

Frequency boarding allows waiting for a later operating window. The router
takes the earliest expected boarding among applicable windows, including their
half-headway estimate. This preserves FIFO: arriving earlier at a stop cannot
force a later boarding than arriving later. That property makes elapsed-time
dominance safe at changing headways. Calendar windows are cached once per
query/service. Expected boarding is not allowed beyond a window's end.

The engine returns one Recommended result. It does not yet expose the
entire destination Pareto set as alternative journey cards.

## Required acceptance cases

- Recommended Putra Heights (`KJ37`) to Pasar Seni (`KJ14`) stays on KJL with
  zero transfers.
- A transfer that saves less than its inconvenience and walking cost does not
  beat a direct journey.
- A transfer remains valid when it provides a substantial overall benefit or
  no direct journey exists.
- Equal-time alternatives prefer fewer changes, then less walking.
- Transfer penalties influence ranking but never displayed clock time.
- The router must not introduce backtracking or repeated service changes merely
  to gain a small theoretical time saving.

## Verification

- Synthetic tests cover time/walking trade-offs, substantial savings, equal-score
  tie-breaking, same-line vehicle changes, window-boundary FIFO, and cycles.
- A connection test requires retaining an earlier/more-transfer label at a shared
  state after a lower-score/later label has already been reached.
- An independent exhaustive path enumerator checks Recommended on 25 small
  directed acyclic networks.
- The bundled-feed regression checks that Putra Heights to Pasar Seni stays on
  KJL instead of changing through Masjid Jamek for a small theoretical saving.
- A widget test searches directly, confirms a Recommended result, and verifies
  that no preference selector or alternative routing modes appear.
- `dart run tool/routing_benchmark.dart` runs a repeatable desktop smoke benchmark
  on four station pairs. Device benchmarks remain part of evaluation.

The Pareto treatment follows the established public-transit multi-criteria problem
described in [Route Planning in Transportation Networks](https://www.microsoft.com/en-us/research/wp-content/uploads/2014/01/MSR-TR-2014-4.pdf).
TransitKL retains its modified Dijkstra implementation; it does not implement the
survey's other algorithms.

## Consequences

- “Shortest path” in the report must be described as generalized shortest path,
  not simply minimum travel seconds.
- Transfer and walking parameters must be documented and evaluated with sample
  journeys and, where possible, user feedback.
- Tests must include both synthetic trade-off networks and real Klang Valley
  regression cases.
- Future UI work should keep the single Recommended flow clear and explain the
  journey's time, walking, and transfer details.

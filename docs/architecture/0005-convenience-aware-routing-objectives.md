# ADR 0005: Treat convenience as a first-class routing objective

## Status

Accepted as the routing policy and acceptance criteria. The current default
implements transfer aversion; walking weighting and selectable profiles are the
next algorithm refinements.

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
- number of changes between services;
- walking seconds and distance; and
- generalized inconvenience cost.

The default **Recommended** profile will optimize a generalized cost rather than
raw arrival time:

```text
recommended cost = actual elapsed time
                 + transfer inconvenience
                 + additional walking reluctance
```

The current transfer inconvenience is ten minutes per service change. It is a
ranking penalty only and must never be added to the arrival time shown to the
user. The next refinement will count walking more heavily than seated or
in-vehicle time because commuters generally perceive walking through a station
as less convenient.

When generalized costs are equal or nearly equal, the deterministic tie-break
order is:

1. fewer service changes;
2. less walking;
3. earlier actual arrival; and
4. stable route/service identifiers.

The application may later expose explicit profiles:

- **Fastest**: earliest actual arrival, then fewer changes and less walking;
- **Recommended / straightforward**: balanced generalized cost;
- **Fewer transfers**: changes are the primary criterion;
- **Least walking**: walking is the primary criterion.

Supporting all profiles correctly may require a multi-label modified Dijkstra
algorithm. Instead of retaining one label per `(stop, active run)` state, the
router retains a small Pareto frontier of non-dominated labels across elapsed
time, transfers, and walking. A label is discarded only when another label is
no worse on every criterion and better on at least one.

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

## Consequences

- “Shortest path” in the report must be described as generalized shortest path,
  not simply minimum travel seconds.
- Transfer and walking parameters must be documented and evaluated with sample
  journeys and, where possible, user feedback.
- Tests must include both synthetic trade-off networks and real Klang Valley
  regression cases.
- Future UI work should explain the selected preference and allow comparison
  without presenting an inconvenient route as universally “best.”

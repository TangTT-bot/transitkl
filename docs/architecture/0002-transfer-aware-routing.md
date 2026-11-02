# ADR 0002: Use a transfer-aware, time-dependent routing graph

## Status

Accepted. Extended by ADR 0003.

## Context

A stop-only shortest-path graph cannot distinguish staying on a train from
changing lines. It would either charge a wait at every station or ignore the
extra waiting and inconvenience caused by an interchange. TransitKL also needs
the journey duration shown to a user to remain separate from any preference
penalty used to rank routes.

## Decision

The preprocessing pipeline derives a compact graph from the audited GTFS data:

- `ride_edges` contain the median observed time between adjacent stops for one
  route and direction.
- `headway_profiles` contain each route/direction frequency window.
- `transfer_edges` contain directed walking links. They come from GTFS parent
  stations, nearby stops with the same normalized station name, or
  `transfers.txt` when supplied.

Same-name transfers are generated only when both stops have coordinates and
are at most 500 metres apart. Walking time uses 1.2 metres per second with a
minimum two-minute station traversal allowance. A directed `transfers.txt`
record overrides the inferred edge, including a forbidden transfer.

The Dart router applies Dijkstra's algorithm to `(stop, active service)` states.
It charges half the active headway as the expected wait when boarding, charges
no new wait while continuing on the same service, and adds a five-minute
generalized-cost penalty when changing services. Walking and waiting still
contribute to actual elapsed time; the transfer penalty does not. This gives the
application both a realistic displayed duration and a separate value for
ranking alternatives.

## Consequences

- The algorithm can prefer a slightly slower direct journey over a fragile
  transfer while still reporting honest clock time.
- GTFS times after midnight remain usable because the router recognizes
  `24:xx` frequency windows.
- Interchanges represented as separate platform IDs in the Rapid Rail feed are
  connected automatically.
- Generated JSON graphs can exercise the same pure-Dart router before SQLite is
  embedded in the Flutter application.

Calendar filtering and exact scheduled departures are added in ADR 0003.
Curated cross-name walkways and accessibility-specific transfer costs remain
later milestones.

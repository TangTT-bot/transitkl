# ADR 0008: Integrate only published Rapid Bus coverage

## Status

Implemented 9 November 2026 using the official snapshot downloaded 8 November.
Device performance, walking validation and commuter evaluation remain required.

## Scope and evidence

The proposal's coverage limitation is retained: TransitKL is not a complete
Klang Valley bus planner. Only the official `rapid-bus-kl` source is bundled.
The separate MRT feeder dataset is not included in this milestone. The KL feed
can itself contain T-numbered routes; this does not imply full feeder coverage.

The source has 139 routes, 4,106 stops, 2,121 trips and 2,118 frequency rows.
Its audit has zero errors and three explicit warnings for trips with no stop
sequences. The official API also documents removed Rapid Bus trip stop times:
<https://developer.data.gov.my/realtime-api/gtfs-static>.

All 138 remaining published routes are selected after excluding B1000, the
duplicate Sunway BRT. Three missing-sequence weekend T4069 trips are not routed.
No unpublished route, assumed reverse direction or missing trip is synthesized.
Per-source metadata retains selected route IDs, source checksum, omitted trip
IDs, coverage note and validity (bus through 31 March 2027; KTM still through
17 November 2026). The merged date-picker union does not extend rail calendars.

## Pattern-aware frequency graph

Simply merging bus ride edges by route and direction is unsafe: source direction
IDs are not a reliable representation of every branch or loop. Different trips
can revisit the same stop or have different relative travel times.

The `--frequency-patterns` exporter groups only identical ordered stop/time and
pickup/drop-off profiles. Source windows and weekday/weekend calendars stay with
their profile. Graph schema 3 adds sequence, departure offset, dwell and boarding
permissions to frequency edges. Rail/KTM schema 2 inputs remain compatible, but
old app versions safely reject a new schema 3 asset instead of ignoring its semantics.

The state remembers the current profile position. Through riding must follow
the next position, not any edge with the same physical stop ID. Different
profiles require a vehicle change. Boarding windows are shifted downstream by
the source departure offset because GTFS frequency windows apply at the first
stop. Staying aboard includes dwell; alighting and new boarding respect permissions.
The source's three complete nonfrequency bus trips remain exact scheduled trips.
Frequency rows with exact_times=1 are deliberately rejected by pattern mode until
an exact-departure expansion implementation is provided.

GTFS semantics: <https://gtfs.org/documentation/schedule/reference/#frequenciestxt>.
Expected headway waits remain estimates, not guaranteed departures or traffic forecasts.

## Search scalability without changing the objective

Recommended is unchanged: actual elapsed seconds + 600 per vehicle change +
walking seconds. Penalties never inflate the displayed arrival time.

Station platform combinations use one multi-source/multi-target search instead
of a Cartesian product of separate runs. On-board states preserve useful through
rides; a zero-duration alighting transition enters a shared off-board Pareto
frontier. Walks and new boarding expand from that frontier rather than repeatedly
from every incoming vehicle state. Boarding after alighting still counts as a
change, including on the same route. No arbitrary label cap removes alternatives.

The mobile/desktop UI invokes routing with Flutter compute in a worker isolate,
shows a busy state and discards stale results after input changes. A failed worker
produces retryable feedback. Web compute runs on the current event loop and is
not a claim of browser background execution. Exact station autocomplete matches
rank ahead of substring bus matches so USJ 7 is not hidden by many bus stops.

## Connectivity and limitations

The first integration adds 36 explicit bus/rail walking pairs, including ten
Pasar Seni platform IDs, and links at Gombak, Wangsa Maju, KL Sentral, USJ 7,
Kajang, Putrajaya Sentral, Titiwangsa and KTM Batu Tiga. Names and coordinates
are checked against official GTFS, with five/seven-minute traversal estimates.
They are not measured pedestrian paths or accessibility guarantees. More links
require separate review; no blanket radius-based cross-mode connections are added.
Bus-to-bus changes use shared stop IDs or existing explicit transfer records.
The bus manifest only permits parent-station and transfers.txt source links;
42 same-name inferred source links are deliberately not promoted into the app.
Opposite-side stops are not automatically merged or linked across roads.

The asset contains 4,343 operator stop IDs, 443 directional/timing services,
18,327 directed ride edges, 170 walking edges, seven calendars and 167 exact
scheduled trips (164 KTM and three bus). Services are not the number of lines.
The historical asset filename is retained but contains both rail and buses.

Tests cover missing sequence warnings, schema propagation, duplicate BRT
exclusion, pattern/offset export, loops, dwell, restrictions, multi-source
equivalence, direct T200 weekday/weekend and reverse journeys, rail/bus walking
links, validity, real worker execution, stale results and failure feedback.
The independent 25-network route oracle and prior KJL/KTM/BRT regressions remain.
See PROJECT_PROGRESS and the bus validation record for final run results.

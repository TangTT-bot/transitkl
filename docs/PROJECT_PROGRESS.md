# TransitKL project progress

Last updated: 16 November 2026

## Current position

TransitKL supports rail, Klang Valley KTM Komuter, Sunway BRT and 138 officially
published Rapid Bus KL routes in the usable Flutter application. The three
audited source feeds travel through the complete
path from GTFS audit to a Recommended offline journey result:

```text
Official GTFS -> audit -> per-feed SQLite -> routing graph exports
              -> route selection + curated interchange merge
              -> bundled Flutter asset -> station search
              -> calendar-aware router -> journey result cards
```

This means work has moved from data and algorithm prototyping into product
development. The audit pipeline is still required when a feed is added or
updated; it is no longer the main daily implementation task.

## Milestone map

| Milestone | Status | Evidence |
| --- | --- | --- |
| 1. Proposal, scope, repository and Flutter scaffold | Complete | Project structure and documented MVP |
| 2. Reproducible GTFS audit and preprocessing | Complete | Python audit/build commands and automated tests |
| 3. Rapid Rail data validation | Complete | Reviewed audit with zero errors and warnings |
| 4. Transfer-aware routing engine | Implemented; evaluation remains | Multi-label modified Dijkstra with convenience-aware Recommended ranking |
| 5. First usable Flutter vertical slice | Complete | Offline asset loading, station search and journey results |
| 6a. KTM Komuter integration | Implemented; field validation remains | Audited exact timetables, two Klang Valley routes, curated transfers and per-feed validity |
| 6b. Sunway BRT connectivity | Implemented; walking validation remains | Seven stops and connections to LRT at USJ 7 and KTM at Setia Jaya |
| 6c. Published Rapid Bus KL integration | Implemented; coverage and field limits remain | 138 source routes, ordered bus profiles, duplicate BRT excluded, 36 explicit bus/rail pairs and visible partial-coverage notice |
| 7a. Offline favourites | Implemented | Save, reopen and remove station/stop favourites and directional journey pairs; stored independently of the graph |
| 7b. Remaining MVP product features | Next | Timetable view, settings and further empty/error state polish |
| 8. Evaluation and release preparation | Not started | Performance study, usability testing, final report evidence and release build |

The five foundation/application milestones and KTM, BRT and published Rapid Bus
integration are implemented. This is not a percentage estimate: product features,
field validation, evaluation and report evidence still require substantial work.
Full Klang Valley bus coverage is not claimed or available from this snapshot.

## What is working now

- The app starts offline with 4,343 operator stop IDs, 443 directional/timing
  services, 167 exact trips (164 KTM and three bus), seven calendars, 18,327
  directed ride edges and 170 directed walking links. Service counts are not line counts.
- Transfer-connected same-name platforms share a search entry. Disconnected
  namesakes such as KTM Sentul and LRT Sentul remain distinct.
- Origin and destination fields search stations and bus stops. Exact station
  matches rank first, before substring bus matches.
- Users can save stations and directional journey pairs on the device. Reopening
  them fills the planner, and the next search uses the selected departure time
  and current offline data. Stops are restored by ID, not by similar names.
- Users choose a departure date and time inside the feed validity range.
- The real modified Dijkstra engine returns route, wait, ride, walk and
  interchange details.
- The default recommendation penalizes service changes so small time savings do
  not automatically beat a straightforward direct journey.
- All searches use Recommended with no preference selector to keep the app simple.
  Recommended counts walking twice and adds ten minutes per vehicle
  change for ranking; displayed clock times remain actual estimates.
- The router retains useful alternatives across time, changes, and walking, and
  has regression tests against an independent exhaustive path search.
- The algorithm validation and desktop smoke measurements are recorded in
  [routing-validation-2026-11-03.md](routing-validation-2026-11-03.md).
- The screen displays total duration, arrival time, transfers and line colours.
- Static-data limitations, validity and attribution are visible in the app.
- Rapid Rail, KTM and Rapid Bus expiry dates are shown separately. The date picker does not
  override each operator's own calendar validity.
- The original 18 curated rail/BRT/KTM pairs are retained and 36 explicit bus/rail
  pairs are added. Walking durations remain estimates requiring field validation;
  the graph is not a measured pedestrian or accessibility network.
- Sunway BRT connects to LRT at USJ 7 with three minutes walking, and to KTM at
  Setia Jaya with six minutes walking, in both directions. BRT uses the existing
  Rapid Rail source export and has not been duplicated as another feed.
- Automated tests cover the pipeline, graph asset, routing, station grouping
  real KTM-only and cross-operator journeys, expiry, short-turn gaps, and a real
  Gombak-to-Kajang screen flow.
- Bus routing preserves variants, loops, relative downstream windows, dwell and
  pickup/drop-off restrictions. Three trips with no published stop sequence are
  warned about and omitted, not replaced with invented service.
- Mobile/desktop searches run in a worker isolate, with a busy indicator,
  stale-result protection and retryable failure feedback. Station platforms use
  one multi-source search; shared off-board Pareto frontiers reduce repeated work.

Latest bus verification and performance measurements are recorded in
[rapid-bus-validation-2026-11-09.md](rapid-bus-validation-2026-11-09.md).
The final run passed 46 Flutter tests and 23 Python tests, with clean static
analysis and a successful compiled Flutter bundle. The processed and packaged
graph checksums match.
The final eight-pair desktop smoke run measured median 877.34 ms and p95
5292.84 ms over 40 searches. Some full-network searches remain multi-second;
the worker keeps the mobile UI responsive, but phone profiling and optimization
remain part of the next validation work.
The earlier rail/KTM-only desktop baseline (156.09 ms median, 392.89 ms p95)
is historical and must not be presented as current full-network performance.
Phone performance still needs measurement.

## What is not implemented yet

- Complete Klang Valley bus coverage is not available. Only published, routable
  data from `rapid-bus-kl` is included. The separate MRT feeder feed is not bundled,
  and not every rail/bus walking connection is configured. ETS, intercity, northern
  and southern Komuter services outside the Klang Valley scope are excluded.
- The current KTM timetable expires on **17 November 2026**. Refresh, audit,
  rebuild, and merge before a later demonstration.
- The supplied Komuter feed has short-turn trips and directional/time gaps.
  Gombak to Seremban at 08:00 has no connection within six hours, while a 16:00
  search finds one. The application follows the supplied schedule.
- The production app currently loads the compact graph JSON asset. The SQLite
  database remains a preprocessing artifact; it can replace the JSON runtime
  source later through the existing repository boundary if the final proposal
  specifically requires runtime SQLite queries.
- General app settings are not persisted; favourites have their own local store.
- There is no dedicated static timetable screen.
- The algorithm weights still need commuter feedback and evaluation; they are
  configurable starting values. The app returns one Recommended result and does
  not display a list of all Pareto alternatives.
- Real-time arrivals, disruptions, fares and ticketing remain outside the MVP.
- Accessibility testing, performance benchmarks and user evaluation are still
  required.

## Recommended next milestone

First run the updated app and manually inspect these searches on a phone:

1. Batu Caves to KL Sentral, 3 November 08:00 (KTM only).
2. Batu Caves to KLCC, 3 November 08:00 (cross-operator).
3. Gombak to Seremban, 3 November 16:00 (evening southern connection).
4. Putra Heights to Pasar Seni, 3 November 08:00 (direct KJL regression).
5. Putra Heights to SunU–Monash, 7 November 08:00 (LRT/BRT through USJ 7).
6. Sunway Lagoon to Klang, 7 November 09:00 (BRT/KTM through Setia Jaya).
7. SL311 LRT Gombak to SL162 Hub UIA, 9 November 08:00 (direct T200 bus).
8. KLCC to SL162 Hub UIA and reverse, 9 November 08:00 (rail/bus via Gombak).

First refresh KTM before its expiry and measure the larger bus graph on the target
phone in airplane mode. Validate the selected walking links and tune performance
without discarding useful routing labels or weakening the convenience objective.
The bus scope and implementation are recorded in
[ADR 0008](architecture/0008-rapid-bus-published-coverage.md).

Next implement a timetable screen, followed by performance and
usability evaluation for the capstone report. Additional MRT feeder coverage or
walking links can be separate bounded extensions, not a claim of universal coverage.

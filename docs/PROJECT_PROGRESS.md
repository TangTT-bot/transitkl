# TransitKL project progress

Last updated: 7 November 2026

## Current position

TransitKL supports rail, Klang Valley KTM Komuter, and Sunway BRT in the usable
Flutter application. The two audited source feeds travel through the complete
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
| 6c. Selected regular Rapid Bus integration | Next | Bus feed selection, audit, merging and rail/bus links |
| 7. Remaining MVP product features | Not started | Favourites, timetable view, settings and polished empty/error states |
| 8. Evaluation and release preparation | Not started | Performance study, usability testing, final report evidence and release build |

The five foundation/application milestones, KTM and Sunway BRT integration
are implemented. This is not a percentage estimate: regular Rapid Bus,
product features, field validation, evaluation, and report evidence still require
substantial work.

## What is working now

- The app starts offline with 244 operator stop IDs, 20 directional services,
  164 exact KTM trips, five calendars, and 98 directed walking links.
- Transfer-connected same-name platforms share a search entry. Disconnected
  namesakes such as KTM Sentul and LRT Sentul remain distinct.
- Origin and destination fields provide filtered station suggestions.
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
- Rapid Rail and KTM expiry dates are shown separately. The date picker does not
  override each operator's own calendar validity.
- Eighteen curated transfer pairs cover thirteen interchange areas. Walking
  durations are conservative estimates requiring field validation.
- Sunway BRT connects to LRT at USJ 7 with three minutes walking, and to KTM at
  Setia Jaya with six minutes walking, in both directions. BRT uses the existing
  Rapid Rail source export and has not been duplicated as another feed.
- Automated tests cover the pipeline, graph asset, routing, station grouping
  real KTM-only and cross-operator journeys, expiry, short-turn gaps, and a real
  Gombak-to-Kajang screen flow.

Latest verification: 31 Flutter tests and 17 Python tests passed; static
analysis found no issues. The merged asset checksum matches the generated
network graph. The earlier KTM desktop smoke baseline after scheduled-instance caching was
median 156.09 ms and p95 392.89 ms over 30 station searches; phone performance
still needs measurement.

## What is not implemented yet

- Regular Rapid KL buses and MRT feeder buses are not included yet; Sunway BRT
  is included. ETS, intercity, northern and
  southern Komuter services outside the Klang Valley scope are excluded.
- The current KTM timetable expires on **17 November 2026**. Refresh, audit,
  rebuild, and merge before a later demonstration.
- The supplied Komuter feed has short-turn trips and directional/time gaps.
  Gombak to Seremban at 08:00 has no connection within six hours, while a 16:00
  search finds one. The application follows the supplied schedule.
- The production app currently loads the compact graph JSON asset. The SQLite
  database remains a preprocessing artifact; it can replace the JSON runtime
  source later through the existing repository boundary if the final proposal
  specifically requires runtime SQLite queries.
- Favourites and preferences are not persisted.
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

Then add a deliberately limited Rapid Bus or MRT feeder service set. Audit the
new feed, extend the existing merge configuration, curate rail/bus walking
links, verify scheduled connections and the six-hour search horizon, and bundle
the resulting network. [ADR 0006](architecture/0006-ktm-komuter-integration.md)
contains the implementation and coverage rationale.
The completed BRT connection and validation are recorded in
[ADR 0007](architecture/0007-sunway-brt-interchanges.md).

After that, implement favourites and a timetable screen, then perform
performance and usability evaluation for the capstone report.

# TransitKL project progress

Last updated: 3 November 2026

## Current position

TransitKL has reached the first end-to-end application milestone. A validated
official Rapid Rail feed now travels through the complete path from GTFS audit
to a usable Flutter journey result:

```text
Official GTFS -> audit -> SQLite build -> routing graph export
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
| 6. Multi-operator coverage | Next | KTM Komuter and selected Rapid Bus feeds are not integrated |
| 7. Remaining MVP product features | Not started | Favourites, timetable view, settings and polished empty/error states |
| 8. Evaluation and release preparation | Not started | Performance study, usability testing, final report evidence and release build |

The project has completed five of eight planned technical milestones. This is
not the same as saying the capstone is five-eighths of the effort: multi-feed
integration, user evaluation, documentation and final testing can take a large
part of the remaining time.

## What is working now

- The app starts with no network connection and loads 187 Rapid Rail stops.
- Duplicate platform IDs are grouped into one user-facing station.
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
- Automated tests cover the pipeline, graph asset, routing, station grouping
  and a real Gombak-to-Kajang screen flow.

## What is not implemented yet

- KTM Komuter and Rapid Bus are not included in the bundled graph.
- Cross-operator interchange mappings have not been curated.
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

Implement multi-operator data integration:

1. Obtain a current KTM Komuter feed and one deliberately limited Rapid Bus
   feed set.
2. Run the audit for each new or refreshed feed.
3. Add a graph merge step that preserves namespaced IDs and service calendars.
4. Add curated cross-operator walking links where station names differ.
5. Re-run routing tests for rail-to-rail, rail-to-bus and after-midnight cases.
6. Publish the merged graph as the Flutter offline asset.

After that, implement favourites and a timetable screen, then perform
performance and usability evaluation for the capstone report.

# TransitKL

TransitKL is an offline-first Flutter journey planner for Klang Valley public
transport. It combines static GTFS schedules from Rapid Rail, Klang Valley KTM
Komuter, Sunway BRT and the officially published Rapid Bus KL subset. This is
not complete Klang Valley bus coverage; the separate MRT feeder feed is not bundled.

## Project status

The project has completed its first usable offline journey-planning milestone:

- Flutter application scaffolded for Android and iOS.
- Reproducible GTFS audit and versioned SQLite build pipeline implemented.
- Transfer-aware modified Dijkstra router implemented in pure Dart.
- Frequency estimates and exact scheduled departures use GTFS service calendars.
- Official Rapid Rail data builds into a working routing graph.
- The Flutter app loads a validated merged Rapid Rail and KTM Komuter graph.
- Users can search stations, choose a departure date/time, and view journey legs.
- Every search returns a Recommended journey with no preference selector.
- KTM Komuter, both Sunway BRT interchanges and 138 published Rapid Bus routes
  are integrated. Missing bus trip sequences are reported and excluded.
- Bus variants, loops and downstream operating times are preserved, with
  worker-isolate searches on mobile/desktop and exact-first autocomplete.
- From and To suggestions label LRT, MRT, Monorail, Sunway BRT, KTM Komuter and
  Rapid Bus by the services that use each stop. Shared station groups show all
  their modes. A bus stop named after a station is still a separate stop.
- Favourite stations and directed journey pairs are saved locally and can
  refill the planner without internet access.

The current app is an end-to-end vertical slice: official data passes through
the audit/build pipeline, is bundled behind a repository interface, and is
used by the production Dart router and Flutter journey screen.

## Minimum viable product

- Search Klang Valley stations and stops.
- Generate offline journey recommendations.
- Present journey legs, estimated duration, interchanges, and transfers.
- View static timetables without an internet connection.
- Save favourite stations and journeys locally.
- Clearly display feed dates, partial coverage, and static-data limitations.

ERL, ticketing, payments, live vehicle tracking, and guaranteed disruption
alerts are outside the initial scope.

## Architecture

```text
Official GTFS feeds
        |
        v
Python audit and preprocessing pipeline
        |
        v
Generated SQLite database and compact routing graph
        |
        v
Bundled graph -> Flutter repository -> routing engine -> application screens
                                                              |
                                                              v
                                      Separate device-local favourites storage
```

Downloaded feeds and generated databases are not committed. The small feed in
`data/fixtures/mini_gtfs` is committed for repeatable automated tests.

## Repository layout

```text
lib/                         Flutter application
test/                        Flutter tests
assets/data/                 Validated offline graph bundled in the app
tool/                        Local Dart routing demonstration command
tools/gtfs_pipeline/         Python GTFS audit and database builder
data/fixtures/               Synthetic test feeds committed to Git
data/downloads/              Downloaded official feeds, ignored by Git
data/processed/              Generated SQLite databases, ignored by Git
docs/architecture/           Architecture decision records
docs/data-audits/            Generated and reviewed feed audit reports
```

## Flutter setup

Prerequisites:

- Flutter stable SDK.
- Android Studio or another configured Android SDK environment.
- Python 3.11 or newer for the GTFS preprocessing pipeline.

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Open **Plan**, type a station name into each field and select a suggestion.
Choose a departure date and time, then select **Find journey**. Use the swap
button to reverse the endpoints. No internet connection is required.

The bottom bar switches between **Plan**, **Timetables** and **Saved** without
clearing your form or search result. The gear opens **Settings** for System,
Light or Dark appearance, bundled data validity and attribution. Appearance
is stored on the device and does not require an account.

Recommended balances actual journey time with a ten-minute ranking penalty per
vehicle change and additional reluctance to walk. This is the single search
behaviour; no route mode selection is required. These scores never inflate
the arrival time shown to the passenger.

### Favourites

After picking a station or bus stop, tap the star beside it to save the stop.
Select both From and To, then tap **Save journey** to save that direction.
Open **Saved** from the bottom bar. Use a saved station as From or To, open
its timetable from its menu, or tap a saved journey to fill both fields. Check the departure
time and tap **Find journey** to get a new Recommended result. Favourites can
also be removed from the list, with **Undo** available after removal.

The app stores namespaced stop IDs in local preferences, separate from the
bundled transit graph. It does not save journey results, timetable times or
upload favourites. Saved stops that no longer resolve in an updated network
remain visible as unavailable and can still be removed.

### Timetables

Open **Timetables** from the bottom bar, choose a station or bus stop,
and select a date. **Scheduled departures** shows published clock times
grouped by line and direction. KTM trips that end before the line terminus
show **Ends at** next to the time instead of opening another group.
**Service frequency** shows
approximate intervals instead of invented departure times. Rapid Rail and
Sunway BRT windows describe the line, not the first or last train at a
particular station. Bus profiles with stop offsets show estimated windows at
the selected stop.

The timetable uses the same offline graph and calendars as journey planning.
Times are in Malaysia time, including after-midnight service carried over from
the previous service day. The selected operator’s data validity is shown
separately from other operators. Live changes are not included. Tap **Use as
From** to return to the planner with this stop selected; it does not change the
planner’s date or start a search.

The application currently uses Flutter's default Android minimum SDK, API 24.
The proposal's API 23 statement should be updated or explicitly configured and
tested before final submission.

## GTFS pipeline

The pipeline uses only the Python standard library.

Verify Python is installed before using it:

```powershell
python --version
```

Run its automated tests:

```powershell
python -m unittest discover -s tools/gtfs_pipeline/tests -v
```

Download the Rapid Rail feed:

```powershell
python tools/gtfs_pipeline/run_pipeline.py download `
  --url "https://api.data.gov.my/gtfs-static/prasarana?category=rapid-rail-kl" `
  --output data/downloads/rapid-rail-kl.zip
```

Audit a feed and create human-readable and machine-readable reports:

```powershell
python tools/gtfs_pipeline/run_pipeline.py audit `
  --input data/downloads/rapid-rail-kl.zip `
  --feed-id prasarana_rapid_rail `
  --markdown-report docs/data-audits/rapid-rail-kl.md `
  --json-report data/processed/rapid-rail-kl-audit.json
```

Build the first offline SQLite database:

```powershell
python tools/gtfs_pipeline/run_pipeline.py build `
  --input data/downloads/rapid-rail-kl.zip `
  --feed-id prasarana_rapid_rail `
  --database data/processed/rapid-rail-kl.sqlite
```

Export the derived graph used by the pure-Dart routing engine:

```powershell
python tools/gtfs_pipeline/run_pipeline.py export-graph `
  --database data/processed/rapid-rail-kl.sqlite `
  --output data/processed/rapid-rail-kl-routing.json
```

Run an end-to-end route calculation against the official feed:

```powershell
dart run tool/route_demo.dart `
  data/processed/rapid-rail-kl-routing.json `
  "GOMBAK" "KAJANG" "2026-11-02" "08:00"
```

The command uses the same Recommended ranking as the app. For a repeatable
desktop routing smoke benchmark:

```powershell
dart run tool/routing_benchmark.dart
```

The demo accepts an exact stop ID or a station name. The date must fall within
the feed's service calendar. Generated databases and graphs stay ignored by
Git. Routing design decisions and current limitations are documented in
[`docs/architecture/0002-transfer-aware-routing.md`](docs/architecture/0002-transfer-aware-routing.md)
and
[`docs/architecture/0003-calendar-aware-scheduled-routing.md`](docs/architecture/0003-calendar-aware-scheduled-routing.md).
The current Flutter asset/repository decision is recorded in
[`docs/architecture/0004-bundle-validated-routing-graph.md`](docs/architecture/0004-bundle-validated-routing-graph.md).
Convenience and multi-criteria routing requirements are defined in
[`docs/architecture/0005-convenience-aware-routing-objectives.md`](docs/architecture/0005-convenience-aware-routing-objectives.md).

After an official feed refresh passes audit, rebuild and export it, then update
the merged app asset. See the KTM commands below; do not overwrite it with a
single-operator graph.

## KTM and merged network build

The current KTM snapshot expires on **17 November 2026**. Refresh it before a
later demonstration. Full KTMB data is audited, but only the two Klang Valley
Komuter routes in `data/network-kl.json` are bundled. ETS and intercity are
excluded. Some Komuter trips terminate early; a route name does not guarantee
an all-day connection.

The result separates total time from the selected start, waiting, and
riding plus walking. Each scheduled leg shows its boarding time. A scheduled
wait of an hour or more gets a notice above the result summary, including the
boarding stop and time. For SunMed to Klang at 13:00 on 16 November, the offline
snapshot shows KTM boarding at Setia Jaya at 17:55, about 4 hr 43 min of total
waiting and 45 min of riding/walking. At 17:25, the same snapshot finds the same
train in 1 hr 3 min including waits. The wait still counts toward ETA and
Recommended ranking. See [data sources](DATA_SOURCES.md) for the official notice
and the one-minute arrival difference.

```powershell
python tools/gtfs_pipeline/run_pipeline.py download `
  --url "https://api.data.gov.my/gtfs-static/ktmb" `
  --output data/downloads/ktmb-2026-11-03.zip
python tools/gtfs_pipeline/run_pipeline.py build `
  --input data/downloads/ktmb-2026-11-03.zip --feed-id ktmb `
  --database data/processed/ktmb-2026-11-03.sqlite
python tools/gtfs_pipeline/run_pipeline.py export-graph `
  --database data/processed/ktmb-2026-11-03.sqlite `
  --output data/processed/ktmb-2026-11-03-routing.json
python tools/gtfs_pipeline/run_pipeline.py merge-graphs `
  --input data/processed/rapid-rail-kl-routing.json `
  --input data/processed/ktmb-2026-11-03-routing.json `
  --input data/processed/rapid-bus-kl-2026-11-08-routing.json `
  --config data/network-kl.json `
  --output data/processed/transitkl-rail-routing.json
Copy-Item data/processed/transitkl-rail-routing.json `
  assets/data/transitkl-rail-routing.json
dart run tool/route_demo.dart assets/data/transitkl-rail-routing.json `
  "BATU CAVES" "KLCC" "2026-11-03" "08:00"
```

First prepare the bus export with the commands below. Use the current exporter
for all inputs; old exports without `auditErrorCount`
must be regenerated. [ADR 0006](docs/architecture/0006-ktm-komuter-integration.md)
documents the merge, interchange estimates, and timetable limitations.

## Sunway BRT

Sunway BRT is included once, from the existing Rapid Rail GTFS feed. Its seven
stops connect to LRT at USJ 7 (three-minute walking allowance) and KTM at Setia
Jaya (six-minute allowance). The two USJ 7 platforms share one station search
entry; through journeys still include the walking transfer. These allowances are
estimates requiring field validation.

```powershell
dart run tool/route_demo.dart assets/data/transitkl-rail-routing.json `
  "PUTRA HEIGHTS" "SunU-Monash" "2026-11-07" "08:00"
```

See [ADR 0007](docs/architecture/0007-sunway-brt-interchanges.md) for the naming
mismatch, interchange fix and regression coverage.

## Rapid Bus KL and partial coverage

Only services supplied in the official `rapid-bus-kl` snapshot are used. The
8 November snapshot has 139 route records. The duplicated BRT route `B1000`
is excluded because Sunway BRT is already supplied by Rapid Rail, leaving
138 bus routes. Three published trips lack stop sequences and cannot be routed.
No missing routes, reverse directions or timetables are fabricated. This limitation
is shown on the planner screen and in the data information sheet.

```powershell
python tools/gtfs_pipeline/run_pipeline.py download `
  --url "https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-kl" `
  --output data/downloads/rapid-bus-kl-2026-11-08.zip
python tools/gtfs_pipeline/run_pipeline.py build `
  --input data/downloads/rapid-bus-kl-2026-11-08.zip `
  --feed-id prasarana_rapid_bus_kl `
  --database data/processed/rapid-bus-kl-2026-11-08.sqlite `
  --markdown-report docs/data-audits/rapid-bus-kl-2026-11-08.md
python tools/gtfs_pipeline/run_pipeline.py export-graph `
  --database data/processed/rapid-bus-kl-2026-11-08.sqlite `
  --frequency-patterns `
  --output data/processed/rapid-bus-kl-2026-11-08-routing.json
```

Then run the three-input merge above. Bus frequency exports use graph schema 3
to preserve each ordered source timing profile, including repeated stop visits,
boarding restrictions, dwell and offsets from the first stop. The old asset filename
is retained for compatibility but now contains the combined rail and bus network.
The merge supports `excludeRouteIds` and keeps per-source coverage notes.

There are 36 explicit bus/rail walking pairs in this first integration, including
Gombak, Pasar Seni, KL Sentral, USJ 7, Titiwangsa and KTM Batu Tiga. These are
named-station GTFS associations with estimated five/seven-minute traversal
allowances, not verified pedestrian navigation. Not all interchanges are configured.
Bus-to-bus transfers work at shared published stop IDs; no blanket proximity links
or opposite-road crossings are invented.

```powershell
dart run tool/route_demo.dart assets/data/transitkl-rail-routing.json `
  "prasarana_rapid_bus_kl:1001801" "prasarana_rapid_bus_kl:1000972" `
  "2026-11-09" "08:00"
```

This checks a direct T200 journey from SL311 LRT Gombak to SL162 Hub UIA.
See [ADR 0008](docs/architecture/0008-rapid-bus-published-coverage.md) for the
coverage boundary, routing changes and required evaluation.

Do not replace the bundled asset with an unaudited feed. See
[`docs/PROJECT_PROGRESS.md`](docs/PROJECT_PROGRESS.md) for the current milestone
map and remaining work.

## Data sources and attribution

Transit data is obtained from Malaysia's official open-data API and is made
available under the Creative Commons Attribution 4.0 International licence.
See [DATA_SOURCES.md](DATA_SOURCES.md) for endpoints and attribution details.

## Academic contribution

The core contribution is the combination of:

1. Multi-operator GTFS preprocessing.
2. An offline mobile database architecture.
3. Transfer-aware modified Dijkstra routing.
4. Convenience-aware ranking across time, transfers, and walking.
5. Accessible presentation of multimodal journey recommendations.

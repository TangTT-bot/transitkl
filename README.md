# TransitKL

TransitKL is an offline-first Flutter journey planner for Klang Valley public
transport. It combines static GTFS schedules from Rapid Rail and Klang Valley
KTM Komuter. Selected Rapid Bus services are the next coverage milestone.

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
- KTM Komuter is integrated; selected Rapid Bus integration is next.

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
Separate writable user database for favourites and preferences
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

On the home screen, type a station name into both fields, select a suggestion,
choose a date and time within the displayed feed range, then select **Find
journey**. No internet connection is required.

Recommended balances actual journey time with a ten-minute ranking penalty per
vehicle change and additional reluctance to walk. This is the single search
behaviour; no route mode selection is required. These scores never inflate
the arrival time shown to the passenger.

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
  --config data/network-kl.json `
  --output data/processed/transitkl-rail-routing.json
Copy-Item data/processed/transitkl-rail-routing.json `
  assets/data/transitkl-rail-routing.json
dart run tool/route_demo.dart assets/data/transitkl-rail-routing.json `
  "BATU CAVES" "KLCC" "2026-11-03" "08:00"
```

Use the current exporter for both inputs; old exports without `auditErrorCount`
must be regenerated. [ADR 0006](docs/architecture/0006-ktm-komuter-integration.md)
documents the merge, interchange estimates, and timetable limitations.

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

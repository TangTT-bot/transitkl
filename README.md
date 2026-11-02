# TransitKL

TransitKL is an offline-first Flutter journey planner for Klang Valley public
transport. It combines static GTFS schedules from Rapid Rail, selected Rapid
Bus services, and KTM Komuter in one mobile application.

## Project status

The project has completed its data-and-routing proof-of-concept milestone:

- Flutter application scaffolded for Android and iOS.
- Reproducible GTFS audit and versioned SQLite build pipeline implemented.
- Transfer-aware modified Dijkstra router implemented in pure Dart.
- Official Rapid Rail data builds into a working routing graph.
- Mobile SQLite integration and journey-search screens are next.

The current Flutter screen is intentionally a status screen. User interface
features will be developed after the data pipeline and routing model are
verified.

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
Generated read-only transit SQLite database
        |
        v
Flutter data repositories -> routing engine -> application screens
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
  "GOMBAK" "KAJANG" "08:00"
```

The demo accepts an exact stop ID or a station name. Generated databases and
graphs stay ignored by Git. Routing design decisions and current limitations
are documented in
[`docs/architecture/0002-transfer-aware-routing.md`](docs/architecture/0002-transfer-aware-routing.md).

## Data sources and attribution

Transit data is obtained from Malaysia's official open-data API and is made
available under the Creative Commons Attribution 4.0 International licence.
See [DATA_SOURCES.md](DATA_SOURCES.md) for endpoints and attribution details.

## Academic contribution

The core contribution is the combination of:

1. Multi-operator GTFS preprocessing.
2. An offline mobile database architecture.
3. Transfer-aware modified Dijkstra routing.
4. Accessible presentation of multimodal journey recommendations.

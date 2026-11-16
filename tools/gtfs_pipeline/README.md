# TransitKL GTFS pipeline

This tool audits GTFS Schedule feeds and converts their core tables into a
normalized SQLite database for the offline TransitKL mobile application.

It deliberately uses only the Python standard library so a fresh clone can run
the first implementation milestone without installing Python packages. Python
3.11 or newer is required.

## Commands

```text
python tools/gtfs_pipeline/run_pipeline.py download --help
python tools/gtfs_pipeline/run_pipeline.py audit --help
python tools/gtfs_pipeline/run_pipeline.py build --help
python tools/gtfs_pipeline/run_pipeline.py export-graph --help
python tools/gtfs_pipeline/run_pipeline.py merge-graphs --help
```

The `feed-id` argument becomes the namespace for every imported identifier. For
example, stop `S1` from feed `prasarana_rapid_rail` becomes
`prasarana_rapid_rail:S1`. This prevents identifiers from different operators
from colliding when graph exports are merged.

The generated schema is versioned in `feed_metadata` using `schema_version`.
Only source feeds that pass the audit are built by default.

Schema version 3 imports agencies, stops, routes, trips, stop times, service
calendars, calendar exceptions, and frequencies. It also derives median
route/direction ride edges, calendar-specific headway profiles, and directed
station transfer edges. `export-graph` converts those tables to routing graph
version 2, including service calendars, exceptions, and exact stop times for
trips that do not use `frequencies.txt`. The pure-Dart planner can therefore
mix high-frequency services such as Rapid Rail with timetable-based services
such as KTM Komuter.

Transfers are derived from GTFS parent stations, same-name stops within 500
metres, and directed `transfers.txt` records. Inferred walking time assumes 1.2
metres per second and at least two minutes within a station.

`merge-graphs --input <rapid.json> --input <ktmb.json> --config
data/network-kl.json --output <merged.json>` applies explicit route selection
and curated interchanges. The source exports must record zero audit errors.
The output retains separate source checksums and service dates, rejects duplicate
IDs and invalid references, and does not infer cross-operator links by proximity.
KTM scheduled stop times include normal boarding/alighting permissions.

## Bus variants and loops

Use `export-graph --frequency-patterns` for the Rapid Bus feed. This writes graph
schema 3 (SQLite remains schema 3), preserving each distinct ordered source
stop/time/permission profile rather than combining route/direction edges.
Identical profiles share deduplicated headway windows. Each edge carries its
sequence position, departure offset from the first stop, dwell, pickup and
drop-off permissions. The Dart planner supports graph schemas 2 and 3.
This prevents silent branch-splicing and repeated-stop loop shortcuts.

Per GTFS, frequency start/end times apply to the first stop. Downstream boarding
windows shift by the source profile offset; continuing on board includes dwell.
Frequency `exact_times=1` is rejected by this export mode rather than silently
treated as a half-headway estimate. The current Rapid Bus frequency rows use 0.

The auditor now warns about trips without stop sequences. They are never
fabricated by export. `merge-graphs` supports `excludeRouteIds` (used to avoid
duplicating BRT), per-feed `coverageNote`, and propagates schema 3 when needed.
Merge all three configured feeds; a two-feed merge no longer matches the config.
The per-feed `transferSources` allowlist prevents unreviewed same-name bus stop
walking links from entering the app. The bus configuration permits only explicit
GTFS parent-station or transfers.txt links; curated links are added separately.

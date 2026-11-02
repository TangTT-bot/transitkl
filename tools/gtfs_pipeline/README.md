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
```

The `feed-id` argument becomes the namespace for every imported identifier. For
example, stop `S1` from feed `prasarana_rapid_rail` becomes
`prasarana_rapid_rail:S1`. This prevents identifiers from different operators
from colliding when databases are merged in a later milestone.

The generated schema is versioned in `feed_metadata` using `schema_version`.
Only source feeds that pass the audit are built by default.

Schema version 2 imports agencies, stops, routes, trips, stop times, service
calendars, calendar exceptions, and frequencies. It also derives median
route/direction ride edges, headway profiles, and directed station transfer
edges. `export-graph` converts those routing tables to the compact JSON format
consumed by the pure-Dart journey planner and the local route demonstration.

Transfers are derived from GTFS parent stations, same-name stops within 500
metres, and directed `transfers.txt` records. Inferred walking time assumes 1.2
metres per second and at least two minutes within a station.

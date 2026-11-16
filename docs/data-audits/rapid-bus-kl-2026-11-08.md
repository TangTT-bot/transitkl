# GTFS audit: prasarana_rapid_bus_kl

- Status: **PASS**
- Generated: `2026-11-08T15:55:12+00:00`
- Source: `data/downloads/rapid-bus-kl-2026-11-08.zip`
- SHA-256: `08c85afdaec25d4c0b77f2e43335f28fe5fb843495bca0c07955c479d628c571`
- Service dates: `20200401` to `20270331`
- Times after midnight: `1906`
- Errors: `0`
- Warnings: `3`

## Row counts

| File | Rows |
| --- | ---: |
| `agency.txt` | 1 |
| `calendar.txt` | 2 |
| `frequencies.txt` | 2118 |
| `routes.txt` | 139 |
| `shapes.txt` | 69185 |
| `stop_times.txt` | 88827 |
| `stops.txt` | 4106 |
| `trips.txt` | 2121 |

## Findings

| Severity | Code | Location | Finding |
| --- | --- | --- | --- |
| WARNING | `trip_without_stop_times` | `trips.txt:1427` | trip_id 'weekend_T4069_T406902_0' has no stop sequence and cannot be routed. |
| WARNING | `trip_without_stop_times` | `trips.txt:1428` | trip_id 'weekend_T4069_T406902_1' has no stop sequence and cannot be routed. |
| WARNING | `trip_without_stop_times` | `trips.txt:1429` | trip_id 'weekend_T4069_T406902_2' has no stop sequence and cannot be routed. |

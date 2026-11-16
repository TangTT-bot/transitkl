# Rapid Bus integration validation

Run date: 9 November 2026. Data snapshot downloaded 8 November 2026.

## Dataset and reproducibility

- Official endpoint: `https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-kl`.
- Source ZIP SHA-256: `08c85afdaec25d4c0b77f2e43335f28fe5fb843495bca0c07955c479d628c571`.
- Source audit: zero errors, three missing-stop-sequence warnings.
- Source calendars: weekday/weekend, 1 April 2020 through 31 March 2027.
- Selection: 138 published routes; duplicate BRT B1000 excluded.
- The separate MRT feeder dataset is not bundled. This is not full bus coverage.
- Bus frequency timing profiles are preserved without averaging incompatible trips.
- All three configured feed exports are merged with `data/network-kl.json`.
- Generated and bundled JSON files have identical SHA-256:
  `57ad55004e29285a64b47f3aaff183fbfc57c6fa8cc2b5d92e51ac9831315dec`.

The bundled graph is schema 3, with 4,343 operator stop IDs, 443 directional/timing
services, 18,327 ride edges, 170 directed walking links, seven calendars and
167 exact scheduled trips (164 KTM, three bus). Services are not line counts.
There are 36 new explicit bus/rail walking pairs. Forty-two automatically
inferred same-name bus-stop links are not promoted into the app: a matching name
does not prove safe road crossing or pedestrian access.

## Automated verification

- 46 Flutter tests passed, including the existing independent 25-network oracle
  and all KJL, KTM and BRT regressions.
- 23 Python tests passed.
- `dart analyze lib test tool`: no issues.
- `flutter build bundle --no-pub`: completed successfully; the compiled bundle
  contains the current offline graph. This is not an Android signing/release test.
- `git diff --check`: no whitespace errors.

New checks cover route exclusion and coverage metadata, missing trip warnings,
deterministic pattern export, repeated stop order, downstream windows beyond the
first-stop closing time, dwell, pickup/drop-off restrictions, multi-source platform
equivalence, exact-first station suggestions and distinct labels for disconnected
same-name bus stops. Full-network tests cover direct T200 in both directions on
weekdays and weekends, rail/bus walks at Gombak, expiry, overnight closures and a
real compute worker. Widget checks cover the coverage notice, bus results, stale
background results and retryable worker failure.

## Reproduce the checks

```powershell
flutter test
dart analyze lib test tool
python -m unittest discover -s tools/gtfs_pipeline/tests -v
flutter build bundle --no-pub
dart run tool/routing_benchmark.dart
dart run tool/route_demo.dart assets/data/transitkl-rail-routing.json `
  "prasarana_rapid_bus_kl:1001801" "prasarana_rapid_bus_kl:1000972" `
  "2026-11-09" "08:00"
```

The direct example is SL311 LRT Gombak to SL162 Hub UIA on T200, with no change
of vehicle. Also inspect KLCC to SL162 Hub UIA and reverse at 08:00: the current
Recommended result uses the explicit five-minute Gombak bus/rail walking allowance.
Keep Putra Heights to Pasar Seni at 08:00 on 3 November as the direct KJL regression.

## Desktop smoke performance

The final graph was measured with the current Dart CLI benchmark on the Windows
development host, with no simultaneous test/build run. Eight station pairs are
used: the previous six rail/KTM pairs plus direct T200 and KLCC/Hub UIA. One warmup
round is excluded, leaving 40 timed station searches.

| Measure | Result |
| --- | ---: |
| Median | 877.34 ms |
| 95th percentile | 5292.84 ms |

These are JIT desktop domain-search measurements, excluding asset load and
worker creation/graph transfer. They are not phone or release-build guarantees.
Long full-network searches can take several seconds. Mobile isolation keeps
the UI responsive, but further device profiling/optimization is still necessary.
Do not compare these figures directly with the older rail-only/KTM-only datasets
or different sample sets as a controlled speedup study.

## Remaining evaluation

This confirms implementation, not complete public transport or pedestrian
coverage. The source lacks three weekend T4069 stop sequences; no substitute
trips are fabricated. The official API documents a wider historic data accuracy
limitation: <https://developer.data.gov.my/realtime-api/gtfs-static>.

Measure startup, memory, median/p95 search and responsiveness on the target phone
in airplane mode and a release/profile build. Worker execution prevents synchronous
search from occupying the mobile UI isolate, but does not itself make the algorithm
faster or establish a phone latency guarantee. Web compute does not create a worker.
Interchange durations are estimates requiring field validation; the map is not an
accessibility routing network. KTM still expires 17 November 2026 and must be
refreshed before a later demonstration. Convenience weights still need user study.

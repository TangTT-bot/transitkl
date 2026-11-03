# Convenience-aware routing validation

Run date: 3 November 2026. Source: bundled Rapid Rail graph schema 2, based on
source feed SHA-256 `532afb6c518489ec612912cefe957c3f05ccb66efad9ce3f61b95981f67df669`.

## Reference case

Putra Heights to Pasar Seni, Tuesday 3 November 2026, departing 08:00:

| Ranking | Result | Actual duration | Changes | Walking |
| --- | --- | --- | --- | --- |
| Recommended | Direct KJL, KJ37 to KJ14 | 60 min 25 sec | 0 | 0 sec |
| Raw-time comparison (not an app option) | SPL to Masjid Jamek, then KJL | 51 min 36 sec | 1 | 120 sec |

Recommended scores are 3625 seconds for direct KJL and
`3096 + 600 + 120 = 3816` seconds for SPL/KJL. The direct journey therefore wins
over the raw-time alternative. Ranking penalties do not change actual displayed
durations. All searches now return Recommended, with no preference selector.

## Repeatable checks

```powershell
flutter test
dart analyze lib test tool
dart run tool/route_demo.dart assets/data/rapid-rail-kl-routing.json `
  "PUTRA HEIGHTS" "PASAR SENI" "2026-11-03" "08:00"
dart run tool/routing_benchmark.dart
```

The multi-criteria tests include an independent path enumerator over 25 small
acyclic networks using Recommended (25 comparisons). The tests also cover Pareto pruning,
a missed-connection counterexample, same-line train changes, headway-window
FIFO, score ties, walking trade-offs, and zero-cost cycles.

## Desktop smoke performance

Measured using `dart run` on the development Windows host. Recommended has
20 timed station searches after one warm-up round. Four pairs are used: Putra
Heights/Pasar Seni, Gombak/Kajang, Titiwangsa/Bukit Bintang, and Ampang/Kwasa
Damansara. Station searches include all platform combinations.

| Ranking | Median | 95th percentile |
| --- | --- | --- |
| Recommended | 32.47 ms | 61.62 ms |

These are local smoke measurements, not Android/iOS performance guarantees.
Run device benchmarks and user evaluation after multi-operator integration.
The ten-minute transfer weight and double walking weight are starting values
and must be evaluated with commuter feedback.

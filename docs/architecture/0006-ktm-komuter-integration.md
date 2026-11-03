# ADR 0006: Merge audited Klang Valley Komuter schedules with Rapid Rail

## Status

Implemented, 3 November 2026. Live operator verification and device evaluation
remain part of final testing.

## Feed and scope

The official KTMB endpoint is documented in the
[data.gov.my GTFS API](https://developer.data.gov.my/realtime-api/gtfs-static).
The 3 November download passes the project audit with zero errors and warnings.
Its SHA-256 is `59b3a75c299a2caaa2ef5e097654b38230957e3079e015817b0cd9dda69be0b3`.
The timetable is valid from 18 August through 17 November 2026.

KTMB publishes nine routes, including intercity, ETS, northern, and southern
services. TransitKL selects only these Klang Valley routes:

- `ktmb:KA15_KD19`: Tanjung Malim to Pelabuhan Klang;
- `ktmb:KC05_KB18`: Batu Caves to Pulau Sebang/Tampin.

The merged asset has 244 operator stop IDs, 20 directional services, five
calendars, 505 ride edges, 164 exact scheduled trips, and 96 directed walking
links. The raw source remains untouched; route selection is recorded in the
checked-in `data/network-kl.json` configuration.

## Merge and transfer design

`merge-graphs` reads the audited graph exports, applies route selection, removes
unused stops/calendars, preserves namespaced identifiers, rejects collisions and
unknown references, and writes a deterministic merged graph. It rejects exports
without evidence of a zero-error pipeline audit. Each source retains its own
checksum, calendar validity, selected route IDs, and display name.

The top-level validity range is the union for the date picker. It does not extend
an operator's service: each headway/trip still uses its original calendar. The
app displays each feed's expiry separately, including an expired status.

Seventeen configured walking pairs (34 directed links) connect twelve interchange
areas: KL Sentral, Abdullah Hukum, Subang Jaya, Kajang, Sungai Buloh, Kepong
Sentral/Sri Damansara Timur, Kampung Batu, Bandar Tasik Selatan, Bank Negara/
Bandaraya, Putra/PWTC, Kuala Lumpur/Pasar Seni, and Setia Jaya/BRT. Connections
are based on operator interchange information and integrated transit maps:

- [MRT Corp: Putrajaya Line connections](https://www.mymrt.com.my/events/mrt-putrajaya-line-phase-one-opened-to-the-public/)
- [MRT Corp: Sri Damansara Timur](https://www.mymrt.com.my/projects/putrajaya-line/stations/sri-damansara-timur/)
- [National Museum: KL Sentral connections](https://www.muziumnegara.gov.my/index.php/en/getting-here)
- [Rapid KL integrated map](https://myrapid.com.my/wp-content/uploads/2025/10/Transit-Map_131025.pdf)

Walking allowances of 5–10 minutes are conservative implementation estimates,
not operator-measured platform traversal times. Displayed distance is a
straight-line reference. Field validation remains necessary. The merger checks
that allowances are not shorter than straight-line walking at 1.2 m/s.

No blanket cross-operator proximity rule is used. In particular, KTM Sentul is
not connected to LRT Sentul simply because both have the same name. Station
search groups same-name platform IDs only within transfer-connected components
and labels disconnected groups separately. Small name overrides improve search
for KL Sentral, Bandar Tasik Selatan, Mid Valley and feed spelling variants;
the original source name is retained in the merged JSON.

## Routing logic

Rapid Rail uses expected waits from frequency windows. Komuter uses exact trip
instances: the rider must reach the platform before its scheduled departure,
can stay aboard through dwell times, and must wait for another actual trip if
the departure is missed. Calendar exceptions and times above 24:00 remain tied
to the correct service day. Boarding/alighting restrictions are preserved.
Scheduled instances are cached once per stop per query to reduce repeated work.

The single Recommended objective remains elapsed time plus 600 seconds per
vehicle change plus an extra walking-time penalty. Physical walking time affects
the clock; the extra preference penalties only affect ranking.

## Coverage limitations and checks

The source includes many short-turn trips, not a continuous all-day train on
every section implied by its route names. For example, Gombak to Seremban at
08:00 on 3 November has no connection in the six-hour search horizon. At 16:00,
the graph provides a journey arriving at 18:31. TransitKL does not fabricate a
frequency service to bridge a timetable gap.

Real-feed regression cases include Batu Caves/KL Sentral, Batu Caves/KLCC in
both directions, weekend Komuter service, the southern evening connection,
KTM expiry after 17 November, and Rapid Rail continuing after that date.
The existing direct KJL Putra Heights/Pasar Seni regression remains required.

Final checks passed: 24 Flutter tests, 17 Python pipeline tests, and Dart static
analysis. The bundled asset matches the generated graph by SHA-256. The local
30-query smoke benchmark measured median 156.09 ms and p95 392.89 ms after
scheduled-instance caching; these are not device performance guarantees.

## Next steps

Refresh the KTM snapshot before any demonstration after 17 November. Add a
deliberately limited Rapid Bus feed, audit it, and extend the same merge config.
Then implement favourites and timetable views, followed by device performance,
interchange walking validation, usability evaluation, and the capstone report.

# TransitKL data sources

TransitKL uses GTFS Schedule data published through Malaysia's official open
data API.

## Initial feeds

| Network | Endpoint |
| --- | --- |
| Rapid Rail KL | `https://api.data.gov.my/gtfs-static/prasarana?category=rapid-rail-kl` |
| Rapid Bus KL | `https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-kl` |
| MRT feeder buses | `https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-mrtfeeder` |
| KTMB | `https://api.data.gov.my/gtfs-static/ktmb` |

Official API documentation:
<https://developer.data.gov.my/realtime-api/gtfs-static>

GTFS Schedule reference:
<https://gtfs.org/documentation/schedule/reference/>

## Licence and attribution

The data.gov.my platform states that its data is made available under the
Creative Commons Attribution 4.0 International licence (CC BY 4.0):
<https://developer.data.gov.my/faq>

Application attribution text:

> Transit schedule data provided by the Government of Malaysia through
> data.gov.my and the relevant transport operators, licensed under CC BY 4.0.

Every generated database records:

- Source URL or input path.
- Feed identifier.
- SHA-256 checksum of the source feed.
- Database build timestamp.
- Row counts and audit findings.

Downloaded feed ZIPs are deliberately excluded from version control because
they change independently of the application. Audit reports and small synthetic
test fixtures may be committed.

## KTM integration snapshot (3 November 2026)

The KTMB feed has nine routes. The application selects the Tanjung Malim–Port
Klang and Batu Caves–Pulau Sebang/Tampin Komuter routes; other KTMB services are
not bundled. The current feed is valid 18 August–17 November 2026, with weekday,
weekend, and holiday exceptions. The reviewed audit is in
`docs/data-audits/ktmb-2026-11-03.md`.

### Setia Jaya to Klang timetable check (16 November 2026)

KTMB's [one-day Port Klang Line timetable](https://www.ktmb.com.my/assets/pdf/2026/28%20-%20TM-PK-TM_SPK-PK%20DNLINE_WEEKDAY_PROJEK%20RIDT%20SH100A%26SH101B.pdf)
shows a gap after 09:25 at Setia Jaya toward Klang. The next through train
leaves Setia Jaya at 17:55 and reaches Klang at 18:29. This is not a blanket
10:00–17:00 KTM closure: times depend on the station, direction and date.

The bundled GTFS reports 17:55 to 18:28 for this train. An audited public
GTFS download from 16 November extends nominal validity to 30 November but
still gives the same 18:28 arrival for this check. The app does not import or
assume one-day PDF changes as recurring service. The bundled asset remains
unchanged by the wait-display improvement; check KTMB for day-specific notices.

`data/network-kl.json` records selection and curated interchange sources.
Walking durations are implementation estimates, and distances are straight-line
references. Per-feed checksums and validity are retained in the merged app asset.

## Sunway BRT coverage (7 November 2026)

The Rapid Rail feed already supplies the Sunway BRT route, so no duplicate bus
feed was added. Explicit walking links connect BRT to LRT at USJ 7 and to KTM
at Setia Jaya. The BRT `USJ7` display name is normalized to `USJ 7` in the merge
configuration while retaining the original ID and source name. Interchange
information is supported by the
[Monash University transport guide](https://www.monash.edu.my/about/maps-and-transport/bus-rapid-transit).

## Rapid Bus KL snapshot and coverage limitation

The official `rapid-bus-kl` snapshot downloaded on 8 November 2026 has 139
routes, 4,106 stop records, 2,121 trips, 88,827 stop times and 2,118 frequency
records. Source SHA-256:
`08c85afdaec25d4c0b77f2e43335f28fe5fb843495bca0c07955c479d628c571`.
Its two calendars cover 1 April 2020 to 31 March 2027.

TransitKL includes all 138 routable published routes after excluding duplicate
Sunway BRT `B1000`. This count is a snapshot count, not the total number of
bus services operating in Klang Valley. The separate `rapid-bus-mrtfeeder`
endpoint has not been integrated, even though the KL snapshot itself contains
some T-numbered feeder services. A route label is not proof that the whole
dedicated feeder dataset is covered.

The official API documentation explicitly notes removed Rapid Bus trip stop
times due to data accuracy issues and links a problematic-trips CSV:
[GTFS Static API](https://developer.data.gov.my/realtime-api/gtfs-static).
The current snapshot audit reports three trips without stop sequences:
`weekend_T4069_T406902_0`, `_1` and `_2`. They are retained in audit evidence
and omitted from routing; no replacement timetable is inferred.
See [the reviewed audit](docs/data-audits/rapid-bus-kl-2026-11-08.md).

Frequency headways are not live arrival predictions. Three complete bus trips
without frequency rows are represented by their published exact stop times.
Cross-mode walking links are an explicit limited list in `data/network-kl.json`.
Named GTFS stops and coordinate sanity checks support these associations, but
walking durations and pedestrian accessibility still need field validation.

## Rail and Sunway BRT interchange audit (16 November 2026)

The [interchange audit](docs/data-audits/rail-interchanges-2026-11-16.md)
compares 29 published station areas against the bundled graph. Nine two-way
links were added across five areas, including Glenmarie. These use the existing
curated-link configuration; the source feeds and their timetables were not
refreshed. Walk durations remain estimates.


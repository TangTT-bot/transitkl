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


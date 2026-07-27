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


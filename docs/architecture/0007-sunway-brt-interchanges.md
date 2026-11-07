# ADR 0007: Complete Sunway BRT interchanges without duplicating the line

## Status

Implemented on 7 November 2026. Physical walking allowances remain estimates
pending field validation.

## Context and decision

The existing Rapid Rail GTFS export already includes all seven Sunway BRT stops,
both directions, twelve directed ride edges, and frequency/calendar profiles.
The KTM integration also added Setia Jaya KTM (`ktmb:53600`) to Sunway–Setia Jaya
BRT (`prasarana_rapid_rail:BRT1`), with six minutes walking in each direction.

The LRT connection was missing because the feed names the two platforms `USJ 7`
and `USJ7`. Normalized-name matching alone could not establish an interchange.

The network configuration now adds an explicit bidirectional link between
`prasarana_rapid_rail:KJ31` and `prasarana_rapid_rail:BRT7`, with 180 seconds of
walking. The connection is supported by the
[Monash University BRT guide](https://www.monash.edu.my/about/maps-and-transport/bus-rapid-transit).
The coordinates are about 50 metres apart in a straight line. Three minutes is
a conservative implementation allowance for platform access, not a measured
walking-path duration. The generic merger verifies the allowance is not shorter
than straight-line walking at 1.2 m/s.

`BRT7` receives the canonical display name `USJ 7`, retaining `USJ7` in its
`sourceName` field. Its original operator-scoped ID remains unchanged. Station
search can therefore group the two connected platforms as one interchange.
Search matching ignores spaces and punctuation, so both `USJ7` and `USJ 7`
find that single interchange entry.
Journeys passing through the interchange still incur a physical walking leg;
name grouping does not remove the transfer from an in-progress journey.

The source display label and app coverage text now explicitly include Sunway
BRT. This is completion of existing feed coverage, not another downloaded feed
or a second copy of the BRT line. When ordinary Rapid Bus data is added later,
any duplicate Sunway BRT representation must be excluded from that selection.

## Recommended routing

No change to the objective was needed. BRT uses its existing half-headway wait
estimates and calendar windows. Changing between LRT, KTM, and BRT increments
vehicle changes. Physical walking and waiting affect arrival time; the ten-minute
change penalty and extra walking reluctance affect ranking only.

On Saturday 7 November 2026 at 08:00, Putra Heights to SunU–Monash takes KJL to
USJ 7, walks for three minutes, and takes BRT for the remaining two segments.
It arrives at 08:30:12 with one transfer. This prevents a missing graph edge
from forcing an unnecessary detour through KTM.

Klang to Sunway Lagoon at 10:00 uses KTM to Setia Jaya, six minutes walking, and
BRT, arriving at 10:53. Sunway Lagoon to Klang at 09:00 uses the same interchange
in reverse, arriving at 09:58. At 08:00, the reverse journey instead uses BRT,
LRT at USJ 7, and KTM at Subang Jaya to catch an earlier train, arriving at 09:03.
The router does not force Setia Jaya when actual scheduled service makes a
different interchange substantially better, or invent extra KTM departures.

## Verification and resulting coverage

The merged network remains 244 stop IDs, 20 directional services, 164 scheduled
KTM trips, and 505 ride edges. Walking edges increase from 96 to 98: eighteen
curated pairs now cover thirteen interchange areas.

Regression tests verify:

- the seven BRT stops and both directions;
- both directed walking links at USJ 7 and at Setia Jaya;
- connected-platform grouping for USJ 7;
- LRT/BRT and KTM/BRT journeys in both directions;
- a timetable-dependent earlier connection through BRT/LRT/KTM;
- end-to-end BRT journeys staying on BRT without extra changes;
- weekday/weekend headways and a query outside operating hours/search horizon;
- clock durations equalling the sum of legs, separate from ranking penalties;
- the Flutter search/results flow displaying BRT and the USJ 7 transfer.

No raw GTFS data or routing weights were changed. The merge was rerun from the
existing zero-error audited exports, and its output is bundled in the app.
Final verification passed: 31 Flutter tests, 17 Python pipeline tests, no static
analysis issues, and matching generated/bundled SHA-256 checksums.
Regular Rapid KL and MRT feeder bus integration remains the next coverage step.

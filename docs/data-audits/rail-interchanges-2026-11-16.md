# Rail and Sunway BRT interchange audit

Reviewed on 16 November 2026. This is a connectivity audit of the bundled
LRT, MRT, monorail, KTM Komuter and Sunway BRT services, not a timetable
refresh or a survey of all pedestrian routes in the Klang Valley.

## Method and result

Compared the transit map reproduced on page 97 of the
[UTM 2026–27 handbook](https://mjiit.utm.my/wp-content/uploads/2026/10/FINAL_PG-HANDBOOK_202620271.pdf)
and the [Tourism Malaysia rail map and transfer notes, page 1](https://www.jwp.gov.my/storage/article/Kuala-Lumpur-Map-%26-Guide_small.pdf)
with the bundled graph. Cross-checked the Shah Alam Line interchanges against
[Prasarana’s announcement](https://myrapid.com.my/wp-content/uploads/2025/01/KENYATAAN-MEDIA-PRASARANA-KOMITED-DALAM-TRANSFORMASI-PENGANGKUTAN-AWAM-TINGKAT-MUTU-PERKHIDMATAN-DAN-SASAR-LONJAKAN-PENUMPANG-.pdf)
and the Putrajaya Line interchange list against
[MRT Corp’s service announcement](https://www.mymrt.com.my/wp-content/uploads/2022/12/22122022_MRT-PUTRAJAYA-LINE-FULL-OPERATIONS-TO-COMMENCE-IN-MARCH-2023.pdf).
Mapped each supported station area to the actual boardable GTFS IDs and
checked for a walking edge in each direction. The checked list of 29 station
areas and their IDs is retained in
[`rail_interchange_integration_test.dart`](../../test/data/routing/rail_interchange_integration_test.dart),
including the pre-existing links at Bandar Utama, Pasar Seni, Ampang Park,
Kwasa Damansara, Kajang, USJ 7 and Setia Jaya.

## Missing or indirect links added

| Station area | GTFS stop pairs (Rapid Rail namespace) | Walk allowance | Evidence |
| --- | --- | ---: | --- |
| Glenmarie / Glenmarie 2 | KJ27 ↔ SA7 | 8 min | Prasarana interchange announcement |
| Merdeka / Plaza Rakyat | KG17 ↔ AG8; KG17 ↔ SP8 | 4 min each | [MRT Corp Merdeka linkway, Entrance A](https://www.mymrt.com.my/wp-content/uploads/2022/06/MRT-Corp-Vending-Mahine-Space-Information-Kit-July-2022.pdf) |
| Dang Wangi / Bukit Nanas | KJ12 ↔ MR8 | 7 min | [Rapid Rail confirmation](https://myrapid.com.my/wp-content/uploads/2024/04/RAPID-RAIL-HOLDING-STATEMENT-GANGGUAN-BEKALAN-KUASA-JEJAS-KEKERAPAN-PERKHIDMATAN-LRT-LALUAN-KELANA-JAYA.pdf) and the map’s walk connector |
| Sultan Ismail / Medan Tuanku | AG5 ↔ MR9; SP5 ↔ MR9 | 11 min each | Tourism Malaysia map and transfer notes |
| KL Sentral / Muzium Negara | KJ15 ↔ KG15; MR1 ↔ KG15; KJ15 ↔ MR1 | 10 min each | Tourism Malaysia transfer notes; [National Museum access guidance](https://www.muziumnegara.gov.my/en/how-get-national-museum) |

KL Sentral was already navigable via multiple walking edges through the KTM
stop node, but this double-counted traversal through the hub for some journeys.
The new edges represent the complete walk between the listed boarding points;
the existing KTM links stay in the graph. Separate station IDs and names are
preserved. The duration allowances are estimates including platform access and
gate changes where applicable; they are not field measurements. The graph’s
distance field is a straight-line reference, not the walking distance.

The nine bidirectional pairs add 18 directed edges (170 → 188). The graph was
rebuilt from the same three audited exports. No ride edge, stop identity,
timetable, feed validity window or Recommended scoring weight was changed.
With the static snapshot at 08:00 on 16 November, SS15 → Klang Jaya switches
from Pasar Seni and Bandar Utama (2:04:03, two changes) to Glenmarie (1:01:14,
one change). The reverse uses the same interchange. Pudu ↔ Muzium Negara now
uses Merdeka / Plaza Rakyat at the test departure time in both directions.

## Limits and future refreshes

- Out of scope: ERL, Skypark Link, future stations, unmarked proximity
  connections, and new bus-to-rail links. Jambatan Kota / KTM Klang, LRT /
  KTM Sentul, and LRT / KTM Salak Selatan are not treated as interchanges.
- This checks whether the documented links exist, not the quality of existing
  walk allowances, lift/gate accessibility, live closures, or service changes.
  Verify those separately in field testing.
- On a feed refresh, rerun the audit checks against the generated asset.
  Investigate a missing or changed ID against operator sources; don't replace
  it based on station-name similarity alone.

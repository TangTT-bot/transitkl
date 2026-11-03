from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
from .database import normalize_search_text


def merge_graphs(
    input_paths: list[Path], config_path: Path, output_path: Path
) -> dict[str, object]:
    """Merge audited exports without collapsing operator IDs or calendars."""
    config = json.loads(config_path.read_text(encoding="utf-8"))
    merged = {key: [] for key in (
        "feeds", "stops", "services", "serviceCalendars", "scheduledTrips",
        "rideEdges", "transferEdges",
    )}
    seen_feeds: set[str] = set()
    for path in input_paths:
        graph = json.loads(path.read_text(encoding="utf-8"))
        if graph.get("schemaVersion") != 2:
            raise ValueError(f"Unsupported graph schema in {path}")
        feed_id = graph["feed"]["id"]
        if graph["feed"].get("auditErrorCount") != 0:
            raise ValueError(f"{feed_id} must be exported from a database with zero audit errors")
        if feed_id in seen_feeds:
            raise ValueError(f"Duplicate feed ID: {feed_id}")
        seen_feeds.add(feed_id)
        if feed_id not in config["feeds"]:
            raise ValueError(f"Feed is not configured: {feed_id}")
        selection = config["feeds"][feed_id]
        available_routes = {service["routeId"] for service in graph["services"]}
        selected_routes = set(selection.get("routeIds", available_routes))
        if not selected_routes or not selected_routes <= available_routes:
            raise ValueError(f"Unknown or empty route selection for {feed_id}")
        services = [s for s in graph["services"] if s["routeId"] in selected_routes]
        service_ids = {s["id"] for s in services}
        trips = [t for t in graph["scheduledTrips"] if t["serviceId"] in service_ids]
        rides = [e for e in graph["rideEdges"] if e["serviceId"] in service_ids]
        stop_ids = {e[k] for e in rides for k in ("fromStopId", "toStopId")}
        stop_ids.update(t["stopId"] for trip in trips for t in trip["stopTimes"])
        calendar_ids = {t["calendarId"] for t in trips}
        calendar_ids.update(w["calendarId"] for s in services for w in s["headways"])
        merged["feeds"].append({**graph["feed"], "displayName": selection["displayName"],
                                "includedRouteIds": sorted(selected_routes)})
        merged["stops"].extend(s for s in graph["stops"] if s["id"] in stop_ids)
        merged["services"].extend(services)
        merged["scheduledTrips"].extend(trips)
        merged["rideEdges"].extend(rides)
        merged["serviceCalendars"].extend(c for c in graph["serviceCalendars"] if c["id"] in calendar_ids)
        merged["transferEdges"].extend(e for e in graph["transferEdges"]
            if e["fromStopId"] in stop_ids and e["toStopId"] in stop_ids)

    if seen_feeds != set(config["feeds"]):
        raise ValueError("Input feeds must exactly match the network configuration")
    for key in ("stops", "services", "serviceCalendars", "scheduledTrips"):
        ids = [record["id"] for record in merged[key]]
        if len(ids) != len(set(ids)):
            raise ValueError(f"Duplicate identifier in {key}; use feed namespaces")

    stops = {s["id"]: s for s in merged["stops"]}
    for stop_id, name in config.get("stopNameOverrides", {}).items():
        if stop_id not in stops or not isinstance(name, str) or not name.strip():
            raise ValueError(f"Invalid stop name override: {stop_id}")
        stops[stop_id]["sourceName"] = stops[stop_id]["name"]
        stops[stop_id]["name"] = name
        stops[stop_id]["normalizedName"] = normalize_search_text(name)
    transfers = {(e["fromStopId"], e["toStopId"]): e for e in merged["transferEdges"]}
    for link in config.get("transfers", []):
        first, second = link["fromStopId"], link["toStopId"]
        if first not in stops or second not in stops or first == second:
            raise ValueError(f"Invalid curated interchange: {first} -> {second}")
        distance = _distance(stops[first], stops[second])
        walk = link["walkSeconds"]
        if not isinstance(walk, int) or walk < 60 or walk < math.ceil(distance / 1.2):
            raise ValueError(f"Walking allowance is too short: {first} -> {second}")
        pairs = [(first, second)]
        if link.get("bidirectional", True):
            pairs.append((second, first))
        for source, target in pairs:
            transfers[(source, target)] = {
                "fromStopId": source, "toStopId": target,
                "walkSeconds": walk, "distanceMetres": round(distance),
                "source": "curated_interchange", "sourceUrl": link["sourceUrl"],
            }
    merged["transferEdges"] = sorted(transfers.values(), key=lambda e: (e["fromStopId"], e["toStopId"]))
    for key in ("stops", "services", "serviceCalendars", "scheduledTrips", "feeds"):
        merged[key].sort(key=lambda record: record["id"])
    merged["rideEdges"].sort(key=lambda e: (e["fromStopId"], e["toStopId"], e["serviceId"]))
    _validate_references(merged)
    digest = hashlib.sha256(json.dumps({"data": merged, "config": config}, sort_keys=True).encode()).hexdigest()
    payload = {
        "schemaVersion": 2,
        "feed": {
            "id": config["id"], "sourceSha256": digest,
            # Union for the date picker; each operator keeps its own calendar.
            "serviceDateStart": min(f["serviceDateStart"] for f in merged["feeds"]),
            "serviceDateEnd": max(f["serviceDateEnd"] for f in merged["feeds"]),
        },
        **merged,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = output_path.with_suffix(output_path.suffix + ".part")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, output_path)
    return payload


def _validate_references(graph: dict) -> None:
    stops = {s["id"] for s in graph["stops"]}
    services = {s["id"] for s in graph["services"]}
    calendars = {c["id"] for c in graph["serviceCalendars"]}
    for service in graph["services"]:
        if any(w["calendarId"] not in calendars for w in service["headways"]):
            raise ValueError("Unknown headway calendar")
    for trip in graph["scheduledTrips"]:
        if trip["serviceId"] not in services or trip["calendarId"] not in calendars:
            raise ValueError("Unknown scheduled-trip service or calendar")
        if any(t["stopId"] not in stops for t in trip["stopTimes"]):
            raise ValueError("Unknown scheduled-trip stop")
    for edge in graph["rideEdges"] + graph["transferEdges"]:
        if edge["fromStopId"] not in stops or edge["toStopId"] not in stops:
            raise ValueError("Unknown edge stop")
        if "serviceId" in edge and edge["serviceId"] not in services:
            raise ValueError("Unknown ride service")


def _distance(first: dict, second: dict) -> float:
    lat1, lat2 = math.radians(first["latitude"]), math.radians(second["latitude"])
    lon = math.radians(second["longitude"] - first["longitude"])
    a = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(lon / 2) ** 2
    return 12_742_000 * math.asin(math.sqrt(min(1, max(0, a))))

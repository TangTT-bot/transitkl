from __future__ import annotations

import json
import os
import sqlite3
from collections import defaultdict
from pathlib import Path


def service_id(route_id: str, direction_id: int) -> str:
    return f"{route_id}::direction:{direction_id}"


def export_routing_graph(
    database_path: str | Path,
    output_path: str | Path,
) -> dict[str, object]:
    database = Path(database_path).resolve()
    if not database.is_file():
        raise FileNotFoundError(f"SQLite database does not exist: {database}")

    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    try:
        metadata = {
            row["key"]: row["value"]
            for row in connection.execute("SELECT key, value FROM feed_metadata")
        }
        _require_routing_schema(connection)

        headways: dict[tuple[str, int], list[dict[str, int]]] = defaultdict(list)
        for row in connection.execute(
            """
            SELECT route_id, direction_id, start_seconds, end_seconds,
                   headway_seconds
            FROM headway_profiles
            ORDER BY route_id, direction_id, start_seconds, end_seconds
            """
        ):
            headways[(row["route_id"], row["direction_id"])].append(
                {
                    "startSeconds": row["start_seconds"],
                    "endSeconds": row["end_seconds"],
                    "headwaySeconds": row["headway_seconds"],
                }
            )

        services = []
        for row in connection.execute(
            """
            SELECT DISTINCT ride_edges.route_id,
                            ride_edges.direction_id,
                            routes.route_short_name,
                            routes.route_long_name,
                            routes.route_type,
                            routes.route_color,
                            routes.route_text_color
            FROM ride_edges
            JOIN routes ON routes.route_id = ride_edges.route_id
            ORDER BY ride_edges.route_id, ride_edges.direction_id
            """
        ):
            key = (row["route_id"], row["direction_id"])
            services.append(
                {
                    "id": service_id(*key),
                    "routeId": row["route_id"],
                    "directionId": row["direction_id"],
                    "shortName": row["route_short_name"],
                    "longName": row["route_long_name"],
                    "routeType": row["route_type"],
                    "color": row["route_color"],
                    "textColor": row["route_text_color"],
                    "headways": headways[key],
                }
            )

        payload: dict[str, object] = {
            "schemaVersion": 1,
            "feed": {
                "id": metadata.get("feed_id", ""),
                "sourceSha256": metadata.get("source_sha256", ""),
                "serviceDateStart": metadata.get("service_date_start", ""),
                "serviceDateEnd": metadata.get("service_date_end", ""),
            },
            "stops": [
                {
                    "id": row["stop_id"],
                    "name": row["stop_name"],
                    "normalizedName": row["normalized_name"],
                    "latitude": row["stop_lat"],
                    "longitude": row["stop_lon"],
                }
                for row in connection.execute(
                    """
                    SELECT stop_id, stop_name, normalized_name, stop_lat, stop_lon
                    FROM stops
                    ORDER BY stop_id
                    """
                )
            ],
            "services": services,
            "rideEdges": [
                {
                    "fromStopId": row["from_stop_id"],
                    "toStopId": row["to_stop_id"],
                    "serviceId": service_id(row["route_id"], row["direction_id"]),
                    "travelSeconds": row["travel_seconds"],
                }
                for row in connection.execute(
                    """
                    SELECT from_stop_id, to_stop_id, route_id, direction_id,
                           travel_seconds
                    FROM ride_edges
                    ORDER BY from_stop_id, to_stop_id, route_id, direction_id
                    """
                )
            ],
            "transferEdges": [
                {
                    "fromStopId": row["from_stop_id"],
                    "toStopId": row["to_stop_id"],
                    "walkSeconds": row["walk_seconds"],
                    "distanceMetres": row["distance_metres"],
                    "source": row["source"],
                }
                for row in connection.execute(
                    """
                    SELECT from_stop_id, to_stop_id, walk_seconds,
                           distance_metres, source
                    FROM transfer_edges
                    ORDER BY from_stop_id, to_stop_id
                    """
                )
            ],
        }
    finally:
        connection.close()

    output = Path(output_path).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".part")
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(payload, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    os.replace(temporary, output)
    return payload


def _require_routing_schema(connection: sqlite3.Connection) -> None:
    tables = {
        row[0]
        for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table'"
        )
    }
    required = {"ride_edges", "headway_profiles", "transfer_edges"}
    missing = sorted(required - tables)
    if missing:
        raise ValueError(
            "Database predates the routing schema; rebuild it first. "
            f"Missing table(s): {', '.join(missing)}"
        )

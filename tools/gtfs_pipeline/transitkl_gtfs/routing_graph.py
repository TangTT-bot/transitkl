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

        calendars = _service_calendars(connection)
        headways: dict[tuple[str, int], list[dict[str, object]]] = defaultdict(list)
        for row in connection.execute(
            """
            SELECT route_id, direction_id, service_id, start_seconds,
                   end_seconds, headway_seconds
            FROM headway_profiles
            ORDER BY route_id, direction_id, service_id,
                     start_seconds, end_seconds
            """
        ):
            headways[(row["route_id"], row["direction_id"])].append(
                {
                    "calendarId": row["service_id"],
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
            "schemaVersion": 2,
            "feed": {
                "id": metadata.get("feed_id", ""),
                "sourceSha256": metadata.get("source_sha256", ""),
                "serviceDateStart": metadata.get("service_date_start", ""),
                "serviceDateEnd": metadata.get("service_date_end", ""),
            },
            "serviceCalendars": calendars,
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
            "scheduledTrips": _scheduled_trips(connection),
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


def _service_calendars(connection: sqlite3.Connection) -> list[dict[str, object]]:
    exceptions: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in connection.execute(
        """
        SELECT service_id, service_date, exception_type
        FROM calendar_exceptions
        ORDER BY service_id, service_date
        """
    ):
        exceptions[row["service_id"]].append(
            {
                "date": _iso_date(row["service_date"]),
                "isRunning": row["exception_type"] == 1,
            }
        )

    base_calendars = {
        row["service_id"]: row
        for row in connection.execute(
            """
            SELECT service_id, monday, tuesday, wednesday, thursday,
                   friday, saturday, sunday, start_date, end_date
            FROM service_calendars
            """
        )
    }
    service_ids = {
        row[0] for row in connection.execute("SELECT DISTINCT service_id FROM trips")
    } | set(exceptions)
    calendars = []
    for calendar_id in sorted(service_ids):
        row = base_calendars.get(calendar_id)
        calendars.append(
            {
                "id": calendar_id,
                "weekdays": (
                    [
                        bool(row["monday"]),
                        bool(row["tuesday"]),
                        bool(row["wednesday"]),
                        bool(row["thursday"]),
                        bool(row["friday"]),
                        bool(row["saturday"]),
                        bool(row["sunday"]),
                    ]
                    if row is not None
                    else [False] * 7
                ),
                "startDate": _iso_date(row["start_date"]) if row is not None else None,
                "endDate": _iso_date(row["end_date"]) if row is not None else None,
                "exceptions": exceptions[calendar_id],
            }
        )
    return calendars


def _scheduled_trips(connection: sqlite3.Connection) -> list[dict[str, object]]:
    trips = []
    for trip in connection.execute(
        """
        SELECT trips.trip_id, trips.route_id, trips.service_id,
               COALESCE(trips.direction_id, -1) AS direction_id,
               trips.trip_headsign
        FROM trips
        WHERE NOT EXISTS (
            SELECT 1 FROM frequencies
            WHERE frequencies.trip_id = trips.trip_id
        )
        ORDER BY trips.trip_id
        """
    ):
        stop_times = []
        is_complete = True
        for row in connection.execute(
            """
            SELECT stop_id, arrival_seconds, departure_seconds
            FROM stop_times
            WHERE trip_id = ?
            ORDER BY stop_sequence
            """,
            (trip["trip_id"],),
        ):
            arrival = (
                row["arrival_seconds"]
                if row["arrival_seconds"] is not None
                else row["departure_seconds"]
            )
            departure = (
                row["departure_seconds"]
                if row["departure_seconds"] is not None
                else row["arrival_seconds"]
            )
            if arrival is None or departure is None:
                is_complete = False
                break
            stop_times.append(
                {
                    "stopId": row["stop_id"],
                    "arrivalSeconds": arrival,
                    "departureSeconds": departure,
                }
            )
        if not is_complete or len(stop_times) < 2:
            continue
        trips.append(
            {
                "id": trip["trip_id"],
                "serviceId": service_id(trip["route_id"], trip["direction_id"]),
                "calendarId": trip["service_id"],
                "headsign": trip["trip_headsign"],
                "stopTimes": stop_times,
            }
        )
    return trips


def _iso_date(gtfs_date: str) -> str:
    if len(gtfs_date) != 8 or not gtfs_date.isdigit():
        raise ValueError(f"Invalid GTFS date in database: {gtfs_date!r}")
    return f"{gtfs_date[0:4]}-{gtfs_date[4:6]}-{gtfs_date[6:8]}"


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

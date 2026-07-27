from __future__ import annotations

import os
import re
import sqlite3
import unicodedata
from pathlib import Path
from .audit import AuditReport, audit_feed, parse_gtfs_time
from .feed import FeedSource


SCHEMA = """
PRAGMA journal_mode = DELETE;

CREATE TABLE feed_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE agencies (
    agency_id TEXT PRIMARY KEY,
    raw_agency_id TEXT NOT NULL,
    agency_name TEXT NOT NULL,
    agency_url TEXT NOT NULL,
    agency_timezone TEXT NOT NULL,
    agency_lang TEXT,
    agency_phone TEXT
);

CREATE TABLE stops (
    stop_id TEXT PRIMARY KEY,
    raw_stop_id TEXT NOT NULL,
    stop_code TEXT,
    stop_name TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    stop_lat REAL,
    stop_lon REAL,
    location_type INTEGER NOT NULL DEFAULT 0,
    parent_station TEXT,
    wheelchair_boarding INTEGER,
    FOREIGN KEY (parent_station) REFERENCES stops(stop_id)
);

CREATE TABLE routes (
    route_id TEXT PRIMARY KEY,
    raw_route_id TEXT NOT NULL,
    agency_id TEXT,
    route_short_name TEXT,
    route_long_name TEXT,
    route_type INTEGER NOT NULL,
    route_color TEXT,
    route_text_color TEXT,
    FOREIGN KEY (agency_id) REFERENCES agencies(agency_id)
);

CREATE TABLE service_calendars (
    service_id TEXT PRIMARY KEY,
    raw_service_id TEXT NOT NULL,
    monday INTEGER NOT NULL,
    tuesday INTEGER NOT NULL,
    wednesday INTEGER NOT NULL,
    thursday INTEGER NOT NULL,
    friday INTEGER NOT NULL,
    saturday INTEGER NOT NULL,
    sunday INTEGER NOT NULL,
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL
);

CREATE TABLE calendar_exceptions (
    service_id TEXT NOT NULL,
    raw_service_id TEXT NOT NULL,
    service_date TEXT NOT NULL,
    exception_type INTEGER NOT NULL,
    PRIMARY KEY (service_id, service_date)
);

CREATE TABLE trips (
    trip_id TEXT PRIMARY KEY,
    raw_trip_id TEXT NOT NULL,
    route_id TEXT NOT NULL,
    service_id TEXT NOT NULL,
    trip_headsign TEXT,
    direction_id INTEGER,
    shape_id TEXT,
    FOREIGN KEY (route_id) REFERENCES routes(route_id)
);

CREATE TABLE stop_times (
    trip_id TEXT NOT NULL,
    stop_sequence INTEGER NOT NULL,
    stop_id TEXT NOT NULL,
    arrival_seconds INTEGER,
    departure_seconds INTEGER,
    stop_headsign TEXT,
    pickup_type INTEGER,
    drop_off_type INTEGER,
    PRIMARY KEY (trip_id, stop_sequence),
    FOREIGN KEY (trip_id) REFERENCES trips(trip_id),
    FOREIGN KEY (stop_id) REFERENCES stops(stop_id)
);

CREATE TABLE frequencies (
    trip_id TEXT NOT NULL,
    start_seconds INTEGER NOT NULL,
    end_seconds INTEGER NOT NULL,
    headway_seconds INTEGER NOT NULL,
    exact_times INTEGER,
    PRIMARY KEY (trip_id, start_seconds, end_seconds),
    FOREIGN KEY (trip_id) REFERENCES trips(trip_id)
);

CREATE INDEX idx_stops_normalized_name ON stops(normalized_name);
CREATE INDEX idx_trips_route_service ON trips(route_id, service_id);
CREATE INDEX idx_stop_times_stop_id ON stop_times(stop_id);
CREATE INDEX idx_stop_times_trip_sequence ON stop_times(trip_id, stop_sequence);
CREATE INDEX idx_frequencies_trip_start ON frequencies(trip_id, start_seconds);
CREATE INDEX idx_calendar_exceptions_date ON calendar_exceptions(service_date);
"""


class FeedValidationError(ValueError):
    pass


def build_database(
    input_path: str | Path,
    feed_id: str,
    output_path: str | Path,
    *,
    allow_errors: bool = False,
) -> AuditReport:
    report = audit_feed(input_path, feed_id)
    if report.error_count and not allow_errors:
        raise FeedValidationError(
            f"GTFS audit found {report.error_count} error(s); database was not built."
        )

    source = FeedSource(input_path)
    output = Path(output_path).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".part")
    if temporary.exists():
        temporary.unlink()

    connection = sqlite3.connect(temporary)
    try:
        connection.execute("PRAGMA foreign_keys = OFF")
        connection.executescript(SCHEMA)
        _insert_metadata(connection, report)
        agency_ids = _insert_agencies(connection, source, feed_id)
        _insert_stops(connection, source, feed_id)
        _insert_routes(connection, source, feed_id, agency_ids)
        _insert_calendars(connection, source, feed_id)
        _insert_calendar_exceptions(connection, source, feed_id)
        _insert_trips(connection, source, feed_id)
        _insert_stop_times(connection, source, feed_id)
        _insert_frequencies(connection, source, feed_id)

        foreign_key_problems = list(connection.execute("PRAGMA foreign_key_check"))
        if foreign_key_problems:
            sample = ", ".join(str(problem) for problem in foreign_key_problems[:5])
            raise FeedValidationError(f"SQLite foreign-key validation failed: {sample}")

        connection.commit()
    except Exception:
        connection.close()
        if temporary.exists():
            temporary.unlink()
        raise
    else:
        connection.close()

    os.replace(temporary, output)
    return report


def normalize_search_text(value: str) -> str:
    decomposed = unicodedata.normalize("NFKD", value)
    without_marks = "".join(char for char in decomposed if not unicodedata.combining(char))
    alphanumeric = re.sub(r"[^a-z0-9]+", " ", without_marks.casefold())
    return " ".join(alphanumeric.split())


def _namespaced(feed_id: str, raw_id: str) -> str:
    return f"{feed_id}:{raw_id}"


def _optional_namespaced(feed_id: str, raw_id: str) -> str | None:
    return _namespaced(feed_id, raw_id) if raw_id else None


def _optional_int(value: str) -> int | None:
    return int(value) if value else None


def _optional_float(value: str) -> float | None:
    return float(value) if value else None


def _optional_time(value: str) -> int | None:
    return parse_gtfs_time(value) if value else None


def _rows(source: FeedSource, file_name: str) -> list[dict[str, str]]:
    return source.read_rows(file_name) if source.has_file(file_name) else []


def _insert_metadata(connection: sqlite3.Connection, report: AuditReport) -> None:
    values = {
        "schema_version": "1",
        "feed_id": report.feed_id,
        "source": report.source,
        "source_sha256": report.source_sha256,
        "built_at_utc": report.generated_at_utc,
        "service_date_start": report.service_date_start or "",
        "service_date_end": report.service_date_end or "",
        "audit_error_count": str(report.error_count),
        "audit_warning_count": str(report.warning_count),
    }
    connection.executemany(
        "INSERT INTO feed_metadata(key, value) VALUES (?, ?)",
        values.items(),
    )


def _insert_agencies(
    connection: sqlite3.Connection,
    source: FeedSource,
    feed_id: str,
) -> list[str]:
    records = []
    for index, row in enumerate(_rows(source, "agency.txt"), start=1):
        raw_id = row.get("agency_id", "") or ("default" if index == 1 else f"agency_{index}")
        records.append(
            (
                _namespaced(feed_id, raw_id),
                raw_id,
                row.get("agency_name", ""),
                row.get("agency_url", ""),
                row.get("agency_timezone", ""),
                row.get("agency_lang") or None,
                row.get("agency_phone") or None,
            )
        )
    connection.executemany(
        """
        INSERT INTO agencies(
            agency_id, raw_agency_id, agency_name, agency_url,
            agency_timezone, agency_lang, agency_phone
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        records,
    )
    return [record[0] for record in records]


def _insert_stops(connection: sqlite3.Connection, source: FeedSource, feed_id: str) -> None:
    records = []
    for row in _rows(source, "stops.txt"):
        raw_id = row.get("stop_id", "")
        records.append(
            (
                _namespaced(feed_id, raw_id),
                raw_id,
                row.get("stop_code") or None,
                row.get("stop_name", ""),
                normalize_search_text(row.get("stop_name", "")),
                _optional_float(row.get("stop_lat", "")),
                _optional_float(row.get("stop_lon", "")),
                _optional_int(row.get("location_type", "")) or 0,
                _optional_namespaced(feed_id, row.get("parent_station", "")),
                _optional_int(row.get("wheelchair_boarding", "")),
            )
        )
    connection.executemany(
        """
        INSERT INTO stops(
            stop_id, raw_stop_id, stop_code, stop_name, normalized_name,
            stop_lat, stop_lon, location_type, parent_station, wheelchair_boarding
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        records,
    )


def _insert_routes(
    connection: sqlite3.Connection,
    source: FeedSource,
    feed_id: str,
    agency_ids: list[str],
) -> None:
    default_agency = agency_ids[0] if len(agency_ids) == 1 else None
    records = []
    for row in _rows(source, "routes.txt"):
        raw_id = row.get("route_id", "")
        raw_agency_id = row.get("agency_id", "")
        agency_id = _optional_namespaced(feed_id, raw_agency_id) or default_agency
        records.append(
            (
                _namespaced(feed_id, raw_id),
                raw_id,
                agency_id,
                row.get("route_short_name") or None,
                row.get("route_long_name") or None,
                int(row.get("route_type", "0")),
                row.get("route_color") or None,
                row.get("route_text_color") or None,
            )
        )
    connection.executemany(
        """
        INSERT INTO routes(
            route_id, raw_route_id, agency_id, route_short_name,
            route_long_name, route_type, route_color, route_text_color
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        records,
    )


def _insert_calendars(connection: sqlite3.Connection, source: FeedSource, feed_id: str) -> None:
    records = []
    for row in _rows(source, "calendar.txt"):
        raw_id = row.get("service_id", "")
        records.append(
            (
                _namespaced(feed_id, raw_id),
                raw_id,
                int(row.get("monday", "0")),
                int(row.get("tuesday", "0")),
                int(row.get("wednesday", "0")),
                int(row.get("thursday", "0")),
                int(row.get("friday", "0")),
                int(row.get("saturday", "0")),
                int(row.get("sunday", "0")),
                row.get("start_date", ""),
                row.get("end_date", ""),
            )
        )
    connection.executemany(
        """
        INSERT INTO service_calendars(
            service_id, raw_service_id, monday, tuesday, wednesday,
            thursday, friday, saturday, sunday, start_date, end_date
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        records,
    )


def _insert_calendar_exceptions(
    connection: sqlite3.Connection,
    source: FeedSource,
    feed_id: str,
) -> None:
    records = []
    for row in _rows(source, "calendar_dates.txt"):
        raw_id = row.get("service_id", "")
        records.append(
            (
                _namespaced(feed_id, raw_id),
                raw_id,
                row.get("date", ""),
                int(row.get("exception_type", "0")),
            )
        )
    connection.executemany(
        """
        INSERT INTO calendar_exceptions(
            service_id, raw_service_id, service_date, exception_type
        ) VALUES (?, ?, ?, ?)
        """,
        records,
    )


def _insert_trips(connection: sqlite3.Connection, source: FeedSource, feed_id: str) -> None:
    records = []
    for row in _rows(source, "trips.txt"):
        raw_id = row.get("trip_id", "")
        records.append(
            (
                _namespaced(feed_id, raw_id),
                raw_id,
                _namespaced(feed_id, row.get("route_id", "")),
                _namespaced(feed_id, row.get("service_id", "")),
                row.get("trip_headsign") or None,
                _optional_int(row.get("direction_id", "")),
                _optional_namespaced(feed_id, row.get("shape_id", "")),
            )
        )
    connection.executemany(
        """
        INSERT INTO trips(
            trip_id, raw_trip_id, route_id, service_id,
            trip_headsign, direction_id, shape_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        records,
    )


def _insert_stop_times(
    connection: sqlite3.Connection,
    source: FeedSource,
    feed_id: str,
) -> None:
    records = []
    for row in _rows(source, "stop_times.txt"):
        records.append(
            (
                _namespaced(feed_id, row.get("trip_id", "")),
                int(row.get("stop_sequence", "0")),
                _namespaced(feed_id, row.get("stop_id", "")),
                _optional_time(row.get("arrival_time", "")),
                _optional_time(row.get("departure_time", "")),
                row.get("stop_headsign") or None,
                _optional_int(row.get("pickup_type", "")),
                _optional_int(row.get("drop_off_type", "")),
            )
        )
    connection.executemany(
        """
        INSERT INTO stop_times(
            trip_id, stop_sequence, stop_id, arrival_seconds,
            departure_seconds, stop_headsign, pickup_type, drop_off_type
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        records,
    )


def _insert_frequencies(
    connection: sqlite3.Connection,
    source: FeedSource,
    feed_id: str,
) -> None:
    records = []
    for row in _rows(source, "frequencies.txt"):
        records.append(
            (
                _namespaced(feed_id, row.get("trip_id", "")),
                parse_gtfs_time(row.get("start_time", "")),
                parse_gtfs_time(row.get("end_time", "")),
                int(row.get("headway_secs", "0")),
                _optional_int(row.get("exact_times", "")),
            )
        )
    connection.executemany(
        """
        INSERT INTO frequencies(
            trip_id, start_seconds, end_seconds, headway_seconds, exact_times
        ) VALUES (?, ?, ?, ?, ?)
        """,
        records,
    )

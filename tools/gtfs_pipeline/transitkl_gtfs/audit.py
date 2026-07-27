from __future__ import annotations

import json
from collections import defaultdict
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .feed import FeedSource


CORE_FILES = ("agency.txt", "stops.txt", "routes.txt", "trips.txt", "stop_times.txt")

REQUIRED_COLUMNS: dict[str, set[str]] = {
    "agency.txt": {"agency_name", "agency_url", "agency_timezone"},
    "stops.txt": {"stop_id", "stop_name", "stop_lat", "stop_lon"},
    "routes.txt": {"route_id", "route_type"},
    "trips.txt": {"route_id", "service_id", "trip_id"},
    "stop_times.txt": {"trip_id", "stop_id", "stop_sequence"},
    "frequencies.txt": {"trip_id", "start_time", "end_time", "headway_secs"},
    "calendar.txt": {
        "service_id",
        "monday",
        "tuesday",
        "wednesday",
        "thursday",
        "friday",
        "saturday",
        "sunday",
        "start_date",
        "end_date",
    },
    "calendar_dates.txt": {"service_id", "date", "exception_type"},
}

PRIMARY_KEYS: dict[str, tuple[str, ...]] = {
    "stops.txt": ("stop_id",),
    "routes.txt": ("route_id",),
    "trips.txt": ("trip_id",),
    "stop_times.txt": ("trip_id", "stop_sequence"),
    "calendar.txt": ("service_id",),
    "calendar_dates.txt": ("service_id", "date"),
    "frequencies.txt": ("trip_id", "start_time", "end_time"),
}

ISSUE_LIMIT = 250


@dataclass(frozen=True)
class AuditIssue:
    severity: str
    code: str
    message: str
    file_name: str | None = None
    row_number: int | None = None


@dataclass
class AuditReport:
    feed_id: str
    source: str
    source_sha256: str
    generated_at_utc: str
    files: list[str]
    row_counts: dict[str, int]
    service_date_start: str | None
    service_date_end: str | None
    after_midnight_time_count: int
    issues: list[AuditIssue] = field(default_factory=list)
    suppressed_issue_count: int = 0

    @property
    def error_count(self) -> int:
        return sum(issue.severity == "error" for issue in self.issues)

    @property
    def warning_count(self) -> int:
        return sum(issue.severity == "warning" for issue in self.issues)

    @property
    def is_valid(self) -> bool:
        return self.error_count == 0 and self.suppressed_issue_count == 0

    def to_dict(self) -> dict[str, Any]:
        result = asdict(self)
        result.update(
            {
                "error_count": self.error_count,
                "warning_count": self.warning_count,
                "is_valid": self.is_valid,
            }
        )
        return result

    def write_json(self, output_path: str | Path) -> None:
        path = Path(output_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(self.to_dict(), indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    def write_markdown(self, output_path: str | Path) -> None:
        path = Path(output_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(self.to_markdown(), encoding="utf-8")

    def to_markdown(self) -> str:
        status = "PASS" if self.is_valid else "FAIL"
        lines = [
            f"# GTFS audit: {self.feed_id}",
            "",
            f"- Status: **{status}**",
            f"- Generated: `{self.generated_at_utc}`",
            f"- Source: `{self.source}`",
            f"- SHA-256: `{self.source_sha256}`",
            f"- Service dates: `{self.service_date_start or 'unknown'}` to "
            f"`{self.service_date_end or 'unknown'}`",
            f"- Times after midnight: `{self.after_midnight_time_count}`",
            f"- Errors: `{self.error_count}`",
            f"- Warnings: `{self.warning_count}`",
            "",
            "## Row counts",
            "",
            "| File | Rows |",
            "| --- | ---: |",
        ]
        for file_name, count in sorted(self.row_counts.items()):
            lines.append(f"| `{file_name}` | {count} |")

        lines.extend(["", "## Findings", ""])
        if not self.issues:
            lines.append("No validation issues were detected.")
        else:
            lines.extend(
                [
                    "| Severity | Code | Location | Finding |",
                    "| --- | --- | --- | --- |",
                ]
            )
            for issue in self.issues:
                location = issue.file_name or "-"
                if issue.row_number is not None:
                    location += f":{issue.row_number}"
                message = issue.message.replace("|", "\\|")
                lines.append(
                    f"| {issue.severity.upper()} | `{issue.code}` | `{location}` | {message} |"
                )
        if self.suppressed_issue_count:
            lines.extend(
                [
                    "",
                    f"An additional {self.suppressed_issue_count} findings were suppressed "
                    f"after the {ISSUE_LIMIT}-issue report limit.",
                ]
            )
        return "\n".join(lines) + "\n"


def parse_gtfs_time(value: str) -> int:
    """Convert a GTFS HH:MM:SS value to seconds since the service-day start."""

    parts = value.strip().split(":")
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        raise ValueError(f"Invalid GTFS time: {value!r}")
    hours, minutes, seconds = (int(part) for part in parts)
    if minutes > 59 or seconds > 59:
        raise ValueError(f"Invalid GTFS time: {value!r}")
    return hours * 3600 + minutes * 60 + seconds


def audit_feed(input_path: str | Path, feed_id: str) -> AuditReport:
    source = FeedSource(input_path)
    rows_by_file: dict[str, list[dict[str, str]]] = {}
    issues: list[AuditIssue] = []
    suppressed = 0

    def add_issue(issue: AuditIssue) -> None:
        nonlocal suppressed
        if len(issues) < ISSUE_LIMIT:
            issues.append(issue)
        else:
            suppressed += 1

    for file_name in CORE_FILES:
        if not source.has_file(file_name):
            add_issue(
                AuditIssue(
                    "error",
                    "missing_file",
                    f"Required file {file_name} is absent.",
                    file_name,
                )
            )

    if not source.has_file("calendar.txt") and not source.has_file("calendar_dates.txt"):
        add_issue(
            AuditIssue(
                "error",
                "missing_service_calendar",
                "At least one of calendar.txt or calendar_dates.txt is required.",
            )
        )

    for file_name in source.file_names:
        try:
            rows_by_file[file_name] = source.read_rows(file_name)
        except (UnicodeError, ValueError) as error:
            rows_by_file[file_name] = []
            add_issue(AuditIssue("error", "unreadable_file", str(error), file_name))

    for file_name, expected_columns in REQUIRED_COLUMNS.items():
        if file_name not in rows_by_file:
            continue
        rows = rows_by_file[file_name]
        actual_columns = set(rows[0]) if rows else set()
        missing_columns = sorted(expected_columns - actual_columns)
        if missing_columns:
            add_issue(
                AuditIssue(
                    "error",
                    "missing_columns",
                    f"Missing columns: {', '.join(missing_columns)}.",
                    file_name,
                )
            )

    for file_name, key_fields in PRIMARY_KEYS.items():
        rows = rows_by_file.get(file_name, [])
        seen: set[tuple[str, ...]] = set()
        for row_number, row in enumerate(rows, start=2):
            key = tuple(row.get(field, "") for field in key_fields)
            if any(not value for value in key):
                add_issue(
                    AuditIssue(
                        "error",
                        "missing_primary_key",
                        f"Missing primary-key value for {', '.join(key_fields)}.",
                        file_name,
                        row_number,
                    )
                )
                continue
            if key in seen:
                add_issue(
                    AuditIssue(
                        "error",
                        "duplicate_primary_key",
                        f"Duplicate key {key!r}.",
                        file_name,
                        row_number,
                    )
                )
            seen.add(key)

    _validate_foreign_keys(rows_by_file, add_issue)
    after_midnight_count = _validate_stop_times(rows_by_file, add_issue)
    after_midnight_count += _validate_frequencies(rows_by_file, add_issue)
    service_start, service_end = _service_date_range(rows_by_file)

    return AuditReport(
        feed_id=feed_id,
        source=_display_source(source.path),
        source_sha256=source.sha256(),
        generated_at_utc=datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        files=source.file_names,
        row_counts={name: len(rows) for name, rows in rows_by_file.items()},
        service_date_start=service_start,
        service_date_end=service_end,
        after_midnight_time_count=after_midnight_count,
        issues=issues,
        suppressed_issue_count=suppressed,
    )


def _validate_foreign_keys(
    rows_by_file: dict[str, list[dict[str, str]]],
    add_issue: Any,
) -> None:
    stop_ids = {row.get("stop_id", "") for row in rows_by_file.get("stops.txt", [])}
    route_ids = {row.get("route_id", "") for row in rows_by_file.get("routes.txt", [])}
    trip_ids = {row.get("trip_id", "") for row in rows_by_file.get("trips.txt", [])}

    for row_number, row in enumerate(rows_by_file.get("trips.txt", []), start=2):
        route_id = row.get("route_id", "")
        if route_id and route_id not in route_ids:
            add_issue(
                AuditIssue(
                    "error",
                    "unknown_route",
                    f"trip_id {row.get('trip_id', '')!r} references unknown route_id {route_id!r}.",
                    "trips.txt",
                    row_number,
                )
            )

    for row_number, row in enumerate(rows_by_file.get("stop_times.txt", []), start=2):
        trip_id = row.get("trip_id", "")
        stop_id = row.get("stop_id", "")
        if trip_id and trip_id not in trip_ids:
            add_issue(
                AuditIssue(
                    "error",
                    "unknown_trip",
                    f"stop time references unknown trip_id {trip_id!r}.",
                    "stop_times.txt",
                    row_number,
                )
            )
        if stop_id and stop_id not in stop_ids:
            add_issue(
                AuditIssue(
                    "error",
                    "unknown_stop",
                    f"stop time references unknown stop_id {stop_id!r}.",
                    "stop_times.txt",
                    row_number,
                )
            )

    for row_number, row in enumerate(rows_by_file.get("frequencies.txt", []), start=2):
        trip_id = row.get("trip_id", "")
        if trip_id and trip_id not in trip_ids:
            add_issue(
                AuditIssue(
                    "error",
                    "unknown_frequency_trip",
                    f"frequency references unknown trip_id {trip_id!r}.",
                    "frequencies.txt",
                    row_number,
                )
            )


def _validate_stop_times(
    rows_by_file: dict[str, list[dict[str, str]]],
    add_issue: Any,
) -> int:
    by_trip: dict[str, list[tuple[int, int, dict[str, str]]]] = defaultdict(list)
    after_midnight = 0

    for row_number, row in enumerate(rows_by_file.get("stop_times.txt", []), start=2):
        sequence_value = row.get("stop_sequence", "")
        try:
            sequence = int(sequence_value)
            if sequence < 0:
                raise ValueError
        except ValueError:
            add_issue(
                AuditIssue(
                    "error",
                    "invalid_stop_sequence",
                    f"Invalid stop_sequence {sequence_value!r}.",
                    "stop_times.txt",
                    row_number,
                )
            )
            continue

        for field_name in ("arrival_time", "departure_time"):
            value = row.get(field_name, "")
            if not value:
                continue
            try:
                parsed = parse_gtfs_time(value)
                if parsed >= 24 * 3600:
                    after_midnight += 1
            except ValueError as error:
                add_issue(
                    AuditIssue(
                        "error",
                        "invalid_time",
                        str(error),
                        "stop_times.txt",
                        row_number,
                    )
                )

        by_trip[row.get("trip_id", "")].append((sequence, row_number, row))

    for trip_id, records in by_trip.items():
        previous_departure: int | None = None
        for _, row_number, row in sorted(records):
            arrival = _optional_time(row.get("arrival_time", ""))
            departure = _optional_time(row.get("departure_time", ""))
            if arrival is not None and departure is not None and departure < arrival:
                add_issue(
                    AuditIssue(
                        "error",
                        "departure_before_arrival",
                        f"trip_id {trip_id!r} departs before it arrives.",
                        "stop_times.txt",
                        row_number,
                    )
                )
            if arrival is not None and previous_departure is not None and arrival < previous_departure:
                add_issue(
                    AuditIssue(
                        "error",
                        "non_monotonic_trip_time",
                        f"trip_id {trip_id!r} moves backwards in time.",
                        "stop_times.txt",
                        row_number,
                    )
                )
            if departure is not None:
                previous_departure = departure
            elif arrival is not None:
                previous_departure = arrival

    return after_midnight


def _optional_time(value: str) -> int | None:
    if not value:
        return None
    try:
        return parse_gtfs_time(value)
    except ValueError:
        return None


def _validate_frequencies(
    rows_by_file: dict[str, list[dict[str, str]]],
    add_issue: Any,
) -> int:
    after_midnight = 0
    for row_number, row in enumerate(rows_by_file.get("frequencies.txt", []), start=2):
        parsed_times: dict[str, int] = {}
        for field_name in ("start_time", "end_time"):
            value = row.get(field_name, "")
            try:
                parsed_times[field_name] = parse_gtfs_time(value)
                if parsed_times[field_name] >= 24 * 3600:
                    after_midnight += 1
            except ValueError as error:
                add_issue(
                    AuditIssue(
                        "error",
                        "invalid_frequency_time",
                        str(error),
                        "frequencies.txt",
                        row_number,
                    )
                )

        if (
            "start_time" in parsed_times
            and "end_time" in parsed_times
            and parsed_times["end_time"] <= parsed_times["start_time"]
        ):
            add_issue(
                AuditIssue(
                    "error",
                    "invalid_frequency_window",
                    "Frequency end_time must be later than start_time.",
                    "frequencies.txt",
                    row_number,
                )
            )

        headway_value = row.get("headway_secs", "")
        try:
            if int(headway_value) <= 0:
                raise ValueError
        except ValueError:
            add_issue(
                AuditIssue(
                    "error",
                    "invalid_headway",
                    f"headway_secs must be a positive integer, got {headway_value!r}.",
                    "frequencies.txt",
                    row_number,
                )
            )
    return after_midnight


def _display_source(path: Path) -> str:
    try:
        return path.relative_to(Path.cwd().resolve()).as_posix()
    except ValueError:
        return str(path)


def _service_date_range(
    rows_by_file: dict[str, list[dict[str, str]]],
) -> tuple[str | None, str | None]:
    dates: list[str] = []
    for row in rows_by_file.get("calendar.txt", []):
        dates.extend(
            value
            for value in (row.get("start_date", ""), row.get("end_date", ""))
            if value
        )
    dates.extend(
        row.get("date", "")
        for row in rows_by_file.get("calendar_dates.txt", [])
        if row.get("date", "")
    )
    return (min(dates), max(dates)) if dates else (None, None)

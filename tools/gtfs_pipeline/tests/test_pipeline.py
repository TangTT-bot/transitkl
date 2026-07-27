from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile


PIPELINE_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
FIXTURE = REPOSITORY_ROOT / "data" / "fixtures" / "mini_gtfs"
sys.path.insert(0, str(PIPELINE_ROOT))

from transitkl_gtfs.audit import audit_feed, parse_gtfs_time  # noqa: E402
from transitkl_gtfs.database import build_database, normalize_search_text  # noqa: E402


class GtfsTimeTests(unittest.TestCase):
    def test_parses_time_after_midnight(self) -> None:
        self.assertEqual(parse_gtfs_time("25:10:30"), 25 * 3600 + 10 * 60 + 30)

    def test_rejects_invalid_minutes(self) -> None:
        with self.assertRaises(ValueError):
            parse_gtfs_time("10:60:00")


class AuditTests(unittest.TestCase):
    def test_fixture_passes_audit(self) -> None:
        report = audit_feed(FIXTURE, "fixture")

        self.assertTrue(report.is_valid)
        self.assertEqual(report.error_count, 0)
        self.assertEqual(report.row_counts["stops.txt"], 5)
        self.assertEqual(report.row_counts["routes.txt"], 2)
        self.assertEqual(report.row_counts["trips.txt"], 2)
        self.assertEqual(report.row_counts["stop_times.txt"], 6)
        self.assertEqual(report.row_counts["frequencies.txt"], 2)
        self.assertEqual(report.after_midnight_time_count, 12)
        self.assertEqual(report.service_date_start, "20260101")
        self.assertEqual(report.service_date_end, "20261231")

    def test_writes_json_and_markdown_reports(self) -> None:
        report = audit_feed(FIXTURE, "fixture")
        with tempfile.TemporaryDirectory() as temporary_directory:
            output = Path(temporary_directory)
            json_path = output / "audit.json"
            markdown_path = output / "audit.md"

            report.write_json(json_path)
            report.write_markdown(markdown_path)

            payload = json.loads(json_path.read_text(encoding="utf-8"))
            self.assertTrue(payload["is_valid"])
            self.assertIn("Status: **PASS**", markdown_path.read_text(encoding="utf-8"))

    def test_ignores_macos_resource_fork_files_in_zip(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            archive_path = Path(temporary_directory) / "fixture.zip"
            with ZipFile(archive_path, "w") as archive:
                for source_file in FIXTURE.glob("*.txt"):
                    archive.write(source_file, source_file.name)
                archive.writestr("__MACOSX/._stops.txt", b"\x00\xffnot-csv")

            report = audit_feed(archive_path, "fixture")

            self.assertTrue(report.is_valid)
            self.assertNotIn("._stops.txt", report.files)

    def test_reports_broken_stop_reference_and_headway(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            archive_path = Path(temporary_directory) / "invalid.zip"
            with ZipFile(archive_path, "w") as archive:
                for source_file in FIXTURE.glob("*.txt"):
                    content = source_file.read_text(encoding="utf-8")
                    if source_file.name == "stop_times.txt":
                        content = content.replace(",S5,3,", ",UNKNOWN,3,")
                    if source_file.name == "frequencies.txt":
                        content = content.replace(",900,0", ",0,0")
                    archive.writestr(source_file.name, content)

            report = audit_feed(archive_path, "invalid_fixture")
            issue_codes = {issue.code for issue in report.issues}

            self.assertFalse(report.is_valid)
            self.assertIn("unknown_stop", issue_codes)
            self.assertIn("invalid_headway", issue_codes)


class DatabaseTests(unittest.TestCase):
    def test_builds_namespaced_database(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            database_path = Path(temporary_directory) / "transit.sqlite"
            report = build_database(FIXTURE, "fixture", database_path)

            self.assertTrue(report.is_valid)
            self.assertTrue(database_path.exists())

            connection = sqlite3.connect(database_path)
            try:
                stop_count = connection.execute("SELECT COUNT(*) FROM stops").fetchone()[0]
                route_count = connection.execute("SELECT COUNT(*) FROM routes").fetchone()[0]
                frequency_count = connection.execute(
                    "SELECT COUNT(*) FROM frequencies"
                ).fetchone()[0]
                last_arrival = connection.execute(
                    """
                    SELECT arrival_seconds
                    FROM stop_times
                    WHERE trip_id = ? AND stop_sequence = 3
                    """,
                    ("fixture:T2",),
                ).fetchone()[0]
                normalized_name = connection.execute(
                    "SELECT normalized_name FROM stops WHERE stop_id = ?",
                    ("fixture:S3",),
                ).fetchone()[0]
                feed_id = connection.execute(
                    "SELECT value FROM feed_metadata WHERE key = 'feed_id'"
                ).fetchone()[0]
                foreign_key_problems = list(connection.execute("PRAGMA foreign_key_check"))
            finally:
                connection.close()

            self.assertEqual(stop_count, 5)
            self.assertEqual(route_count, 2)
            self.assertEqual(frequency_count, 2)
            self.assertEqual(last_arrival, 24 * 3600 + 35 * 60)
            self.assertEqual(normalized_name, "central interchange")
            self.assertEqual(feed_id, "fixture")
            self.assertEqual(foreign_key_problems, [])

    def test_normalizes_search_text(self) -> None:
        self.assertEqual(normalize_search_text("  Masjid-Jámek  "), "masjid jamek")


if __name__ == "__main__":
    unittest.main()

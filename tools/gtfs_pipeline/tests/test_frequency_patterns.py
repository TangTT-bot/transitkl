from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from transitkl_gtfs.audit import audit_feed
from transitkl_gtfs.database import build_database
from transitkl_gtfs.routing_graph import export_routing_graph

FIXTURE = Path(__file__).resolve().parents[3] / "data/fixtures/mini_gtfs"


class FrequencyPatternTests(unittest.TestCase):
    def test_reports_missing_stop_sequences_without_inventing_a_trip(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "feed.zip"
            with ZipFile(archive, "w") as output:
                for file in FIXTURE.glob("*.txt"):
                    content = file.read_text(encoding="utf-8")
                    if file.name == "trips.txt":
                        content += "R1,WKD,REMOVED,Missing published sequence,0\n"
                    output.writestr(file.name, content)
            report = audit_feed(archive, "test")
            self.assertTrue(report.is_valid)
            self.assertEqual(report.warning_count, 1)
            self.assertEqual(report.issues[0].code, "trip_without_stop_times")
            build_database(archive, "test", Path(temporary) / "feed.sqlite")
            graph = export_routing_graph(Path(temporary) / "feed.sqlite",
                Path(temporary) / "graph.json", preserve_frequency_patterns=True)
            self.assertEqual(graph["feed"]["tripsWithoutStopTimes"], ["test:REMOVED"])
            self.assertFalse(any(t["id"] == "test:REMOVED" for t in graph["scheduledTrips"]))

    def test_preserves_variants_repeated_stops_offsets_and_permissions(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "feed.zip"
            with ZipFile(archive, "w") as output:
                for file in FIXTURE.glob("*.txt"):
                    content = file.read_text(encoding="utf-8")
                    if file.name == "trips.txt":
                        content += "R1,WKD,LOOP,Loop variant,0\n"
                    elif file.name == "stop_times.txt":
                        content += ("LOOP,08:00:00,08:00:00,S1,1,0,0\n"
                            "LOOP,08:10:00,08:12:00,S3,2,1,1\n"
                            "LOOP,08:20:00,08:20:00,S1,3,0,0\n"
                            "LOOP,08:30:00,08:30:00,S4,4,0,0\n")
                    elif file.name == "frequencies.txt":
                        content += "LOOP,08:00:00,09:00:00,600,0\n"
                    output.writestr(file.name, content)
            build_database(archive, "test", root / "feed.sqlite")
            graph = export_routing_graph(root / "feed.sqlite", root / "graph.json",
                preserve_frequency_patterns=True)
            self.assertEqual(graph["schemaVersion"], 3)
            variants = [s for s in graph["services"] if s["routeId"] == "test:R1"]
            self.assertEqual(len(variants), 2)
            for service in variants:
                self.assertIn("::pattern:", service["id"])
            loop = next(s for s in variants if s["headways"][0]["startSeconds"] == 8 * 3600)
            edges = [e for e in graph["rideEdges"] if e["serviceId"] == loop["id"]]
            self.assertEqual([e["sequence"] for e in edges], [0, 1, 2])
            self.assertEqual([e["fromStopId"] for e in edges], ["test:S1", "test:S3", "test:S1"])
            self.assertEqual(edges[1]["departureOffsetSeconds"], 720)
            self.assertEqual(edges[1]["dwellSeconds"], 120)
            self.assertFalse(edges[1]["pickupAllowed"])
            self.assertFalse(edges[0]["dropOffAllowed"])
            self.assertEqual(graph, export_routing_graph(root / "feed.sqlite", root / "again.json",
                preserve_frequency_patterns=True))


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from transitkl_gtfs.database import build_database
from transitkl_gtfs.routing_graph import export_routing_graph
from transitkl_gtfs.merge import merge_graphs

FIXTURE = Path(__file__).resolve().parents[3] / "data/fixtures/mini_gtfs"


class MergeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.inputs = []
        for feed_id in ("first", "second"):
            source = FIXTURE
            if feed_id == "second":
                source = self.root / "scheduled.zip"
                with ZipFile(source, "w") as archive:
                    for file in FIXTURE.glob("*.txt"):
                        if file.name != "frequencies.txt":
                            archive.write(file, file.name)
            database = self.root / f"{feed_id}.sqlite"
            output = self.root / f"{feed_id}.json"
            build_database(source, feed_id, database)
            export_routing_graph(database, output)
            self.inputs.append(output)
        self.config = {
            "id": "test_network",
            "feeds": {"first": {"displayName": "First"},
                      "second": {"displayName": "Second", "routeIds": ["second:R1"]}},
            "transfers": [{"fromStopId": "first:S3", "toStopId": "second:S3",
                           "walkSeconds": 120, "sourceUrl": "https://example.test/map"}],
        }
        self.config_path = self.root / "config.json"
        self.output = self.root / "merged.json"

    def merge(self):
        self.config_path.write_text(json.dumps(self.config), encoding="utf-8")
        return merge_graphs(self.inputs, self.config_path, self.output)

    def test_filters_routes_preserves_schedules_and_adds_real_walking_edges(self):
        result = self.merge()
        self.assertEqual(len(result["stops"]), 9)
        self.assertEqual(len(result["services"]), 3)
        self.assertEqual([t["id"] for t in result["scheduledTrips"]], ["second:T1"])
        self.assertNotIn("second:S6", {s["id"] for s in result["stops"]})
        self.assertEqual(len(result["feeds"]), 2)
        curated = [e for e in result["transferEdges"] if e["source"] == "curated_interchange"]
        self.assertEqual(len(curated), 2)
        self.assertTrue(all(e["walkSeconds"] == 120 for e in curated))
        self.inputs.reverse()
        self.assertEqual(result, self.merge())

    def test_rejects_duplicate_feed(self):
        self.inputs.append(self.inputs[0])
        with self.assertRaisesRegex(ValueError, "Duplicate feed"):
            self.merge()

    def test_rejects_unknown_route(self):
        self.config["feeds"]["second"]["routeIds"] = ["second:UNKNOWN"]
        with self.assertRaisesRegex(ValueError, "route selection"):
            self.merge()

    def test_rejects_dangling_interchange(self):
        self.config["transfers"][0]["toStopId"] = "second:UNKNOWN"
        with self.assertRaisesRegex(ValueError, "Invalid curated"):
            self.merge()

    def test_rejects_graph_without_audit_evidence(self):
        graph = json.loads(self.inputs[0].read_text(encoding="utf-8"))
        del graph["feed"]["auditErrorCount"]
        self.inputs[0].write_text(json.dumps(graph), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "zero audit errors"):
            self.merge()

    def test_rejects_impossibly_short_walking_time(self):
        self.config["transfers"][0]["walkSeconds"] = 1
        with self.assertRaisesRegex(ValueError, "Walking allowance"):
            self.merge()

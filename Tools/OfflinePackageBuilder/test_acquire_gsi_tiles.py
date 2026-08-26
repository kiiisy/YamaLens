#!/usr/bin/env python3
"""Deterministic tests for the GSI elevation tile acquisition planner."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import acquire_gsi_tiles


class GSITileAcquisitionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(prefix="yamalens-gsi-plan-test-")
        self.root = Path(self.temporary_directory.name)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_creates_deterministic_paths_for_review_before_download(self) -> None:
        config = self.write_config()
        output = self.root / "plan.json"

        plan = acquire_gsi_tiles.create_plan(config, output)

        self.assertGreater(plan["tileCount"], 0)
        self.assertEqual(plan["tileCount"], len(plan["tiles"]))
        first = plan["tiles"][0]
        self.assertEqual(first["dataset"], "DEM5A")
        self.assertTrue(first["url"].startswith("https://cyberjapandata.gsi.go.jp/xyz/dem5a_png/15/"))
        self.assertTrue(first["relativePath"].startswith("DEM5A/15/"))

    def test_rejects_unapproved_download_host(self) -> None:
        plan_path = self.root / "unsafe-plan.json"
        plan_path.write_text(
            json.dumps(
                {
                    "formatVersion": 1,
                    "tiles": [
                        {
                            "dataset": "DEM5A",
                            "url": "https://example.com/xyz/dem5a_png/15/1/2.png",
                            "relativePath": "DEM5A/15/1/2.png",
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )

        with self.assertRaisesRegex(ValueError, "unsafe acquisition entry"):
            acquire_gsi_tiles.validated_plan_entries(plan_path)

    def test_selects_named_terrain_profile_and_records_it_in_plan(self) -> None:
        config = self.write_profiled_config()
        output = self.root / "compact-plan.json"

        plan = acquire_gsi_tiles.create_plan(config, output, requested_profile="compact")

        self.assertEqual(plan["terrainProfile"], "compact")
        self.assertEqual(plan["layers"][0]["zoom"], 13)
        self.assertTrue(plan["tiles"][0]["relativePath"].startswith("DEM10B/13/"))

    def test_uses_default_terrain_profile_when_not_specified(self) -> None:
        config = self.write_profiled_config()
        output = self.root / "default-plan.json"

        plan = acquire_gsi_tiles.create_plan(config, output)

        self.assertEqual(plan["terrainProfile"], "detailed")
        self.assertEqual(plan["layers"][0]["zoom"], 15)

    def test_rejects_unknown_terrain_profile(self) -> None:
        config = self.write_profiled_config()

        with self.assertRaisesRegex(ValueError, "unknown terrain profile"):
            acquire_gsi_tiles.create_plan(config, self.root / "plan.json", requested_profile="missing")

    def test_rejects_invalid_fetch_batch_limit(self) -> None:
        plan_path = self.root / "plan.json"
        plan_path.write_text(
            json.dumps({"formatVersion": 1, "tiles": []}),
            encoding="utf-8",
        )

        with self.assertRaisesRegex(ValueError, "maximumRequests"):
            acquire_gsi_tiles.fetch_plan(
                plan_path,
                self.root / "destination",
                interval=0.2,
                maximum_requests=0,
            )

    def write_config(self) -> Path:
        path = self.root / "config.json"
        path.write_text(
            json.dumps(
                {
                    "formatVersion": 1,
                    "provider": "国土地理院",
                    "sourceInformationURL": "https://maps.gsi.go.jp/development/ichiran.html#dem",
                    "layers": [
                        {
                            "id": "test",
                            "dataset": "DEM5A",
                            "tileSet": "dem5a_png",
                            "extension": "png",
                            "zoom": 15,
                            "bounds": {
                                "north": 35.50,
                                "south": 35.49,
                                "east": 139.15,
                                "west": 139.14,
                            },
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        return path

    def write_profiled_config(self) -> Path:
        path = self.root / "profiled-config.json"
        bounds = {
            "north": 35.50,
            "south": 35.49,
            "east": 139.15,
            "west": 139.14,
        }
        path.write_text(
            json.dumps(
                {
                    "formatVersion": 2,
                    "provider": "国土地理院",
                    "sourceInformationURL": "https://maps.gsi.go.jp/development/ichiran.html#dem",
                    "defaultProfile": "detailed",
                    "profiles": {
                        "detailed": {
                            "layers": [
                                {
                                    "id": "detailed",
                                    "dataset": "DEM5A",
                                    "tileSet": "dem5a_png",
                                    "extension": "png",
                                    "zoom": 15,
                                    "bounds": bounds,
                                }
                            ]
                        },
                        "compact": {
                            "layers": [
                                {
                                    "id": "compact",
                                    "dataset": "DEM10B",
                                    "tileSet": "dem_png",
                                    "extension": "png",
                                    "zoom": 13,
                                    "bounds": bounds,
                                }
                            ]
                        },
                    },
                }
            ),
            encoding="utf-8",
        )
        return path


if __name__ == "__main__":
    unittest.main()

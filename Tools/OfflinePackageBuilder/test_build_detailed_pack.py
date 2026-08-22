#!/usr/bin/env python3
"""Deterministic tests for the detailed offline package builder."""

from __future__ import annotations

import hashlib
import json
import shutil
import sqlite3
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

import build_detailed_pack


class DetailedPackBuilderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(prefix="yamalens-builder-test-")
        self.root = Path(self.temporary_directory.name)
        self.openssl = shutil.which("openssl")
        if self.openssl is None:
            self.skipTest("OpenSSL is unavailable")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_builds_signed_package_and_fills_missing_cells_by_priority(self) -> None:
        dem5a_root = self.root / "DEM5A"
        dem10b_root = self.root / "DEM10B"
        dem5a_tile = dem5a_root / "15" / "29000" / "12900.txt"
        dem10b_tile = dem10b_root / "14" / "14500" / "6450.txt"
        self.write_tile(dem5a_tile, default="123.4", first="e")
        self.write_tile(dem10b_tile, default="42.4")

        terrain_index = self.root / "terrain-index.json"
        build_detailed_pack.create_terrain_index(
            [f"DEM5A={dem5a_root}", f"DEM10B={dem10b_root}"],
            terrain_index,
        )
        config = self.write_config(15, 29000, 12900)
        private_key = self.generate_private_key()
        public_key = self.root / "public-key.raw"
        build_detailed_pack.export_raw_public_key(private_key, public_key)
        output = self.root / "package"

        build_detailed_pack.build_package(config, terrain_index, output, private_key)

        self.assertEqual(
            sorted(path.name for path in output.iterdir()),
            ["catalog.sqlite", "manifest.json", "manifest.sig", "terrain.lzfse"],
        )
        self.assertEqual((output / "manifest.sig").stat().st_size, 64)
        self.assertEqual(public_key.stat().st_size, 32)
        manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["packageID"], "jp.kanagawa.tanzawa.test")
        self.assertEqual([record["path"] for record in manifest["files"]], [
            "catalog.sqlite",
            "terrain.lzfse",
        ])

        connection = sqlite3.connect(output / "catalog.sqlite")
        try:
            metadata = dict(connection.execute("SELECT key, value FROM package_metadata"))
            tile_row = connection.execute(
                """
                SELECT offset_bytes, compressed_bytes, sha256
                FROM terrain_tiles WHERE id = 'z15-x29000-y12900'
                """
            ).fetchone()
        finally:
            connection.close()
        self.assertEqual(metadata["package_id"], "jp.kanagawa.tanzawa.test")
        self.assertEqual(metadata["content_version"], "1.0.0")
        self.assertIsNotNone(tile_row)
        offset, compressed_bytes, expected_hash = tile_row
        terrain = (output / "terrain.lzfse").read_bytes()
        header = struct.unpack("<4sHHII", terrain[:16])
        self.assertEqual(header, (b"YLTF", 1, 16, 2, 0))
        payload = build_detailed_pack.LZFSECodec().decompress(
            terrain[offset : offset + compressed_bytes],
            build_detailed_pack.TERRAIN_UNCOMPRESSED_BYTES,
        )
        elevations = struct.unpack("<65536h", payload)
        self.assertEqual(elevations[0], 42)
        self.assertEqual(elevations[1], 123)
        self.assertEqual(hashlib.sha256(payload).hexdigest(), expected_hash)

    def test_rejects_source_file_when_inventory_hash_no_longer_matches(self) -> None:
        source_root = self.root / "DEM5A"
        tile = source_root / "15" / "29000" / "12900.txt"
        self.write_tile(tile, default="100")
        terrain_index = self.root / "terrain-index.json"
        build_detailed_pack.create_terrain_index([f"DEM5A={source_root}"], terrain_index)
        self.write_tile(tile, default="101")

        with self.assertRaisesRegex(ValueError, "source hash mismatch"):
            build_detailed_pack.load_terrain_index(terrain_index)

    def test_rejects_tile_outside_configured_package_bounds(self) -> None:
        source_root = self.root / "DEM5A"
        tile = source_root / "15" / "29000" / "12900.txt"
        self.write_tile(tile, default="100")
        terrain_index = self.root / "terrain-index.json"
        build_detailed_pack.create_terrain_index([f"DEM5A={source_root}"], terrain_index)
        config = self.write_config(15, 29000, 12900, exclude_tile=True)

        with self.assertRaisesRegex(ValueError, "outside allowedBounds"):
            build_detailed_pack.build_package(
                config,
                terrain_index,
                self.root / "package",
                self.generate_private_key(),
            )

    def write_tile(self, path: Path, default: str, first: str | None = None) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        rows = []
        for row_index in range(256):
            cells = [default] * 256
            if row_index == 0 and first is not None:
                cells[0] = first
            rows.append(",".join(cells))
        path.write_text("\n".join(rows) + "\n", encoding="utf-8")

    def write_config(
        self,
        zoom: int,
        x: int,
        y: int,
        exclude_tile: bool = False,
    ) -> Path:
        catalog_input = self.root / "bootstrap.json"
        catalog_input.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "contentVersion": "1.0.0",
                    "sourceManifestID": "test-bootstrap-v1",
                    "regions": [
                        {
                            "id": "test-region",
                            "name": "テスト山域",
                            "prefectureName": "神奈川県",
                        }
                    ],
                    "mountains": [
                        {
                            "id": "test-mountain",
                            "regionID": "test-region",
                            "coverageRole": "core",
                            "canonicalName": "テスト山",
                            "searchName": "テスト山",
                            "latitude": 35.4,
                            "longitude": 139.1,
                            "elevationMeters": 1000,
                            "updatedAt": "2026-08-22",
                            "aliases": [],
                        }
                    ],
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        source_manifest_directory = self.root / "source-manifests"
        source_manifest_directory.mkdir(exist_ok=True)
        (source_manifest_directory / "test-dem-v1.yaml").write_text(
            "id: test-dem-v1\nstatus: test_fixture\n",
            encoding="utf-8",
        )
        north, south, east, west = build_detailed_pack.tile_bounds(zoom, x, y)
        if exclude_tile:
            allowed_bounds = {
                "north": north - 0.1,
                "south": south - 0.2,
                "east": east,
                "west": west,
            }
        else:
            parent_north, parent_south, parent_east, parent_west = (
                build_detailed_pack.tile_bounds(zoom - 1, x // 2, y // 2)
            )
            allowed_bounds = {
                "north": max(north, parent_north) + 0.01,
                "south": min(south, parent_south) - 0.01,
                "east": max(east, parent_east) + 0.01,
                "west": min(west, parent_west) - 0.01,
            }
        config = self.root / "config.json"
        config.write_text(
            json.dumps(
                {
                    "formatVersion": 1,
                    "packageID": "jp.kanagawa.tanzawa.test",
                    "contentVersion": "1.0.0",
                    "schemaVersion": 1,
                    "keyID": "test-key-01",
                    "createdAt": "2026-08-22T00:00:00Z",
                    "minimumAppVersion": "0.1.0",
                    "allowedBounds": allowed_bounds,
                    "catalogInput": catalog_input.name,
                    "sourceManifestIDs": ["test-dem-v1"],
                    "sourceManifestDirectory": source_manifest_directory.name,
                    "sourceLinks": [
                        {
                            "id": "test-dem",
                            "provider": "テスト提供者",
                            "title": "テスト標高",
                            "url": "https://example.com/source",
                            "licenseURL": "https://example.com/terms",
                            "checkedAt": "2026-08-22",
                            "isPrimary": True,
                            "attributionText": "テストデータ",
                            "processingNote": "固定テスト入力",
                        }
                    ],
                    "terrainSourceLinkID": "test-dem",
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        return config

    def generate_private_key(self) -> Path:
        private_key = self.root / "test-private.pem"
        subprocess.run(
            [self.openssl, "genpkey", "-algorithm", "Ed25519", "-out", str(private_key)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return private_key


if __name__ == "__main__":
    unittest.main()

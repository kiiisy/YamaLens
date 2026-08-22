#!/usr/bin/env python3
"""Build and verify YamaLens's deterministic bootstrap SQLite catalog."""

from __future__ import annotations

import argparse
import json
import math
import sqlite3
import sys
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
MAX_MOUNTAINS = 10_000


SCHEMA = """
PRAGMA foreign_keys = ON;
CREATE TABLE package_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE regions (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    prefecture_name TEXT NOT NULL
);
CREATE TABLE mountains (
    id TEXT PRIMARY KEY,
    region_id TEXT NOT NULL REFERENCES regions(id),
    canonical_name TEXT NOT NULL,
    search_name TEXT NOT NULL,
    coverage_role TEXT NOT NULL CHECK(coverage_role IN ('core', 'surroundingCandidate')),
    latitude REAL NOT NULL CHECK(latitude BETWEEN -90.0 AND 90.0),
    longitude REAL NOT NULL CHECK(longitude BETWEEN -180.0 AND 180.0),
    elevation_m INTEGER NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE mountain_names (
    mountain_id TEXT NOT NULL REFERENCES mountains(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    search_name TEXT NOT NULL,
    kind TEXT NOT NULL CHECK(kind IN ('canonical', 'alias')),
    PRIMARY KEY(mountain_id, name)
);
CREATE TABLE points_of_interest (
    id TEXT PRIMARY KEY,
    region_id TEXT NOT NULL REFERENCES regions(id),
    type TEXT NOT NULL,
    name TEXT NOT NULL,
    latitude REAL,
    longitude REAL,
    summary TEXT,
    official_url TEXT,
    checked_at TEXT
);
CREATE TABLE mountain_points_of_interest (
    mountain_id TEXT NOT NULL REFERENCES mountains(id) ON DELETE CASCADE,
    point_of_interest_id TEXT NOT NULL REFERENCES points_of_interest(id) ON DELETE CASCADE,
    PRIMARY KEY(mountain_id, point_of_interest_id)
);
CREATE TABLE source_links (
    id TEXT PRIMARY KEY,
    provider TEXT NOT NULL,
    title TEXT NOT NULL,
    url TEXT NOT NULL,
    license_url TEXT,
    checked_at TEXT NOT NULL,
    is_primary INTEGER NOT NULL CHECK(is_primary IN (0, 1)),
    attribution_text TEXT NOT NULL,
    processing_note TEXT
);
CREATE TABLE entity_sources (
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    source_id TEXT NOT NULL REFERENCES source_links(id),
    PRIMARY KEY(entity_type, entity_id, source_id)
);
CREATE TABLE terrain_tiles (
    id TEXT PRIMARY KEY,
    north REAL NOT NULL,
    south REAL NOT NULL,
    east REAL NOT NULL,
    west REAL NOT NULL,
    resolution_m REAL NOT NULL,
    row_count INTEGER NOT NULL,
    column_count INTEGER NOT NULL,
    offset_bytes INTEGER NOT NULL,
    compressed_bytes INTEGER NOT NULL,
    uncompressed_bytes INTEGER NOT NULL,
    sha256 TEXT NOT NULL
);
CREATE INDEX mountains_region_id_idx ON mountains(region_id);
CREATE INDEX mountains_search_name_idx ON mountains(search_name);
CREATE INDEX mountain_names_search_name_idx ON mountain_names(search_name);
CREATE INDEX points_of_interest_region_type_idx ON points_of_interest(region_id, type);
CREATE INDEX terrain_tiles_bounds_idx ON terrain_tiles(south, north, west, east);
"""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="Verify an existing output database without replacing it.",
    )
    return parser.parse_args()


def require_text(value: Any, field: str, maximum_length: int = 256) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > maximum_length:
        raise ValueError(f"{field} must be non-empty text of at most {maximum_length} characters")
    return value


def require_number(value: Any, field: str, minimum: float, maximum: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{field} must be a number")
    number = float(value)
    if not math.isfinite(number) or not minimum <= number <= maximum:
        raise ValueError(f"{field} is outside the allowed range")
    return number


def load_source(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("root must be an object")
    if payload.get("schemaVersion") != SCHEMA_VERSION:
        raise ValueError("unsupported schemaVersion")

    require_text(payload.get("contentVersion"), "contentVersion", 32)
    require_text(payload.get("sourceManifestID"), "sourceManifestID", 128)
    regions = payload.get("regions")
    if not isinstance(regions, list) or not 1 <= len(regions) <= 128:
        raise ValueError("regions must contain 1...128 records")
    region_ids: set[str] = set()
    for index, region in enumerate(regions):
        if not isinstance(region, dict):
            raise ValueError(f"regions[{index}] must be an object")
        region_id = require_text(region.get("id"), f"regions[{index}].id", 128)
        if region_id in region_ids:
            raise ValueError(f"duplicate region id: {region_id}")
        region_ids.add(region_id)
        require_text(region.get("name"), f"regions[{index}].name", 128)
        require_text(region.get("prefectureName"), f"regions[{index}].prefectureName", 128)

    mountains = payload.get("mountains")
    if not isinstance(mountains, list) or not 1 <= len(mountains) <= MAX_MOUNTAINS:
        raise ValueError(f"mountains must contain 1...{MAX_MOUNTAINS} records")

    ids: set[str] = set()
    for index, mountain in enumerate(mountains):
        if not isinstance(mountain, dict):
            raise ValueError(f"mountains[{index}] must be an object")
        mountain_id = require_text(mountain.get("id"), f"mountains[{index}].id", 128)
        if mountain_id in ids:
            raise ValueError(f"duplicate mountain id: {mountain_id}")
        ids.add(mountain_id)
        region_id = require_text(mountain.get("regionID"), f"mountains[{index}].regionID", 128)
        if region_id not in region_ids:
            raise ValueError(f"mountains[{index}].regionID references an unknown region")
        if mountain.get("coverageRole") not in ("core", "surroundingCandidate"):
            raise ValueError(f"mountains[{index}].coverageRole is unsupported")
        require_text(mountain.get("canonicalName"), f"mountains[{index}].canonicalName", 128)
        require_text(mountain.get("searchName"), f"mountains[{index}].searchName", 256)
        require_text(mountain.get("updatedAt"), f"mountains[{index}].updatedAt", 32)
        require_number(mountain.get("latitude"), f"mountains[{index}].latitude", -90, 90)
        require_number(mountain.get("longitude"), f"mountains[{index}].longitude", -180, 180)
        require_number(mountain.get("elevationMeters"), f"mountains[{index}].elevationMeters", -500, 9_000)
        aliases = mountain.get("aliases")
        if not isinstance(aliases, list) or len(aliases) > 32:
            raise ValueError(f"mountains[{index}].aliases must be an array of at most 32 entries")
        for alias_index, alias in enumerate(aliases):
            require_text(alias, f"mountains[{index}].aliases[{alias_index}]", 128)
    return payload


def create_database(source: dict[str, Any], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()

    connection = sqlite3.connect(output)
    try:
        connection.executescript(SCHEMA)
        connection.executemany(
            "INSERT INTO package_metadata(key, value) VALUES(?, ?)",
            [
                ("schema_version", str(source["schemaVersion"])),
                ("content_version", source["contentVersion"]),
                ("source_manifest_id", source["sourceManifestID"]),
            ],
        )
        connection.executemany(
            "INSERT INTO regions(id, name, prefecture_name) VALUES(?, ?, ?)",
            [
                (region["id"], region["name"], region["prefectureName"])
                for region in source["regions"]
            ],
        )
        for mountain in source["mountains"]:
            connection.execute(
                """
                INSERT INTO mountains(
                    id, region_id, canonical_name, search_name, coverage_role, latitude,
                    longitude, elevation_m, updated_at
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    mountain["id"],
                    mountain["regionID"],
                    mountain["canonicalName"],
                    mountain["searchName"],
                    mountain["coverageRole"],
                    mountain["latitude"],
                    mountain["longitude"],
                    mountain["elevationMeters"],
                    mountain["updatedAt"],
                ),
            )
            connection.execute(
                "INSERT INTO mountain_names(mountain_id, name, search_name, kind) VALUES(?, ?, ?, 'canonical')",
                (mountain["id"], mountain["canonicalName"], mountain["searchName"]),
            )
            for alias in mountain["aliases"]:
                if alias == mountain["canonicalName"]:
                    continue
                connection.execute(
                    "INSERT INTO mountain_names(mountain_id, name, search_name, kind) VALUES(?, ?, ?, 'alias')",
                    (mountain["id"], alias, alias),
                )
        connection.commit()
        connection.execute("VACUUM")
    finally:
        connection.close()


def verify_database(source: dict[str, Any], output: Path) -> None:
    if not output.is_file():
        raise ValueError(f"database does not exist: {output}")
    connection = sqlite3.connect(f"file:{output}?mode=ro", uri=True)
    try:
        integrity = connection.execute("PRAGMA integrity_check").fetchone()
        if integrity != ("ok",):
            raise ValueError("SQLite integrity_check failed")
        foreign_keys = connection.execute("PRAGMA foreign_key_check").fetchall()
        if foreign_keys:
            raise ValueError("SQLite foreign_key_check failed")
        schema = connection.execute(
            "SELECT value FROM package_metadata WHERE key = 'schema_version'"
        ).fetchone()
        if schema != (str(SCHEMA_VERSION),):
            raise ValueError("unexpected database schema version")
        rows = connection.execute(
            "SELECT id, canonical_name, coverage_role, latitude, longitude, elevation_m FROM mountains ORDER BY id"
        ).fetchall()
        expected = sorted(
            (
                mountain["id"],
                mountain["canonicalName"],
                mountain["coverageRole"],
                mountain["latitude"],
                mountain["longitude"],
                mountain["elevationMeters"],
            )
            for mountain in source["mountains"]
        )
        if rows != expected:
            raise ValueError("database mountains do not match source data")
    finally:
        connection.close()


def main() -> int:
    arguments = parse_arguments()
    try:
        source = load_source(arguments.input)
        if not arguments.verify_only:
            create_database(source, arguments.output)
        verify_database(source, arguments.output)
    except (OSError, ValueError, json.JSONDecodeError, sqlite3.Error) as error:
        print(f"bootstrap build failed: {error}", file=sys.stderr)
        return 1
    print(f"bootstrap database verified: {arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

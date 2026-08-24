#!/usr/bin/env python3
"""Build and verify YamaLens's deterministic bootstrap SQLite catalog."""

from __future__ import annotations

import argparse
import json
import math
import re
import sqlite3
import sys
from datetime import date
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit


SCHEMA_VERSION = 1
MAX_MOUNTAINS = 10_000
MAX_POINTS_OF_INTEREST = 10_000
POINT_OF_INTEREST_TYPES = {
    "mountainHut",
    "trailhead",
    "parking",
    "publicTransport",
    "cableway",
    "hotSpring",
}


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
    yamap_url TEXT,
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
CREATE TABLE point_of_interest_details (
    point_of_interest_id TEXT NOT NULL REFERENCES points_of_interest(id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    value TEXT NOT NULL,
    display_order INTEGER NOT NULL CHECK(display_order >= 0),
    PRIMARY KEY(point_of_interest_id, kind)
);
CREATE TABLE mountain_points_of_interest (
    mountain_id TEXT NOT NULL REFERENCES mountains(id) ON DELETE CASCADE,
    point_of_interest_id TEXT NOT NULL REFERENCES points_of_interest(id) ON DELETE CASCADE,
    display_order INTEGER NOT NULL CHECK(display_order >= 0),
    PRIMARY KEY(mountain_id, point_of_interest_id)
);
CREATE TABLE trailhead_access_points (
    trailhead_id TEXT NOT NULL REFERENCES points_of_interest(id) ON DELETE CASCADE,
    point_of_interest_id TEXT NOT NULL REFERENCES points_of_interest(id) ON DELETE CASCADE,
    display_order INTEGER NOT NULL CHECK(display_order >= 0),
    PRIMARY KEY(trailhead_id, point_of_interest_id)
);
CREATE TABLE trailhead_search_areas (
    id TEXT PRIMARY KEY,
    trailhead_id TEXT NOT NULL REFERENCES points_of_interest(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    display_order INTEGER NOT NULL CHECK(display_order >= 0)
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
CREATE INDEX point_of_interest_details_point_id_idx ON point_of_interest_details(point_of_interest_id, display_order);
CREATE INDEX trailhead_access_points_trailhead_id_idx ON trailhead_access_points(trailhead_id, display_order);
CREATE INDEX trailhead_search_areas_trailhead_id_idx ON trailhead_search_areas(trailhead_id, display_order);
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


def require_https_url(value: Any, field: str) -> str:
    url = require_text(value, field, 2_048)
    parsed = urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError(f"{field} must be an HTTPS URL without user information")
    return url


def require_yamap_mountain_url(value: Any, field: str) -> str:
    url = require_https_url(value, field)
    parsed = urlsplit(url)
    if (
        parsed.hostname != "yamap.com"
        or parsed.port is not None
        or parsed.query
        or parsed.fragment
        or not re.fullmatch(r"/mountains/[1-9][0-9]*", parsed.path)
    ):
        raise ValueError(f"{field} must be a canonical YAMAP mountain URL")
    return url


def require_date(value: Any, field: str) -> str:
    text = require_text(value, field, 10)
    try:
        date.fromisoformat(text)
    except ValueError as error:
        raise ValueError(f"{field} must be an ISO 8601 calendar date") from error
    return text


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
        if mountain.get("yamapURL") is not None:
            require_yamap_mountain_url(
                mountain.get("yamapURL"),
                f"mountains[{index}].yamapURL",
            )
        aliases = mountain.get("aliases")
        if not isinstance(aliases, list) or len(aliases) > 32:
            raise ValueError(f"mountains[{index}].aliases must be an array of at most 32 entries")
        for alias_index, alias in enumerate(aliases):
            require_text(alias, f"mountains[{index}].aliases[{alias_index}]", 128)

    source_links = payload.get("sourceLinks", [])
    if not isinstance(source_links, list) or len(source_links) > 128:
        raise ValueError("sourceLinks must contain at most 128 records")
    source_ids: set[str] = set()
    for index, source in enumerate(source_links):
        if not isinstance(source, dict):
            raise ValueError(f"sourceLinks[{index}] must be an object")
        source_id = require_text(source.get("id"), f"sourceLinks[{index}].id", 128)
        if source_id in source_ids:
            raise ValueError(f"duplicate source link id: {source_id}")
        source_ids.add(source_id)
        require_text(source.get("provider"), f"sourceLinks[{index}].provider", 128)
        require_text(source.get("title"), f"sourceLinks[{index}].title", 256)
        require_https_url(source.get("url"), f"sourceLinks[{index}].url")
        require_date(source.get("checkedAt"), f"sourceLinks[{index}].checkedAt")
        require_text(
            source.get("attributionText"),
            f"sourceLinks[{index}].attributionText",
            512,
        )

    points_of_interest = payload.get("pointsOfInterest", [])
    if not isinstance(points_of_interest, list) or len(points_of_interest) > MAX_POINTS_OF_INTEREST:
        raise ValueError(f"pointsOfInterest must contain at most {MAX_POINTS_OF_INTEREST} records")
    point_ids: set[str] = set()
    for index, point in enumerate(points_of_interest):
        if not isinstance(point, dict):
            raise ValueError(f"pointsOfInterest[{index}] must be an object")
        point_id = require_text(point.get("id"), f"pointsOfInterest[{index}].id", 128)
        if point_id in point_ids:
            raise ValueError(f"duplicate point of interest id: {point_id}")
        point_ids.add(point_id)
        region_id = require_text(point.get("regionID"), f"pointsOfInterest[{index}].regionID", 128)
        if region_id not in region_ids:
            raise ValueError(f"pointsOfInterest[{index}].regionID references an unknown region")
        if point.get("type") not in POINT_OF_INTEREST_TYPES:
            raise ValueError(f"pointsOfInterest[{index}].type is unsupported")
        require_text(point.get("name"), f"pointsOfInterest[{index}].name", 128)
        require_text(point.get("summary"), f"pointsOfInterest[{index}].summary", 512)
        require_https_url(point.get("officialURL"), f"pointsOfInterest[{index}].officialURL")
        require_date(point.get("checkedAt"), f"pointsOfInterest[{index}].checkedAt")
        source_id = require_text(point.get("sourceID"), f"pointsOfInterest[{index}].sourceID", 128)
        if source_id not in source_ids:
            raise ValueError(f"pointsOfInterest[{index}].sourceID references an unknown source")
        latitude = point.get("latitude")
        longitude = point.get("longitude")
        if (latitude is None) != (longitude is None):
            raise ValueError(f"pointsOfInterest[{index}] must provide both latitude and longitude")
        if latitude is not None:
            require_number(latitude, f"pointsOfInterest[{index}].latitude", -90, 90)
            require_number(longitude, f"pointsOfInterest[{index}].longitude", -180, 180)
        details = point.get("details", [])
        if not isinstance(details, list) or len(details) > 16:
            raise ValueError(f"pointsOfInterest[{index}].details must contain at most 16 records")
        detail_kinds: set[str] = set()
        for detail_index, detail in enumerate(details):
            if not isinstance(detail, dict):
                raise ValueError(f"pointsOfInterest[{index}].details[{detail_index}] must be an object")
            kind = require_text(
                detail.get("kind"),
                f"pointsOfInterest[{index}].details[{detail_index}].kind",
                64,
            )
            if kind not in {
                "operatingPeriod", "reservation", "capacity", "fee",
                "openingHours", "closedDays", "access", "transportOperator",
            }:
                raise ValueError(f"pointsOfInterest[{index}].details[{detail_index}].kind is unsupported")
            if kind in detail_kinds:
                raise ValueError(f"pointsOfInterest[{index}].details contains duplicate kind: {kind}")
            detail_kinds.add(kind)
            require_text(
                detail.get("value"),
                f"pointsOfInterest[{index}].details[{detail_index}].value",
                256,
            )

    links = payload.get("mountainPointOfInterestLinks", [])
    if not isinstance(links, list) or len(links) > 50_000:
        raise ValueError("mountainPointOfInterestLinks must contain at most 50000 records")
    link_pairs: set[tuple[str, str]] = set()
    for index, link in enumerate(links):
        if not isinstance(link, dict):
            raise ValueError(f"mountainPointOfInterestLinks[{index}] must be an object")
        mountain_id = require_text(
            link.get("mountainID"),
            f"mountainPointOfInterestLinks[{index}].mountainID",
            128,
        )
        point_id = require_text(
            link.get("pointOfInterestID"),
            f"mountainPointOfInterestLinks[{index}].pointOfInterestID",
            128,
        )
        if mountain_id not in ids or point_id not in point_ids:
            raise ValueError(f"mountainPointOfInterestLinks[{index}] references an unknown record")
        require_number(
            link.get("displayOrder"),
            f"mountainPointOfInterestLinks[{index}].displayOrder",
            0,
            10_000,
        )
        pair = (mountain_id, point_id)
        if pair in link_pairs:
            raise ValueError(f"duplicate mountain point of interest link: {pair}")
        link_pairs.add(pair)

    trailhead_access_points = payload.get("trailheadAccessPoints", [])
    if not isinstance(trailhead_access_points, list) or len(trailhead_access_points) > 50_000:
        raise ValueError("trailheadAccessPoints must contain at most 50000 records")
    access_pairs: set[tuple[str, str]] = set()
    for index, link in enumerate(trailhead_access_points):
        if not isinstance(link, dict):
            raise ValueError(f"trailheadAccessPoints[{index}] must be an object")
        trailhead_id = require_text(link.get("trailheadID"), f"trailheadAccessPoints[{index}].trailheadID", 128)
        point_id = require_text(link.get("pointOfInterestID"), f"trailheadAccessPoints[{index}].pointOfInterestID", 128)
        if trailhead_id not in point_ids or point_id not in point_ids:
            raise ValueError(f"trailheadAccessPoints[{index}] references an unknown point of interest")
        if next(point["type"] for point in points_of_interest if point["id"] == trailhead_id) != "trailhead":
            raise ValueError(f"trailheadAccessPoints[{index}].trailheadID must reference a trailhead")
        require_number(link.get("displayOrder"), f"trailheadAccessPoints[{index}].displayOrder", 0, 10_000)
        pair = (trailhead_id, point_id)
        if pair in access_pairs:
            raise ValueError(f"duplicate trailhead access point link: {pair}")
        access_pairs.add(pair)

    search_areas = payload.get("trailheadSearchAreas", [])
    if not isinstance(search_areas, list) or len(search_areas) > 10_000:
        raise ValueError("trailheadSearchAreas must contain at most 10000 records")
    search_area_ids: set[str] = set()
    for index, area in enumerate(search_areas):
        if not isinstance(area, dict):
            raise ValueError(f"trailheadSearchAreas[{index}] must be an object")
        area_id = require_text(area.get("id"), f"trailheadSearchAreas[{index}].id", 128)
        if area_id in search_area_ids:
            raise ValueError(f"duplicate trailhead search area id: {area_id}")
        search_area_ids.add(area_id)
        trailhead_id = require_text(area.get("trailheadID"), f"trailheadSearchAreas[{index}].trailheadID", 128)
        if trailhead_id not in point_ids:
            raise ValueError(f"trailheadSearchAreas[{index}].trailheadID references an unknown point of interest")
        if next(point["type"] for point in points_of_interest if point["id"] == trailhead_id) != "trailhead":
            raise ValueError(f"trailheadSearchAreas[{index}].trailheadID must reference a trailhead")
        require_text(area.get("name"), f"trailheadSearchAreas[{index}].name", 128)
        require_number(area.get("displayOrder"), f"trailheadSearchAreas[{index}].displayOrder", 0, 10_000)
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
                    longitude, elevation_m, yamap_url, updated_at
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    mountain.get("yamapURL"),
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
        connection.executemany(
            """
            INSERT INTO source_links(
                id, provider, title, url, checked_at, is_primary, attribution_text
            ) VALUES(?, ?, ?, ?, ?, 1, ?)
            """,
            [
                (
                    source_link["id"],
                    source_link["provider"],
                    source_link["title"],
                    source_link["url"],
                    source_link["checkedAt"],
                    source_link["attributionText"],
                )
                for source_link in source.get("sourceLinks", [])
            ],
        )
        for point in source.get("pointsOfInterest", []):
            connection.execute(
                """
                INSERT INTO points_of_interest(
                    id, region_id, type, name, latitude, longitude, summary,
                    official_url, checked_at
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    point["id"],
                    point["regionID"],
                    point["type"],
                    point["name"],
                    point.get("latitude"),
                    point.get("longitude"),
                    point["summary"],
                    point["officialURL"],
                    point["checkedAt"],
                ),
            )
            connection.execute(
                """
                INSERT INTO entity_sources(entity_type, entity_id, source_id)
                VALUES('point_of_interest', ?, ?)
                """,
                (point["id"], point["sourceID"]),
            )
            connection.executemany(
                """
                INSERT INTO point_of_interest_details(
                    point_of_interest_id, kind, value, display_order
                ) VALUES(?, ?, ?, ?)
                """,
                [
                    (point["id"], detail["kind"], detail["value"], display_order)
                    for display_order, detail in enumerate(point.get("details", []))
                ],
            )
        connection.executemany(
            """
            INSERT INTO mountain_points_of_interest(
                mountain_id, point_of_interest_id, display_order
            ) VALUES(?, ?, ?)
            """,
            [
                (link["mountainID"], link["pointOfInterestID"], link["displayOrder"])
                for link in source.get("mountainPointOfInterestLinks", [])
            ],
        )
        connection.executemany(
            """
            INSERT INTO trailhead_access_points(trailhead_id, point_of_interest_id, display_order)
            VALUES(?, ?, ?)
            """,
            [
                (link["trailheadID"], link["pointOfInterestID"], link["displayOrder"])
                for link in source.get("trailheadAccessPoints", [])
            ],
        )
        connection.executemany(
            """
            INSERT INTO trailhead_search_areas(id, trailhead_id, name, display_order)
            VALUES(?, ?, ?, ?)
            """,
            [
                (
                    area["id"],
                    area["trailheadID"],
                    area["name"],
                    area["displayOrder"],
                )
                for area in source.get("trailheadSearchAreas", [])
            ],
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
            "SELECT id, canonical_name, coverage_role, latitude, longitude, elevation_m, yamap_url FROM mountains ORDER BY id"
        ).fetchall()
        expected = sorted(
            (
                mountain["id"],
                mountain["canonicalName"],
                mountain["coverageRole"],
                mountain["latitude"],
                mountain["longitude"],
                mountain["elevationMeters"],
                mountain.get("yamapURL"),
            )
            for mountain in source["mountains"]
        )
        if rows != expected:
            raise ValueError("database mountains do not match source data")
        point_rows = connection.execute(
            "SELECT id, type, name, official_url, checked_at FROM points_of_interest ORDER BY id"
        ).fetchall()
        expected_points = sorted(
            (
                point["id"],
                point["type"],
                point["name"],
                point["officialURL"],
                point["checkedAt"],
            )
            for point in source.get("pointsOfInterest", [])
        )
        if point_rows != expected_points:
            raise ValueError("database points of interest do not match source data")
        detail_rows = connection.execute(
            "SELECT point_of_interest_id, kind, value, display_order "
            "FROM point_of_interest_details ORDER BY point_of_interest_id, display_order"
        ).fetchall()
        expected_details = sorted(
            [
                (
                    point["id"],
                    detail["kind"],
                    detail["value"],
                    display_order,
                )
                for point in source.get("pointsOfInterest", [])
                for display_order, detail in enumerate(point.get("details", []))
            ],
            key=lambda item: (item[0], item[3]),
        )
        if detail_rows != expected_details:
            raise ValueError("database point of interest details do not match source data")
        link_rows = connection.execute(
            "SELECT mountain_id, point_of_interest_id, display_order "
            "FROM mountain_points_of_interest ORDER BY mountain_id, display_order, point_of_interest_id"
        ).fetchall()
        expected_links = sorted(
            (
                link["mountainID"],
                link["pointOfInterestID"],
                link["displayOrder"],
            )
            for link in source.get("mountainPointOfInterestLinks", [])
        )
        if link_rows != expected_links:
            raise ValueError("database mountain point of interest links do not match source data")
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

#!/usr/bin/env python3
"""Build a signed YamaLens detailed offline package from GSI elevation tiles."""

from __future__ import annotations

import argparse
import csv
import ctypes
import functools
import hashlib
import json
import math
import os
import re
import shutil
import sqlite3
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import build_bootstrap


FORMAT_VERSION = 1
SCHEMA_VERSION = 1
TERRAIN_FORMAT_VERSION = 1
TERRAIN_HEADER_BYTES = 16
TERRAIN_ROWS = 256
TERRAIN_COLUMNS = 256
TERRAIN_CELL_COUNT = TERRAIN_ROWS * TERRAIN_COLUMNS
TERRAIN_UNCOMPRESSED_BYTES = TERRAIN_CELL_COUNT * 2
TERRAIN_MISSING_VALUE = -32_768
MAXIMUM_COMPRESSED_TILE_BYTES = 262_144
MAXIMUM_TERRAIN_TILES = 100_000
MAXIMUM_SOURCE_FILE_BYTES = 2 * 1_024 * 1_024
MAXIMUM_JSON_BYTES = 16 * 1_024 * 1_024
COMPRESSION_LZFSE = 0x801
DATASET_PRIORITIES = {
    "DEM5A": 0,
    "DEM5B": 1,
    "DEM5C": 2,
    "DEM10B": 3,
}
DATASET_MAXIMUM_ZOOM = {
    "DEM5A": 15,
    "DEM5B": 15,
    "DEM5C": 15,
    "DEM10B": 14,
}
SAFE_IDENTIFIER = re.compile(r"^[A-Za-z0-9._-]+$")
SEMANTIC_VERSION = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
LOWERCASE_SHA256 = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class TerrainSource:
    dataset: str
    path: Path
    sha256: str


@dataclass(frozen=True)
class TerrainTileInput:
    zoom: int
    x: int
    y: int
    sources: tuple[TerrainSource, ...]

    @property
    def identifier(self) -> str:
        return f"z{self.zoom}-x{self.x}-y{self.y}"


@dataclass(frozen=True)
class EncodedTerrainTile:
    identifier: str
    north: float
    south: float
    east: float
    west: float
    resolution_meters: float
    compressed: bytes
    uncompressed_sha256: str


class LZFSECodec:
    def __init__(self) -> None:
        try:
            library = ctypes.CDLL("/usr/lib/libcompression.dylib")
        except OSError as error:
            raise ValueError("Apple Compression framework is unavailable; run this tool on macOS") from error

        library.compression_encode_scratch_buffer_size.argtypes = [ctypes.c_int]
        library.compression_encode_scratch_buffer_size.restype = ctypes.c_size_t
        library.compression_encode_buffer.argtypes = [
            ctypes.POINTER(ctypes.c_uint8),
            ctypes.c_size_t,
            ctypes.POINTER(ctypes.c_uint8),
            ctypes.c_size_t,
            ctypes.c_void_p,
            ctypes.c_int,
        ]
        library.compression_encode_buffer.restype = ctypes.c_size_t
        library.compression_decode_buffer.argtypes = [
            ctypes.POINTER(ctypes.c_uint8),
            ctypes.c_size_t,
            ctypes.POINTER(ctypes.c_uint8),
            ctypes.c_size_t,
            ctypes.c_void_p,
            ctypes.c_int,
        ]
        library.compression_decode_buffer.restype = ctypes.c_size_t
        self._library = library

    def compress(self, payload: bytes) -> bytes:
        source = (ctypes.c_uint8 * len(payload)).from_buffer_copy(payload)
        destination = (ctypes.c_uint8 * MAXIMUM_COMPRESSED_TILE_BYTES)()
        scratch_size = self._library.compression_encode_scratch_buffer_size(COMPRESSION_LZFSE)
        scratch = ctypes.create_string_buffer(scratch_size) if scratch_size > 0 else None
        encoded_count = self._library.compression_encode_buffer(
            destination,
            len(destination),
            source,
            len(payload),
            scratch,
            COMPRESSION_LZFSE,
        )
        if encoded_count == 0 or encoded_count > MAXIMUM_COMPRESSED_TILE_BYTES:
            raise ValueError("LZFSE compression failed or exceeded the per-tile limit")
        return bytes(destination[:encoded_count])

    def decompress(self, payload: bytes, expected_bytes: int) -> bytes:
        source = (ctypes.c_uint8 * len(payload)).from_buffer_copy(payload)
        destination = (ctypes.c_uint8 * expected_bytes)()
        decoded_count = self._library.compression_decode_buffer(
            destination,
            expected_bytes,
            source,
            len(payload),
            None,
            COMPRESSION_LZFSE,
        )
        if decoded_count != expected_bytes:
            raise ValueError("LZFSE decompression did not produce one complete terrain tile")
        return bytes(destination)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    index_parser = subparsers.add_parser(
        "index",
        help="Inventory already downloaded GSI z/x/y.txt elevation tiles.",
    )
    index_parser.add_argument(
        "--source",
        action="append",
        required=True,
        metavar="DATASET=DIRECTORY",
        help="Repeat for DEM5A, DEM5B, DEM5C, or DEM10B source roots.",
    )
    index_parser.add_argument("--output", required=True, type=Path)

    build_parser = subparsers.add_parser(
        "build",
        help="Build catalog.sqlite, terrain.lzfse, manifest.json, and manifest.sig.",
    )
    build_parser.add_argument("--config", required=True, type=Path)
    build_parser.add_argument("--terrain-index", required=True, type=Path)
    build_parser.add_argument("--output", required=True, type=Path)
    build_parser.add_argument(
        "--private-key",
        required=True,
        type=Path,
        help="External PKCS#8 PEM Ed25519 private key; never store it in this repository.",
    )

    public_key_parser = subparsers.add_parser(
        "public-key",
        help="Export the 32-byte raw Ed25519 public key expected by CryptoKit.",
    )
    public_key_parser.add_argument("--private-key", required=True, type=Path)
    public_key_parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def require_mapping(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{field} must be an object")
    return value


def require_text(value: Any, field: str, maximum_length: int = 256) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > maximum_length:
        raise ValueError(f"{field} must be non-empty text of at most {maximum_length} characters")
    return value


def require_identifier(value: Any, field: str) -> str:
    text = require_text(value, field, 128)
    if not SAFE_IDENTIFIER.fullmatch(text):
        raise ValueError(f"{field} must contain only ASCII letters, digits, period, underscore, or hyphen")
    return text


def require_https_url(value: Any, field: str) -> str:
    text = require_text(value, field, 2_048)
    parsed = urlparse(text)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError(f"{field} must be an HTTPS URL without user information")
    return text


def require_integer(value: Any, field: str, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
        raise ValueError(f"{field} must be an integer in {minimum}...{maximum}")
    return value


def load_json(path: Path) -> Any:
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"JSON input must be a regular file: {path}")
    size = path.stat().st_size
    if size <= 0 or size > MAXIMUM_JSON_BYTES:
        raise ValueError(f"JSON input size is invalid: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_file(path: Path, maximum_bytes: int | None = None) -> str:
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"input must be a regular file: {path}")
    size = path.stat().st_size
    if maximum_bytes is not None and size > maximum_bytes:
        raise ValueError(f"input exceeds the allowed size: {path}")
    digest = hashlib.sha256()
    read_bytes = 0
    with path.open("rb") as stream:
        while chunk := stream.read(1_024 * 1_024):
            read_bytes += len(chunk)
            if maximum_bytes is not None and read_bytes > maximum_bytes:
                raise ValueError(f"input exceeds the allowed size: {path}")
            digest.update(chunk)
    return digest.hexdigest()


def parse_source_argument(raw_value: str) -> tuple[str, Path]:
    dataset, separator, raw_path = raw_value.partition("=")
    if not separator or dataset not in DATASET_PRIORITIES or not raw_path:
        raise ValueError("--source must use DATASET=DIRECTORY with DEM5A, DEM5B, DEM5C, or DEM10B")
    directory = Path(raw_path).expanduser().resolve()
    if not directory.is_dir():
        raise ValueError(f"source directory does not exist: {directory}")
    return dataset, directory


def parse_xyz_path(root: Path, tile_path: Path) -> tuple[int, int, int]:
    relative = tile_path.relative_to(root)
    if len(relative.parts) != 3 or relative.suffix != ".txt":
        raise ValueError(f"tile path must use z/x/y.txt below its source root: {tile_path}")
    try:
        zoom = int(relative.parts[0])
        x = int(relative.parts[1])
        y = int(relative.stem)
    except ValueError as error:
        raise ValueError(f"tile path contains a non-integer z, x, or y: {tile_path}") from error
    validate_tile_coordinate(zoom, x, y)
    return zoom, x, y


def validate_tile_coordinate(zoom: int, x: int, y: int) -> None:
    if not 1 <= zoom <= 15:
        raise ValueError("tile zoom must be in 1...15")
    maximum_coordinate = (1 << zoom) - 1
    if not 0 <= x <= maximum_coordinate or not 0 <= y <= maximum_coordinate:
        raise ValueError("tile x and y must be valid for their zoom level")


def create_terrain_index(source_arguments: list[str], output: Path) -> None:
    output = output.expanduser().resolve()
    if output.exists():
        raise ValueError(f"refusing to replace an existing terrain index: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    tiles: dict[tuple[int, int, int], list[dict[str, str]]] = {}
    seen_dataset_tiles: set[tuple[str, int, int, int]] = set()

    for raw_source in source_arguments:
        dataset, root = parse_source_argument(raw_source)
        for tile_path in sorted(root.glob("*/*/*.txt")):
            if tile_path.is_symlink():
                raise ValueError(f"symbolic links are not accepted as elevation input: {tile_path}")
            zoom, x, y = parse_xyz_path(root, tile_path)
            if zoom > DATASET_MAXIMUM_ZOOM[dataset]:
                raise ValueError(f"{dataset} does not support zoom {zoom}: {tile_path}")
            uniqueness_key = (dataset, zoom, x, y)
            if uniqueness_key in seen_dataset_tiles:
                raise ValueError(f"duplicate {dataset} tile: z{zoom}/{x}/{y}")
            seen_dataset_tiles.add(uniqueness_key)
            relative_path = os.path.relpath(tile_path, output.parent)
            tiles.setdefault((zoom, x, y), []).append(
                {
                    "dataset": dataset,
                    "path": relative_path,
                    "sha256": sha256_file(tile_path, MAXIMUM_SOURCE_FILE_BYTES),
                }
            )

    if not tiles:
        raise ValueError("no z/x/y.txt elevation tiles were found")
    if len(tiles) > MAXIMUM_TERRAIN_TILES:
        raise ValueError(f"terrain index exceeds {MAXIMUM_TERRAIN_TILES} unique tiles")

    payload = {
        "formatVersion": FORMAT_VERSION,
        "tiles": [
            {
                "z": zoom,
                "x": x,
                "y": y,
                "sources": sorted(
                    sources,
                    key=lambda source: DATASET_PRIORITIES[source["dataset"]],
                ),
            }
            for (zoom, x, y), sources in sorted(tiles.items())
        ],
    }
    output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def load_terrain_index(path: Path) -> list[TerrainTileInput]:
    payload = require_mapping(load_json(path), "terrain index")
    if payload.get("formatVersion") != FORMAT_VERSION:
        raise ValueError("unsupported terrain index formatVersion")
    raw_tiles = payload.get("tiles")
    if not isinstance(raw_tiles, list) or not 1 <= len(raw_tiles) <= MAXIMUM_TERRAIN_TILES:
        raise ValueError(f"terrain index must contain 1...{MAXIMUM_TERRAIN_TILES} tiles")

    tiles: list[TerrainTileInput] = []
    seen_coordinates: set[tuple[int, int, int]] = set()
    for tile_index, raw_tile_value in enumerate(raw_tiles):
        raw_tile = require_mapping(raw_tile_value, f"tiles[{tile_index}]")
        zoom = require_integer(raw_tile.get("z"), f"tiles[{tile_index}].z", 1, 15)
        maximum_coordinate = (1 << zoom) - 1
        x = require_integer(raw_tile.get("x"), f"tiles[{tile_index}].x", 0, maximum_coordinate)
        y = require_integer(raw_tile.get("y"), f"tiles[{tile_index}].y", 0, maximum_coordinate)
        coordinate = (zoom, x, y)
        if coordinate in seen_coordinates:
            raise ValueError(f"duplicate terrain tile coordinate: z{zoom}/{x}/{y}")
        seen_coordinates.add(coordinate)

        raw_sources = raw_tile.get("sources")
        if not isinstance(raw_sources, list) or not 1 <= len(raw_sources) <= len(DATASET_PRIORITIES):
            raise ValueError(f"tiles[{tile_index}].sources must contain 1...4 entries")
        sources: list[TerrainSource] = []
        seen_datasets: set[str] = set()
        for source_index, raw_source_value in enumerate(raw_sources):
            raw_source = require_mapping(
                raw_source_value,
                f"tiles[{tile_index}].sources[{source_index}]",
            )
            dataset = require_text(
                raw_source.get("dataset"),
                f"tiles[{tile_index}].sources[{source_index}].dataset",
                16,
            )
            if dataset not in DATASET_PRIORITIES or zoom > DATASET_MAXIMUM_ZOOM[dataset]:
                raise ValueError(f"unsupported dataset or zoom for tile {tile_index}: {dataset}")
            if dataset in seen_datasets:
                raise ValueError(f"duplicate dataset for tile {tile_index}: {dataset}")
            seen_datasets.add(dataset)
            raw_path = require_text(
                raw_source.get("path"),
                f"tiles[{tile_index}].sources[{source_index}].path",
                2_048,
            )
            source_path = (path.parent / raw_path).resolve()
            expected_hash = require_text(
                raw_source.get("sha256"),
                f"tiles[{tile_index}].sources[{source_index}].sha256",
                64,
            )
            if not LOWERCASE_SHA256.fullmatch(expected_hash):
                raise ValueError(f"source hash must be lowercase SHA-256 for tile {tile_index}")
            if sha256_file(source_path, MAXIMUM_SOURCE_FILE_BYTES) != expected_hash:
                raise ValueError(f"source hash mismatch: {source_path}")
            sources.append(TerrainSource(dataset, source_path, expected_hash))

        tiles.append(
            TerrainTileInput(
                zoom=zoom,
                x=x,
                y=y,
                sources=tuple(sorted(sources, key=lambda source: DATASET_PRIORITIES[source.dataset])),
            )
        )
    return sorted(tiles, key=lambda tile: (tile.zoom, tile.x, tile.y))


def load_elevation_cells(source: TerrainSource) -> list[int | None]:
    cells: list[int | None] = []
    with source.path.open("r", encoding="utf-8", newline="") as stream:
        rows = list(csv.reader(stream))
    if len(rows) != TERRAIN_ROWS:
        raise ValueError(f"elevation tile must contain {TERRAIN_ROWS} rows: {source.path}")
    for row_index, row in enumerate(rows):
        if len(row) != TERRAIN_COLUMNS:
            raise ValueError(
                f"elevation tile row {row_index} must contain {TERRAIN_COLUMNS} cells: {source.path}"
            )
        for raw_cell in row:
            token = raw_cell.strip()
            if token.lower() == "e":
                cells.append(None)
                continue
            try:
                elevation = Decimal(token)
            except InvalidOperation as error:
                raise ValueError(f"invalid elevation cell in {source.path}: {token}") from error
            if not elevation.is_finite():
                raise ValueError(f"non-finite elevation cell in {source.path}")
            rounded = int(elevation.quantize(Decimal("1"), rounding=ROUND_HALF_UP))
            if not -32_767 <= rounded <= 32_767:
                raise ValueError(f"elevation is outside Int16 data range in {source.path}")
            cells.append(rounded)
    return cells


@functools.lru_cache(maxsize=32)
def merge_source_cells(tile: TerrainTileInput) -> tuple[int | None, ...]:
    merged: list[int | None] = [None] * TERRAIN_CELL_COUNT
    for source in tile.sources:
        cells = load_elevation_cells(source)
        for index, elevation in enumerate(cells):
            if merged[index] is None and elevation is not None:
                merged[index] = elevation
    if all(elevation is None for elevation in merged):
        raise ValueError(f"terrain tile has no usable elevation cells: {tile.identifier}")
    return tuple(merged)


def merge_elevation_cells(
    tile: TerrainTileInput,
    dem10b_parent: TerrainTileInput | None,
) -> list[int]:
    merged = list(merge_source_cells(tile))
    if tile.zoom == 15 and dem10b_parent is not None:
        parent_cells = merge_source_cells(dem10b_parent)
        parent_row_origin = (tile.y % 2) * (TERRAIN_ROWS // 2)
        parent_column_origin = (tile.x % 2) * (TERRAIN_COLUMNS // 2)
        for row in range(TERRAIN_ROWS):
            parent_row = parent_row_origin + row // 2
            for column in range(TERRAIN_COLUMNS):
                index = row * TERRAIN_COLUMNS + column
                if merged[index] is not None:
                    continue
                parent_column = parent_column_origin + column // 2
                parent_index = parent_row * TERRAIN_COLUMNS + parent_column
                merged[index] = parent_cells[parent_index]
    return [elevation if elevation is not None else TERRAIN_MISSING_VALUE for elevation in merged]


def tile_bounds(zoom: int, x: int, y: int) -> tuple[float, float, float, float]:
    tile_count = float(1 << zoom)
    west = x / tile_count * 360.0 - 180.0
    east = (x + 1) / tile_count * 360.0 - 180.0

    def latitude(tile_y: int) -> float:
        mercator_y = math.pi * (1.0 - 2.0 * tile_y / tile_count)
        return math.degrees(math.atan(math.sinh(mercator_y)))

    north = latitude(y)
    south = latitude(y + 1)
    return north, south, east, west


def tile_resolution_meters(zoom: int, north: float, south: float) -> float:
    center_latitude = math.radians((north + south) / 2.0)
    return 156_543.033_928_040_97 * math.cos(center_latitude) / float(1 << zoom)


def encode_terrain_tiles(
    inputs: list[TerrainTileInput],
    codec: LZFSECodec,
) -> list[EncodedTerrainTile]:
    encoded_tiles: list[EncodedTerrainTile] = []
    inputs_by_coordinate = {
        (tile.zoom, tile.x, tile.y): tile
        for tile in inputs
    }
    for tile in inputs:
        dem10b_parent: TerrainTileInput | None = None
        if tile.zoom == 15:
            parent = inputs_by_coordinate.get((14, tile.x // 2, tile.y // 2))
            if parent is not None and any(source.dataset == "DEM10B" for source in parent.sources):
                dem10b_parent = parent
        elevations = merge_elevation_cells(tile, dem10b_parent)
        payload = struct.pack(f"<{TERRAIN_CELL_COUNT}h", *elevations)
        if len(payload) != TERRAIN_UNCOMPRESSED_BYTES:
            raise ValueError("terrain encoding produced an unexpected byte count")
        compressed = codec.compress(payload)
        if codec.decompress(compressed, len(payload)) != payload:
            raise ValueError(f"LZFSE round-trip failed: {tile.identifier}")
        north, south, east, west = tile_bounds(tile.zoom, tile.x, tile.y)
        encoded_tiles.append(
            EncodedTerrainTile(
                identifier=tile.identifier,
                north=north,
                south=south,
                east=east,
                west=west,
                resolution_meters=tile_resolution_meters(tile.zoom, north, south),
                compressed=compressed,
                uncompressed_sha256=hashlib.sha256(payload).hexdigest(),
            )
        )
    return encoded_tiles


def validate_bounds(raw_value: Any, field: str) -> dict[str, float]:
    raw_bounds = require_mapping(raw_value, field)
    bounds: dict[str, float] = {}
    for key, minimum, maximum in (
        ("north", -90.0, 90.0),
        ("south", -90.0, 90.0),
        ("east", -180.0, 180.0),
        ("west", -180.0, 180.0),
    ):
        value = raw_bounds.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError(f"{field}.{key} must be a number")
        number = float(value)
        if not math.isfinite(number) or not minimum <= number <= maximum:
            raise ValueError(f"{field}.{key} is outside the allowed range")
        bounds[key] = number
    if bounds["north"] <= bounds["south"] or bounds["east"] <= bounds["west"]:
        raise ValueError(f"{field} must have ordered north/south and east/west values")
    return bounds


def load_config(path: Path) -> dict[str, Any]:
    config = require_mapping(load_json(path), "config")
    if config.get("formatVersion") != FORMAT_VERSION or config.get("schemaVersion") != SCHEMA_VERSION:
        raise ValueError("unsupported package config formatVersion or schemaVersion")
    require_identifier(config.get("packageID"), "packageID")
    content_version = require_text(config.get("contentVersion"), "contentVersion", 32)
    minimum_app_version = require_text(config.get("minimumAppVersion"), "minimumAppVersion", 32)
    if not SEMANTIC_VERSION.fullmatch(content_version) or not SEMANTIC_VERSION.fullmatch(minimum_app_version):
        raise ValueError("contentVersion and minimumAppVersion must be semantic versions")
    require_identifier(config.get("keyID"), "keyID")
    created_at = require_text(config.get("createdAt"), "createdAt", 32)
    try:
        parsed_date = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError("createdAt must be an RFC 3339 timestamp") from error
    if parsed_date.utcoffset() is None or not created_at.endswith("Z"):
        raise ValueError("createdAt must be expressed in UTC with a trailing Z")
    validate_bounds(config.get("allowedBounds"), "allowedBounds")

    source_manifest_ids = config.get("sourceManifestIDs")
    if not isinstance(source_manifest_ids, list) or not 1 <= len(source_manifest_ids) <= 128:
        raise ValueError("sourceManifestIDs must contain 1...128 identifiers")
    if len(set(source_manifest_ids)) != len(source_manifest_ids):
        raise ValueError("sourceManifestIDs must not contain duplicates")
    for index, source_id in enumerate(source_manifest_ids):
        require_identifier(source_id, f"sourceManifestIDs[{index}]")

    source_manifest_directory = require_text(
        config.get("sourceManifestDirectory"),
        "sourceManifestDirectory",
        2_048,
    )
    resolved_source_manifest_directory = (path.parent / source_manifest_directory).resolve()
    if not resolved_source_manifest_directory.is_dir():
        raise ValueError("sourceManifestDirectory does not exist")
    for source_id in source_manifest_ids:
        manifest_path = resolved_source_manifest_directory / f"{source_id}.yaml"
        if not manifest_path.is_file() or manifest_path.is_symlink():
            raise ValueError(f"source manifest does not exist: {manifest_path}")

    catalog_input = require_text(config.get("catalogInput"), "catalogInput", 2_048)
    resolved_catalog_input = (path.parent / catalog_input).resolve()
    if not resolved_catalog_input.is_file():
        raise ValueError(f"catalogInput does not exist: {resolved_catalog_input}")
    config["resolvedCatalogInput"] = resolved_catalog_input

    source_links = config.get("sourceLinks")
    if not isinstance(source_links, list) or not 1 <= len(source_links) <= 128:
        raise ValueError("sourceLinks must contain 1...128 records")
    source_link_ids: set[str] = set()
    for index, raw_link_value in enumerate(source_links):
        link = require_mapping(raw_link_value, f"sourceLinks[{index}]")
        link_id = require_identifier(link.get("id"), f"sourceLinks[{index}].id")
        if link_id in source_link_ids:
            raise ValueError(f"duplicate source link id: {link_id}")
        source_link_ids.add(link_id)
        for key in ("provider", "title", "checkedAt", "attributionText"):
            require_text(link.get(key), f"sourceLinks[{index}].{key}", 2_048)
        require_https_url(link.get("url"), f"sourceLinks[{index}].url")
        license_url = link.get("licenseURL")
        if license_url is not None:
            require_https_url(license_url, f"sourceLinks[{index}].licenseURL")
        if not isinstance(link.get("isPrimary"), bool):
            raise ValueError(f"sourceLinks[{index}].isPrimary must be a boolean")
        processing_note = link.get("processingNote")
        if processing_note is not None:
            require_text(processing_note, f"sourceLinks[{index}].processingNote", 4_096)

    terrain_source_link_id = require_identifier(
        config.get("terrainSourceLinkID"),
        "terrainSourceLinkID",
    )
    if terrain_source_link_id not in source_link_ids:
        raise ValueError("terrainSourceLinkID must reference sourceLinks")
    return config


def validate_tiles_within_allowed_bounds(
    tiles: list[EncodedTerrainTile],
    allowed_bounds: dict[str, float],
) -> None:
    epsilon = 1e-9
    for tile in tiles:
        if (
            tile.north > allowed_bounds["north"] + epsilon
            or tile.south < allowed_bounds["south"] - epsilon
            or tile.east > allowed_bounds["east"] + epsilon
            or tile.west < allowed_bounds["west"] - epsilon
        ):
            raise ValueError(f"terrain tile is outside allowedBounds: {tile.identifier}")


def create_catalog(
    config: dict[str, Any],
    encoded_tiles: list[EncodedTerrainTile],
    output: Path,
) -> None:
    catalog_source = build_bootstrap.load_source(config["resolvedCatalogInput"])
    build_bootstrap.create_database(catalog_source, output)
    connection = sqlite3.connect(output)
    try:
        connection.execute("PRAGMA foreign_keys = ON")
        metadata = {
            "schema_version": str(SCHEMA_VERSION),
            "content_version": config["contentVersion"],
            "package_id": config["packageID"],
            "source_manifest_ids": ",".join(config["sourceManifestIDs"]),
        }
        connection.executemany(
            "INSERT OR REPLACE INTO package_metadata(key, value) VALUES(?, ?)",
            sorted(metadata.items()),
        )
        for source_link in config["sourceLinks"]:
            connection.execute(
                """
                INSERT INTO source_links(
                    id, provider, title, url, license_url, checked_at,
                    is_primary, attribution_text, processing_note
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    source_link["id"],
                    source_link["provider"],
                    source_link["title"],
                    source_link["url"],
                    source_link.get("licenseURL"),
                    source_link["checkedAt"],
                    int(source_link["isPrimary"]),
                    source_link["attributionText"],
                    source_link.get("processingNote"),
                ),
            )

        offset = TERRAIN_HEADER_BYTES
        for tile in encoded_tiles:
            connection.execute(
                """
                INSERT INTO terrain_tiles(
                    id, north, south, east, west, resolution_m, row_count,
                    column_count, offset_bytes, compressed_bytes,
                    uncompressed_bytes, sha256
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    tile.identifier,
                    tile.north,
                    tile.south,
                    tile.east,
                    tile.west,
                    tile.resolution_meters,
                    TERRAIN_ROWS,
                    TERRAIN_COLUMNS,
                    offset,
                    len(tile.compressed),
                    TERRAIN_UNCOMPRESSED_BYTES,
                    tile.uncompressed_sha256,
                ),
            )
            connection.execute(
                "INSERT INTO entity_sources(entity_type, entity_id, source_id) VALUES('terrain_tile', ?, ?)",
                (tile.identifier, config["terrainSourceLinkID"]),
            )
            offset += len(tile.compressed)
        connection.commit()
        connection.execute("VACUUM")
    finally:
        connection.close()


def create_terrain_file(encoded_tiles: list[EncodedTerrainTile], output: Path) -> None:
    header = struct.pack(
        "<4sHHII",
        b"YLTF",
        TERRAIN_FORMAT_VERSION,
        TERRAIN_HEADER_BYTES,
        len(encoded_tiles),
        0,
    )
    with output.open("wb") as stream:
        stream.write(header)
        for tile in encoded_tiles:
            stream.write(tile.compressed)


def create_manifest(config: dict[str, Any], package_directory: Path) -> bytes:
    files = []
    for filename in ("catalog.sqlite", "terrain.lzfse"):
        file_path = package_directory / filename
        files.append(
            {
                "path": filename,
                "byteCount": file_path.stat().st_size,
                "sha256": sha256_file(file_path),
            }
        )
    connection = sqlite3.connect(package_directory / "catalog.sqlite")
    try:
        terrain_rows = connection.execute(
            "SELECT north, south, east, west FROM terrain_tiles"
        ).fetchall()
    finally:
        connection.close()
    if not terrain_rows:
        raise ValueError("catalog contains no terrain tiles")
    bounds = {
        "north": max(row[0] for row in terrain_rows),
        "south": min(row[1] for row in terrain_rows),
        "east": max(row[2] for row in terrain_rows),
        "west": min(row[3] for row in terrain_rows),
    }
    manifest = {
        "formatVersion": FORMAT_VERSION,
        "packageID": config["packageID"],
        "contentVersion": config["contentVersion"],
        "schemaVersion": SCHEMA_VERSION,
        "signatureAlgorithm": "Ed25519",
        "keyID": config["keyID"],
        "createdAt": config["createdAt"],
        "minimumAppVersion": config["minimumAppVersion"],
        "bounds": bounds,
        "sourceManifestIDs": config["sourceManifestIDs"],
        "files": files,
    }
    return (
        json.dumps(manifest, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n"
    ).encode("utf-8")


def run_openssl(arguments: list[str]) -> None:
    openssl = shutil.which("openssl")
    if openssl is None:
        raise ValueError("OpenSSL with Ed25519 support is required for package signing")
    try:
        subprocess.run(
            [openssl, *arguments],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as error:
        raise ValueError("OpenSSL could not sign or verify the package manifest") from error


def export_raw_public_key(private_key: Path, output: Path) -> None:
    if not private_key.is_file() or private_key.is_symlink():
        raise ValueError("private key must be a regular external file")
    if output.exists():
        raise ValueError(f"refusing to replace an existing public key: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="yamalens-public-key-", dir=output.parent) as raw_staging:
        der_path = Path(raw_staging) / "public.der"
        run_openssl(
            [
                "pkey",
                "-in",
                str(private_key),
                "-pubout",
                "-outform",
                "DER",
                "-out",
                str(der_path),
            ]
        )
        encoded_key = der_path.read_bytes()
        subject_public_key_prefix = bytes.fromhex("302a300506032b6570032100")
        if len(encoded_key) != 44 or not encoded_key.startswith(subject_public_key_prefix):
            raise ValueError("OpenSSL output is not an Ed25519 public key")
        output.write_bytes(encoded_key[len(subject_public_key_prefix) :])


def sign_manifest(private_key: Path, package_directory: Path) -> None:
    if not private_key.is_file() or private_key.is_symlink():
        raise ValueError("private key must be a regular external file")
    manifest_path = package_directory / "manifest.json"
    signature_path = package_directory / "manifest.sig"
    public_key_path = package_directory / ".verification-public-key.pem"
    run_openssl(["pkey", "-in", str(private_key), "-pubout", "-out", str(public_key_path)])
    try:
        run_openssl(
            [
                "pkeyutl",
                "-sign",
                "-rawin",
                "-inkey",
                str(private_key),
                "-in",
                str(manifest_path),
                "-out",
                str(signature_path),
            ]
        )
        if signature_path.stat().st_size != 64:
            raise ValueError("Ed25519 signature must be exactly 64 bytes")
        run_openssl(
            [
                "pkeyutl",
                "-verify",
                "-pubin",
                "-inkey",
                str(public_key_path),
                "-rawin",
                "-in",
                str(manifest_path),
                "-sigfile",
                str(signature_path),
            ]
        )
    finally:
        public_key_path.unlink(missing_ok=True)


def verify_catalog_and_terrain(package_directory: Path, codec: LZFSECodec) -> None:
    catalog_path = package_directory / "catalog.sqlite"
    terrain_path = package_directory / "terrain.lzfse"
    connection = sqlite3.connect(f"file:{catalog_path}?mode=ro", uri=True)
    try:
        if connection.execute("PRAGMA integrity_check").fetchone() != ("ok",):
            raise ValueError("generated catalog failed SQLite integrity_check")
        if connection.execute("PRAGMA foreign_key_check").fetchall():
            raise ValueError("generated catalog failed SQLite foreign_key_check")
        rows = connection.execute(
            """
            SELECT id, offset_bytes, compressed_bytes, uncompressed_bytes, sha256
            FROM terrain_tiles ORDER BY offset_bytes
            """
        ).fetchall()
    finally:
        connection.close()
    with terrain_path.open("rb") as stream:
        header = stream.read(TERRAIN_HEADER_BYTES)
        expected_header = struct.pack(
            "<4sHHII",
            b"YLTF",
            TERRAIN_FORMAT_VERSION,
            TERRAIN_HEADER_BYTES,
            len(rows),
            0,
        )
        if header != expected_header:
            raise ValueError("generated terrain header is invalid")
        previous_end = TERRAIN_HEADER_BYTES
        for tile_id, offset, compressed_bytes, uncompressed_bytes, expected_hash in rows:
            if offset != previous_end or uncompressed_bytes != TERRAIN_UNCOMPRESSED_BYTES:
                raise ValueError(f"generated terrain offset or size is invalid: {tile_id}")
            stream.seek(offset)
            compressed = stream.read(compressed_bytes)
            if len(compressed) != compressed_bytes:
                raise ValueError(f"generated terrain tile is truncated: {tile_id}")
            payload = codec.decompress(compressed, uncompressed_bytes)
            if hashlib.sha256(payload).hexdigest() != expected_hash:
                raise ValueError(f"generated terrain tile hash mismatch: {tile_id}")
            previous_end = offset + compressed_bytes
        if previous_end != terrain_path.stat().st_size:
            raise ValueError("generated terrain file contains unindexed trailing bytes")


def build_package(config_path: Path, terrain_index_path: Path, output: Path, private_key: Path) -> None:
    if output.exists():
        raise ValueError(f"refusing to replace an existing package directory: {output}")
    config = load_config(config_path)
    tile_inputs = load_terrain_index(terrain_index_path)
    codec = LZFSECodec()
    encoded_tiles = encode_terrain_tiles(tile_inputs, codec)
    allowed_bounds = validate_bounds(config["allowedBounds"], "allowedBounds")
    validate_tiles_within_allowed_bounds(encoded_tiles, allowed_bounds)

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="yamalens-pack-", dir=output.parent) as raw_staging:
        staging = Path(raw_staging)
        create_catalog(config, encoded_tiles, staging / "catalog.sqlite")
        create_terrain_file(encoded_tiles, staging / "terrain.lzfse")
        verify_catalog_and_terrain(staging, codec)
        manifest_data = create_manifest(config, staging)
        (staging / "manifest.json").write_bytes(manifest_data)
        sign_manifest(private_key, staging)
        staging.rename(output)


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.command == "index":
            create_terrain_index(arguments.source, arguments.output)
            print(f"terrain index created: {arguments.output}")
        elif arguments.command == "build":
            build_package(
                arguments.config,
                arguments.terrain_index,
                arguments.output,
                arguments.private_key,
            )
            print(f"signed detailed package created: {arguments.output}")
        elif arguments.command == "public-key":
            export_raw_public_key(arguments.private_key, arguments.output)
            print(f"raw Ed25519 public key created: {arguments.output}")
        else:
            raise ValueError(f"unsupported command: {arguments.command}")
    except (OSError, ValueError, json.JSONDecodeError, sqlite3.Error) as error:
        print(f"detailed package build failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

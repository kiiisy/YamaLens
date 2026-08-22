#!/usr/bin/env python3
"""Plan and explicitly fetch official GSI elevation tiles for YamaLens development."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


FORMAT_VERSION = 1
GSI_HOST = "cyberjapandata.gsi.go.jp"
ALLOWED_DATASETS = {"DEM5A", "DEM5B", "DEM5C", "DEM10B"}
ALLOWED_TILE_SETS = {
    "DEM5A": "dem5a_png",
    "DEM5B": "dem5b_png",
    "DEM5C": "dem5c_png",
    "DEM10B": "dem_png",
}
MAXIMUM_PLAN_TILES = 10_000
MAXIMUM_SOURCE_BYTES = 2 * 1_024 * 1_024


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    plan_parser = subparsers.add_parser("plan", help="Create a deterministic URL and path list.")
    plan_parser.add_argument("--config", required=True, type=Path)
    plan_parser.add_argument("--output", required=True, type=Path)

    fetch_parser = subparsers.add_parser(
        "fetch",
        help="Fetch one previously reviewed plan without credentials or parallel requests.",
    )
    fetch_parser.add_argument("--plan", required=True, type=Path)
    fetch_parser.add_argument("--destination", required=True, type=Path)
    fetch_parser.add_argument("--interval", type=float, default=0.2)
    return parser.parse_args()


def load_json(path: Path) -> Any:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 16 * 1_024 * 1_024:
        raise ValueError(f"JSON input is not a safe regular file: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def require_mapping(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{field} must be an object")
    return value


def require_text(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value or len(value) > 256:
        raise ValueError(f"{field} must be non-empty text")
    return value


def require_number(value: Any, field: str, minimum: float, maximum: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{field} must be a number")
    number = float(value)
    if not math.isfinite(number) or not minimum <= number <= maximum:
        raise ValueError(f"{field} must be in {minimum}...{maximum}")
    return number


def longitude_to_tile_x(longitude: float, zoom: int) -> int:
    return math.floor((longitude + 180.0) / 360.0 * (1 << zoom))


def latitude_to_tile_y(latitude: float, zoom: int) -> int:
    radians = math.radians(latitude)
    return math.floor(
        (1.0 - math.asinh(math.tan(radians)) / math.pi) / 2.0 * (1 << zoom)
    )


def create_plan(config_path: Path, output_path: Path) -> dict[str, Any]:
    config = require_mapping(load_json(config_path), "config")
    if config.get("formatVersion") != FORMAT_VERSION:
        raise ValueError("unsupported acquisition config formatVersion")
    layers = config.get("layers")
    if not isinstance(layers, list) or not layers:
        raise ValueError("layers must be a non-empty array")

    entries: list[dict[str, Any]] = []
    seen_paths: set[str] = set()
    summaries: list[dict[str, Any]] = []
    for layer_index, raw_layer in enumerate(layers):
        layer = require_mapping(raw_layer, f"layers[{layer_index}]")
        layer_id = require_text(layer.get("id"), f"layers[{layer_index}].id")
        dataset = require_text(layer.get("dataset"), f"layers[{layer_index}].dataset")
        tile_set = require_text(layer.get("tileSet"), f"layers[{layer_index}].tileSet")
        extension = require_text(layer.get("extension"), f"layers[{layer_index}].extension")
        zoom = layer.get("zoom")
        if dataset not in ALLOWED_DATASETS or ALLOWED_TILE_SETS.get(dataset) != tile_set:
            raise ValueError(f"unsupported dataset or tile set in layer {layer_id}")
        if extension != "png" or isinstance(zoom, bool) or not isinstance(zoom, int):
            raise ValueError(f"layer {layer_id} must use PNG and an integer zoom")
        maximum_zoom = 14 if dataset == "DEM10B" else 15
        if not 1 <= zoom <= maximum_zoom:
            raise ValueError(f"zoom is unsupported for {dataset} in layer {layer_id}")
        bounds = require_mapping(layer.get("bounds"), f"layers[{layer_index}].bounds")
        north = require_number(bounds.get("north"), "north", -85.0, 85.0)
        south = require_number(bounds.get("south"), "south", -85.0, 85.0)
        east = require_number(bounds.get("east"), "east", -180.0, 180.0)
        west = require_number(bounds.get("west"), "west", -180.0, 180.0)
        if south >= north or west >= east:
            raise ValueError(f"bounds are invalid in layer {layer_id}")

        minimum_x = longitude_to_tile_x(west, zoom)
        maximum_x = longitude_to_tile_x(math.nextafter(east, west), zoom)
        minimum_y = latitude_to_tile_y(math.nextafter(north, south), zoom)
        maximum_y = latitude_to_tile_y(south, zoom)
        layer_count = 0
        for x in range(minimum_x, maximum_x + 1):
            for y in range(minimum_y, maximum_y + 1):
                relative_path = f"{dataset}/{zoom}/{x}/{y}.{extension}"
                if relative_path in seen_paths:
                    continue
                seen_paths.add(relative_path)
                entries.append(
                    {
                        "dataset": dataset,
                        "z": zoom,
                        "x": x,
                        "y": y,
                        "url": f"https://{GSI_HOST}/xyz/{tile_set}/{zoom}/{x}/{y}.{extension}",
                        "relativePath": relative_path,
                    }
                )
                layer_count += 1
        summaries.append({"id": layer_id, "dataset": dataset, "zoom": zoom, "tileCount": layer_count})

    if not entries or len(entries) > MAXIMUM_PLAN_TILES:
        raise ValueError(f"acquisition plan must contain 1...{MAXIMUM_PLAN_TILES} unique tiles")
    plan = {
        "formatVersion": FORMAT_VERSION,
        "provider": require_text(config.get("provider"), "provider"),
        "sourceInformationURL": require_text(
            config.get("sourceInformationURL"), "sourceInformationURL"
        ),
        "layers": summaries,
        "tileCount": len(entries),
        "tiles": entries,
    }
    if output_path.exists():
        raise ValueError(f"refusing to replace an existing acquisition plan: {output_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(plan, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return plan


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def validated_plan_entries(plan_path: Path) -> list[dict[str, Any]]:
    plan = require_mapping(load_json(plan_path), "plan")
    if plan.get("formatVersion") != FORMAT_VERSION:
        raise ValueError("unsupported acquisition plan formatVersion")
    raw_tiles = plan.get("tiles")
    if not isinstance(raw_tiles, list) or not 1 <= len(raw_tiles) <= MAXIMUM_PLAN_TILES:
        raise ValueError("acquisition plan has an invalid tile count")
    entries: list[dict[str, Any]] = []
    seen_paths: set[str] = set()
    for index, raw_entry in enumerate(raw_tiles):
        entry = require_mapping(raw_entry, f"tiles[{index}]")
        dataset = require_text(entry.get("dataset"), f"tiles[{index}].dataset")
        url = require_text(entry.get("url"), f"tiles[{index}].url")
        relative_path = require_text(entry.get("relativePath"), f"tiles[{index}].relativePath")
        parsed = urlparse(url)
        parts = Path(relative_path).parts
        if (
            dataset not in ALLOWED_DATASETS
            or parsed.scheme != "https"
            or parsed.hostname != GSI_HOST
            or parsed.username
            or parsed.password
            or len(parts) != 4
            or parts[0] != dataset
            or Path(relative_path).is_absolute()
            or ".." in parts
            or not relative_path.endswith(".png")
            or relative_path in seen_paths
        ):
            raise ValueError(f"unsafe acquisition entry at index {index}")
        seen_paths.add(relative_path)
        entries.append({"dataset": dataset, "url": url, "relativePath": relative_path})
    return entries


def fetch_plan(plan_path: Path, destination: Path, interval: float) -> dict[str, Any]:
    if not math.isfinite(interval) or interval < 0.1:
        raise ValueError("interval must be at least 0.1 seconds")
    destination = destination.expanduser().resolve()
    destination.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        raise ValueError("destination must not be a symbolic link")
    entries = validated_plan_entries(plan_path)
    acquired: list[dict[str, Any]] = []
    unavailable: list[str] = []
    for index, entry in enumerate(entries):
        target = destination.joinpath(*Path(entry["relativePath"]).parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_file() and not target.is_symlink():
            payload = target.read_bytes()
            if 0 < len(payload) <= MAXIMUM_SOURCE_BYTES and payload.startswith(b"\x89PNG\r\n\x1a\n"):
                acquired.append(
                    {"relativePath": entry["relativePath"], "sha256": sha256(payload), "bytes": len(payload)}
                )
                continue
            raise ValueError(f"existing source is invalid; refusing to replace it: {target}")
        request = urllib.request.Request(
            entry["url"],
            headers={"User-Agent": "YamaLens-development-dem-acquisition/1.0"},
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read(MAXIMUM_SOURCE_BYTES + 1)
        except urllib.error.HTTPError as error:
            if error.code == 404:
                unavailable.append(entry["relativePath"])
                continue
            raise
        if not 0 < len(payload) <= MAXIMUM_SOURCE_BYTES or not payload.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError(f"downloaded source is not a bounded PNG: {entry['url']}")
        temporary = target.with_suffix(target.suffix + ".partial")
        if temporary.exists():
            raise ValueError(f"stale partial file must be reviewed before retrying: {temporary}")
        temporary.write_bytes(payload)
        os.replace(temporary, target)
        acquired.append(
            {"relativePath": entry["relativePath"], "sha256": sha256(payload), "bytes": len(payload)}
        )
        if index + 1 < len(entries):
            time.sleep(interval)

    inventory = {
        "formatVersion": FORMAT_VERSION,
        "provider": "国土地理院",
        "acquiredAt": datetime.now(timezone.utc).isoformat(),
        "plan": plan_path.name,
        "acquired": acquired,
        "unavailable": unavailable,
    }
    inventory_path = destination / "acquisition-inventory.json"
    if inventory_path.exists():
        raise ValueError(f"refusing to replace an existing acquisition inventory: {inventory_path}")
    inventory_path.write_text(
        json.dumps(inventory, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return inventory


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.command == "plan":
            plan = create_plan(arguments.config, arguments.output)
            print(f"acquisition plan created: {arguments.output} ({plan['tileCount']} tiles)")
        else:
            inventory = fetch_plan(arguments.plan, arguments.destination, arguments.interval)
            print(
                f"acquisition completed: {len(inventory['acquired'])} acquired, "
                f"{len(inventory['unavailable'])} unavailable"
            )
    except (OSError, ValueError, json.JSONDecodeError, urllib.error.URLError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

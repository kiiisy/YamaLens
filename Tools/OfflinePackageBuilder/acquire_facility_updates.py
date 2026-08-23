#!/usr/bin/env python3
"""Fetch one approved facility source and create review-only update artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


FORMAT_VERSION = 1
APPROVED_API_HOST = "catalog.opendata.pref.kanagawa.jp"
APPROVED_API_PATH = "/api/3/action/datastore_search"
MAXIMUM_JSON_INPUT_BYTES = 16 * 1_024 * 1_024
EXPECTED_SOURCE_TYPE = "ckanDatastoreAPI"
EXPECTED_PARSER_VERSION = "kanagawa-park-ckan-v1"
EXPECTED_FIELDS = {
    "地方公共団体名",
    "名称",
    "所在地",
    "無料駐車場",
    "有料駐車場",
    "開園時間",
    "休園日",
    "最終更新日",
}
SAFE_IDENTIFIER = re.compile(r"^[A-Za-z0-9._-]+$")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--canonical", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def load_json(path: Path, maximum_bytes: int = MAXIMUM_JSON_INPUT_BYTES) -> Any:
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"JSON input must be a regular file: {path}")
    size = path.stat().st_size
    if size <= 0 or size > maximum_bytes:
        raise ValueError(f"JSON input size is invalid: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def require_mapping(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{field} must be an object")
    return value


def require_text(value: Any, field: str, maximum_length: int = 256) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > maximum_length:
        raise ValueError(f"{field} must be non-empty text of at most {maximum_length} characters")
    return value.strip()


def require_identifier(value: Any, field: str) -> str:
    identifier = require_text(value, field, 128)
    if not SAFE_IDENTIFIER.fullmatch(identifier):
        raise ValueError(f"{field} contains unsupported characters")
    return identifier


def require_https_url(value: Any, field: str, expected_host: str | None = None) -> str:
    url = require_text(value, field, 2_048)
    parsed = urllib.parse.urlsplit(url)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.fragment
        or (expected_host is not None and parsed.hostname != expected_host)
    ):
        raise ValueError(f"{field} must be an approved HTTPS URL")
    return url


def require_integer(value: Any, field: str, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
        raise ValueError(f"{field} must be an integer in {minimum}...{maximum}")
    return value


def load_config(path: Path) -> dict[str, Any]:
    config = require_mapping(load_json(path), "config")
    if config.get("formatVersion") != FORMAT_VERSION:
        raise ValueError("unsupported facility acquisition formatVersion")
    if config.get("status") != "approvedForPilot":
        raise ValueError("facility source is not approved for the pilot")
    if config.get("sourceType") != EXPECTED_SOURCE_TYPE:
        raise ValueError("unsupported facility source type")
    if config.get("parserVersion") != EXPECTED_PARSER_VERSION:
        raise ValueError("unsupported facility parser version")

    require_identifier(config.get("id"), "id")
    require_text(config.get("provider"), "provider", 128)
    api_url = require_https_url(config.get("apiURL"), "apiURL", APPROVED_API_HOST)
    parsed_api_url = urllib.parse.urlsplit(api_url)
    if parsed_api_url.path != APPROVED_API_PATH or parsed_api_url.query:
        raise ValueError("apiURL must use the approved CKAN datastore endpoint")
    require_identifier(config.get("resourceID"), "resourceID")
    require_https_url(config.get("datasetURL"), "datasetURL", APPROVED_API_HOST)
    require_https_url(config.get("termsURL"), "termsURL")
    require_https_url(config.get("licenseURL"), "licenseURL", "creativecommons.org")
    require_text(config.get("license"), "license", 128)
    require_text(config.get("attributionText"), "attributionText", 512)
    require_identifier(config.get("canonicalPointOfInterestID"), "canonicalPointOfInterestID")

    filters = require_mapping(config.get("filters"), "filters")
    if set(filters) != {"地方公共団体名", "名称"}:
        raise ValueError("filters must identify one municipality and park name")
    for key, value in filters.items():
        require_text(value, f"filters.{key}", 128)

    allowed_fields = config.get("allowedFields")
    if not isinstance(allowed_fields, list) or set(allowed_fields) != EXPECTED_FIELDS:
        raise ValueError("allowedFields must match the reviewed parser fields")

    fetch_policy = require_mapping(config.get("fetchPolicy"), "fetchPolicy")
    if fetch_policy.get("execution") != "manual":
        raise ValueError("the pilot must remain manually triggered")
    require_integer(fetch_policy.get("minimumIntervalHours"), "minimumIntervalHours", 24, 8_760)
    require_integer(fetch_policy.get("timeoutSeconds"), "timeoutSeconds", 1, 30)
    require_integer(
        fetch_policy.get("maximumResponseBytes"),
        "maximumResponseBytes",
        1_024,
        2 * 1_024 * 1_024,
    )

    review_policy = require_mapping(config.get("reviewPolicy"), "reviewPolicy")
    if review_policy.get("automaticCanonicalUpdate") is not False:
        raise ValueError("the pilot must not update canonical data automatically")
    review_fields = review_policy.get("humanReviewRequiredFields")
    if not isinstance(review_fields, list) or not set(review_fields).issubset(EXPECTED_FIELDS):
        raise ValueError("humanReviewRequiredFields contains unsupported fields")
    return config


def build_request_url(config: dict[str, Any]) -> str:
    query = urllib.parse.urlencode(
        {
            "resource_id": config["resourceID"],
            "filters": json.dumps(
                config["filters"],
                ensure_ascii=False,
                separators=(",", ":"),
                sort_keys=True,
            ),
            "limit": "2",
        }
    )
    return f"{config['apiURL']}?{query}"


def parse_source_date(value: Any, field: str) -> str:
    text = require_text(value, field, 32)
    match = re.fullmatch(r"(\d{4})年(\d{1,2})月(\d{1,2})日", text)
    if match is None:
        raise ValueError(f"{field} must use a Japanese calendar date")
    year, month, day = (int(component) for component in match.groups())
    try:
        return datetime(year, month, day, tzinfo=timezone.utc).date().isoformat()
    except ValueError as error:
        raise ValueError(f"{field} is not a valid calendar date") from error


def parse_presence(value: Any, field: str) -> bool | None:
    if value in (0, "0"):
        return False
    if value in (1, "1"):
        return True
    if value in (None, "", "-"):
        return None
    raise ValueError(f"{field} must be 0, 1, or unknown")


def extract_candidate(response_payload: Any, config: dict[str, Any]) -> dict[str, Any]:
    response = require_mapping(response_payload, "response")
    if response.get("success") is not True:
        raise ValueError("CKAN response did not report success")
    result = require_mapping(response.get("result"), "result")
    records = result.get("records")
    if not isinstance(records, list) or len(records) != 1 or result.get("total") != 1:
        raise ValueError("approved filters must return exactly one facility record")
    record = require_mapping(records[0], "records[0]")
    selected = {field: record.get(field) for field in config["allowedFields"]}
    for filter_name, expected_value in config["filters"].items():
        if selected.get(filter_name) != expected_value:
            raise ValueError(f"source record does not match approved filter: {filter_name}")

    return {
        "formatVersion": FORMAT_VERSION,
        "sourceID": config["id"],
        "parserVersion": config["parserVersion"],
        "canonicalPointOfInterestID": config["canonicalPointOfInterestID"],
        "values": {
            "sourceName": require_text(selected["名称"], "名称", 128),
            "address": require_text(selected["所在地"], "所在地", 256),
            "hasFreeParking": parse_presence(selected["無料駐車場"], "無料駐車場"),
            "hasPaidParking": parse_presence(selected["有料駐車場"], "有料駐車場"),
            "openingHours": require_text(selected["開園時間"], "開園時間", 512),
            "closedDays": require_text(selected["休園日"], "休園日", 512),
            "sourceUpdatedAt": parse_source_date(selected["最終更新日"], "最終更新日"),
        },
        "datasetURL": config["datasetURL"],
        "license": config["license"],
        "licenseURL": config["licenseURL"],
        "attributionText": config["attributionText"],
        "automaticCanonicalUpdate": False,
    }


def find_canonical_point_of_interest(
    canonical_payload: Any,
    point_of_interest_id: str,
) -> dict[str, Any]:
    canonical = require_mapping(canonical_payload, "canonical")
    points = canonical.get("pointsOfInterest")
    if not isinstance(points, list):
        raise ValueError("canonical pointsOfInterest must be an array")
    matches = [point for point in points if isinstance(point, dict) and point.get("id") == point_of_interest_id]
    if len(matches) != 1:
        raise ValueError("canonical point of interest must exist exactly once")
    point = matches[0]
    if point.get("type") != "parking":
        raise ValueError("pilot canonical point of interest must be parking")
    require_text(point.get("name"), "canonical.name", 128)
    require_text(point.get("summary"), "canonical.summary", 1_024)
    require_text(point.get("checkedAt"), "canonical.checkedAt", 32)
    require_https_url(point.get("officialURL"), "canonical.officialURL")
    return point


def build_review_diff(candidate: dict[str, Any], canonical_point: dict[str, Any]) -> dict[str, Any]:
    reasons = ["operatingInformationRequiresHumanReview"]
    source_updated_at = candidate["values"]["sourceUpdatedAt"]
    if source_updated_at > canonical_point["checkedAt"]:
        reasons.insert(0, "sourceIsNewerThanCanonicalCheck")
    return {
        "formatVersion": FORMAT_VERSION,
        "sourceID": candidate["sourceID"],
        "canonicalPointOfInterestID": canonical_point["id"],
        "reviewStatus": "humanReviewRequired",
        "reasons": reasons,
        "canonicalBefore": {
            "name": canonical_point["name"],
            "summary": canonical_point["summary"],
            "officialURL": canonical_point["officialURL"],
            "checkedAt": canonical_point["checkedAt"],
        },
        "sourceCandidate": candidate["values"],
        "automaticMutationApplied": False,
    }


def fetch_source(
    config: dict[str, Any],
    *,
    urlopen: Callable[..., Any] = urllib.request.urlopen,
    fetched_at: datetime | None = None,
) -> tuple[bytes, dict[str, Any]]:
    request_url = build_request_url(config)
    request = urllib.request.Request(
        request_url,
        headers={
            "Accept": "application/json",
            "User-Agent": "YamaLens-facility-pilot/1.0 (+manual-review-only)",
        },
    )
    fetch_policy = config["fetchPolicy"]
    with urlopen(request, timeout=fetch_policy["timeoutSeconds"]) as response:
        status = response.getcode()
        final_url = response.geturl()
        final_parts = urllib.parse.urlsplit(final_url)
        content_type = response.headers.get_content_type()
        maximum_bytes = fetch_policy["maximumResponseBytes"]
        payload = response.read(maximum_bytes + 1)
    if (
        status != 200
        or final_parts.scheme != "https"
        or final_parts.hostname != APPROVED_API_HOST
        or final_parts.path != APPROVED_API_PATH
        or content_type not in {"application/json", "application/ld+json"}
        or not 0 < len(payload) <= maximum_bytes
    ):
        raise ValueError("facility response failed URL, type, status, or size validation")
    acquired_at = fetched_at or datetime.now(timezone.utc)
    if acquired_at.tzinfo is None:
        raise ValueError("fetched_at must include a timezone")
    metadata = {
        "formatVersion": FORMAT_VERSION,
        "sourceID": config["id"],
        "fetchedAt": acquired_at.astimezone(timezone.utc).isoformat(),
        "requestedURL": request_url,
        "finalURL": final_url,
        "httpStatus": status,
        "contentType": content_type,
        "byteCount": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "parserVersion": config["parserVersion"],
        "minimumIntervalHours": fetch_policy["minimumIntervalHours"],
        "datasetURL": config["datasetURL"],
        "termsURL": config["termsURL"],
        "licenseURL": config["licenseURL"],
    }
    return payload, metadata


def write_json(path: Path, payload: Any) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def write_review_artifacts(
    output_path: Path,
    raw_payload: bytes,
    metadata: dict[str, Any],
    candidate: dict[str, Any],
    review_diff: dict[str, Any],
) -> None:
    output_path = output_path.expanduser().resolve()
    if output_path.exists():
        raise ValueError(f"refusing to replace existing review output: {output_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f".{output_path.name}-", dir=output_path.parent))
    try:
        temporary.joinpath("source-response.json").write_bytes(raw_payload)
        write_json(temporary / "acquisition-metadata.json", metadata)
        write_json(temporary / "candidate.json", candidate)
        write_json(temporary / "review-diff.json", review_diff)
        os.replace(temporary, output_path)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def run(config_path: Path, canonical_path: Path, output_path: Path) -> dict[str, Any]:
    config = load_config(config_path)
    canonical_payload = load_json(canonical_path)
    raw_payload, metadata = fetch_source(config)
    response_payload = json.loads(raw_payload.decode("utf-8"))
    candidate = extract_candidate(response_payload, config)
    canonical_point = find_canonical_point_of_interest(
        canonical_payload,
        config["canonicalPointOfInterestID"],
    )
    review_diff = build_review_diff(candidate, canonical_point)
    write_review_artifacts(output_path, raw_payload, metadata, candidate, review_diff)
    return review_diff


def main() -> int:
    arguments = parse_arguments()
    try:
        review_diff = run(arguments.config, arguments.canonical, arguments.output)
        print(
            "facility acquisition completed: "
            f"{review_diff['reviewStatus']} for {review_diff['canonicalPointOfInterestID']}"
        )
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError, urllib.error.URLError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

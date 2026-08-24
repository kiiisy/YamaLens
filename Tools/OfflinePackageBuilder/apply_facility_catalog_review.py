#!/usr/bin/env python3
"""Apply a complete human review of the current facility catalog to a new JSON file."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import date
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit


FORMAT_VERSION = 1
MAXIMUM_JSON_BYTES = 16 * 1_024 * 1_024
REVIEW_STATUSES = {"confirmed", "confirmedWithLimitations"}
SAFE_IDENTIFIER = re.compile(r"^[A-Za-z0-9._-]+$")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", required=True, type=Path)
    parser.add_argument("--canonical", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def load_json_bytes(path: Path) -> tuple[bytes, Any]:
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"JSON input must be a regular file: {path}")
    size = path.stat().st_size
    if size <= 0 or size > MAXIMUM_JSON_BYTES:
        raise ValueError(f"JSON input size is invalid: {path}")
    raw = path.read_bytes()
    return raw, json.loads(raw.decode("utf-8"))


def require_mapping(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{field} must be an object")
    return value


def require_list(value: Any, field: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValueError(f"{field} must be an array")
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


def require_date(value: Any, field: str) -> str:
    text = require_text(value, field, 10)
    try:
        date.fromisoformat(text)
    except ValueError as error:
        raise ValueError(f"{field} must be an ISO 8601 calendar date") from error
    return text


def require_https_url(value: Any, field: str) -> str:
    url = require_text(value, field, 2_048)
    parsed = urlsplit(url)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.fragment
    ):
        raise ValueError(f"{field} must be a safe HTTPS URL")
    return url


def require_semantic_version(value: Any, field: str) -> tuple[str, tuple[int, int, int]]:
    version = require_text(value, field, 32)
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        raise ValueError(f"{field} must be a semantic version")
    parts = tuple(int(part) for part in version.split("."))
    return version, parts  # type: ignore[return-value]


def validate_review(canonical_raw: bytes, canonical: Any, review: Any) -> dict[str, Any]:
    canonical_payload = require_mapping(canonical, "canonical")
    review_payload = require_mapping(review, "review")
    if review_payload.get("formatVersion") != FORMAT_VERSION:
        raise ValueError("unsupported review formatVersion")
    if review_payload.get("reviewStatus") != "approved":
        raise ValueError("facility catalog review is not approved")
    if review_payload.get("canonicalSHA256") != hashlib.sha256(canonical_raw).hexdigest():
        raise ValueError("review canonicalSHA256 does not match the canonical file")

    reviewed_at = require_date(review_payload.get("reviewedAt"), "reviewedAt")
    require_text(review_payload.get("reviewedByRole"), "reviewedByRole", 128)
    expected_version, expected_parts = require_semantic_version(
        review_payload.get("expectedContentVersion"),
        "expectedContentVersion",
    )
    reviewed_version, reviewed_parts = require_semantic_version(
        review_payload.get("reviewedContentVersion"),
        "reviewedContentVersion",
    )
    if canonical_payload.get("contentVersion") != expected_version:
        raise ValueError("canonical contentVersion changed after the review was prepared")
    if reviewed_parts != (expected_parts[0], expected_parts[1], expected_parts[2] + 1):
        raise ValueError("reviewedContentVersion must increment the patch version by one")

    sources = require_list(canonical_payload.get("sourceLinks"), "canonical.sourceLinks")
    points = require_list(canonical_payload.get("pointsOfInterest"), "canonical.pointsOfInterest")
    source_by_id = index_unique_records(sources, "canonical.sourceLinks")
    point_by_id = index_unique_records(points, "canonical.pointsOfInterest")

    source_reviews = require_list(review_payload.get("sourceReviews"), "sourceReviews")
    source_review_by_id = index_unique_records(source_reviews, "sourceReviews")
    if set(source_review_by_id) != set(source_by_id):
        raise ValueError("sourceReviews must cover every canonical source exactly once")
    for source_id, review_value in source_review_by_id.items():
        source_review = validate_common_review(review_value, f"sourceReviews.{source_id}")
        evidence = require_mapping(source_review.get("evidence"), f"sourceReviews.{source_id}.evidence")
        evidence_url = require_https_url(evidence.get("url"), f"sourceReviews.{source_id}.evidence.url")
        if evidence_url != source_by_id[source_id].get("url"):
            raise ValueError(f"sourceReviews.{source_id} evidence URL must match the canonical source")
        if require_date(evidence.get("checkedAt"), f"sourceReviews.{source_id}.evidence.checkedAt") != reviewed_at:
            raise ValueError(f"sourceReviews.{source_id} evidence must be checked on the review date")
        require_text(evidence.get("note"), f"sourceReviews.{source_id}.evidence.note", 1_024)
        patch = require_mapping(source_review.get("patch"), f"sourceReviews.{source_id}.patch")
        if set(patch) != {"checkedAt"} or require_date(
            patch.get("checkedAt"),
            f"sourceReviews.{source_id}.patch.checkedAt",
        ) != reviewed_at:
            raise ValueError(f"sourceReviews.{source_id}.patch must update checkedAt to reviewedAt")

    point_reviews = require_list(review_payload.get("pointReviews"), "pointReviews")
    point_review_by_id = index_unique_records(point_reviews, "pointReviews")
    if set(point_review_by_id) != set(point_by_id):
        raise ValueError("pointReviews must cover every canonical point exactly once")
    for point_id, review_value in point_review_by_id.items():
        point_review = validate_common_review(review_value, f"pointReviews.{point_id}")
        evidence_source_id = require_identifier(
            point_review.get("evidenceSourceID"),
            f"pointReviews.{point_id}.evidenceSourceID",
        )
        point = point_by_id[point_id]
        patch = require_mapping(point_review.get("patch"), f"pointReviews.{point_id}.patch")
        required_patch_fields = {"summary", "checkedAt"}
        optional_patch_fields = {"officialURL", "sourceID"}
        if not required_patch_fields.issubset(patch) or not set(patch).issubset(
            required_patch_fields | optional_patch_fields
        ):
            raise ValueError(
                f"pointReviews.{point_id}.patch must contain summary and checkedAt, with only optional officialURL and sourceID"
            )
        require_text(patch.get("summary"), f"pointReviews.{point_id}.patch.summary", 512)
        if require_date(patch.get("checkedAt"), f"pointReviews.{point_id}.patch.checkedAt") != reviewed_at:
            raise ValueError(f"pointReviews.{point_id}.patch.checkedAt must equal reviewedAt")
        reviewed_source_id = patch.get("sourceID", point.get("sourceID"))
        if reviewed_source_id != evidence_source_id or evidence_source_id not in source_review_by_id:
            raise ValueError(f"pointReviews.{point_id} must use its reviewed evidence source")
        reviewed_official_url = patch.get("officialURL", point.get("officialURL"))
        require_https_url(reviewed_official_url, f"pointReviews.{point_id}.patch.officialURL")
        if reviewed_official_url != source_by_id[evidence_source_id].get("url"):
            raise ValueError(f"pointReviews.{point_id} officialURL must match its reviewed evidence source")

    return review_payload


def index_unique_records(values: list[Any], field: str) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for index, value in enumerate(values):
        record = require_mapping(value, f"{field}[{index}]")
        identifier = require_identifier(record.get("id"), f"{field}[{index}].id")
        if identifier in result:
            raise ValueError(f"{field} contains duplicate id: {identifier}")
        result[identifier] = record
    return result


def validate_common_review(value: dict[str, Any], field: str) -> dict[str, Any]:
    status = value.get("status")
    if status not in REVIEW_STATUSES:
        raise ValueError(f"{field}.status is unsupported")
    require_text(value.get("reason"), f"{field}.reason", 1_024)
    return value


def apply_review(canonical_raw: bytes, canonical: Any, review: Any) -> dict[str, Any]:
    review_payload = validate_review(canonical_raw, canonical, review)
    updated = copy.deepcopy(canonical)
    updated["contentVersion"] = review_payload["reviewedContentVersion"]
    source_patches = {item["id"]: item["patch"] for item in review_payload["sourceReviews"]}
    point_patches = {item["id"]: item["patch"] for item in review_payload["pointReviews"]}
    for source in updated["sourceLinks"]:
        source.update(source_patches[source["id"]])
    for point in updated["pointsOfInterest"]:
        point.update(point_patches[point["id"]])
    return updated


def write_json_without_overwrite(path: Path, payload: Any) -> None:
    output = path.expanduser().resolve()
    if output.exists():
        raise ValueError(f"refusing to replace existing reviewed output: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{output.name}-", dir=output.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as file:
            json.dump(payload, file, ensure_ascii=False, indent=2)
            file.write("\n")
        os.link(temporary, output)
        temporary.unlink()
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def run(review_path: Path, canonical_path: Path, output_path: Path) -> None:
    canonical_raw, canonical = load_json_bytes(canonical_path)
    _, review = load_json_bytes(review_path)
    updated = apply_review(canonical_raw, canonical, review)
    if canonical_path.read_bytes() != canonical_raw:
        raise ValueError("canonical input changed while applying the review")
    write_json_without_overwrite(output_path, updated)


def main() -> int:
    arguments = parse_arguments()
    try:
        run(arguments.review, arguments.canonical, arguments.output)
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"reviewed facility catalog written without replacing canonical input: {arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

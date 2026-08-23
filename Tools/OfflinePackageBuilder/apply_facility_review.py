#!/usr/bin/env python3
"""Apply an explicitly reviewed facility patch to a new canonical JSON file."""

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
CANDIDATE_FIELDS = {
    "sourceName",
    "address",
    "hasFreeParking",
    "hasPaidParking",
    "openingHours",
    "closedDays",
    "sourceUpdatedAt",
}
DECISION_STATUSES = {"acceptedAsSupportingEvidence", "rejectedForCanonicalUse"}
PATCH_FIELDS = {"summary", "checkedAt"}
SAFE_IDENTIFIER = re.compile(r"^[A-Za-z0-9._-]+$")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True, type=Path)
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


def require_text(value: Any, field: str, maximum_length: int = 256) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > maximum_length:
        raise ValueError(f"{field} must be non-empty text of at most {maximum_length} characters")
    return value.strip()


def require_identifier(value: Any, field: str) -> str:
    identifier = require_text(value, field, 128)
    if not SAFE_IDENTIFIER.fullmatch(identifier):
        raise ValueError(f"{field} contains unsupported characters")
    return identifier


def require_semantic_version(value: Any, field: str) -> str:
    version = require_text(value, field, 32)
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        raise ValueError(f"{field} must be a semantic version")
    return version


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


def sha256_hex(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def validate_review(candidate_raw: bytes, candidate: Any, review: Any) -> dict[str, Any]:
    candidate_payload = require_mapping(candidate, "candidate")
    review_payload = require_mapping(review, "review")
    if review_payload.get("formatVersion") != FORMAT_VERSION:
        raise ValueError("unsupported review formatVersion")
    if review_payload.get("reviewStatus") != "approved":
        raise ValueError("facility review is not approved")
    if candidate_payload.get("automaticCanonicalUpdate") is not False:
        raise ValueError("candidate must prohibit automatic canonical updates")

    source_id = require_identifier(candidate_payload.get("sourceID"), "candidate.sourceID")
    parser_version = require_identifier(
        candidate_payload.get("parserVersion"),
        "candidate.parserVersion",
    )
    point_id = require_identifier(
        candidate_payload.get("canonicalPointOfInterestID"),
        "candidate.canonicalPointOfInterestID",
    )
    if (
        review_payload.get("sourceID") != source_id
        or review_payload.get("parserVersion") != parser_version
        or review_payload.get("canonicalPointOfInterestID") != point_id
    ):
        raise ValueError("review identity does not match the candidate")
    if review_payload.get("candidateSHA256") != sha256_hex(candidate_raw):
        raise ValueError("review candidateSHA256 does not match the candidate file")

    reviewed_at = require_date(review_payload.get("reviewedAt"), "reviewedAt")
    require_text(review_payload.get("reviewedByRole"), "reviewedByRole", 128)
    evidence = require_mapping(review_payload.get("officialEvidence"), "officialEvidence")
    require_https_url(evidence.get("url"), "officialEvidence.url")
    evidence_checked_at = require_date(
        evidence.get("checkedAt"),
        "officialEvidence.checkedAt",
    )
    if evidence_checked_at != reviewed_at:
        raise ValueError("official evidence must be checked on the review date")
    require_text(evidence.get("note"), "officialEvidence.note", 1_024)

    candidate_values = require_mapping(candidate_payload.get("values"), "candidate.values")
    if set(candidate_values) != CANDIDATE_FIELDS:
        raise ValueError("candidate values do not match the reviewed pilot fields")
    decisions = require_mapping(review_payload.get("candidateFieldDecisions"), "candidateFieldDecisions")
    if set(decisions) != CANDIDATE_FIELDS:
        raise ValueError("every candidate field must have an explicit review decision")
    for field, decision_value in decisions.items():
        decision = require_mapping(decision_value, f"candidateFieldDecisions.{field}")
        if decision.get("status") not in DECISION_STATUSES:
            raise ValueError(f"candidateFieldDecisions.{field}.status is unsupported")
        require_text(decision.get("reason"), f"candidateFieldDecisions.{field}.reason", 512)

    expected_before = require_mapping(
        review_payload.get("expectedCanonicalBefore"),
        "expectedCanonicalBefore",
    )
    if set(expected_before) != {"name", "summary", "officialURL", "checkedAt"}:
        raise ValueError("expectedCanonicalBefore fields are invalid")
    require_text(expected_before.get("name"), "expectedCanonicalBefore.name", 128)
    require_text(expected_before.get("summary"), "expectedCanonicalBefore.summary", 512)
    require_https_url(expected_before.get("officialURL"), "expectedCanonicalBefore.officialURL")
    require_date(expected_before.get("checkedAt"), "expectedCanonicalBefore.checkedAt")

    patch = require_mapping(review_payload.get("canonicalPatch"), "canonicalPatch")
    if set(patch) != PATCH_FIELDS:
        raise ValueError("canonicalPatch must contain only summary and checkedAt")
    require_text(patch.get("summary"), "canonicalPatch.summary", 512)
    patch_checked_at = require_date(patch.get("checkedAt"), "canonicalPatch.checkedAt")
    if patch_checked_at != reviewed_at or patch_checked_at < expected_before["checkedAt"]:
        raise ValueError("canonicalPatch.checkedAt must be current and non-regressing")

    source_before = require_mapping(
        review_payload.get("expectedCanonicalSourceBefore"),
        "expectedCanonicalSourceBefore",
    )
    if set(source_before) != {"id", "url", "checkedAt"}:
        raise ValueError("expectedCanonicalSourceBefore fields are invalid")
    require_identifier(source_before.get("id"), "expectedCanonicalSourceBefore.id")
    require_https_url(source_before.get("url"), "expectedCanonicalSourceBefore.url")
    require_date(source_before.get("checkedAt"), "expectedCanonicalSourceBefore.checkedAt")
    source_patch = require_mapping(review_payload.get("canonicalSourcePatch"), "canonicalSourcePatch")
    if set(source_patch) != {"checkedAt"}:
        raise ValueError("canonicalSourcePatch must contain only checkedAt")
    source_checked_at = require_date(
        source_patch.get("checkedAt"),
        "canonicalSourcePatch.checkedAt",
    )
    if source_checked_at != reviewed_at or source_checked_at < source_before["checkedAt"]:
        raise ValueError("canonicalSourcePatch.checkedAt must be current and non-regressing")
    expected_content_version = require_semantic_version(
        review_payload.get("expectedContentVersion"),
        "expectedContentVersion",
    )
    reviewed_content_version = require_semantic_version(
        review_payload.get("reviewedContentVersion"),
        "reviewedContentVersion",
    )
    expected_parts = tuple(int(part) for part in expected_content_version.split("."))
    reviewed_parts = tuple(int(part) for part in reviewed_content_version.split("."))
    if reviewed_parts != (expected_parts[0], expected_parts[1], expected_parts[2] + 1):
        raise ValueError("reviewedContentVersion must increment the patch version by one")
    return review_payload


def apply_review(candidate_raw: bytes, candidate: Any, review: Any, canonical: Any) -> dict[str, Any]:
    review_payload = validate_review(candidate_raw, candidate, review)
    canonical_payload = require_mapping(canonical, "canonical")
    if canonical_payload.get("contentVersion") != review_payload["expectedContentVersion"]:
        raise ValueError("canonical contentVersion changed after the review was prepared")
    points = canonical_payload.get("pointsOfInterest")
    if not isinstance(points, list):
        raise ValueError("canonical pointsOfInterest must be an array")
    point_id = review_payload["canonicalPointOfInterestID"]
    matching_indexes = [
        index
        for index, point in enumerate(points)
        if isinstance(point, dict) and point.get("id") == point_id
    ]
    if len(matching_indexes) != 1:
        raise ValueError("canonical point of interest must exist exactly once")
    point = require_mapping(points[matching_indexes[0]], "canonical point of interest")
    if point.get("type") != "parking":
        raise ValueError("pilot canonical point of interest must be parking")
    before = review_payload["expectedCanonicalBefore"]
    current_before = {field: point.get(field) for field in before}
    if current_before != before:
        raise ValueError("canonical point changed after the review was prepared")
    if review_payload["officialEvidence"]["url"] != point.get("officialURL"):
        raise ValueError("official evidence URL must match the canonical officialURL")

    sources = canonical_payload.get("sourceLinks")
    if not isinstance(sources, list):
        raise ValueError("canonical sourceLinks must be an array")
    source_before = review_payload["expectedCanonicalSourceBefore"]
    source_indexes = [
        index
        for index, source in enumerate(sources)
        if isinstance(source, dict) and source.get("id") == source_before["id"]
    ]
    if len(source_indexes) != 1:
        raise ValueError("canonical source link must exist exactly once")
    source = require_mapping(sources[source_indexes[0]], "canonical source link")
    current_source_before = {field: source.get(field) for field in source_before}
    if current_source_before != source_before:
        raise ValueError("canonical source changed after the review was prepared")
    if source.get("url") != review_payload["officialEvidence"]["url"]:
        raise ValueError("review evidence must match the canonical source link")

    updated = copy.deepcopy(canonical_payload)
    updated["contentVersion"] = review_payload["reviewedContentVersion"]
    updated_point = updated["pointsOfInterest"][matching_indexes[0]]
    updated_point.update(review_payload["canonicalPatch"])
    updated_source = updated["sourceLinks"][source_indexes[0]]
    updated_source.update(review_payload["canonicalSourcePatch"])
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


def run(candidate_path: Path, review_path: Path, canonical_path: Path, output_path: Path) -> None:
    candidate_raw, candidate = load_json_bytes(candidate_path)
    _, review = load_json_bytes(review_path)
    canonical_raw, canonical = load_json_bytes(canonical_path)
    updated = apply_review(candidate_raw, candidate, review, canonical)
    if canonical_path.read_bytes() != canonical_raw:
        raise ValueError("canonical input changed while applying the review")
    write_json_without_overwrite(output_path, updated)


def main() -> int:
    arguments = parse_arguments()
    try:
        run(arguments.candidate, arguments.review, arguments.canonical, arguments.output)
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"reviewed facility JSON written without replacing canonical input: {arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

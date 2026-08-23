#!/usr/bin/env python3
"""Deterministic tests for explicitly reviewed facility updates."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import apply_facility_review


class FacilityReviewApplicationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(prefix="yamalens-facility-review-")
        self.root = Path(self.temporary_directory.name)
        self.candidate_path = self.write_json(self.root / "candidate.json", self.candidate())
        candidate_hash = hashlib.sha256(self.candidate_path.read_bytes()).hexdigest()
        self.review_path = self.write_json(
            self.root / "review.json",
            self.review(candidate_hash),
        )
        self.canonical_path = self.write_json(
            self.root / "canonical.json",
            self.canonical(),
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_applies_only_explicit_patch_without_mutating_input(self) -> None:
        canonical_before = self.canonical_path.read_bytes()
        output = self.root / "reviewed.json"

        apply_facility_review.run(
            self.candidate_path,
            self.review_path,
            self.canonical_path,
            output,
        )

        reviewed = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(reviewed["contentVersion"], "1.2.1")
        point = reviewed["pointsOfInterest"][0]
        self.assertEqual(point["summary"], "有料駐車場です。最新情報は公式案内で確認してください。")
        self.assertEqual(point["checkedAt"], "2026-08-24")
        self.assertEqual(point["name"], "秦野戸川公園 大倉駐車場")
        self.assertEqual(reviewed["sourceLinks"][0]["checkedAt"], "2026-08-24")
        self.assertEqual(self.canonical_path.read_bytes(), canonical_before)

    def test_rejects_candidate_hash_mismatch(self) -> None:
        review = self.review("0" * 64)

        with self.assertRaisesRegex(ValueError, "candidateSHA256"):
            apply_facility_review.apply_review(
                self.candidate_path.read_bytes(),
                self.candidate(),
                review,
                self.canonical(),
            )

    def test_requires_decision_for_every_candidate_field(self) -> None:
        candidate_raw = self.candidate_path.read_bytes()
        review = self.review(hashlib.sha256(candidate_raw).hexdigest())
        del review["candidateFieldDecisions"]["openingHours"]

        with self.assertRaisesRegex(ValueError, "every candidate field"):
            apply_facility_review.apply_review(
                candidate_raw,
                self.candidate(),
                review,
                self.canonical(),
            )

    def test_rejects_canonical_changed_after_review(self) -> None:
        candidate_raw = self.candidate_path.read_bytes()
        canonical = self.canonical()
        canonical["pointsOfInterest"][0]["summary"] = "別の更新"

        with self.assertRaisesRegex(ValueError, "changed after the review"):
            apply_facility_review.apply_review(
                candidate_raw,
                self.candidate(),
                self.review(hashlib.sha256(candidate_raw).hexdigest()),
                canonical,
            )

    def test_refuses_to_replace_reviewed_output(self) -> None:
        output = self.write_json(self.root / "reviewed.json", {"existing": True})

        with self.assertRaisesRegex(ValueError, "refusing to replace"):
            apply_facility_review.run(
                self.candidate_path,
                self.review_path,
                self.canonical_path,
                output,
            )

    def candidate(self) -> dict[str, object]:
        return {
            "formatVersion": 1,
            "sourceID": "kanagawa-hadano-tokawa-park-v1",
            "parserVersion": "kanagawa-park-ckan-v1",
            "canonicalPointOfInterestID": "hadano-tokawa-okura-parking",
            "values": {
                "sourceName": "秦野戸川公園",
                "address": "神奈川県秦野市掘山下1513",
                "hasFreeParking": False,
                "hasPaidParking": True,
                "openingHours": "パークセンター：午前9時～午後4時30分",
                "closedDays": "公園：無休",
                "sourceUpdatedAt": "2026-07-08",
            },
            "automaticCanonicalUpdate": False,
        }

    def review(self, candidate_hash: str) -> dict[str, object]:
        return {
            "formatVersion": 1,
            "reviewStatus": "approved",
            "sourceID": "kanagawa-hadano-tokawa-park-v1",
            "parserVersion": "kanagawa-park-ckan-v1",
            "canonicalPointOfInterestID": "hadano-tokawa-okura-parking",
            "candidateSHA256": candidate_hash,
            "expectedContentVersion": "1.2.0",
            "reviewedContentVersion": "1.2.1",
            "reviewedAt": "2026-08-24",
            "reviewedByRole": "repositoryMaintainer",
            "officialEvidence": {
                "url": "https://www.kanagawa-park.or.jp/hadanotokawa/access.html",
                "checkedAt": "2026-08-24",
                "note": "公式アクセス案内で有料駐車場であることを確認した。",
            },
            "candidateFieldDecisions": {
                field: {
                    "status": "acceptedAsSupportingEvidence",
                    "reason": "テスト用の明示的な判断です。",
                }
                for field in apply_facility_review.CANDIDATE_FIELDS
            },
            "expectedCanonicalBefore": {
                "name": "秦野戸川公園 大倉駐車場",
                "summary": "利用時間・料金・混雑情報は公式案内で確認してください。",
                "officialURL": "https://www.kanagawa-park.or.jp/hadanotokawa/access.html",
                "checkedAt": "2026-08-22",
            },
            "canonicalPatch": {
                "summary": "有料駐車場です。最新情報は公式案内で確認してください。",
                "checkedAt": "2026-08-24",
            },
            "expectedCanonicalSourceBefore": {
                "id": "hadano-tokawa-access",
                "url": "https://www.kanagawa-park.or.jp/hadanotokawa/access.html",
                "checkedAt": "2026-08-22",
            },
            "canonicalSourcePatch": {
                "checkedAt": "2026-08-24",
            },
        }

    def canonical(self) -> dict[str, object]:
        return {
            "contentVersion": "1.2.0",
            "sourceLinks": [
                {
                    "id": "hadano-tokawa-access",
                    "url": "https://www.kanagawa-park.or.jp/hadanotokawa/access.html",
                    "checkedAt": "2026-08-22",
                }
            ],
            "pointsOfInterest": [
                {
                    "id": "hadano-tokawa-okura-parking",
                    "type": "parking",
                    "name": "秦野戸川公園 大倉駐車場",
                    "summary": "利用時間・料金・混雑情報は公式案内で確認してください。",
                    "officialURL": "https://www.kanagawa-park.or.jp/hadanotokawa/access.html",
                    "checkedAt": "2026-08-22",
                }
            ]
        }

    @staticmethod
    def write_json(path: Path, payload: object) -> Path:
        path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return path


if __name__ == "__main__":
    unittest.main()

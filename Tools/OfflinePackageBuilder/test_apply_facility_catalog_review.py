#!/usr/bin/env python3
"""Deterministic tests for complete facility catalog reviews."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import apply_facility_catalog_review


class FacilityCatalogReviewTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(prefix="yamalens-catalog-review-")
        self.root = Path(self.temporary_directory.name)
        self.canonical_path = self.write_json(self.root / "canonical.json", self.canonical())
        canonical_hash = hashlib.sha256(self.canonical_path.read_bytes()).hexdigest()
        self.review_path = self.write_json(self.root / "review.json", self.review(canonical_hash))

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_applies_complete_review_without_mutating_input(self) -> None:
        original = self.canonical_path.read_bytes()
        output = self.root / "reviewed.json"

        apply_facility_catalog_review.run(self.review_path, self.canonical_path, output)

        reviewed = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(reviewed["contentVersion"], "1.2.2")
        self.assertEqual(reviewed["sourceLinks"][0]["checkedAt"], "2026-08-24")
        self.assertEqual(reviewed["pointsOfInterest"][0]["summary"], "公式確認済みの案内")
        self.assertEqual(reviewed["pointsOfInterest"][0]["checkedAt"], "2026-08-24")
        self.assertEqual(self.canonical_path.read_bytes(), original)

    def test_rejects_canonical_hash_mismatch(self) -> None:
        review = self.review("0" * 64)

        with self.assertRaisesRegex(ValueError, "canonicalSHA256"):
            apply_facility_catalog_review.apply_review(
                self.canonical_path.read_bytes(),
                self.canonical(),
                review,
            )

    def test_requires_review_for_every_point(self) -> None:
        review = self.review(hashlib.sha256(self.canonical_path.read_bytes()).hexdigest())
        review["pointReviews"] = []

        with self.assertRaisesRegex(ValueError, "every canonical point"):
            apply_facility_catalog_review.apply_review(
                self.canonical_path.read_bytes(),
                self.canonical(),
                review,
            )

    def test_requires_evidence_url_to_match_source(self) -> None:
        review = self.review(hashlib.sha256(self.canonical_path.read_bytes()).hexdigest())
        review["sourceReviews"][0]["evidence"]["url"] = "https://example.org/other"

        with self.assertRaisesRegex(ValueError, "evidence URL"):
            apply_facility_catalog_review.apply_review(
                self.canonical_path.read_bytes(),
                self.canonical(),
                review,
            )

    def test_allows_point_to_move_to_a_better_reviewed_source(self) -> None:
        canonical = self.canonical()
        canonical["sourceLinks"].append(
            {
                "id": "better-source",
                "url": "https://example.org/better",
                "checkedAt": "2026-08-23",
            }
        )
        canonical_raw = (json.dumps(canonical, ensure_ascii=False) + "\n").encode("utf-8")
        review = self.review(hashlib.sha256(canonical_raw).hexdigest())
        review["sourceReviews"].append(
            {
                "id": "better-source",
                "status": "confirmed",
                "reason": "より直接的な公式根拠。",
                "evidence": {
                    "url": "https://example.org/better",
                    "checkedAt": "2026-08-24",
                    "note": "対象施設を直接掲載している。",
                },
                "patch": {"checkedAt": "2026-08-24"},
            }
        )
        review["pointReviews"][0]["evidenceSourceID"] = "better-source"
        review["pointReviews"][0]["patch"].update(
            {
                "officialURL": "https://example.org/better",
                "sourceID": "better-source",
            }
        )

        reviewed = apply_facility_catalog_review.apply_review(canonical_raw, canonical, review)

        self.assertEqual(reviewed["pointsOfInterest"][0]["sourceID"], "better-source")
        self.assertEqual(
            reviewed["pointsOfInterest"][0]["officialURL"],
            "https://example.org/better",
        )

    def test_refuses_to_replace_output(self) -> None:
        output = self.write_json(self.root / "reviewed.json", {"existing": True})

        with self.assertRaisesRegex(ValueError, "refusing to replace"):
            apply_facility_catalog_review.run(self.review_path, self.canonical_path, output)

    @staticmethod
    def canonical() -> dict[str, object]:
        return {
            "contentVersion": "1.2.1",
            "sourceLinks": [
                {
                    "id": "official-source",
                    "url": "https://example.org/official",
                    "checkedAt": "2026-08-23",
                }
            ],
            "pointsOfInterest": [
                {
                    "id": "facility",
                    "type": "parking",
                    "name": "施設",
                    "summary": "以前の案内",
                    "officialURL": "https://example.org/official",
                    "checkedAt": "2026-08-23",
                    "sourceID": "official-source",
                }
            ],
        }

    @staticmethod
    def review(canonical_hash: str) -> dict[str, object]:
        return {
            "formatVersion": 1,
            "reviewStatus": "approved",
            "canonicalSHA256": canonical_hash,
            "expectedContentVersion": "1.2.1",
            "reviewedContentVersion": "1.2.2",
            "reviewedAt": "2026-08-24",
            "reviewedByRole": "repositoryMaintainer",
            "sourceReviews": [
                {
                    "id": "official-source",
                    "status": "confirmed",
                    "reason": "公式ページで施設情報を確認した。",
                    "evidence": {
                        "url": "https://example.org/official",
                        "checkedAt": "2026-08-24",
                        "note": "テスト用の公式根拠。",
                    },
                    "patch": {"checkedAt": "2026-08-24"},
                }
            ],
            "pointReviews": [
                {
                    "id": "facility",
                    "status": "confirmed",
                    "reason": "名称と案内を確認した。",
                    "evidenceSourceID": "official-source",
                    "patch": {
                        "summary": "公式確認済みの案内",
                        "checkedAt": "2026-08-24",
                    },
                }
            ],
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

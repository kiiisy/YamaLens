#!/usr/bin/env python3
"""Deterministic tests for review-only facility acquisition."""

from __future__ import annotations

import email.message
import json
import tempfile
import unittest
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path

import acquire_facility_updates


class FakeResponse:
    def __init__(self, payload: bytes, final_url: str) -> None:
        self.payload = payload
        self.final_url = final_url
        self.headers = email.message.Message()
        self.headers["Content-Type"] = "application/json; charset=utf-8"

    def __enter__(self) -> FakeResponse:
        return self

    def __exit__(self, *_: object) -> None:
        return None

    def getcode(self) -> int:
        return 200

    def geturl(self) -> str:
        return self.final_url

    def read(self, maximum_bytes: int) -> bytes:
        return self.payload[:maximum_bytes]


class FacilityAcquisitionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(prefix="yamalens-facility-test-")
        self.root = Path(self.temporary_directory.name)
        self.config_path = self.write_json(self.root / "config.json", self.config_payload())
        self.canonical_path = self.write_json(
            self.root / "canonical.json",
            self.canonical_payload(),
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_builds_exact_filtered_official_api_url(self) -> None:
        config = acquire_facility_updates.load_config(self.config_path)

        url = acquire_facility_updates.build_request_url(config)
        components = urllib.parse.urlsplit(url)
        query = urllib.parse.parse_qs(components.query)

        self.assertEqual(components.scheme, "https")
        self.assertEqual(components.hostname, "catalog.opendata.pref.kanagawa.jp")
        self.assertEqual(components.path, "/api/3/action/datastore_search")
        self.assertEqual(query["resource_id"], [config["resourceID"]])
        self.assertEqual(json.loads(query["filters"][0]), config["filters"])
        self.assertEqual(query["limit"], ["2"])

    def test_extracts_candidate_without_mutating_canonical_data(self) -> None:
        config = acquire_facility_updates.load_config(self.config_path)
        canonical_before = self.canonical_path.read_bytes()

        candidate = acquire_facility_updates.extract_candidate(self.source_payload(), config)
        canonical = acquire_facility_updates.find_canonical_point_of_interest(
            acquire_facility_updates.load_json(self.canonical_path),
            config["canonicalPointOfInterestID"],
        )
        review_diff = acquire_facility_updates.build_review_diff(candidate, canonical)

        self.assertEqual(candidate["values"]["sourceUpdatedAt"], "2026-07-08")
        self.assertFalse(candidate["values"]["hasFreeParking"])
        self.assertTrue(candidate["values"]["hasPaidParking"])
        self.assertEqual(review_diff["reviewStatus"], "humanReviewRequired")
        self.assertIn("sourceIsNewerThanCanonicalCheck", review_diff["reasons"])
        self.assertFalse(review_diff["automaticMutationApplied"])
        self.assertEqual(self.canonical_path.read_bytes(), canonical_before)

    def test_rejects_ambiguous_source_records(self) -> None:
        config = acquire_facility_updates.load_config(self.config_path)
        payload = self.source_payload()
        payload["result"]["records"].append(dict(payload["result"]["records"][0]))
        payload["result"]["total"] = 2

        with self.assertRaisesRegex(ValueError, "exactly one"):
            acquire_facility_updates.extract_candidate(payload, config)

    def test_fetch_records_bounded_metadata_and_writes_review_artifacts(self) -> None:
        config = acquire_facility_updates.load_config(self.config_path)
        raw_payload = json.dumps(self.source_payload(), ensure_ascii=False).encode("utf-8")
        request_url = acquire_facility_updates.build_request_url(config)

        def fake_urlopen(*_: object, **__: object) -> FakeResponse:
            return FakeResponse(raw_payload, request_url)

        payload, metadata = acquire_facility_updates.fetch_source(
            config,
            urlopen=fake_urlopen,
            fetched_at=datetime(2026, 8, 24, 1, 2, 3, tzinfo=timezone.utc),
        )
        candidate = acquire_facility_updates.extract_candidate(json.loads(payload), config)
        canonical = acquire_facility_updates.find_canonical_point_of_interest(
            acquire_facility_updates.load_json(self.canonical_path),
            config["canonicalPointOfInterestID"],
        )
        review_diff = acquire_facility_updates.build_review_diff(candidate, canonical)
        output = self.root / "review"

        acquire_facility_updates.write_review_artifacts(
            output,
            payload,
            metadata,
            candidate,
            review_diff,
        )

        self.assertEqual(metadata["fetchedAt"], "2026-08-24T01:02:03+00:00")
        self.assertEqual(
            sorted(path.name for path in output.iterdir()),
            [
                "acquisition-metadata.json",
                "candidate.json",
                "review-diff.json",
                "source-response.json",
            ],
        )
        with self.assertRaisesRegex(ValueError, "refusing to replace"):
            acquire_facility_updates.write_review_artifacts(
                output,
                payload,
                metadata,
                candidate,
                review_diff,
            )

    def test_rejects_unapproved_api_host(self) -> None:
        config = self.config_payload()
        config["apiURL"] = "https://example.com/api/3/action/datastore_search"
        path = self.write_json(self.root / "unsafe.json", config)

        with self.assertRaisesRegex(ValueError, "approved HTTPS URL"):
            acquire_facility_updates.load_config(path)

    def config_payload(self) -> dict[str, object]:
        return {
            "formatVersion": 1,
            "id": "kanagawa-hadano-tokawa-park-v1",
            "status": "approvedForPilot",
            "provider": "神奈川県",
            "sourceType": "ckanDatastoreAPI",
            "apiURL": "https://catalog.opendata.pref.kanagawa.jp/api/3/action/datastore_search",
            "resourceID": "2b416702-1a0e-4b89-b17f-42739ef5d580",
            "datasetURL": "https://catalog.opendata.pref.kanagawa.jp/dataset/example/resource/example",
            "termsURL": "https://opendata.pref.kanagawa.jp/terms",
            "license": "クリエイティブ・コモンズ 表示 4.0 国際",
            "licenseURL": "https://creativecommons.org/licenses/by/4.0/deed.ja",
            "attributionText": "神奈川県公園データを改変して利用（CC BY 4.0）",
            "parserVersion": "kanagawa-park-ckan-v1",
            "filters": {"地方公共団体名": "神奈川県", "名称": "秦野戸川公園"},
            "canonicalPointOfInterestID": "hadano-tokawa-okura-parking",
            "allowedFields": sorted(acquire_facility_updates.EXPECTED_FIELDS),
            "fetchPolicy": {
                "execution": "manual",
                "minimumIntervalHours": 168,
                "timeoutSeconds": 15,
                "maximumResponseBytes": 2_097_152,
            },
            "reviewPolicy": {
                "automaticCanonicalUpdate": False,
                "humanReviewRequiredFields": [
                    "無料駐車場",
                    "有料駐車場",
                    "開園時間",
                    "休園日",
                    "最終更新日",
                ],
            },
        }

    def canonical_payload(self) -> dict[str, object]:
        return {
            "pointsOfInterest": [
                {
                    "id": "hadano-tokawa-okura-parking",
                    "type": "parking",
                    "name": "秦野戸川公園 大倉駐車場",
                    "summary": "利用時間・料金・混雑情報は公式案内で確認してください。",
                    "officialURL": "https://www.kanagawa-park.or.jp/hadanotokawa/access.html",
                    "checkedAt": "2026-01-01",
                }
            ]
        }

    def source_payload(self) -> dict[str, object]:
        return {
            "success": True,
            "result": {
                "total": 1,
                "records": [
                    {
                        "地方公共団体名": "神奈川県",
                        "名称": "秦野戸川公園",
                        "所在地": "神奈川県秦野市掘山下1513",
                        "無料駐車場": "0",
                        "有料駐車場": "1",
                        "開園時間": "パークセンター：午前9時～午後4時30分",
                        "休園日": "公園：無休",
                        "最終更新日": "2026年7月8日",
                    }
                ],
            },
        }

    @staticmethod
    def write_json(path: Path, payload: object) -> Path:
        path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        return path


if __name__ == "__main__":
    unittest.main()

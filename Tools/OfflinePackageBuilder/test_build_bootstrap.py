import copy
import json
import tempfile
import unittest
from pathlib import Path

import build_bootstrap


class BuildBootstrapTests(unittest.TestCase):
    def valid_source(self) -> dict:
        return {
            "schemaVersion": 1,
            "contentVersion": "1.0.0",
            "sourceManifestID": "test-source",
            "regions": [
                {"id": "test-region", "name": "テスト山域", "prefectureName": "神奈川県"}
            ],
            "mountains": [
                {
                    "id": "test-mountain",
                    "regionID": "test-region",
                    "coverageRole": "core",
                    "canonicalName": "テスト山",
                    "searchName": "てすとやま",
                    "aliases": [],
                    "latitude": 35.0,
                    "longitude": 139.0,
                    "elevationMeters": 1_000,
                    "updatedAt": "2026-08-22T00:00:00Z",
                }
            ],
            "sourceLinks": [
                {
                    "id": "test-official",
                    "provider": "テスト自治体",
                    "title": "公式ページ",
                    "url": "https://example.com/official",
                    "checkedAt": "2026-08-22",
                    "attributionText": "出典：テスト自治体",
                }
            ],
            "pointsOfInterest": [
                {
                    "id": "test-trailhead",
                    "regionID": "test-region",
                    "type": "trailhead",
                    "name": "テスト登山口",
                    "summary": "公式情報を確認してください。",
                    "officialURL": "https://example.com/official",
                    "checkedAt": "2026-08-22",
                    "sourceID": "test-official",
                }
            ],
            "mountainPointOfInterestLinks": [
                {"mountainID": "test-mountain", "pointOfInterestID": "test-trailhead"}
            ],
        }

    def test_writes_facility_and_source_records(self) -> None:
        source = self.valid_source()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "bootstrap.sqlite"
            build_bootstrap.create_database(source, output)
            build_bootstrap.verify_database(source, output)

    def test_rejects_non_https_official_url(self) -> None:
        source = copy.deepcopy(self.valid_source())
        source["pointsOfInterest"][0]["officialURL"] = "http://example.com/official"
        with tempfile.TemporaryDirectory() as directory:
            input_path = Path(directory) / "source.json"
            input_path.write_text(json.dumps(source), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "must be an HTTPS URL"):
                build_bootstrap.load_source(input_path)


if __name__ == "__main__":
    unittest.main()

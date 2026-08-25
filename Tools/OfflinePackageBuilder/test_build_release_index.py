from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from build_release_index import build_release_index, parse_arguments


class BuildReleaseIndexTests(unittest.TestCase):
    def test_builds_verified_release_index(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            private_key = root / "signing.pem"
            subprocess.run(
                ["openssl", "genpkey", "-algorithm", "Ed25519", "-out", str(private_key)],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            output = root / "release"
            arguments = parse_arguments_for_test(private_key, output)

            build_release_index(arguments)

            self.assertEqual(
                json.loads((output / "release.json").read_text(encoding="utf-8")),
                {
                    "contentVersion": "1.0.1",
                    "formatVersion": 1,
                    "keyID": "test-key-01",
                    "packageID": "jp.kanagawa.tanzawa",
                    "signatureAlgorithm": "Ed25519",
                },
            )
            self.assertEqual((output / "release.sig").stat().st_size, 64)
            self.assertFalse((output / ".verification-public-key.pem").exists())


def parse_arguments_for_test(private_key: Path, output: Path):
    import sys

    previous_arguments = sys.argv
    sys.argv = [
        "build_release_index.py",
        "--package-id", "jp.kanagawa.tanzawa",
        "--content-version", "1.0.1",
        "--key-id", "test-key-01",
        "--private-key", str(private_key),
        "--output", str(output),
    ]
    try:
        return parse_arguments()
    finally:
        sys.argv = previous_arguments


if __name__ == "__main__":
    unittest.main()

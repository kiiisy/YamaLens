#!/usr/bin/env python3
"""Build a signed YamaLens offline-package release index."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
from pathlib import Path


SEMANTIC_VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
SAFE_IDENTIFIER = re.compile(r"^[A-Za-z0-9._-]{1,128}$")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-id", required=True)
    parser.add_argument("--content-version", required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--private-key", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def validate_identifier(value: str, name: str) -> None:
    if not SAFE_IDENTIFIER.fullmatch(value) or ".." in value or value == ".":
        raise ValueError(f"{name} must be a safe identifier")


def validate_arguments(arguments: argparse.Namespace) -> None:
    validate_identifier(arguments.package_id, "package-id")
    validate_identifier(arguments.key_id, "key-id")
    if not SEMANTIC_VERSION.fullmatch(arguments.content_version):
        raise ValueError("content-version must use major.minor.patch")
    if not arguments.private_key.is_file() or arguments.private_key.is_symlink():
        raise ValueError("private-key must be a regular file outside the repository")
    if arguments.output.exists():
        raise ValueError("refusing to replace an existing output directory")


def run_openssl(arguments: list[str]) -> None:
    openssl = shutil.which("openssl")
    if openssl is None:
        raise ValueError("OpenSSL with Ed25519 support is required")
    try:
        subprocess.run(
            [openssl, *arguments],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as error:
        raise ValueError("OpenSSL could not sign or verify the release index") from error


def release_index_bytes(arguments: argparse.Namespace) -> bytes:
    payload = {
        "contentVersion": arguments.content_version,
        "formatVersion": 1,
        "keyID": arguments.key_id,
        "packageID": arguments.package_id,
        "signatureAlgorithm": "Ed25519",
    }
    return (json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n").encode("utf-8")


def build_release_index(arguments: argparse.Namespace) -> None:
    validate_arguments(arguments)
    arguments.output.mkdir(parents=True)
    index_path = arguments.output / "release.json"
    signature_path = arguments.output / "release.sig"
    public_key_path = arguments.output / ".verification-public-key.pem"
    index_path.write_bytes(release_index_bytes(arguments))
    try:
        run_openssl(["pkey", "-in", str(arguments.private_key), "-pubout", "-out", str(public_key_path)])
        run_openssl([
            "pkeyutl", "-sign", "-rawin", "-inkey", str(arguments.private_key),
            "-in", str(index_path), "-out", str(signature_path),
        ])
        if signature_path.stat().st_size != 64:
            raise ValueError("Ed25519 signature must be exactly 64 bytes")
        run_openssl([
            "pkeyutl", "-verify", "-pubin", "-inkey", str(public_key_path),
            "-rawin", "-in", str(index_path), "-sigfile", str(signature_path),
        ])
    except Exception:
        shutil.rmtree(arguments.output)
        raise
    finally:
        public_key_path.unlink(missing_ok=True)


def main() -> None:
    try:
        build_release_index(parse_arguments())
    except ValueError as error:
        raise SystemExit(f"error: {error}") from error


if __name__ == "__main__":
    main()

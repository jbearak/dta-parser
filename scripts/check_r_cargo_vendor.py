#!/usr/bin/env python3
"""Validate the R package's offline Cargo dependency archive."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys
import tarfile

if sys.version_info < (3, 11):
    raise SystemExit("R Cargo vendor validation requires Python 3.11 or newer")

import tomllib


CRATES_IO_SOURCE = "registry+https://github.com/rust-lang/crates.io-index"


class VendorError(RuntimeError):
    """An offline Cargo vendor invariant failed."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_archive_digest(path: Path) -> str:
    lines = path.read_text(encoding="ascii").splitlines()
    if len(lines) != 1:
        raise VendorError("vendor.sha256 must contain exactly one entry")
    fields = lines[0].split()
    if (
        len(fields) != 2
        or not re.fullmatch(r"[0-9a-f]{64}", fields[0])
        or fields[1] != "vendor.tar.gz"
    ):
        raise VendorError(f"malformed vendor archive digest: {lines[0]!r}")
    return fields[0]


def registry_packages(lock_path: Path) -> dict[tuple[str, str], str]:
    lock = tomllib.loads(lock_path.read_text(encoding="utf-8"))
    packages = lock.get("package")
    if not isinstance(packages, list):
        raise VendorError(f"Cargo lock has no [[package]] entries: {lock_path}")

    registry: dict[tuple[str, str], str] = {}
    for package in packages:
        if not isinstance(package, dict):
            raise VendorError(f"malformed Cargo package entry: {lock_path}")
        source = package.get("source")
        if source is None:
            continue
        if source != CRATES_IO_SOURCE:
            raise VendorError(f"unsupported Cargo dependency source: {source}")
        name = package.get("name")
        version = package.get("version")
        checksum = package.get("checksum")
        if not all(isinstance(value, str) for value in (name, version, checksum)):
            raise VendorError(
                f"registry package lacks name, version, or checksum: {lock_path}"
            )
        assert isinstance(name, str) and isinstance(version, str) and isinstance(checksum, str)
        identity = (name, version)
        if identity in registry:
            raise VendorError(f"duplicate locked registry package: {name} {version}")
        registry[identity] = checksum
    return registry


def check_vendor_archive(archive: Path, integrity_path: Path, lock_path: Path) -> None:
    expected_archive = read_archive_digest(integrity_path)
    if sha256_file(archive) != expected_archive:
        raise VendorError("offline vendor archive digest differs from vendor.sha256")

    entries: dict[str, tarfile.TarInfo] = {}
    metadata: dict[str, bytes] = {}
    with tarfile.open(archive, mode="r|gz") as source:
        for member in source:
            name = member.name.rstrip("/")
            relative = PurePosixPath(name)
            if not name or relative.is_absolute() or ".." in relative.parts or "\\" in name:
                raise VendorError(
                    f"offline vendor archive has an unsafe path: {member.name}"
                )
            if not (member.isfile() or member.isdir()):
                raise VendorError(
                    f"offline vendor archive has a special entry: {member.name}"
                )
            if name in entries:
                raise VendorError(f"offline vendor archive has a duplicate entry: {name}")
            entries[name] = member

            if member.isfile() and PurePosixPath(name).name in {
                ".cargo-checksum.json",
                "Cargo.toml",
            }:
                contents = source.extractfile(member)
                assert contents is not None
                metadata[name] = contents.read()

    for name in entries:
        for parent in PurePosixPath(name).parents:
            if parent == PurePosixPath("."):
                break
            parent_member = entries.get(parent.as_posix())
            if parent_member is not None and parent_member.isfile():
                raise VendorError(
                    f"offline vendor archive puts {name} below file {parent.as_posix()}"
                )

    archived_packages: dict[tuple[str, str], tuple[str, str]] = {}
    archive_directories = sorted(
        name
        for name, member in entries.items()
        if member.isdir() and PurePosixPath(name).parent == PurePosixPath("v")
    )
    for directory in archive_directories:
        checksum_path = f"{directory}/.cargo-checksum.json"
        manifest_path = f"{directory}/Cargo.toml"
        for required in (checksum_path, manifest_path):
            member = entries.get(required)
            if member is None or not member.isfile():
                raise VendorError(
                    f"offline vendor archive is missing regular file {required}"
                )

        checksum = json.loads(metadata[checksum_path].decode("utf-8"))
        if not isinstance(checksum, dict) or not isinstance(checksum.get("package"), str):
            raise VendorError(f"vendored checksum lacks package digest: {directory}")

        manifest = tomllib.loads(metadata[manifest_path].decode("utf-8"))
        package = manifest.get("package")
        if not isinstance(package, dict):
            raise VendorError(f"vendored Cargo.toml has no [package]: {directory}")
        name = package.get("name")
        version = package.get("version")
        if not isinstance(name, str) or not isinstance(version, str):
            raise VendorError(f"vendored Cargo.toml lacks name or version: {directory}")
        identity = (name, version)
        if identity in archived_packages:
            raise VendorError(f"duplicate vendored package identity: {name} {version}")
        archived_packages[identity] = (directory, checksum["package"])

    locked_packages = registry_packages(lock_path)

    expected_identities = set(locked_packages)
    archived_identities = set(archived_packages)
    if archived_identities != expected_identities:
        locked_versions: dict[str, set[str]] = {}
        archived_versions: dict[str, set[str]] = {}
        for name, version in expected_identities:
            locked_versions.setdefault(name, set()).add(version)
        for name, version in archived_identities:
            archived_versions.setdefault(name, set()).add(version)
        for name in sorted(locked_versions.keys() & archived_versions.keys()):
            if locked_versions[name] != archived_versions[name]:
                raise VendorError(f"offline vendor version differs from Cargo.lock: {name}")

        missing = sorted(expected_identities - archived_identities)
        extra = sorted(archived_identities - expected_identities)
        details = []
        if missing:
            details.append(
                "missing locked packages: "
                + ", ".join(f"{name} {version}" for name, version in missing)
            )
        if extra:
            details.append(
                "unexpected packages: "
                + ", ".join(f"{name} {version}" for name, version in extra)
            )
        raise VendorError("offline vendor package inventory differs; " + "; ".join(details))

    for identity, locked_checksum in locked_packages.items():
        directory, archived_checksum = archived_packages[identity]
        if archived_checksum != locked_checksum:
            raise VendorError(
                f"offline vendor checksum differs from Cargo.lock: {directory}"
            )


def check_repository(root: Path) -> None:
    rust = root / "r-package/dtaparser/src/rust"
    check_vendor_archive(
        rust / "vendor.tar.gz",
        rust / "vendor.sha256",
        rust / "Cargo.lock",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help=argparse.SUPPRESS,
    )
    arguments = parser.parse_args()

    try:
        check_repository(arguments.root.resolve())
    except (OSError, VendorError, tarfile.TarError, tomllib.TOMLDecodeError) as error:
        print(f"R Cargo vendor: FAIL: {error}", file=sys.stderr)
        return 1

    print("R Cargo vendor: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

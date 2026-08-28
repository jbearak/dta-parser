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

from archive_safety import (
    canonical_relative_path,
    parent_file_conflict,
    portable_extraction_key,
)

if sys.version_info < (3, 11):
    raise SystemExit("R Cargo vendor validation requires Python 3.11 or newer")

import tomllib


CRATES_IO_SOURCE = "registry+https://github.com/rust-lang/crates.io-index"
SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")


class VendorError(RuntimeError):
    """An offline Cargo vendor invariant failed."""


def unique_json_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_archive_digest(path: Path) -> str:
    try:
        lines = path.read_text(encoding="ascii").splitlines()
    except UnicodeDecodeError as error:
        raise VendorError(f"invalid vendor archive digest: {path}") from error
    if len(lines) != 1:
        raise VendorError("vendor.sha256 must contain exactly one entry")
    fields = lines[0].split()
    if (
        len(fields) != 2
        or SHA256_PATTERN.fullmatch(fields[0]) is None
        or fields[1] != "vendor.tar.gz"
    ):
        raise VendorError(f"malformed vendor archive digest: {lines[0]!r}")
    return fields[0]


def registry_packages(lock_path: Path) -> dict[tuple[str, str], str]:
    try:
        lock = tomllib.loads(lock_path.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError) as error:
        raise VendorError(f"invalid Cargo lock: {lock_path}") from error
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
        if not (
            isinstance(name, str)
            and isinstance(version, str)
            and isinstance(checksum, str)
        ):
            raise VendorError(
                f"registry package lacks name, version, or checksum: {lock_path}"
            )
        if SHA256_PATTERN.fullmatch(checksum) is None:
            raise VendorError(f"malformed registry package checksum: {name} {version}")
        identity = (name, version)
        if identity in registry:
            raise VendorError(f"duplicate locked registry package: {name} {version}")
        registry[identity] = checksum
    return registry


def check_vendor_archive(archive: Path, integrity_path: Path, lock_path: Path) -> None:
    expected_archive = read_archive_digest(integrity_path)
    if sha256_file(archive) != expected_archive:
        raise VendorError("offline vendor archive digest differs from vendor.sha256")

    entries: dict[str, bool] = {}
    extraction_names: dict[str, str] = {}
    package_file_digests: dict[str, dict[str, str]] = {}
    metadata: dict[str, bytes] = {}
    with tarfile.open(archive, mode="r|gz") as source:
        for member in source:
            name = member.name.removesuffix("/")
            relative = canonical_relative_path(name)
            if (
                relative is None
                or (name != "v" and not name.startswith("v/"))
            ):
                raise VendorError(
                    f"offline vendor archive has an unsafe path: {member.name}"
                )
            if not (member.isfile() or member.isdir()):
                raise VendorError(
                    f"offline vendor archive has a special entry: {member.name}"
                )
            if name in entries:
                raise VendorError(
                    f"offline vendor archive has a duplicate entry: {name}"
                )
            try:
                key = portable_extraction_key(relative)
            except ValueError as error:
                raise VendorError(
                    f"offline vendor archive has a non-portable path: {name}"
                ) from error
            alias = extraction_names.get(key)
            if alias is not None:
                raise VendorError(
                    f"offline vendor archive paths collide: {alias} and {name}"
                )
            entries[name] = member.isfile()
            extraction_names[key] = name

            if member.isfile():
                contents = source.extractfile(member)
                assert contents is not None
                is_package_metadata = len(relative.parts) == 3
                if is_package_metadata and relative.name == ".cargo-checksum.json":
                    metadata[name] = contents.read()
                    continue

                digest = hashlib.sha256()
                if is_package_metadata and relative.name == "Cargo.toml":
                    data = contents.read()
                    metadata[name] = data
                    digest.update(data)
                else:
                    while chunk := contents.read(1024 * 1024):
                        digest.update(chunk)
                if len(relative.parts) > 2:
                    directory = f"v/{relative.parts[1]}"
                    package_path = PurePosixPath(*relative.parts[2:]).as_posix()
                    package_file_digests.setdefault(directory, {})[
                        package_path
                    ] = digest.hexdigest()

    conflict = parent_file_conflict(entries)
    if conflict is not None:
        name, parent = conflict
        raise VendorError(f"offline vendor archive puts {name} below file {parent}")

    archived_packages: dict[tuple[str, str], tuple[str, str]] = {}
    archive_directories = sorted(
        {
            f"v/{name.split('/', 2)[1]}"
            for name in entries
            if name.startswith("v/")
        }
    )
    for directory in archive_directories:
        if entries.get(directory) is not False:
            raise VendorError(
                f"offline vendor archive is missing package directory {directory}"
            )
        checksum_path = f"{directory}/.cargo-checksum.json"
        manifest_path = f"{directory}/Cargo.toml"
        for required in (checksum_path, manifest_path):
            if entries.get(required) is not True:
                raise VendorError(
                    f"offline vendor archive is missing regular file {required}"
                )

        try:
            checksum = json.loads(
                metadata[checksum_path].decode("utf-8"),
                object_pairs_hook=unique_json_object,
            )
        except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
            raise VendorError(
                f"invalid vendored checksum metadata: {directory}"
            ) from error
        if not isinstance(checksum, dict) or not isinstance(
            checksum.get("package"), str
        ):
            raise VendorError(f"vendored checksum lacks package digest: {directory}")
        if SHA256_PATTERN.fullmatch(checksum["package"]) is None:
            raise VendorError(f"malformed vendored package checksum: {directory}")
        checksum_files = checksum.get("files")
        if not isinstance(checksum_files, dict):
            raise VendorError(f"vendored checksum lacks file digests: {directory}")
        for path, digest in checksum_files.items():
            if (
                not isinstance(path, str)
                or canonical_relative_path(path) is None
                or not isinstance(digest, str)
                or SHA256_PATTERN.fullmatch(digest) is None
            ):
                raise VendorError(f"invalid vendored file checksum: {directory}")

        archived_files = package_file_digests.pop(directory, {})
        if checksum_files.keys() != archived_files.keys():
            raise VendorError(f"vendored file inventory differs: {directory}")
        if any(
            archived_files[path] != digest
            for path, digest in checksum_files.items()
        ):
            raise VendorError(f"vendored file checksum differs: {directory}")

        try:
            manifest = tomllib.loads(metadata[manifest_path].decode("utf-8"))
        except (UnicodeDecodeError, tomllib.TOMLDecodeError) as error:
            raise VendorError(f"invalid vendored Cargo.toml: {directory}") from error
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
                raise VendorError(
                    f"offline vendor version differs from Cargo.lock: {name}"
                )

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
        raise VendorError(
            "offline vendor package inventory differs; " + "; ".join(details)
        )

    for identity, locked_checksum in locked_packages.items():
        directory, archived_checksum = archived_packages[identity]
        if archived_checksum != locked_checksum:
            raise VendorError(
                f"offline vendor checksum differs from Cargo.lock: {directory}"
            )


def check_repository(root: Path) -> None:
    rust = root / "r-package/dtatools/src/rust"
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
    except (OSError, VendorError, tarfile.TarError) as error:
        print(f"R Cargo vendor: FAIL: {error}", file=sys.stderr)
        return 1

    print("R Cargo vendor: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

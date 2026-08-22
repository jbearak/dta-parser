#!/usr/bin/env python3
"""Mutation tests for the R package's offline Cargo dependency archive."""

from __future__ import annotations

import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("check_r_cargo_vendor.py")
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("check_r_cargo_vendor", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
vendor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(vendor)


class VendorFixture:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.rust = root / "r-package/dtaparser/src/rust"
        self.archive = self.rust / "vendor.tar.gz"
        self.integrity = self.rust / "vendor.sha256"
        self.lock = self.rust / "Cargo.lock"
        self.rust.mkdir(parents=True)
        self.lock.write_text(
            f"""\
version = 3

[[package]]
name = "dtaparser-r"
version = "0.1.0"

[[package]]
name = "encoding_rs"
version = "1.0.0"
source = "{vendor.CRATES_IO_SOURCE}"
checksum = "0000000000000000000000000000000000000000000000000000000000000000"

[[package]]
name = "serde"
version = "1.0.0"
source = "{vendor.CRATES_IO_SOURCE}"
checksum = "1111111111111111111111111111111111111111111111111111111111111111"
""",
            encoding="utf-8",
        )
        self.write_archive()

    def write_archive(
        self,
        packages: tuple[tuple[str, str, str, str], ...] | None = None,
        checksum_contents: bytes | None = None,
        manifest_contents: bytes | None = None,
        member_overrides: dict[str, tarfile.TarInfo] | None = None,
    ) -> None:
        if packages is None:
            packages = (
                ("encoding_rs", "encoding_rs", "1.0.0", "0" * 64),
                ("serde", "serde", "1.0.0", "1" * 64),
            )
        overrides = member_overrides or {}
        with tarfile.open(self.archive, mode="w:gz") as archive:

            def add_member(
                name: str,
                *,
                contents: bytes | None = None,
                directory: bool = False,
            ) -> None:
                member = overrides.get(name, tarfile.TarInfo(name))
                if name not in overrides and directory:
                    member.type = tarfile.DIRTYPE
                if member.isfile():
                    data = contents or b""
                    member.size = len(data)
                    archive.addfile(member, io.BytesIO(data))
                else:
                    archive.addfile(member)

            add_member("v", directory=True)
            for directory_name, package_name, version, checksum_value in packages:
                directory = f"v/{directory_name}"
                add_member(directory, directory=True)

                manifest_data = (
                    manifest_contents
                    if manifest_contents is not None
                    else (
                        f'[package]\nname = "{package_name}"\nversion = "{version}"\n'
                    ).encode("utf-8")
                )
                package_checksum = (
                    checksum_contents
                    if checksum_contents is not None
                    else json.dumps(
                        {
                            "files": {
                                "Cargo.toml": hashlib.sha256(
                                    manifest_data
                                ).hexdigest()
                            },
                            "package": checksum_value,
                        },
                        separators=(",", ":"),
                    ).encode("utf-8")
                )
                add_member(
                    f"{directory}/.cargo-checksum.json",
                    contents=package_checksum,
                )
                add_member(f"{directory}/Cargo.toml", contents=manifest_data)
        self.refresh_integrity()

    def write_members(self, members: tuple[tarfile.TarInfo, ...]) -> None:
        with tarfile.open(self.archive, mode="w:gz") as archive:
            for member in members:
                if member.isfile():
                    member.size = 0
                    archive.addfile(member, io.BytesIO())
                else:
                    archive.addfile(member)
        self.refresh_integrity()

    def refresh_integrity(self) -> None:
        self.integrity.write_text(
            f"{vendor.sha256_file(self.archive)}  vendor.tar.gz\n",
            encoding="ascii",
        )


class CargoVendorTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.fixture = VendorFixture(Path(temporary.name))

    def check(self) -> None:
        vendor.check_repository(self.fixture.root)

    def test_matching_archive_and_lock_pass(self) -> None:
        self.check()

    def test_multiple_locked_versions_of_one_package_pass(self) -> None:
        with self.fixture.lock.open("a", encoding="utf-8") as lock:
            lock.write(
                f"""\

[[package]]
name = "serde"
version = "2.0.0"
source = "{vendor.CRATES_IO_SOURCE}"
checksum = "2222222222222222222222222222222222222222222222222222222222222222"
"""
            )
        self.fixture.write_archive(
            (
                ("encoding_rs", "encoding_rs", "1.0.0", "0" * 64),
                ("serde", "serde", "1.0.0", "1" * 64),
                ("serde-2.0.0", "serde", "2.0.0", "2" * 64),
            )
        )
        self.check()

    def test_non_crates_io_dependency_sources_fail_clearly(self) -> None:
        self.fixture.lock.write_text(
            self.fixture.lock.read_text().replace(
                vendor.CRATES_IO_SOURCE,
                "git+https://example.test/dependency#0123456789abcdef",
                1,
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(
            vendor.VendorError, "unsupported Cargo dependency source"
        ):
            self.check()

    def test_integrity_file_must_contain_one_archive_digest(self) -> None:
        first = self.fixture.integrity.read_text(encoding="ascii").splitlines()[0]
        with self.fixture.integrity.open("a", encoding="ascii") as destination:
            destination.write(f"{first}\n")
        with self.assertRaisesRegex(vendor.VendorError, "exactly one entry"):
            self.check()

    def test_archive_digest_must_match_integrity_file(self) -> None:
        self.fixture.integrity.write_text(
            f"{'f' * 64}  vendor.tar.gz\n",
            encoding="ascii",
        )
        with self.assertRaisesRegex(vendor.VendorError, "archive digest differs"):
            self.check()

    def test_malformed_checksum_metadata_fails_clearly(self) -> None:
        for contents in (b"{", b"\xff"):
            with self.subTest(contents=contents):
                self.fixture.write_archive(checksum_contents=contents)
                with self.assertRaisesRegex(
                    vendor.VendorError, "invalid vendored checksum metadata"
                ):
                    self.check()

    def test_malformed_manifest_fails_clearly(self) -> None:
        for contents in (b"[package", b"\xff"):
            with self.subTest(contents=contents):
                self.fixture.write_archive(manifest_contents=contents)
                with self.assertRaisesRegex(
                    vendor.VendorError, "invalid vendored Cargo.toml"
                ):
                    self.check()

    def test_malformed_lock_fails_clearly(self) -> None:
        for contents in (b"[[package]", b"\xff"):
            with self.subTest(contents=contents):
                self.fixture.lock.write_bytes(contents)
                with self.assertRaisesRegex(vendor.VendorError, "invalid Cargo lock"):
                    self.check()

    def test_archive_inventory_must_match_the_bridge_lock(self) -> None:
        with self.fixture.lock.open("a", encoding="utf-8") as lock:
            lock.write(
                f"""\

[[package]]
name = "cfg-if"
version = "1.0.0"
source = "{vendor.CRATES_IO_SOURCE}"
checksum = "2222222222222222222222222222222222222222222222222222222222222222"
"""
            )
        with self.assertRaisesRegex(
            vendor.VendorError, "missing locked packages: cfg-if"
        ):
            self.check()

    def test_archive_must_not_contain_unlocked_packages(self) -> None:
        self.fixture.write_archive(
            (
                ("cfg-if", "cfg-if", "1.0.0", "2" * 64),
                ("encoding_rs", "encoding_rs", "1.0.0", "0" * 64),
                ("serde", "serde", "1.0.0", "1" * 64),
            )
        )
        with self.assertRaisesRegex(
            vendor.VendorError, "unexpected packages: cfg-if 1.0.0"
        ):
            self.check()

    def test_archive_version_must_match_the_bridge_lock(self) -> None:
        self.fixture.lock.write_text(
            self.fixture.lock.read_text().replace(
                'name = "serde"\nversion = "1.0.0"',
                'name = "serde"\nversion = "1.0.1"',
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(vendor.VendorError, "vendor version differs"):
            self.check()

    def test_archive_checksum_must_match_the_bridge_lock(self) -> None:
        self.fixture.lock.write_text(
            self.fixture.lock.read_text().replace(
                'checksum = "' + "1" * 64,
                'checksum = "' + "2" * 64,
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(vendor.VendorError, "vendor checksum differs"):
            self.check()

    def test_locked_checksum_must_be_lowercase_sha256(self) -> None:
        original = self.fixture.lock.read_text(encoding="utf-8")
        for malformed in ("0" * 63, "A" * 64, "g" * 64):
            with self.subTest(malformed=malformed):
                self.fixture.lock.write_text(
                    original.replace("0" * 64, malformed, 1),
                    encoding="utf-8",
                )
                with self.assertRaisesRegex(
                    vendor.VendorError, "malformed registry package checksum"
                ):
                    self.check()

    def test_archived_checksum_must_be_lowercase_sha256(self) -> None:
        for malformed in ("0" * 63, "A" * 64, "g" * 64):
            with self.subTest(malformed=malformed):
                self.fixture.write_archive(
                    (
                        ("encoding_rs", "encoding_rs", "1.0.0", malformed),
                        ("serde", "serde", "1.0.0", "1" * 64),
                    )
                )
                with self.assertRaisesRegex(
                    vendor.VendorError, "malformed vendored package checksum"
                ):
                    self.check()

    def test_vendored_file_inventory_and_digests_must_match(self) -> None:
        for files, message in (
            ({}, "file inventory differs"),
            ({"Cargo.toml": "f" * 64}, "file checksum differs"),
            ({"../Cargo.toml": "f" * 64}, "invalid vendored file checksum"),
        ):
            with self.subTest(message=message):
                self.fixture.write_archive(
                    checksum_contents=json.dumps(
                        {"files": files, "package": "0" * 64}
                    ).encode("utf-8")
                )
                with self.assertRaisesRegex(vendor.VendorError, message):
                    self.check()

    def test_duplicate_checksum_metadata_keys_fail(self) -> None:
        self.fixture.write_archive(
            checksum_contents=(
                b'{"files":{},"files":{},"package":"'
                + b"0" * 64
                + b'"}'
            )
        )
        with self.assertRaisesRegex(
            vendor.VendorError, "invalid vendored checksum metadata"
        ):
            self.check()

    def test_archive_members_must_be_canonical_and_beneath_vendor_root(self) -> None:
        for name in (
            "Cargo.toml",
            "v//",
            "v/serde/./Cargo.toml",
            "v//serde/Cargo.toml",
        ):
            with self.subTest(name=name):
                self.fixture.write_members((tarfile.TarInfo(name),))
                with self.assertRaisesRegex(vendor.VendorError, "unsafe path"):
                    self.check()

    def test_archive_rejects_cross_platform_path_aliases(self) -> None:
        for names in (
            ("v/serde", "v/SERDE"),
            (
                "v/caf\N{LATIN SMALL LETTER E WITH ACUTE}",
                "v/cafe\N{COMBINING ACUTE ACCENT}",
            ),
        ):
            with self.subTest(names=names):
                members = tuple(tarfile.TarInfo(name) for name in names)
                for member in members:
                    member.type = tarfile.DIRTYPE
                self.fixture.write_members(members)
                with self.assertRaisesRegex(vendor.VendorError, "paths collide"):
                    self.check()

    def test_package_roots_must_be_explicit_directories(self) -> None:
        root = tarfile.TarInfo("v")
        root.type = tarfile.DIRTYPE
        self.fixture.write_members((root, tarfile.TarInfo("v/unexpected/payload")))
        with self.assertRaisesRegex(vendor.VendorError, "missing package directory"):
            self.check()

    def test_archive_rejects_special_and_duplicate_entries(self) -> None:
        for mode in ("special", "duplicate"):
            with self.subTest(mode=mode):
                member = tarfile.TarInfo("v/member")
                if mode == "special":
                    member.type = tarfile.SYMTYPE
                    member.linkname = "target"
                    members = (member,)
                else:
                    members = (member, member)
                self.fixture.write_members(members)
                with self.assertRaisesRegex(vendor.VendorError, f"{mode} entry"):
                    self.check()

    def test_archive_parent_file_conflict_fails(self) -> None:
        self.fixture.write_members(
            tuple(
                tarfile.TarInfo(name)
                for name in (
                    "v/encoding_rs/.cargo-checksum.json",
                    "v/serde",
                    "v/serde/.cargo-checksum.json",
                )
            )
        )
        with self.assertRaisesRegex(vendor.VendorError, "below file v/serde"):
            self.check()

    def test_required_checksum_must_be_a_regular_file(self) -> None:
        path = "v/serde/.cargo-checksum.json"
        directory = tarfile.TarInfo(path)
        directory.type = tarfile.DIRTYPE
        self.fixture.write_archive(member_overrides={path: directory})
        with self.assertRaisesRegex(
            vendor.VendorError,
            r"missing regular file v/serde/\.cargo-checksum\.json",
        ):
            self.check()


if __name__ == "__main__":
    unittest.main()

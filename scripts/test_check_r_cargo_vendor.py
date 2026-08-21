#!/usr/bin/env python3
"""Mutation tests for the R package's offline Cargo dependency archive."""

from __future__ import annotations

import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("check_r_cargo_vendor.py")
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
    ) -> None:
        if packages is None:
            packages = (
                ("encoding_rs", "encoding_rs", "1.0.0", "0" * 64),
                ("serde", "serde", "1.0.0", "1" * 64),
            )
        with tarfile.open(self.archive, mode="w:gz") as archive:
            root = tarfile.TarInfo("v")
            root.type = tarfile.DIRTYPE
            archive.addfile(root)
            for directory_name, package_name, version, checksum_value in packages:
                directory = tarfile.TarInfo(f"v/{directory_name}")
                directory.type = tarfile.DIRTYPE
                archive.addfile(directory)

                checksum_contents = json.dumps(
                    {"files": {}, "package": checksum_value}, separators=(",", ":")
                ).encode("utf-8")
                checksum = tarfile.TarInfo(
                    f"v/{directory_name}/.cargo-checksum.json"
                )
                checksum.size = len(checksum_contents)
                archive.addfile(checksum, io.BytesIO(checksum_contents))

                manifest_contents = (
                    f'[package]\nname = "{package_name}"\nversion = "{version}"\n'
                ).encode("utf-8")
                manifest = tarfile.TarInfo(f"v/{directory_name}/Cargo.toml")
                manifest.size = len(manifest_contents)
                archive.addfile(manifest, io.BytesIO(manifest_contents))
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
        with self.assertRaisesRegex(vendor.VendorError, "unsupported Cargo dependency source"):
            self.check()

    def test_integrity_file_must_contain_one_archive_digest(self) -> None:
        first = self.fixture.integrity.read_text(encoding="ascii").splitlines()[0]
        with self.fixture.integrity.open("a", encoding="ascii") as destination:
            destination.write(f"{first}\n")
        with self.assertRaisesRegex(vendor.VendorError, "exactly one entry"):
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
        with self.assertRaisesRegex(vendor.VendorError, "missing locked packages: cfg-if"):
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

    def test_archive_parent_file_conflict_fails(self) -> None:
        with tarfile.open(self.fixture.archive, mode="w:gz") as archive:
            for name in ("v/encoding_rs/.cargo-checksum.json", "v/serde"):
                member = tarfile.TarInfo(name)
                member.size = 2
                archive.addfile(member, io.BytesIO(b"{}"))
            child = tarfile.TarInfo("v/serde/.cargo-checksum.json")
            child.size = 2
            archive.addfile(child, io.BytesIO(b"{}"))
        self.fixture.refresh_integrity()
        with self.assertRaisesRegex(vendor.VendorError, "below file v/serde"):
            self.check()

    def test_required_checksum_must_be_a_regular_file(self) -> None:
        with tarfile.open(self.fixture.archive, mode="w:gz") as archive:
            for name in ("v", "v/encoding_rs", "v/serde"):
                directory = tarfile.TarInfo(name)
                directory.type = tarfile.DIRTYPE
                archive.addfile(directory)
            regular = tarfile.TarInfo("v/encoding_rs/.cargo-checksum.json")
            regular.size = 2
            archive.addfile(regular, io.BytesIO(b"{}"))
            directory = tarfile.TarInfo("v/serde/.cargo-checksum.json")
            directory.type = tarfile.DIRTYPE
            archive.addfile(directory)
        self.fixture.refresh_integrity()
        with self.assertRaisesRegex(vendor.VendorError, "missing regular file"):
            self.check()


if __name__ == "__main__":
    unittest.main()

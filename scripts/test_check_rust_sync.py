#!/usr/bin/env python3
"""Mutation tests for the Rust/R runtime-tree pinning contract."""

from __future__ import annotations

import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("check_rust_sync.py")
SPEC = importlib.util.spec_from_file_location("check_rust_sync", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
sync = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync)


ROOT_MANIFEST = """\
[workspace]
members = ["rust/dta-parser"]
resolver = "2"

[workspace.package]
edition = "2021"
license = "GPL-3.0-only"
rust-version = "1.74"
"""

CANONICAL_MANIFEST = """\
[package]
name = "dta-parser"
version = "0.1.0"
description = "test parser"
edition.workspace = true
license.workspace = true
rust-version.workspace = true
repository = "https://example.test/parser"
readme = "README.md"
exclude = ["tests/**"]

[dependencies]
serde = { version = "1.0", features = ["derive"] }
"""

MIRROR_MANIFEST = """\
[package]
name = "dta-parser"
version = "0.1.0"
description = "test parser"
edition = "2021"
license = "GPL-3.0-only"
rust-version = "1.74"
repository = "https://example.test/parser"
readme = "README.md"
publish = false

[dependencies]
serde = { features = ["derive"], version = "1.0" }

[workspace]
"""


class RepositoryFixture:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.canonical = root / "rust/dta-parser"
        self.mirror = root / "r-package/dtaparser/src/vendor/dta-parser"
        self.canonical_pin = root / "rust/dta-parser.tree.sha256"
        self.mirror_pin = root / "r-package/dtaparser/src/vendor/dta-parser.tree.sha256"
        self.archive = root / "r-package/dtaparser/src/rust/vendor.tar.gz"
        self.integrity = root / "r-package/dtaparser/src/rust/vendor.sha256"
        self.bridge_lock = root / "r-package/dtaparser/src/rust/Cargo.lock"

        (root / "Cargo.toml").parent.mkdir(parents=True, exist_ok=True)
        (root / "Cargo.toml").write_text(ROOT_MANIFEST, encoding="utf-8")
        (root / "Cargo.lock").write_text("lock\n", encoding="utf-8")
        for crate, manifest in (
            (self.canonical, CANONICAL_MANIFEST),
            (self.mirror, MIRROR_MANIFEST),
        ):
            (crate / "src/nested").mkdir(parents=True, exist_ok=True)
            (crate / "Cargo.toml").write_text(manifest, encoding="utf-8")
            (crate / "README.md").write_text("readme\n", encoding="utf-8")
            (crate / "LICENSE").write_text("license\n", encoding="utf-8")
            (crate / "src/lib.rs").write_text("pub mod nested;\n", encoding="utf-8")
            (crate / "src/nested/data.bin").write_bytes(b"\x00runtime\xff")
        (self.mirror / "Cargo.lock").write_text("lock\n", encoding="utf-8")
        make_sources = """\
RUST_SOURCES = rust/src/lib.rs \\
\tvendor/dta-parser/src/lib.rs \\
\tvendor/dta-parser/src/nested/data.bin
"""
        make_root = root / "r-package/dtaparser/src"
        for name in ("Makevars.in", "Makevars.win.in"):
            (make_root / name).write_text(make_sources, encoding="utf-8")
        self.bridge_lock.parent.mkdir(parents=True, exist_ok=True)
        self.bridge_lock.write_text(
            """\
version = 3

[[package]]
name = "encoding_rs"
version = "1.0.0"
source = "registry+https://example.test/index"
checksum = "0000000000000000000000000000000000000000000000000000000000000000"

[[package]]
name = "serde"
version = "1.0.0"
source = "registry+https://example.test/index"
checksum = "1111111111111111111111111111111111111111111111111111111111111111"
""",
            encoding="utf-8",
        )
        self._write_archive()
        sync.check_repository(root, update_pins=True)

    def _write_archive(self) -> None:
        self.archive.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(self.archive, mode="w:gz") as archive:
            root = tarfile.TarInfo("v")
            root.type = tarfile.DIRTYPE
            archive.addfile(root)
            for package, checksum_value in (
                ("encoding_rs", "0" * 64),
                ("serde", "1" * 64),
            ):
                directory = tarfile.TarInfo(f"v/{package}")
                directory.type = tarfile.DIRTYPE
                archive.addfile(directory)

                checksum_contents = json.dumps(
                    {"files": {}, "package": checksum_value}, separators=(",", ":")
                ).encode("utf-8")
                checksum = tarfile.TarInfo(f"v/{package}/.cargo-checksum.json")
                checksum.size = len(checksum_contents)
                archive.addfile(checksum, io.BytesIO(checksum_contents))

                manifest_contents = (
                    f'[package]\nname = "{package}"\nversion = "1.0.0"\n'
                ).encode("utf-8")
                manifest = tarfile.TarInfo(f"v/{package}/Cargo.toml")
                manifest.size = len(manifest_contents)
                archive.addfile(manifest, io.BytesIO(manifest_contents))
        self.refresh_integrity()

    def refresh_integrity(self) -> None:
        with tarfile.open(self.archive, mode="r:gz") as archive:
            rendered = [
                f"{member.name}{'/' if member.isdir() and not member.name.endswith('/') else ''}"
                for member in archive.getmembers()
            ]
        listing = "".join(f"{name}\n" for name in sorted(rendered)).encode("utf-8")
        self.integrity.write_text(
            f"{sync.sha256_file(self.archive)}  vendor.tar.gz\n"
            f"{hashlib.sha256(listing).hexdigest()}  vendor-file-list\n",
            encoding="ascii",
        )

    def refresh_pins(self) -> None:
        canonical_manifest = sync.normalized_manifest(
            self.root / "Cargo.toml", self.canonical / "Cargo.toml", mirror=False
        )
        mirror_manifest = sync.normalized_manifest(
            self.root / "Cargo.toml", self.mirror / "Cargo.toml", mirror=True
        )
        self.canonical_pin.write_text(
            sync.format_pin(sync.runtime_tree_digest(self.canonical, canonical_manifest)),
            encoding="ascii",
        )
        self.mirror_pin.write_text(
            sync.format_pin(sync.runtime_tree_digest(self.mirror, mirror_manifest)),
            encoding="ascii",
        )


class RustSyncTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.fixture = RepositoryFixture(Path(temporary.name))

    def test_equal_trees_and_intentional_manifest_differences_pass(self) -> None:
        digest = sync.check_repository(self.fixture.root)
        self.assertRegex(digest, r"^[0-9a-f]{64}$")
        self.assertEqual(sync.read_pin(self.fixture.canonical_pin), digest)
        self.assertEqual(sync.read_pin(self.fixture.mirror_pin), digest)

    def test_canonical_only_source_change_fails_even_with_refreshed_pins(self) -> None:
        (self.fixture.canonical / "src/lib.rs").write_text(
            "pub mod changed;\n", encoding="utf-8"
        )
        self.fixture.refresh_pins()
        with self.assertRaisesRegex(sync.SyncError, "runtime source differs"):
            sync.check_repository(self.fixture.root)

    def test_mirror_only_nested_file_fails_inventory_check(self) -> None:
        (self.fixture.mirror / "src/nested/extra.rs").write_text("// extra\n")
        with self.assertRaisesRegex(sync.SyncError, "extra in R mirror"):
            sync.check_repository(self.fixture.root)

    def test_canonical_only_build_script_fails_inventory_check(self) -> None:
        (self.fixture.canonical / "build.rs").write_text("fn main() {}\n")
        with self.assertRaisesRegex(sync.SyncError, "missing from R mirror: build.rs"):
            sync.check_repository(self.fixture.root)

    def test_semantic_manifest_drift_fails(self) -> None:
        manifest = self.fixture.mirror / "Cargo.toml"
        manifest.write_text(
            manifest.read_text().replace('version = "1.0"', 'version = "1.1"'),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(sync.SyncError, "Cargo.toml semantics differ"):
            sync.check_repository(self.fixture.root)

    def test_toml_formatting_does_not_change_the_pin(self) -> None:
        before = sync.read_pin(self.fixture.mirror_pin)
        manifest = self.fixture.mirror / "Cargo.toml"
        manifest.write_text(
            manifest.read_text().replace(
                'serde = { features = ["derive"], version = "1.0" }',
                'serde={version="1.0",features=["derive"]}',
            ),
            encoding="utf-8",
        )
        self.assertEqual(sync.check_repository(self.fixture.root), before)

    def test_unexpected_manifest_exception_fails(self) -> None:
        manifest = self.fixture.mirror / "Cargo.toml"
        manifest.write_text(
            manifest.read_text().replace("publish = false", "publish = true"),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(sync.SyncError, "publish = false"):
            sync.check_repository(self.fixture.root)

    def test_stale_and_disagreeing_pins_fail(self) -> None:
        self.fixture.canonical_pin.write_text(
            sync.format_pin("0" * 64), encoding="ascii"
        )
        with self.assertRaisesRegex(sync.SyncError, "tree pins differ"):
            sync.check_repository(self.fixture.root)

        self.fixture.mirror_pin.write_text(sync.format_pin("0" * 64), encoding="ascii")
        with self.assertRaisesRegex(sync.SyncError, "pins are stale"):
            sync.check_repository(self.fixture.root)

    def test_malformed_pin_fails(self) -> None:
        self.fixture.mirror_pin.write_text("not-a-pin\n", encoding="ascii")
        with self.assertRaisesRegex(sync.SyncError, "malformed Rust tree pin"):
            sync.check_repository(self.fixture.root)

    def test_make_source_inventory_cannot_omit_runtime_inputs(self) -> None:
        makevars = self.fixture.root / "r-package/dtaparser/src/Makevars.win.in"
        makevars.write_text(
            makevars.read_text().replace(
                " \\\n\tvendor/dta-parser/src/nested/data.bin", ""
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(sync.SyncError, "RUST_SOURCES"):
            sync.check_repository(self.fixture.root)

    def test_update_pins_waits_for_all_other_invariants(self) -> None:
        canonical_before = self.fixture.canonical_pin.read_bytes()
        mirror_before = self.fixture.mirror_pin.read_bytes()
        (self.fixture.mirror / "README.md").write_text("different\n")
        with self.assertRaisesRegex(sync.SyncError, "crate README differs"):
            sync.check_repository(self.fixture.root, update_pins=True)
        self.assertEqual(self.fixture.canonical_pin.read_bytes(), canonical_before)
        self.assertEqual(self.fixture.mirror_pin.read_bytes(), mirror_before)

    def test_duplicate_integrity_labels_fail(self) -> None:
        first = self.fixture.integrity.read_text(encoding="ascii").splitlines()[0]
        with self.fixture.integrity.open("a", encoding="ascii") as destination:
            destination.write(f"{first}\n")
        with self.assertRaisesRegex(sync.SyncError, "duplicate integrity entry"):
            sync.check_repository(self.fixture.root)

    def test_archive_inventory_must_match_the_bridge_lock(self) -> None:
        with self.fixture.bridge_lock.open("a", encoding="utf-8") as lock:
            lock.write(
                """\

[[package]]
name = "cfg-if"
version = "1.0.0"
source = "registry+https://example.test/index"
checksum = "2222222222222222222222222222222222222222222222222222222222222222"
"""
            )
        with self.assertRaisesRegex(sync.SyncError, "missing locked packages: cfg-if"):
            sync.check_repository(self.fixture.root)

    def test_archive_version_must_match_the_bridge_lock(self) -> None:
        lock = self.fixture.bridge_lock
        lock.write_text(
            lock.read_text().replace(
                'name = "serde"\nversion = "1.0.0"',
                'name = "serde"\nversion = "1.0.1"',
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(sync.SyncError, "vendor version differs"):
            sync.check_repository(self.fixture.root)

    def test_archive_checksum_must_match_the_bridge_lock(self) -> None:
        lock = self.fixture.bridge_lock
        lock.write_text(
            lock.read_text().replace('checksum = "' + "1" * 64, 'checksum = "' + "2" * 64),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(sync.SyncError, "vendor checksum differs"):
            sync.check_repository(self.fixture.root)

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
        with self.assertRaisesRegex(sync.SyncError, "below file v/serde"):
            sync.check_repository(self.fixture.root)

    def test_required_archive_checksum_must_be_a_regular_file(self) -> None:
        with tarfile.open(self.fixture.archive, mode="w:gz") as archive:
            for name in ("v", "v/encoding_rs", "v/serde"):
                package = tarfile.TarInfo(name)
                package.type = tarfile.DIRTYPE
                archive.addfile(package)
            regular = tarfile.TarInfo("v/encoding_rs/.cargo-checksum.json")
            regular.size = 2
            archive.addfile(regular, io.BytesIO(b"{}"))
            directory = tarfile.TarInfo("v/serde/.cargo-checksum.json")
            directory.type = tarfile.DIRTYPE
            archive.addfile(directory)
        self.fixture.refresh_integrity()
        with self.assertRaisesRegex(sync.SyncError, "missing regular file"):
            sync.check_repository(self.fixture.root)

    def test_framing_distinguishes_path_and_content_boundaries(self) -> None:
        left = sync.framed_digest([("a", b"bc"), ("d", b"")])
        right = sync.framed_digest([("ab", b"c"), ("d", b"")])
        self.assertNotEqual(left, right)


if __name__ == "__main__":
    unittest.main()

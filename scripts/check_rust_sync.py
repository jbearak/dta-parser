#!/usr/bin/env python3
"""Validate the canonical Rust parser and the R-package mirror."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tarfile
import tempfile
import tomllib
from typing import Iterable


PIN_SCHEMA = "dta-parser-runtime-tree-v1"
PIN_PATTERN = re.compile(rf"([0-9a-f]{{64}})  {re.escape(PIN_SCHEMA)}\n?\Z")


class SyncError(RuntimeError):
    """A checked Rust/R synchronization invariant failed."""


def normalized_manifest(
    workspace_manifest: Path, crate_manifest: Path, *, mirror: bool
) -> dict[str, object]:
    workspace = tomllib.loads(workspace_manifest.read_text(encoding="utf-8"))
    manifest = copy.deepcopy(
        tomllib.loads(crate_manifest.read_text(encoding="utf-8"))
    )
    package = manifest.get("package")
    if not isinstance(package, dict):
        raise SyncError(f"missing [package] table: {crate_manifest}")

    if mirror:
        if package.pop("publish", None) is not False:
            raise SyncError("R mirror must set package.publish = false")
        if manifest.pop("workspace", None) != {}:
            raise SyncError("R mirror must contain an empty [workspace] table")
    else:
        workspace_package = workspace.get("workspace", {}).get("package", {})
        if not isinstance(workspace_package, dict):
            raise SyncError("root manifest must contain [workspace.package]")
        for field in ("edition", "license", "rust-version"):
            if package.get(field) != {"workspace": True}:
                raise SyncError(
                    f"canonical package.{field} must inherit from the workspace"
                )
            try:
                package[field] = workspace_package[field]
            except KeyError as error:
                raise SyncError(
                    f"root [workspace.package] is missing {field}"
                ) from error
        if package.pop("exclude", None) != ["tests/**"]:
            raise SyncError(
                'canonical package.exclude must be exactly ["tests/**"]'
            )

    return manifest


def source_files(crate: Path) -> list[Path]:
    source_root = crate / "src"
    files: list[Path] = []
    for path in source_root.rglob("*"):
        if path.is_symlink():
            raise SyncError(f"runtime source tree contains a symlink: {path}")
        if path.is_dir():
            continue
        if not path.is_file():
            raise SyncError(f"runtime source tree contains a non-file: {path}")
        files.append(path.relative_to(crate))

    build_script = crate / "build.rs"
    if build_script.is_symlink():
        raise SyncError(f"runtime source tree contains a symlink: {build_script}")
    if build_script.exists():
        if not build_script.is_file():
            raise SyncError(f"runtime source tree contains a non-file: {build_script}")
        files.append(Path("build.rs"))

    return sorted(files, key=lambda item: item.as_posix())


def framed_digest(entries: Iterable[tuple[str, bytes]]) -> str:
    digest = hashlib.sha256()
    digest.update(PIN_SCHEMA.encode("ascii") + b"\0")
    for relative, contents in entries:
        path = relative.encode("utf-8")
        digest.update(path + b"\0")
        digest.update(str(len(contents)).encode("ascii") + b"\0")
        digest.update(contents)
    return digest.hexdigest()


def runtime_tree_digest(crate: Path, manifest: dict[str, object]) -> str:
    normalized = json.dumps(
        manifest, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")
    entries = [("Cargo.toml.normalized.json", normalized)]
    entries.extend(
        (relative.as_posix(), (crate / relative).read_bytes())
        for relative in source_files(crate)
    )
    return framed_digest(entries)


def format_pin(digest: str) -> str:
    return f"{digest}  {PIN_SCHEMA}\n"


def stage_bytes(path: Path, contents: bytes) -> Path:
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary)
    try:
        with os.fdopen(descriptor, "wb") as destination:
            destination.write(contents)
            destination.flush()
            os.fsync(destination.fileno())
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise
    return temporary_path


def atomic_write_bytes(path: Path, contents: bytes) -> None:
    temporary = stage_bytes(path, contents)
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def write_pin_pair(paths: tuple[Path, Path], digest: str) -> None:
    contents = format_pin(digest).encode("ascii")
    originals = [path.read_bytes() if path.exists() else None for path in paths]
    staged = [stage_bytes(path, contents) for path in paths]
    replaced = 0
    try:
        for path, temporary in zip(paths, staged, strict=True):
            os.replace(temporary, path)
            replaced += 1
    except BaseException:
        for path, original in zip(paths[:replaced], originals[:replaced], strict=True):
            if original is None:
                path.unlink(missing_ok=True)
            else:
                atomic_write_bytes(path, original)
        raise
    finally:
        for temporary in staged:
            temporary.unlink(missing_ok=True)


def read_pin(path: Path) -> str:
    match = PIN_PATTERN.fullmatch(path.read_text(encoding="ascii"))
    if match is None:
        raise SyncError(f"malformed Rust tree pin: {path}")
    return match.group(1)


def compare_runtime_sources(canonical: Path, mirror: Path) -> None:
    canonical_files = source_files(canonical)
    mirror_files = source_files(mirror)
    if canonical_files != mirror_files:
        canonical_names = {path.as_posix() for path in canonical_files}
        mirror_names = {path.as_posix() for path in mirror_files}
        missing = sorted(canonical_names - mirror_names)
        extra = sorted(mirror_names - canonical_names)
        details = []
        if missing:
            details.append(f"missing from R mirror: {', '.join(missing)}")
        if extra:
            details.append(f"extra in R mirror: {', '.join(extra)}")
        raise SyncError("runtime source inventory differs; " + "; ".join(details))

    for relative in canonical_files:
        if (canonical / relative).read_bytes() != (mirror / relative).read_bytes():
            raise SyncError(f"runtime source differs: {relative.as_posix()}")


def make_variable_values(path: Path, variable: str) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    prefix = f"{variable} ="
    for index, line in enumerate(lines):
        if not line.startswith(prefix):
            continue
        parts: list[str] = []
        fragment = line[len(prefix) :].strip()
        while True:
            continued = fragment.endswith("\\")
            if continued:
                fragment = fragment[:-1].strip()
            parts.extend(fragment.split())
            if not continued:
                return parts
            index += 1
            if index >= len(lines):
                raise SyncError(f"unterminated {variable} in {path}")
            fragment = lines[index].strip()
    raise SyncError(f"missing {variable} in {path}")


def check_make_source_inventories(root: Path, mirror: Path) -> None:
    expected = ["rust/src/lib.rs"] + [
        f"vendor/dta-parser/{relative.as_posix()}" for relative in source_files(mirror)
    ]
    for name in ("Makevars.in", "Makevars.win.in"):
        path = root / "r-package/dtaparser/src" / name
        actual = make_variable_values(path, "RUST_SOURCES")
        if actual != expected:
            raise SyncError(f"{name} RUST_SOURCES does not match the runtime tree")


def require_equal(canonical: Path, mirror: Path, label: str) -> None:
    if canonical.read_bytes() != mirror.read_bytes():
        raise SyncError(f"{label} differs: {canonical} != {mirror}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_integrity_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="ascii").splitlines():
        fields = line.split()
        if len(fields) != 2 or not re.fullmatch(r"[0-9a-f]{64}", fields[0]):
            raise SyncError(f"malformed integrity entry: {line!r}")
        if fields[1] in values:
            raise SyncError(f"duplicate integrity entry: {fields[1]}")
        values[fields[1]] = fields[0]
    return values


def registry_packages(lock_path: Path) -> dict[str, tuple[str, str]]:
    lock = tomllib.loads(lock_path.read_text(encoding="utf-8"))
    packages = lock.get("package")
    if not isinstance(packages, list):
        raise SyncError(f"Cargo lock has no [[package]] entries: {lock_path}")

    registry: dict[str, tuple[str, str]] = {}
    for package in packages:
        if not isinstance(package, dict):
            raise SyncError(f"malformed Cargo package entry: {lock_path}")
        source = package.get("source")
        if not isinstance(source, str) or not source.startswith("registry+"):
            continue
        name = package.get("name")
        version = package.get("version")
        checksum = package.get("checksum")
        if not all(isinstance(value, str) for value in (name, version, checksum)):
            raise SyncError(
                f"registry package lacks name, version, or checksum: {lock_path}"
            )
        assert isinstance(name, str) and isinstance(version, str) and isinstance(checksum, str)
        if name in registry:
            raise SyncError(
                f"multiple locked registry versions require archive-name handling: {name}"
            )
        registry[name] = (version, checksum)
    return registry


def check_vendor_archive(
    archive: Path, integrity_path: Path, lock_path: Path
) -> None:
    expected = read_integrity_file(integrity_path)
    try:
        expected_archive = expected["vendor.tar.gz"]
        expected_listing = expected["vendor-file-list"]
    except KeyError as error:
        raise SyncError(f"missing integrity entry: {error.args[0]}") from error

    actual_archive = sha256_file(archive)
    if actual_archive != expected_archive:
        raise SyncError("offline vendor archive digest differs from vendor.sha256")

    with tarfile.open(archive, mode="r:gz") as source:
        members = source.getmembers()

    entries: dict[str, tarfile.TarInfo] = {}
    for member in members:
        name = member.name.rstrip("/")
        relative = PurePosixPath(name)
        if (
            not name
            or relative.is_absolute()
            or ".." in relative.parts
            or "\\" in name
        ):
            raise SyncError(f"offline vendor archive has an unsafe path: {member.name}")
        if not (member.isfile() or member.isdir()):
            raise SyncError(f"offline vendor archive has a special entry: {member.name}")
        if name in entries:
            raise SyncError(f"offline vendor archive has a duplicate entry: {name}")
        entries[name] = member

    for name in entries:
        for parent in PurePosixPath(name).parents:
            if parent == PurePosixPath("."):
                break
            parent_member = entries.get(parent.as_posix())
            if parent_member is not None and parent_member.isfile():
                raise SyncError(
                    f"offline vendor archive puts {name} below file {parent.as_posix()}"
                )

    rendered_names = [
        f"{member.name}{'/' if member.isdir() and not member.name.endswith('/') else ''}"
        for member in members
    ]
    listing = "".join(f"{name}\n" for name in sorted(rendered_names))
    actual_listing = hashlib.sha256(listing.encode("utf-8")).hexdigest()
    if actual_listing != expected_listing:
        raise SyncError("offline vendor archive file-list digest differs")

    locked_packages = registry_packages(lock_path)
    expected_packages = set(locked_packages)
    archived_packages = {
        PurePosixPath(name).name
        for name, member in entries.items()
        if member.isdir() and PurePosixPath(name).parent == PurePosixPath("v")
    }
    if archived_packages != expected_packages:
        missing = sorted(expected_packages - archived_packages)
        extra = sorted(archived_packages - expected_packages)
        details = []
        if missing:
            details.append(f"missing locked packages: {', '.join(missing)}")
        if extra:
            details.append(f"unexpected packages: {', '.join(extra)}")
        raise SyncError("offline vendor package inventory differs; " + "; ".join(details))

    required_files = tuple(
        f"v/{name}/.cargo-checksum.json" for name in sorted(expected_packages)
    )
    for required in required_files:
        member = entries.get(required)
        if member is None or not member.isfile():
            raise SyncError(f"offline vendor archive is missing regular file {required}")

    with tempfile.TemporaryDirectory() as temporary:
        destination = Path(temporary)
        with tarfile.open(archive, mode="r:gz") as source:
            source.extractall(destination, filter="data")
        for name, (locked_version, locked_checksum) in locked_packages.items():
            package_root = destination / "v" / name
            checksum_path = package_root / ".cargo-checksum.json"
            manifest_path = package_root / "Cargo.toml"
            if not checksum_path.is_file() or not manifest_path.is_file():
                raise SyncError(f"offline vendor archive did not extract metadata for {name}")

            checksum = json.loads(checksum_path.read_text(encoding="utf-8"))
            if not isinstance(checksum, dict) or checksum.get("package") != locked_checksum:
                raise SyncError(f"offline vendor checksum differs from Cargo.lock: {name}")

            manifest = tomllib.loads(manifest_path.read_text(encoding="utf-8"))
            package = manifest.get("package")
            if not isinstance(package, dict):
                raise SyncError(f"vendored Cargo.toml has no [package]: {name}")
            if package.get("name") != name or package.get("version") != locked_version:
                raise SyncError(f"offline vendor version differs from Cargo.lock: {name}")


def check_repository(root: Path, *, update_pins: bool = False) -> str:
    canonical = root / "rust/dta-parser"
    mirror = root / "r-package/dtaparser/src/vendor/dta-parser"
    canonical_pin_path = root / "rust/dta-parser.tree.sha256"
    mirror_pin_path = root / "r-package/dtaparser/src/vendor/dta-parser.tree.sha256"

    canonical_manifest = normalized_manifest(
        root / "Cargo.toml", canonical / "Cargo.toml", mirror=False
    )
    mirror_manifest = normalized_manifest(
        root / "Cargo.toml", mirror / "Cargo.toml", mirror=True
    )
    if canonical_manifest != mirror_manifest:
        raise SyncError("canonical and R mirror Cargo.toml semantics differ")

    compare_runtime_sources(canonical, mirror)
    check_make_source_inventories(root, mirror)
    canonical_digest = runtime_tree_digest(canonical, canonical_manifest)
    mirror_digest = runtime_tree_digest(mirror, mirror_manifest)
    if canonical_digest != mirror_digest:
        raise SyncError("canonical and R runtime-tree digests differ")

    require_equal(canonical / "README.md", mirror / "README.md", "crate README")
    require_equal(canonical / "LICENSE", mirror / "LICENSE", "crate license")
    require_equal(root / "Cargo.lock", mirror / "Cargo.lock", "Cargo lock")
    check_vendor_archive(
        root / "r-package/dtaparser/src/rust/vendor.tar.gz",
        root / "r-package/dtaparser/src/rust/vendor.sha256",
        root / "r-package/dtaparser/src/rust/Cargo.lock",
    )

    if update_pins:
        write_pin_pair((canonical_pin_path, mirror_pin_path), canonical_digest)

    canonical_pin = read_pin(canonical_pin_path)
    mirror_pin = read_pin(mirror_pin_path)
    if canonical_pin != mirror_pin:
        raise SyncError("canonical and R mirror tree pins differ")
    if canonical_pin != canonical_digest:
        raise SyncError("Rust tree pins are stale; mirror the tree and update both pins")
    return canonical_digest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update-pins", action="store_true")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help=argparse.SUPPRESS,
    )
    arguments = parser.parse_args()

    try:
        digest = check_repository(arguments.root.resolve(), update_pins=arguments.update_pins)
    except (OSError, SyncError, tarfile.TarError, tomllib.TOMLDecodeError) as error:
        print(f"rust sync: FAIL: {error}", file=sys.stderr)
        return 1

    action = "updated and verified" if arguments.update_pins else "verified"
    print(f"rust sync: PASS ({action} {PIN_SCHEMA} {digest})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

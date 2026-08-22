#!/usr/bin/env python3
"""Validate the contents and member types of a dtaparser R source archive."""

from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath
import re
import sys
import tarfile

from archive_safety import (
    canonical_relative_path,
    parent_file_conflict,
    portable_extraction_key,
)


REQUIRED_FILES = {
    "dtaparser/src/dta-parser/Cargo.toml",
    "dtaparser/src/dta-parser/src/lib.rs",
    "dtaparser/src/rust/Cargo.toml",
    "dtaparser/src/rust/Cargo.lock",
    "dtaparser/src/rust/vendor.tar.gz",
    "dtaparser/src/Makevars.rust",
    "dtaparser/tools/configure-rust.sh",
    "dtaparser/tools/rust-source-hash.R",
}
EXCLUDED_PATH = re.compile(
    r"/target(?:/|$)"
    r"|^dtaparser/src/rust/v(?:/|$)"
    r"|^dtaparser/src/dta-parser/(?:tests|examples)(?:/|$)"
    r"|^dtaparser/src/Makevars(?:\.win)?$"
    r"|/vendor/dta-parser"
)


class ArchiveError(RuntimeError):
    """An R package archive invariant failed."""


def normalized_member_name(member: tarfile.TarInfo) -> tuple[str, PurePosixPath]:
    name = member.name.removesuffix("/")
    path = canonical_relative_path(name)
    if (
        path is None
        or (name != "dtaparser" and not name.startswith("dtaparser/"))
    ):
        raise ArchiveError(f"R package archive has an unsafe path: {member.name}")
    return name, path


def check_archive(path: Path) -> None:
    entries: dict[str, bool] = {}
    extraction_names: dict[str, str] = {}
    with tarfile.open(path, mode="r|gz") as source:
        for member in source:
            name, relative = normalized_member_name(member)
            if not (member.isfile() or member.isdir()):
                raise ArchiveError(f"R package archive has a special entry: {name}")
            if name in entries:
                raise ArchiveError(f"R package archive has a duplicate entry: {name}")
            try:
                key = portable_extraction_key(relative)
            except ValueError as error:
                raise ArchiveError(
                    f"R package archive has a non-portable path: {name}"
                ) from error
            alias = extraction_names.get(key)
            if alias is not None:
                raise ArchiveError(
                    f"R package archive paths collide: {alias} and {name}"
                )
            entries[name] = member.isfile()
            extraction_names[key] = name

    conflict = parent_file_conflict(entries)
    if conflict is not None:
        name, parent = conflict
        raise ArchiveError(f"R package archive puts {name} below file {parent}")

    missing = sorted(name for name in REQUIRED_FILES if entries.get(name) is not True)
    if missing:
        raise ArchiveError(
            "R package archive is missing regular file " + ", ".join(missing)
        )

    excluded = sorted(name for name in entries if EXCLUDED_PATH.search(name))
    if excluded:
        raise ArchiveError(
            "R package archive contains excluded Rust development or build files: "
            + ", ".join(excluded)
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    arguments = parser.parse_args()

    try:
        check_archive(arguments.archive)
    except (ArchiveError, OSError, tarfile.TarError) as error:
        print(f"R package archive: FAIL: {error}", file=sys.stderr)
        return 1

    print("R package archive: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

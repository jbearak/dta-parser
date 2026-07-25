#!/usr/bin/env python3
"""Repack the checked Cargo vendor archive with normalized metadata."""

from __future__ import annotations

import gzip
import os
from pathlib import Path
import tarfile
import tempfile


ARCHIVE = Path("r-package/dtaparser/src/rust/vendor.tar.gz")


with tempfile.TemporaryDirectory() as directory:
    temporary = Path(directory)
    with tarfile.open(ARCHIVE, "r:gz") as source:
        source.extractall(temporary, filter="data")

    output = temporary / "vendor.tar.gz"
    with output.open("wb") as raw:
        with gzip.GzipFile(
            filename="", mode="wb", fileobj=raw, mtime=0, compresslevel=9
        ) as compressed:
            with tarfile.open(
                fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT
            ) as target:
                paths = [temporary / "v", *(temporary / "v").rglob("*")]
                for path in sorted(paths, key=lambda item: item.relative_to(temporary).as_posix()):
                    name = path.relative_to(temporary).as_posix()
                    info = target.gettarinfo(str(path), arcname=name)
                    info.uid = 0
                    info.gid = 0
                    info.uname = "root"
                    info.gname = "root"
                    info.mtime = 0
                    if info.isfile():
                        with path.open("rb") as contents:
                            target.addfile(info, contents)
                    else:
                        target.addfile(info)
    os.replace(output, ARCHIVE)

print(f"rebuilt deterministic {ARCHIVE}; update vendor.sha256 intentionally")

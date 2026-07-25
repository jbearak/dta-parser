#!/usr/bin/env python3
"""Repack the checked Cargo vendor archive with normalized metadata."""

from __future__ import annotations

import gzip
import inspect
import os
from pathlib import Path, PurePosixPath
import tarfile
import tempfile


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
ARCHIVE = REPOSITORY_ROOT / "r-package/dtaparser/src/rust/vendor.tar.gz"


def _within(destination: Path, candidate: Path) -> bool:
    try:
        candidate.relative_to(destination)
        return True
    except ValueError:
        return False


def _archive_path(value: str) -> PurePosixPath:
    return PurePosixPath(value.replace("\\", "/"))


def _validate_legacy_member(member: tarfile.TarInfo, destination: Path) -> None:
    name = _archive_path(member.name)
    if name.is_absolute() or ".." in name.parts:
        raise tarfile.ExtractError(f"unsafe archive path: {member.name}")
    target = (destination.joinpath(*name.parts)).resolve()
    if not _within(destination, target):
        raise tarfile.ExtractError(f"archive path escapes destination: {member.name}")
    if member.isdev() or member.isfifo():
        raise tarfile.ExtractError(f"unsupported special archive member: {member.name}")
    if member.issym() or member.islnk():
        link = _archive_path(member.linkname)
        if link.is_absolute():
            raise tarfile.ExtractError(f"absolute archive link: {member.linkname}")
        link_target = (
            target.parent.joinpath(*link.parts)
            if member.issym()
            else destination.joinpath(*link.parts)
        ).resolve()
        if not _within(destination, link_target):
            raise tarfile.ExtractError(
                f"archive link escapes destination: {member.name} -> {member.linkname}"
            )


def safe_extract(
    source: tarfile.TarFile,
    destination: Path,
    *,
    force_legacy: bool = False,
) -> None:
    """Use Python's data filter when available, otherwise validate every member."""
    parameters = inspect.signature(source.extractall).parameters
    if not force_legacy and "filter" in parameters:
        source.extractall(destination, filter="data")
        return
    resolved = destination.resolve()
    for member in source.getmembers():
        _validate_legacy_member(member, resolved)
    source.extractall(destination)


def normalize_info(info: tarfile.TarInfo) -> tarfile.TarInfo:
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "root"
    info.mtime = 0
    if info.isdir():
        info.mode = 0o755
    elif info.isfile():
        info.mode = 0o644
    elif info.issym() or info.islnk():
        info.mode = 0o777
    else:
        raise ValueError(f"unsupported vendor archive member: {info.name}")
    return info


def main() -> None:
    with tempfile.TemporaryDirectory() as directory:
        temporary = Path(directory)
        with tarfile.open(ARCHIVE, "r:gz") as source:
            safe_extract(source, temporary)

        output = temporary / "vendor.tar.gz"
        with output.open("wb") as raw:
            with gzip.GzipFile(
                filename="", mode="wb", fileobj=raw, mtime=0, compresslevel=9
            ) as compressed:
                with tarfile.open(
                    fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT
                ) as target:
                    paths = [temporary / "v", *(temporary / "v").rglob("*")]
                    for path in sorted(
                        paths,
                        key=lambda item: item.relative_to(temporary).as_posix(),
                    ):
                        name = path.relative_to(temporary).as_posix()
                        info = normalize_info(target.gettarinfo(str(path), arcname=name))
                        if info.isfile():
                            with path.open("rb") as contents:
                                target.addfile(info, contents)
                        else:
                            target.addfile(info)
        os.replace(output, ARCHIVE)

    print(f"rebuilt deterministic {ARCHIVE}; update vendor.sha256 intentionally")


if __name__ == "__main__":
    main()

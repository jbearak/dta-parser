#!/usr/bin/env python3
"""Scale a Stata 118/119 file by repeating complete observation rows."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
import hashlib
import os
from pathlib import Path
import struct


MAP_ENTRIES = 14
DATA_OPEN = b"<data>"
DATA_CLOSE = b"</data>"


@dataclass(frozen=True)
class ParsedBase:
    endian: str
    n_start: int
    nobs: int
    map_start: int
    offsets: tuple[int, ...]
    payload_start: int
    payload_end: int
    obs_bytes: int


def one_location(data: bytes, needle: bytes) -> int:
    start = data.find(needle)
    if start < 0 or data.find(needle, start + 1) >= 0:
        raise ValueError(f"expected exactly one {needle!r}")
    return start


def parse_base(data: bytes) -> ParsedBase:
    byte_order_start = one_location(data, b"<byteorder>") + len(b"<byteorder>")
    byte_order = data[byte_order_start : byte_order_start + 3]
    if byte_order == b"LSF":
        endian = "<"
    elif byte_order == b"MSF":
        endian = ">"
    else:
        raise ValueError(f"unsupported byte order {byte_order!r}")

    release_start = one_location(data, b"<release>") + len(b"<release>")
    release = int(data[release_start : release_start + 3])
    if release not in (118, 119):
        raise ValueError(f"expected release 118 or 119, got {release}")

    n_start = one_location(data, b"<N>") + len(b"<N>")
    nobs = struct.unpack_from(f"{endian}Q", data, n_start)[0]
    map_start = one_location(data, b"<map>") + len(b"<map>")
    offsets = list(struct.unpack_from(f"{endian}{MAP_ENTRIES}Q", data, map_start))
    if offsets[13] != len(data):
        raise ValueError(f"map EOF {offsets[13]} != file size {len(data)}")
    if data[offsets[9] : offsets[9] + len(DATA_OPEN)] != DATA_OPEN:
        raise ValueError("map data offset does not point to <data>")
    if data[offsets[10] - len(DATA_CLOSE) : offsets[10]] != DATA_CLOSE:
        raise ValueError("map strls offset is not immediately after </data>")

    payload_start = offsets[9] + len(DATA_OPEN)
    payload_end = offsets[10] - len(DATA_CLOSE)
    payload_length = payload_end - payload_start
    if nobs == 0 or payload_length % nobs:
        raise ValueError("observation payload is not an integral row matrix")
    return ParsedBase(
        endian=endian,
        n_start=n_start,
        nobs=nobs,
        map_start=map_start,
        offsets=tuple(offsets),
        payload_start=payload_start,
        payload_end=payload_end,
        obs_bytes=payload_length // nobs,
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(16 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def update_manifest(path: Path, row: dict[str, object]) -> None:
    rows: list[dict[str, str | object]] = []
    if path.exists():
        with path.open(newline="") as stream:
            rows.extend(csv.DictReader(stream, delimiter="\t"))
    rows = [existing for existing in rows if existing["dataset"] != row["dataset"]]
    rows.append(row)
    order = {"100mb": 0, "1gb": 1}
    rows.sort(key=lambda existing: order.get(str(existing["dataset"]), 2))

    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".partial")
    with temporary.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(row), delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary, path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--target-bytes", type=int, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()

    base = args.base.read_bytes()
    parsed = parse_base(base)
    payload_start = parsed.payload_start
    payload_end = parsed.payload_end
    base_rows = parsed.nobs
    obs_bytes = parsed.obs_bytes
    overhead = len(base) - (payload_end - payload_start)
    rows = max(1, round((args.target_bytes - overhead) / obs_bytes))
    actual_bytes = overhead + rows * obs_bytes
    delta = actual_bytes - len(base)

    prefix = bytearray(base[:payload_start])
    suffix = base[payload_end:]
    endian = parsed.endian
    struct.pack_into(f"{endian}Q", prefix, parsed.n_start, rows)
    map_start = parsed.map_start
    offsets = list(parsed.offsets)
    for index in range(10, 14):
        offsets[index] += delta
    struct.pack_into(f"{endian}{MAP_ENTRIES}Q", prefix, map_start, *offsets)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    payload = memoryview(base)[payload_start:payload_end]
    blocks, remainder = divmod(rows, base_rows)
    temporary = args.output.with_suffix(args.output.suffix + ".partial")
    with temporary.open("wb", buffering=16 * 1024 * 1024) as stream:
        stream.write(prefix)
        for _ in range(blocks):
            stream.write(payload)
        if remainder:
            stream.write(payload[: remainder * obs_bytes])
        stream.write(suffix)
    os.replace(temporary, args.output)
    if args.output.stat().st_size != actual_bytes:
        raise RuntimeError("generated size differs from calculated size")

    update_manifest(
        args.manifest,
        {
            "dataset": args.label,
            "path": str(args.output.resolve()),
            "target_bytes": args.target_bytes,
            "actual_bytes": actual_bytes,
            "sha256": sha256_file(args.output),
            "rows": rows,
            "columns": "",
            "obs_bytes": obs_bytes,
            "base_rows": base_rows,
        },
    )
    print(
        f"wrote {args.output}: {rows} rows, {actual_bytes} bytes "
        f"({actual_bytes / 1_000_000:.3f} MB), {obs_bytes} bytes/row"
    )


if __name__ == "__main__":
    main()

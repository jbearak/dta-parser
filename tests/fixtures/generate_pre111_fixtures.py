#!/usr/bin/env python3
"""Generate legally distributable Stata 5-7 release 105/108/110 fixtures."""

import argparse
from dataclasses import dataclass
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class Layout:
    release: int
    header_size: int
    dataset_label_width: int
    varname_width: int
    variable_label_width: int
    characteristic_width: int
    expansion_length_width: int


LAYOUTS = (
    Layout(105, 60, 32, 9, 32, 9, 2),
    Layout(108, 109, 81, 9, 81, 9, 2),
    Layout(110, 109, 81, 33, 81, 33, 4),
)


def fixed(value: bytes, width: int) -> bytes:
    if len(value) >= width:
        raise ValueError(f"{value!r} does not fit in {width} bytes")
    return value + bytes(width - len(value))


def pack_length(value: int, width: int) -> bytes:
    if width == 2:
        return struct.pack("<h", value)
    if width == 4:
        return struct.pack("<i", value)
    raise ValueError(f"unsupported expansion length width {width}")


def build(layout: Layout) -> bytes:
    names = (b"b", b"i", b"l", b"f", b"d", b"text")
    # Pre-111 numeric types use their ASCII storage-code letters. Fixed strings
    # are encoded as 0x7f plus their byte width.
    types = bytes((ord("b"), ord("i"), ord("l"), ord("f"), ord("d"), 0x7F + 6))
    formats = (b"%8.0g", b"%8.0g", b"%12.0g", b"%9.0g", b"%10.0g", b"%6s")
    value_labels = (b"b_labels", b"", b"", b"", b"", b"")
    variable_labels = (
        b"Byte value",
        b"Integer value",
        b"Long value",
        b"Float value",
        b"Double value",
        b"CP1252 text",
    )

    header = bytearray(layout.header_size)
    header[0:4] = bytes((layout.release, 2, 1, 0))
    header[4:6] = struct.pack("<H", len(names))
    header[6:10] = struct.pack("<i", 2)
    label = f"Release {layout.release} Caf".encode("ascii") + b"\xe9 fixture"
    header[10 : 10 + layout.dataset_label_width] = fixed(
        label, layout.dataset_label_width
    )
    timestamp_start = 10 + layout.dataset_label_width
    header[timestamp_start : timestamp_start + 18] = fixed(
        b"21 Aug 2026 12:00", 18
    )

    descriptors = bytearray(types)
    descriptors.extend(
        b"".join(fixed(value, layout.varname_width) for value in names)
    )
    descriptors.extend(bytes((len(names) + 1) * 2))
    descriptors.extend(b"".join(fixed(value, 12) for value in formats))
    descriptors.extend(
        b"".join(fixed(value, layout.varname_width) for value in value_labels)
    )
    descriptors.extend(
        b"".join(fixed(value, layout.variable_label_width) for value in variable_labels)
    )

    note = (
        fixed(b"_dta", layout.characteristic_width)
        + fixed(b"note1", layout.characteristic_width)
        + f"Release {layout.release} note".encode("ascii")
        + b"\0"
    )
    characteristics = bytes((1,)) + pack_length(
        len(note), layout.expansion_length_width
    ) + note
    characteristics += bytes(1 + layout.expansion_length_width)

    data = bytearray()
    data.extend(struct.pack("<bhi", 1, 321, -123456))
    data.extend(struct.pack("<f", 1.5))
    data.extend(struct.pack("<d", -2.25))
    data.extend(fixed(b"Caf\xe9", 6))
    data.extend(struct.pack("<bhi", 127, 32767, 2147483647))
    data.extend(struct.pack("<I", 0x7F000000))
    data.extend(struct.pack("<Q", 0x7FE0000000000000))
    data.extend(fixed(b"", 6))

    text = b"One\0"
    payload = struct.pack("<ii", 1, len(text))
    payload += struct.pack("<i", 0)
    payload += struct.pack("<i", 1)
    payload += text
    table = struct.pack("<i", len(payload))
    # Legacy value-label table names remain 33 bytes even when descriptor names
    # are 9 bytes in releases 105 and 108.
    table += fixed(b"b_labels", 33) + bytes(3) + payload

    return bytes(header + descriptors + characteristics + data + table)


def default_outputs(layout: Layout) -> tuple[Path, ...]:
    return (
        ROOT / f"rust/dta-parser/tests/data/synthetic-v{layout.release}.dta",
        ROOT / f"r-package/dtaparser/inst/extdata/synthetic_v{layout.release}.dta",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", action="append", type=Path)
    args = parser.parse_args()

    for layout in LAYOUTS:
        payload = build(layout)
        outputs = (
            tuple(
                directory / f"synthetic-v{layout.release}.dta"
                for directory in args.output_dir
            )
            if args.output_dir
            else default_outputs(layout)
        )
        for output in outputs:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(payload)


if __name__ == "__main__":
    main()

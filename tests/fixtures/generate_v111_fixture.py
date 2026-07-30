#!/usr/bin/env python3
"""Generate the legally distributable release-111 conformance fixture."""

import argparse
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[2]
OUTPUTS = (
    ROOT / "rust/dta-parser/tests/data/synthetic-v111.dta",
    ROOT / "r-package/dtaparser/inst/extdata/synthetic_v111.dta",
)


def fixed(value: bytes, width: int) -> bytes:
    if len(value) >= width:
        raise ValueError(f"{value!r} does not fit in {width} bytes")
    return value + bytes(width - len(value))


def build() -> bytes:
    names = (b"b", b"i", b"l", b"f", b"d", b"text")
    types = bytes((251, 252, 253, 254, 255, 6))
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

    data = bytearray()
    ordinary = (1, 321, -123456, 1.5, -2.25, b"alpha")
    data.extend(struct.pack("<bhi", *ordinary[:3]))
    data.extend(struct.pack("<f", ordinary[3]))
    data.extend(struct.pack("<d", ordinary[4]))
    data.extend(fixed(ordinary[5], 6))
    for offset, text in ((0, b""), (1, b"Caf\xe9"), (26, b"omega")):
        data.extend(struct.pack("<bhi", 101 + offset, 32741 + offset, 2147483621 + offset))
        data.extend(struct.pack("<I", 0x7F000000 + offset * 0x800))
        data.extend(struct.pack("<Q", 0x7FE0000000000000 + offset * 0x10000000000))
        data.extend(fixed(text, 6))

    header = bytearray(109)
    header[0:4] = bytes((111, 2, 1, 0))
    header[4:6] = struct.pack("<H", len(names))
    header[6:10] = struct.pack("<I", 4)
    header[10:91] = fixed(b"Stata/SE 7 Caf\xe9 fixture", 81)
    header[91:109] = fixed(b"30 Jul 2026 12:00", 18)

    descriptors = bytearray(types)
    descriptors.extend(b"".join(fixed(value, 33) for value in names))
    descriptors.extend(bytes((len(names) + 1) * 2))
    descriptors.extend(b"".join(fixed(value, 12) for value in formats))
    descriptors.extend(b"".join(fixed(value, 33) for value in value_labels))
    descriptors.extend(b"".join(fixed(value, 81) for value in variable_labels))

    note = fixed(b"_dta", 33) + fixed(b"note1", 33) + b"Release 111 note\0"
    characteristics = bytes((1,)) + struct.pack("<i", len(note)) + note + bytes(5)

    text = b"One\0Old max\0"
    payload = struct.pack("<ii", 2, len(text))
    payload += struct.pack("<ii", 0, 4)
    payload += struct.pack("<ii", 1, 2147483621)
    payload += text
    table = struct.pack("<i", len(payload))
    table += fixed(b"b_labels", 33) + bytes(3) + payload
    return bytes(header + descriptors + characteristics + data + table)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", action="append", type=Path)
    args = parser.parse_args()
    payload = build()
    for output in args.output or OUTPUTS:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(payload)


if __name__ == "__main__":
    main()

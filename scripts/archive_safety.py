"""Shared path-safety helpers for repository tar validators."""

from __future__ import annotations

from collections.abc import Mapping
from pathlib import PurePosixPath
import unicodedata


WINDOWS_RESERVED_NAMES = {
    "AUX",
    "CON",
    "NUL",
    "PRN",
    *(f"COM{number}" for number in range(1, 10)),
    *(f"LPT{number}" for number in range(1, 10)),
}


def canonical_relative_path(name: str) -> PurePosixPath | None:
    path = PurePosixPath(name)
    if (
        not name
        or path.is_absolute()
        or ".." in path.parts
        or "\\" in name
        or path.as_posix() != name
    ):
        return None
    return path


def portable_extraction_key(path: PurePosixPath) -> str:
    components = []
    for component in path.parts:
        if (
            component.endswith((" ", "."))
            or any(
                character in '<>:"|?*' or ord(character) < 32
                for character in component
            )
            or component.split(".", 1)[0].upper() in WINDOWS_RESERVED_NAMES
        ):
            raise ValueError(path.as_posix())
        components.append(unicodedata.normalize("NFC", component).casefold())
    return "/".join(components)


def parent_file_conflict(
    entries: Mapping[str, bool],
) -> tuple[str, str] | None:
    for name in entries:
        for parent in PurePosixPath(name).parents:
            if parent == PurePosixPath("."):
                break
            parent_name = parent.as_posix()
            if entries.get(parent_name) is True:
                return name, parent_name
    return None

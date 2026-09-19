#!/usr/bin/env python3
"""Increment the ai-memory plugin patch version."""

from __future__ import annotations

import re
import sys
from pathlib import Path

DEFAULT_VERSION_FILE = (
    Path(__file__).resolve().parent
    / "plugin-site"
    / "plugins"
    / "ai-memory"
    / "VERSION"
)
SEMVER_PATTERN = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


def bump_patch(version: str) -> str:
    """Return the next patch version for a strict semantic version."""
    match = SEMVER_PATTERN.fullmatch(version)
    if match is None:
        raise ValueError(f"Invalid plugin version: {version!r}")

    major, minor, patch = (int(part) for part in match.groups())
    return f"{major}.{minor}.{patch + 1}"


def main() -> int:
    version_file = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_VERSION_FILE
    if len(sys.argv) > 2:
        print(f"Usage: {Path(sys.argv[0]).name} [VERSION_FILE]", file=sys.stderr)
        return 2

    try:
        current_version = version_file.read_text(encoding="utf-8").strip()
        next_version = bump_patch(current_version)
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1

    version_file.write_text(f"{next_version}\n", encoding="utf-8")
    print(f"Bumped plugin version: {current_version} -> {next_version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

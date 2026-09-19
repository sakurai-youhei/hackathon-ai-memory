#!/usr/bin/env python3
"""Render Serverless API key creation instructions."""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

UUID_PATTERN = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
ROLE_TEMPLATE = Path(__file__).with_name("role-template.json.j2")


def required_env(name: str) -> str:
    """Return a required environment variable."""
    value = os.environ.get(name, "").strip()
    if not value:
        raise ValueError(f"{name} is required")
    return value


def render_role(owner_uuid: str) -> dict[str, object]:
    """Render and parse the UUID-scoped role descriptor."""
    if UUID_PATTERN.fullmatch(owner_uuid) is None:
        raise ValueError("uuid must be a lowercase canonical UUID")

    try:
        template = ROLE_TEMPLATE.read_text(encoding="utf-8")
        return json.loads(template.replace("{{ owner_uuid }}", owner_uuid))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"Unable to render role template: {error}") from error


def main() -> int:
    """Print values to enter in the Kibana API key creation form."""
    try:
        owner_uuid = required_env("uuid")
        create_url = required_env("KIBANA_API_KEY_CREATE_URL")
        role = render_role(owner_uuid)
    except (ValueError, RuntimeError) as error:
        print(error, file=sys.stderr)
        return 1

    print(f"URL: {create_url}")
    print(f"Name: {owner_uuid}-ai-memory")
    print("Control security privileges:")
    role_descriptors = {f"{owner_uuid}-ai-memory": role}
    print(json.dumps(role_descriptors, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

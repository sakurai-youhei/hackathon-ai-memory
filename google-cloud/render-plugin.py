#!/usr/bin/env python3
"""Render the ai-memory plugin MCP config from Jinja templates."""

from __future__ import annotations

import os
import sys
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined

PLUGIN_DIR = Path(__file__).resolve().parent / "plugin-site" / "plugins" / "ai-memory"
TEMPLATE_NAME = ".mcp.json.j2"
OUTPUT_NAME = ".mcp.json"


def main() -> int:
    kb_endpoint = os.environ.get("KB_ENDPOINT", "").strip()
    if not kb_endpoint:
        print(
            "KB_ENDPOINT is required (set it in .env before running make render-plugin).",
            file=sys.stderr,
        )
        return 1

    kibana_mcp_url = f"{kb_endpoint.rstrip('/')}/api/agent_builder/mcp"

    env = Environment(
        loader=FileSystemLoader(str(PLUGIN_DIR)),
        undefined=StrictUndefined,
        keep_trailing_newline=True,
        autoescape=False,
    )
    rendered = env.get_template(TEMPLATE_NAME).render(kibana_mcp_url=kibana_mcp_url)

    output_path = PLUGIN_DIR / OUTPUT_NAME
    output_path.write_text(rendered, encoding="utf-8")
    print(f"Wrote {output_path}")
    print(f"Kibana MCP URL: {kibana_mcp_url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

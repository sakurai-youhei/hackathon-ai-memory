#!/usr/bin/env python3
"""Render the ai-memory plugin MCP configs from Jinja templates."""

from __future__ import annotations

import os
import sys
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined

PLUGIN_DIR = Path(__file__).resolve().parent / "plugin-site" / "plugins" / "ai-memory"
TEMPLATES = (
    (".mcp.json.j2", ".mcp.json"),
    ("gemini-extension.json.j2", "gemini-extension.json"),
)


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
    context = {"kibana_mcp_url": kibana_mcp_url}

    for template_name, output_name in TEMPLATES:
        rendered = env.get_template(template_name).render(**context)
        output_path = PLUGIN_DIR / output_name
        output_path.write_text(rendered, encoding="utf-8")
        print(f"Wrote {output_path}")

    print(f"Kibana MCP URL: {kibana_mcp_url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

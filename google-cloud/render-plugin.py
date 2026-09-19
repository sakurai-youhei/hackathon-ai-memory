#!/usr/bin/env python3
"""Render ai-memory plugin configs, marketplaces, and distribution zip."""

from __future__ import annotations

import os
import re
import sys
import zipfile
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined

SITE_DIR = Path(__file__).resolve().parent / "plugin-site"
PLUGIN_DIR = SITE_DIR / "plugins" / "ai-memory"
VERSION_FILE = PLUGIN_DIR / "VERSION"
MEMORY_INDEX = "c68a3344-6870-433f-9834-5bc11694307a-ai-memory"
SEMVER_PATTERN = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
PLUGIN_TEMPLATES = (
    (".mcp.json.j2", ".mcp.json"),
    (".claude-plugin/plugin.json.j2", ".claude-plugin/plugin.json"),
    (".cursor-plugin/plugin.json.j2", ".cursor-plugin/plugin.json"),
    ("gemini-extension.json.j2", "gemini-extension.json"),
    ("skills/ai-memory/SKILL.md.j2", "skills/ai-memory/SKILL.md"),
)
SITE_TEMPLATES = (
    ("marketplace.json.j2", "marketplace.json"),
    (".claude-plugin/marketplace.json.j2", ".claude-plugin/marketplace.json"),
    (".cursor-plugin/marketplace.json.j2", ".cursor-plugin/marketplace.json"),
    ("index.html.j2", "index.html"),
)
ZIP_EXCLUDE_SUFFIXES = (".j2", ".zip")


def _require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        print(
            f"{name} is required (set it before running make render-plugin).",
            file=sys.stderr,
        )
        raise SystemExit(1)
    return value


def _read_plugin_version() -> str:
    try:
        version = VERSION_FILE.read_text(encoding="utf-8").strip()
    except OSError as error:
        print(f"Unable to read plugin version: {error}", file=sys.stderr)
        raise SystemExit(1) from error

    if SEMVER_PATTERN.fullmatch(version) is None:
        print(f"Invalid plugin version in {VERSION_FILE}: {version!r}", file=sys.stderr)
        raise SystemExit(1)
    return version


def _render(
    env: Environment, template_name: str, output_path: Path, context: dict
) -> None:
    rendered = env.get_template(template_name).render(**context)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(rendered, encoding="utf-8")
    print(f"Wrote {output_path}")


def _build_zip(plugin_dir: Path, zip_path: Path) -> None:
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    if zip_path.exists():
        zip_path.unlink()

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(plugin_dir.rglob("*")):
            if not path.is_file():
                continue
            if path.suffix in ZIP_EXCLUDE_SUFFIXES or path.name.endswith(".j2"):
                continue
            if path.resolve() == zip_path.resolve():
                continue
            arcname = Path("ai-memory") / path.relative_to(plugin_dir)
            zf.write(path, arcname.as_posix())

    print(f"Wrote {zip_path}")


def main() -> int:
    es_endpoint = _require_env("ES_ENDPOINT").rstrip("/")
    kb_endpoint = _require_env("KB_ENDPOINT")
    plugin_public_url = _require_env("PLUGIN_PUBLIC_URL").rstrip("/")
    plugin_version = _read_plugin_version()
    plugin_archive_name = f"ai-memory-{plugin_version}.zip"

    kibana_mcp_url = f"{kb_endpoint.rstrip('/')}/api/agent_builder/mcp"
    context = {
        "es_endpoint": es_endpoint,
        "kibana_mcp_url": kibana_mcp_url,
        "memory_index": MEMORY_INDEX,
        "plugin_public_url": plugin_public_url,
        "plugin_archive_url": f"{plugin_public_url}/plugins/{plugin_archive_name}",
        "marketplace_url": (f"{plugin_public_url}/marketplace.json?v={plugin_version}"),
        "plugin_version": plugin_version,
    }

    plugin_env = Environment(
        loader=FileSystemLoader(str(PLUGIN_DIR)),
        undefined=StrictUndefined,
        keep_trailing_newline=True,
        autoescape=False,
    )
    for template_name, output_name in PLUGIN_TEMPLATES:
        _render(plugin_env, template_name, PLUGIN_DIR / output_name, context)

    site_env = Environment(
        loader=FileSystemLoader(str(SITE_DIR)),
        undefined=StrictUndefined,
        keep_trailing_newline=True,
        autoescape=False,
    )
    for template_name, output_name in SITE_TEMPLATES:
        _render(site_env, template_name, SITE_DIR / output_name, context)

    _build_zip(PLUGIN_DIR, SITE_DIR / "plugins" / plugin_archive_name)
    _build_zip(PLUGIN_DIR, SITE_DIR / "plugins" / "ai-memory.zip")

    print(f"Kibana MCP URL: {kibana_mcp_url}")
    print(f"Elasticsearch URL: {es_endpoint}")
    print(f"Plugin public URL: {plugin_public_url}")
    print(f"Plugin version: {plugin_version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

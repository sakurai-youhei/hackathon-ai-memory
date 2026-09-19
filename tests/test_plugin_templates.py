"""Tests for per-user plugin configuration templates."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined

PLUGIN_DIR = Path(__file__).parents[1] / "google-cloud/plugin-site/plugins/ai-memory"


class PluginTemplatesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.environment = Environment(
            loader=FileSystemLoader(PLUGIN_DIR),
            undefined=StrictUndefined,
            autoescape=False,
        )

    def test_claude_writer_uses_the_configured_index(self) -> None:
        rendered = self.environment.get_template(".claude-mcp.json.j2").render(
            es_endpoint="https://example.test",
            kibana_mcp_url="https://example.test/api/agent_builder/mcp",
        )

        config = json.loads(rendered)
        writer_env = config["mcpServers"]["ai-memory-writer"]["env"]
        self.assertEqual(
            writer_env["AI_MEMORY_INDEX"], "${user_config.AI_MEMORY_INDEX}"
        )

    def test_claude_requires_an_index_alongside_the_api_key(self) -> None:
        rendered = self.environment.get_template(
            ".claude-plugin/plugin.json.j2"
        ).render(plugin_version="1.0.0")

        config = json.loads(rendered)
        self.assertTrue(config["userConfig"]["AI_MEMORY_INDEX"]["required"])


if __name__ == "__main__":
    unittest.main()

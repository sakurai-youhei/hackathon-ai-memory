"""Tests for rendering the per-user API key role descriptor."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "elastic-cloud/render-api-key-instructions.py"
SPEC = importlib.util.spec_from_file_location(
    "render_api_key_instructions", MODULE_PATH
)
assert SPEC is not None and SPEC.loader is not None
renderer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(renderer)


class RenderApiKeyInstructionsTest(unittest.TestCase):
    def test_role_can_create_only_the_owner_index(self) -> None:
        owner_uuid = "00000000-0000-4000-8000-000000000000"

        role = renderer.render_role(owner_uuid)

        self.assertEqual(role["indices"][0]["names"], [f"{owner_uuid}-ai-memory"])
        self.assertIn("create_index", role["indices"][0]["privileges"])


if __name__ == "__main__":
    unittest.main()

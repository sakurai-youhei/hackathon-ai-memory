"""Tests for rendering the per-user API key role descriptor."""

from __future__ import annotations

import importlib.util
import os
import unittest
from pathlib import Path
from unittest import mock

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

    def test_instructions_print_the_plugin_index_setting(self) -> None:
        owner_uuid = "00000000-0000-4000-8000-000000000000"
        environment = {
            "uuid": owner_uuid,
            "KIBANA_API_KEY_CREATE_URL": "https://example.test/create",
        }

        with (
            mock.patch.dict(os.environ, environment, clear=True),
            mock.patch("builtins.print") as print_mock,
        ):
            result = renderer.main()

        self.assertEqual(result, 0)
        print_mock.assert_any_call(f"Index: {owner_uuid}-ai-memory")


if __name__ == "__main__":
    unittest.main()

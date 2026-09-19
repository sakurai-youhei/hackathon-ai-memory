"""Tests for the ai-memory writer MCP server."""

from __future__ import annotations

import importlib.util
import json
import os
import unittest
from pathlib import Path
from typing import Self
from unittest import mock

MODULE_PATH = (
    Path(__file__).parents[1]
    / "google-cloud/plugin-site/plugins/ai-memory/scripts/ai-memory-write-mcp.py"
)
SPEC = importlib.util.spec_from_file_location("ai_memory_write_mcp", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
writer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(writer)


class FakeResponse:
    def __init__(self, body: dict[str, object]) -> None:
        self.body = json.dumps(body).encode()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def read(self, size: int = -1) -> bytes:
        return self.body if size < 0 else self.body[:size]


class AiMemoryWriteMcpTest(unittest.TestCase):
    def test_lists_store_memory_tool(self) -> None:
        response = writer.handle_message(
            {"jsonrpc": "2.0", "id": 1, "method": "tools/list"}
        )

        self.assertEqual(response["result"]["tools"][0]["name"], "store_memory")

    @mock.patch.object(writer.request, "urlopen")
    def test_store_memory_uses_private_environment(self, urlopen: mock.Mock) -> None:
        urlopen.return_value = FakeResponse(
            {"_id": "memory-1", "_index": "owner-ai-memory", "result": "created"}
        )
        environment = {
            "AI_MEMORY_ES_ENDPOINT": "https://example.test/",
            "AI_MEMORY_INDEX": "owner-ai-memory",
            "AI_MEMORY_API_KEY": "secret-key",
        }

        with mock.patch.dict(os.environ, environment, clear=True):
            result = writer.store_memory("Remember this")

        api_request = urlopen.call_args.args[0]
        self.assertEqual(
            api_request.full_url, "https://example.test/owner-ai-memory/_doc"
        )
        self.assertEqual(api_request.get_header("Authorization"), "ApiKey secret-key")
        self.assertEqual(json.loads(api_request.data), {"text": "Remember this"})
        self.assertEqual(result["id"], "memory-1")

    def test_tool_error_does_not_expose_missing_secret(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            response = writer.handle_message(
                {
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "tools/call",
                    "params": {
                        "name": "store_memory",
                        "arguments": {"content": "Remember this"},
                    },
                }
            )

        self.assertTrue(response["result"]["isError"])
        self.assertNotIn("secret-key", response["result"]["content"][0]["text"])


if __name__ == "__main__":
    unittest.main()

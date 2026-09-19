#!/usr/bin/env python3
"""Expose a minimal MCP tool for writing memories to Elasticsearch."""

from __future__ import annotations

import json
import os
import sys
from typing import Any
from urllib import error, request

SERVER_INFO = {"name": "ai-memory-writer", "version": "1.0.0"}
TOOL_NAME = "store_memory"


def _required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required plugin configuration: {name}")
    return value


def store_memory(content: str) -> dict[str, Any]:
    """Index one memory and return non-sensitive result metadata."""
    if not isinstance(content, str) or not content.strip():
        raise ValueError("content must be a non-empty string")

    endpoint = _required_env("AI_MEMORY_ES_ENDPOINT").rstrip("/")
    index = _required_env("AI_MEMORY_INDEX")
    api_key = _required_env("AI_MEMORY_API_KEY")
    body = json.dumps({"text": content.strip()}, ensure_ascii=False).encode()
    api_request = request.Request(
        f"{endpoint}/{index}/_doc",
        data=body,
        headers={
            "Authorization": f"ApiKey {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with request.urlopen(api_request, timeout=30) as response:
            result = json.load(response)
    except error.HTTPError as exc:
        raise RuntimeError(
            f"Elasticsearch rejected the memory (HTTP {exc.code})"
        ) from exc
    except error.URLError as exc:
        raise RuntimeError("Unable to reach Elasticsearch") from exc
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise RuntimeError("Elasticsearch returned an invalid response") from exc

    return {
        "id": result.get("_id"),
        "index": result.get("_index", index),
        "result": result.get("result", "created"),
    }


def _tool_result(result: dict[str, Any]) -> dict[str, Any]:
    return {
        "content": [
            {
                "type": "text",
                "text": f"Memory {result['result']} successfully (id: {result['id']}).",
            }
        ],
        "structuredContent": result,
    }


def handle_message(message: dict[str, Any]) -> dict[str, Any] | None:
    """Handle one JSON-RPC request from the MCP client."""
    request_id = message.get("id")
    method = message.get("method")
    if request_id is None:
        return None

    if method == "initialize":
        protocol_version = message.get("params", {}).get(
            "protocolVersion", "2024-11-05"
        )
        result = {
            "protocolVersion": protocol_version,
            "capabilities": {"tools": {}},
            "serverInfo": SERVER_INFO,
        }
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {
            "tools": [
                {
                    "name": TOOL_NAME,
                    "title": "Store memory",
                    "description": (
                        "Store a concise, non-sensitive memory in Elasticsearch."
                    ),
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "content": {
                                "type": "string",
                                "description": "The searchable memory text to store.",
                                "minLength": 1,
                            }
                        },
                        "required": ["content"],
                        "additionalProperties": False,
                    },
                }
            ]
        }
    elif method == "tools/call":
        params = message.get("params", {})
        if params.get("name") != TOOL_NAME:
            return _rpc_error(request_id, -32602, "Unknown tool")
        try:
            result = _tool_result(
                store_memory(params.get("arguments", {}).get("content"))
            )
        except (ValueError, RuntimeError) as exc:
            result = {
                "content": [{"type": "text", "text": str(exc)}],
                "isError": True,
            }
    else:
        return _rpc_error(request_id, -32601, "Method not found")

    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def _rpc_error(request_id: Any, code: int, message: str) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {"code": code, "message": message},
    }


def main() -> int:
    """Run the line-delimited JSON-RPC stdio loop."""
    for line in sys.stdin:
        try:
            message = json.loads(line)
            response = handle_message(message)
        except (json.JSONDecodeError, TypeError, AttributeError):
            response = _rpc_error(None, -32700, "Parse error")
        if response is not None:
            print(json.dumps(response, ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# AIメモリーいらんかえ～ agent plugin

Cursor / Claude Code plugin that connects agents to the Kibana Agent Builder MCP
server for shared hackathon memory (store and recall).

## Contents

- `.mcp.json.j2` — Jinja template; Kibana MCP URL is filled from `KB_ENDPOINT`
- `.cursor-plugin/plugin.json` — Cursor manifest (`variables.AI_MEMORY_API_KEY`)
- `.claude-plugin/plugin.json` — Claude Code manifest (`userConfig.AI_MEMORY_API_KEY`)
- `skills/ai-memory/` — guidance for remembering and recalling via MCP

## Build

From the repository root (requires `KB_ENDPOINT` in `.env`):

```bash
make render-plugin
```

This writes `.mcp.json` with:

`{KB_ENDPOINT}/api/agent_builder/mcp`

## Runtime configuration

Set your encoded API key as `AI_MEMORY_API_KEY` (environment variable, Cursor
plugin variables, or Claude Code user config). Do not put the API key in the
Jinja template or commit it.

## Caution

Hackathon-grade security only. Do not store personal or confidential data.

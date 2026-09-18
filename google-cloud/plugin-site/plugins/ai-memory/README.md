# AIメモリーいらんかえ～ agent plugin

Cursor / Claude Code / Gemini CLI plugin that connects agents to the Kibana
Agent Builder MCP server for shared hackathon memory (store and recall).

## Setup

Follow the distribution site (marketplace + setup guide):

```text
https://storage.googleapis.com/hackathon-ai-memory-plugin
```

## Contents

- `.mcp.json.j2` — Jinja template for Cursor / Claude (URL from `KB_ENDPOINT`)
- `gemini-extension.json.j2` — Jinja template for Gemini CLI
- `.cursor-plugin/plugin.json` — Cursor manifest (`variables.AI_MEMORY_API_KEY`)
- `.claude-plugin/plugin.json` — Claude Code manifest (`userConfig.AI_MEMORY_API_KEY`)
- `GEMINI.md` — Gemini CLI extension context
- `skills/ai-memory/` — guidance for remembering and recalling via MCP

## Build

From the repository root (requires `KB_ENDPOINT` in `.env`):

```bash
make render-plugin
```

This writes `.mcp.json`, `gemini-extension.json`, marketplace manifests,
`index.html`, and `plugins/ai-memory.zip` using `PLUGIN_PUBLIC_URL`.

## Caution

Hackathon-grade security only. Do not store personal or confidential data.

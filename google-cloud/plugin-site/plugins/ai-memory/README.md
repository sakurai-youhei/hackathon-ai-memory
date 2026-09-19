# AIメモリーいらんかえ～ agent plugin

Cursor / Claude Code / Gemini CLI / Antigravity CLI plugin that connects
agents to the Kibana Agent Builder MCP server for shared hackathon memory
(store and recall).

## Setup

Follow the distribution site (marketplace + setup guide):

```text
https://storage.googleapis.com/hackathon-ai-memory-plugin/index.html
```

## Contents

- `.mcp.json.j2` — Jinja template for Cursor / Claude (URL from `KB_ENDPOINT`)
- `gemini-extension.json.j2` — Jinja template for Gemini CLI
- `.cursor-plugin/plugin.json.j2` — Cursor manifest template (`variables.AI_MEMORY_API_KEY`)
- `.claude-plugin/plugin.json.j2` — Claude Code manifest template (`userConfig.AI_MEMORY_API_KEY`)
- `plugin.json.j2` — Antigravity CLI native plugin manifest
- `mcp_config.json.j2` — Antigravity CLI MCP configuration
- `VERSION` — shared semantic version for all plugin manifests
- `GEMINI.md` — Gemini CLI extension context
- `skills/ai-memory/SKILL.md.j2` — skill template with the Elasticsearch endpoint
  and indexing instructions

## Build

From the repository root (requires `ES_ENDPOINT` and `KB_ENDPOINT` in `.env`):

```bash
make render-plugin
```

This writes `.mcp.json`, `gemini-extension.json`, marketplace manifests,
`index.html`, and both versioned and compatibility plugin archives using
`PLUGIN_PUBLIC_URL`.

To increment the patch version, render the artifacts, and upload them:

```bash
make bump-plugin-version
```

## Caution

Hackathon-grade security only. Do not store personal or confidential data.

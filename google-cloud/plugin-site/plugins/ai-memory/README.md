# AIメモリーいらんかえ～ agent plugin

Cursor / Claude Code / Gemini CLI plugin that connects agents to the Kibana
Agent Builder MCP server for shared hackathon memory (store and recall).

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

This writes `.mcp.json` and `gemini-extension.json` with:

`{KB_ENDPOINT}/api/agent_builder/mcp`

## Install

### Cursor / Claude Code

Add the plugin marketplace / plugin directory from the distribution site, then
set `AI_MEMORY_API_KEY`.

### Gemini CLI

After rendering (or downloading the built plugin directory):

```bash
gemini extensions install /path/to/plugins/ai-memory
```

On install, set the **AI Memory API key** setting (`AI_MEMORY_API_KEY`).

## Runtime configuration

Set your encoded API key as `AI_MEMORY_API_KEY` (environment variable, Cursor
plugin variables, Claude Code user config, or Gemini extension settings). Do
not put the API key in the Jinja templates or commit it.

## Caution

Hackathon-grade security only. Do not store personal or confidential data.

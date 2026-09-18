# AIメモリーいらんかえ～ agent plugin

Cursor / Claude Code / Gemini CLI plugin that connects agents to the Kibana
Agent Builder MCP server for shared hackathon memory (store and recall).

## Marketplace

Distribution site (add this as the marketplace / download source):

```text
https://storage.googleapis.com/hackathon-ai-memory-plugin
```

### Claude Code

```text
/plugin marketplace add https://storage.googleapis.com/hackathon-ai-memory-plugin/marketplace.json
/plugin install ai-memory@hackathon-ai-memory
```

Then set `AI_MEMORY_API_KEY`.

### Cursor

Cursor Team Marketplace currently expects a Git repository. From this GCS site,
install the zip locally:

```bash
curl -fsSL "https://storage.googleapis.com/hackathon-ai-memory-plugin/plugins/ai-memory.zip" -o ai-memory.zip
mkdir -p ~/.cursor/plugins/local
unzip -o ai-memory.zip -d ~/.cursor/plugins/local
```

Reload Cursor, then set `AI_MEMORY_API_KEY`.

### Gemini CLI

```bash
curl -fsSL "https://storage.googleapis.com/hackathon-ai-memory-plugin/plugins/ai-memory.zip" -o ai-memory.zip
unzip -o ai-memory.zip -d /tmp
gemini extensions install /tmp/ai-memory
```

On install, set the **AI Memory API key** (`AI_MEMORY_API_KEY`).

## Recommended skill

Also install **elasticsearch-esql** from
[elastic/agent-skills](https://github.com/elastic/agent-skills). It helps the
agent query and aggregate memory data with ES|QL.

```bash
npx skills add elastic/agent-skills --skill elasticsearch-esql
```

For Claude Code, you can add the Elastic marketplace and install the
Elasticsearch plugin (includes `elasticsearch-esql`):

```bash
claude plugin marketplace add https://github.com/elastic/agent-skills
claude plugin install elastic-elasticsearch@elastic-agent-skills
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

# AIメモリーいらんかえ～

Use the `ai-memory` MCP tools to store and recall shared hackathon knowledge.

- Treat short requests such as 「覚えて」, 「覚えさせて」, 「思い出して」,
  “remember this,” and “recall that” as ai-memory requests even when the user
  does not name ai-memory.
- When the user asks to remember or memorize something, persist it via MCP
  unless they clearly request conversation-only memory.
- When the user asks to recall or search, query via MCP first, then answer from results.
- Prefer the **elasticsearch-esql** skill from
  [elastic/agent-skills](https://github.com/elastic/agent-skills) for ES|QL
  search and aggregation (`npx skills add elastic/agent-skills --skill elasticsearch-esql`).
- Respond in Japanese or English to match the user.
- Never store personal data, secrets, or credentials.

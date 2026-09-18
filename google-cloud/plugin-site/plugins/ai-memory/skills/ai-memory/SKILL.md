---
name: ai-memory
description: >-
  Store and retrieve shared hackathon knowledge through the ai-memory Kibana MCP
  server. Use when the user asks to memorize, remember, recall, search notes, or
  otherwise persist/look up project context in Japanese or English.
---

# AI Memory

Use the `ai-memory` MCP tools to persist and retrieve shared knowledge for this
hackathon project.

## When to use

- The user asks to remember, memorize, or save information
- The user asks to recall, remember, or search what was stored earlier
- The user refers to shared notes, context, or project memory

## Recommended companion skill

Installing **elasticsearch-esql** from
[elastic/agent-skills](https://github.com/elastic/agent-skills) is recommended.
Use it when ES|QL queries or aggregations help recall or explore stored memory.

```bash
npx skills add elastic/agent-skills --skill elasticsearch-esql
```

## Instructions

1. Prefer the `ai-memory` MCP server tools over inventing local files or guesses.
2. When storing information, write a clear, searchable summary of what the user
   asked to remember. Do not invent facts that were not provided.
3. When recalling information, search first, then answer from the returned
   results. Say clearly when nothing relevant was found. Prefer
   `elasticsearch-esql` when structured ES|QL search is a better fit.
4. Respond in Japanese when the user writes in Japanese, and in English when
   they write in English.
5. Never store personal data, secrets, credentials, or other sensitive content.
   If the user asks to store such content, refuse and explain briefly.

## Safety

This service is for a hackathon and has minimal security controls. Do not upload
or retain personally identifiable or confidential information.

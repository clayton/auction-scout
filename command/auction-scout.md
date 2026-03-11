---
description: Scout GoDaddy domain auctions for build-and-flip opportunities, auto-bid on high-scoring domains
argument-hint: [morning|evening|dry-run|report]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, WebSearch, WebFetch, Agent
---

Read and follow the instructions in `~/.claude/skills/auction-scout/SKILL.md`.

Argument: $ARGUMENTS

If no argument provided, auto-detect morning vs evening based on `~/.claude/skills/auction-scout/data/state.json` last_run timestamp. If last run was >8 hours ago or no last run today, run morning pass. Otherwise run evening pass.

# Auction Scout

A Claude Code skill that automatically scouts GoDaddy domain auctions for undervalued build-and-flip domains.

Scrapes your saved search for expiring domains, researches each one (active business detection, blacklist checks, Wayback history, trademark risk), scores them on a 100-point rubric, and auto-bids on high scorers. Designed to run twice daily via `/loop 12h /auction-scout`.

## What it looks for

Domains that map to a **specific, concrete product** in a proven market:

- **Hyper-niche micro-SaaS** — one tool, one buyer, one problem (e.g. `customcabinetquotes.com`)
- **Info products in spending niches** — ebooks/courses where people already pay (pets, fitness, beauty, dating, money)
- **Programmatic SEO / affiliate** — review sites, comparison tools, calculators with commercial intent
- **Simple iOS utility apps** — single-purpose apps the domain name maps to directly

Not interested in: ecommerce, communities, marketplaces, general-purpose SaaS, anything aspirational or requiring a team.

## Setup

1. Clone this repo to `~/.claude/skills/auction-scout/`
2. Copy the command entry point into your Claude Code commands directory:

```bash
cp command/auction-scout.md ~/.claude/commands/auction-scout.md
```

3. Copy the example state file and configure it:

```bash
cp data/state.example.json data/state.json
```

4. Edit `data/state.json` to set your preferences (mode, budgets, saved search name, Slack webhook)
5. Make sure you're logged into GoDaddy Auctions in Chrome (the skill uses browser automation, it won't log in for you)

## Command entry point

The skill is invoked via a Claude Code slash command. Place this file at `~/.claude/commands/auction-scout.md`:

```yaml
---
description: Scout GoDaddy domain auctions for build-and-flip opportunities, auto-bid on high-scoring domains
argument-hint: [morning|evening|dry-run|report]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, WebSearch, WebFetch, Agent
---

Read and follow the instructions in `~/.claude/skills/auction-scout/SKILL.md`.

Argument: $ARGUMENTS

If no argument provided, auto-detect morning vs evening based on
`~/.claude/skills/auction-scout/data/state.json` last_run timestamp.
If last run was >8 hours ago or no last run today, run morning pass.
Otherwise run evening pass.
```

## Usage

```
/auction-scout              # auto-detect morning or evening
/auction-scout morning      # full morning pass (scrape + research + score + bid)
/auction-scout evening      # evening pass (update prices, re-evaluate, final bids)
/auction-scout dry-run      # force dry-run mode regardless of config
/auction-scout report       # show today's report without running a pass
```

For automated twice-daily runs:

```
/loop 12h /auction-scout
```

## How it works

### Morning pass (~2.5 hours)

1. **Scrape** — Opens GoDaddy Auctions in Chrome, loads your saved search, extracts all domains (~600)
2. **Tier 1 filter** (~600 → ~50) — Quick heuristic score based on TF, age, price, name quality
3. **Tier 2 research** (top 50) — Active business detection, Wayback history, blacklist checks, trademark search
4. **Tier 3 deep eval** (top ~15) — AI product concept evaluation, niche opportunity assessment, competitor search
5. **Bidding** — Places bids on domains scoring 75+ (or logs dry-run actions)
6. **Report** — Generates daily markdown report in `data/reports/`

### Evening pass (~30 min)

1. Updates prices for morning candidates
2. Checks for outbids, re-evaluates
3. Quick scan for new listings
4. Places final bids before auctions close

## Scoring rubric (100 points)

| Dimension | Points | What it measures |
|-----------|--------|------------------|
| Domain Quality | 0-35 | Age, Majestic TF/CF, value/price ratio |
| Buildability | 0-35 | Name quality, product-market fit, niche opportunity |
| Risk | 0-30 | Active business, blacklists, trademarks, spam history |

### Action thresholds

| Score | Action | Max Bid |
|-------|--------|---------|
| 0-49 | Skip | — |
| 50-64 | Log only | — |
| 65-74 | Flag as interesting | — |
| 75-84 | Auto-bid | $30 |
| 85-89 | Auto-bid | $50 |
| 90-100 | Auto-bid | $100 (hard cap) |

## File structure

```
SKILL.md                         # Main skill instructions
references/
  scoring-rubric.md              # Detailed scoring weights and thresholds
  godaddy-ui-flow.md             # Chrome automation cookbook for GoDaddy
scripts/
  check-blacklists.sh            # DNS-based blacklist checker
data/
  state.example.json             # Template config (committed)
  state.json                     # Live config + state (gitignored)
  reports/                       # Daily markdown reports (gitignored)
```

## Requirements

- [Claude Code](https://claude.com/claude-code) with claude-in-chrome MCP tools for browser automation
- GoDaddy Auctions account with an active saved search
- Chrome browser with the Claude in Chrome extension

---
name: auction-scout
description: Scout GoDaddy domain auctions for undervalued build-and-flip domains. Scrapes saved search, researches reputation/buildability, scores domains, and auto-bids on high scorers. Run via /loop 12h /auction-scout for morning + evening passes.
---

# Auction Scout

Automated domain auction scouting for build-and-flip opportunities on GoDaddy Auctions.

**Target domains:** Micro-SaaS, programmatic SEO, info products, iOS apps.
**NOT interested in:** Communities, forums, social networks, marketplaces.

## Reference Files

Before executing, read these reference files for detailed scoring and UI automation:
- `~/.claude/skills/auction-scout/references/scoring-rubric.md` - Scoring weights, thresholds, and action table
- `~/.claude/skills/auction-scout/references/godaddy-ui-flow.md` - Chrome automation cookbook for GoDaddy
- `~/.claude/skills/auction-scout/data/state.json` - Config and persistent state

## Arguments

| Argument | Behavior |
|----------|----------|
| `morning` | Full morning pass (scrape + research + score + bid) |
| `evening` | Evening pass (update prices, re-evaluate, final bids) |
| `dry-run` | Force dry-run mode regardless of state.json config |
| `report` | Just show today's report without running a pass |
| _(none)_ | Auto-detect: if last run was >8 hours ago or no run today, morning; otherwise evening |

---

## Morning Pass Workflow

### Step 1: Initialize

1. Read `~/.claude/skills/auction-scout/data/state.json`
2. Check if `mode` is `dry-run` or `live` (argument `dry-run` overrides to dry-run)
3. Reset `spend_today_usd` if date changed since last run
4. Reset `spend_this_week_usd` if new week (Monday)
5. Clear `active_candidates` from previous day

### Step 2: Scrape GoDaddy Auctions

Use Chrome automation (claude-in-chrome tools) following `references/godaddy-ui-flow.md`.

1. Navigate to `https://auctions.godaddy.com/trpSearchResults.aspx`
2. **Screenshot** - verify logged in. If not logged in:
   - Send Slack alert: "GoDaddy login expired - auction scout cannot run"
   - Write error to state.json and EXIT
3. Load saved search "search001" (or the name in `config.saved_search_name`)
4. Wait for results to load, verify filter badges
5. Extract domains from ALL pages using the JS extraction snippet from godaddy-ui-flow.md
   - Navigate through all pages (typically 4 pages of 150)
   - Combine all results
6. Save raw data to `~/.claude/skills/auction-scout/data/raw-scrape-YYYY-MM-DD-morning.json`
7. Update `state.json`: `last_run.timestamp`, `last_run.type = "morning"`, `last_run.domains_scraped`

### Step 3: Tier 1 - Quick Filter (~600 -> ~50)

Filter out immediately disqualified domains:
- Price > $100 (over hard cap)
- Time left < 1 hour (not enough time to research)
- TF = 0 AND CF = 0 AND age < 3 (no signals at all)

Score remaining domains with a quick heuristic:
```
quick_score = (TF * 2) + (age * 0.5) + (estValue / price) + name_quality_heuristic
```

**Name quality heuristic** (quick, no AI needed):
- Length <= 8 chars: +3
- Length 9-12: +2
- Length 13-15: +1
- Contains common keyword (tool, app, hub, pro, dev, etc.): +1
- Contains numbers: -1
- Contains hyphens: -2
- Triple+ consonant cluster: -1

Sort by quick_score descending, take top 50.

### Step 4: Tier 2 - Research (top 50, ~2 min each)

For each of the top 50 domains, research in this order. **Stop early if a disqualifying risk is found.**

#### 4a. Active Business Detection (MOST CRITICAL)

This is the #1 risk check. Domains with active businesses are legal/reputational landmines.

1. **WebSearch**: `"domain.com"` (with quotes)
   - Look for: active company websites, social media profiles, customer reviews, job listings
   - If found: score Risk = -30, mark as SKIP, move to next domain

2. **WebSearch**: `site:domain.com`
   - If significant indexed pages exist: active business likely, SKIP

3. **WebFetch**: Check if the domain currently resolves to a live website
   - If it shows an active business/product page: SKIP

#### 4b. Wayback Machine Check

**WebFetch**: `https://web.archive.org/web/timemap/json?url=domain.com&matchType=prefix&limit=20&output=json`

Evaluate:
- How many snapshots exist? (more = more history = generally good)
- What did the site look like recently? (active business = bad, parked = neutral)
- Any spam indicators? (pharma, casino, doorway pages, Japanese/Chinese character spam)
- Was it parked/unused for most of its life? (slight negative)

#### 4c. Blacklist Check

```bash
bash ~/.claude/skills/auction-scout/scripts/check-blacklists.sh domain.com
```

If `status` is `BLACKLISTED`: deduct 20 from Risk score. If on 2+ lists: SKIP.

#### 4d. Trademark Quick Check

**WebSearch**: `"domain-keyword" trademark` or `"domainname" registered trademark`

If clear trademark match found: SKIP.

#### 4e. Score Domain Quality Dimension

Using data from the GoDaddy scrape (TF, CF, age, estValue, price), calculate the Domain Quality score per the scoring rubric.

#### 4f. Score Risk Dimension

Tally all risk deductions found above. Start at 30, subtract.

#### 4g. Record Tier 2 Results

Store research findings and partial scores for each domain. Domains scoring below 40 at this point are dropped.

### Step 5: Tier 3 - Deep Evaluation (top ~15 scoring 55+)

Take the top 15 domains from Tier 2 that scored 55+.

#### 5a. DataForSEO Backlink Summary (if data-for-seo skill available)

Use the data-for-seo skill to get backlink profile data:
```
/data-for-seo backlinks summary domain.com
```

This provides more detailed link quality data than Majestic metrics alone.

#### 5b. Product Concept Evaluation (Concrete Products Only)

**The filter test:** Does this domain map to a product that helps people make more money, look/feel better, or solve a painful personal problem? If not, score 0-3 and move on.

For each domain, try to identify ONE specific product concept. Be ruthlessly concrete:

1. **What is the exact product?** Not "an AI tool" — what specific thing does it do? "A quote calculator for cabinet shops" or "a dog training video course."
2. **Who exactly buys it?** Not "businesses" — "freelance plumbers who need invoicing" or "first-time dog owners with puppies."
3. **What do they pay?** Name the price point. $29/mo SaaS, $47 ebook, affiliate commission on $X product.
4. **Who else sells this already?** Name 2-3 competitors. If you can't find any, the market probably doesn't exist.
5. **Can a solo dev build and launch this in 1-3 months?** If it needs a team, funding, or years of development, it's a pass.

**WebSearch** for each concept: search for competitors, existing products, pricing. Look for PROOF that people pay for this, not speculation that they might.

Score Product-Market Fit (0-15) per the scoring rubric. Be harsh — most domains will score 0-6 here. A score of 10+ means you found a proven market with paying customers and the domain is a near-perfect fit.

#### 5c. Niche Opportunity Assessment

**WebSearch**: Search for existing paid products in the domain's niche. Look for:
- Competitor products with visible pricing pages
- Affiliate programs in the niche (proof of commercial intent)
- Google Trends data for the niche keywords
- Reddit/forum discussions where people ask for solutions (demand signal)

Score Niche Opportunity (0-10) based on **evidence of existing paying customers**, not speculation about potential demand.

#### 5d. Score Buildability Dimension

Combine: Name Quality + Product-Market Fit + Niche Opportunity

#### 5e. Calculate Final Score

```
Final Score = Domain Quality (0-35) + Buildability (0-35) + Risk (0-30)
```

### Step 6: Bidding

Read action thresholds from scoring rubric. For each domain meeting bid threshold:

1. **Check budget**: Compare `spend_this_week_usd` against `weekly_budget_usd`
   - If >= 80% of weekly budget spent, only bid on 90+ scores
   - If >= 100%, do not bid at all

2. **Determine max bid** per score thresholds:
   - 75-84: up to $30
   - 85-89: up to $50
   - 90-100: up to $100

3. **If mode = "dry-run"**:
   - Log what WOULD be bid, but don't actually place bids
   - Include in report as "[DRY RUN] Would bid $X on domain.com (score: Y)"

4. **If mode = "live"**:
   - Navigate to domain's auction page in Chrome
   - **Screenshot** to verify current price matches expected price
   - If price has changed significantly (>20% increase), re-evaluate
   - Place bid using Chrome automation (see godaddy-ui-flow.md)
   - **Screenshot** after bid to confirm
   - Update `state.json`: add to `bids_placed`, update `spend_today_usd` and `spend_this_week_usd`

5. Add all scored domains (65+) to `active_candidates` in state.json for evening pass

### Step 7: Generate Report

Create `~/.claude/skills/auction-scout/data/reports/YYYY-MM-DD.md`:

```markdown
# Auction Scout Report - YYYY-MM-DD

## Summary
- **Mode**: dry-run / live
- **Domains scraped**: N
- **Passed Tier 1**: N
- **Passed Tier 2**: N
- **Deep evaluated (Tier 3)**: N
- **Bids placed**: N
- **Weekly spend**: $X / $200

## Top Scored Domains

### 1. domain.com - Score: XX/100
- **Price**: $XX | **Est Value**: $XXX | **Age**: X yrs
- **Majestic**: TF XX, CF XX, TF/CF X.XX
- **Domain Quality**: XX/35 | **Buildability**: XX/35 | **Risk**: XX/30
- **Product concepts**:
  1. Concept 1 - brief description
  2. Concept 2 - brief description
- **Action**: [BID $XX / DRY RUN / SKIP / INTERESTING]
- **Risk notes**: any flags found

(repeat for all domains scoring 50+)

## Interesting Domains (scored 65-74, no bid)
- domain1.com (score: XX) - brief note
- domain2.com (score: XX) - brief note

## Skipped Notable Domains
- domain.com - reason (active business / blacklisted / trademark)

## Bids Placed
| Domain | Score | Bid Amount | Current Price | Status |
|--------|-------|------------|---------------|--------|
| ... | ... | ... | ... | ... |
```

### Step 8: Slack Notification

If `config.slack_webhook` is set, send a summary:

```bash
curl -s -X POST "$SLACK_WEBHOOK" \
  -H 'Content-Type: application/json' \
  -d '{
    "text": "Auction Scout Morning Pass Complete\n- Scraped: N domains\n- Top scorer: domain.com (XX pts)\n- Bids placed: N ($XX total)\n- Mode: dry-run/live"
  }'
```

If no webhook configured, just output the summary to the console.

### Step 9: Update State

Write updated `state.json` with:
- `last_run` timestamp and type
- `active_candidates` (domains scoring 65+ for evening follow-up)
- Updated spend tracking
- Any bids placed

---

## Evening Pass Workflow

### Step 1: Initialize
1. Read `state.json`, verify morning pass ran today
2. If no morning pass today, run morning pass instead

### Step 2: Update Active Candidates
1. Navigate to GoDaddy auctions in Chrome
2. Verify login (screenshot)
3. For each domain in `active_candidates`:
   - Search for it on GoDaddy
   - Check current price
   - Check time remaining
   - Has price changed? Has someone outbid us?

### Step 3: Re-evaluate
For domains where we've been outbid:
- Is it still worth bidding at the new price?
- Re-score with updated price
- If still above threshold, decide on re-bid

For domains with < 2 hours remaining:
- Final bid-or-abandon decision
- If we're winning, no action needed
- If we're losing and score is 80+, consider increasing bid

### Step 4: New Listings Quick Scan
1. Load saved search again
2. Compare against morning's raw scrape
3. Any new domains? Run quick Tier 1 filter
4. If any new domains pass Tier 1 with high quick_score, do abbreviated Tier 2 research

### Step 5: Place Final Bids
Same bidding logic as morning pass Step 6, but with updated prices.

### Step 6: Update Report
Append evening section to today's report:

```markdown
## Evening Update

### Price Changes
| Domain | Morning Price | Evening Price | Our Bid | Status |
|--------|--------------|---------------|---------|--------|

### New Listings Found
- domain.com (quick score: XX) - brief assessment

### Final Bids
| Domain | Score | Bid Amount | Action |
|--------|-------|------------|--------|
```

### Step 7: Slack Update
Send evening summary to Slack webhook.

### Step 8: Update State
Update `state.json` with evening results.

---

## Report-Only Mode

When argument is `report`:
1. Read today's report from `data/reports/YYYY-MM-DD.md`
2. If no report exists, say so
3. Display the report contents
4. Show current state.json summary (weekly spend, active candidates, recent purchases)

---

## Error Handling

- **GoDaddy not logged in**: Slack alert + EXIT. Do not attempt to log in.
- **CAPTCHA detected**: Slack alert + EXIT. Do not attempt to solve.
- **Chrome not responding**: Retry once after 10 seconds. If still failing, EXIT with error.
- **DataForSEO unavailable**: Skip backlink analysis, note in report. Don't fail the whole run.
- **Blacklist script timeout**: Allow 10 seconds per domain. Skip on timeout, note in report.
- **Budget exceeded**: Log but don't bid. Make this clear in the report.

## Important Rules

1. **NEVER bid on a domain with an active business** - this is the single most important rule
2. **NEVER exceed the hard cap ($100)** regardless of score
3. **NEVER exceed weekly budget** - track carefully in state.json
4. **Always screenshot before bidding** - create audit trail
5. **In dry-run mode, NEVER place real bids** - log only
6. **If anything feels wrong, err on the side of not bidding**
7. **Clean up old raw scrape files** - keep only last 7 days of raw-scrape JSON files

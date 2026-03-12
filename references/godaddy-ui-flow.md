# GoDaddy Auctions - Chrome Automation Cookbook

## URLs
- Auctions home (beta UI): `https://auctions.godaddy.com/beta`
- Auctions home (legacy): `https://auctions.godaddy.com/trpSearchResults.aspx`
- **Use the beta UI** - it's the default as of 2026-03

## Login Check
Before any scraping, take a screenshot and verify:
- If you see "Sign In" link in the header, login has expired -> Slack alert and EXIT
- If you see user avatar/name in header, you're logged in -> proceed

## Loading Saved Search "search001"

1. Navigate to `https://auctions.godaddy.com/beta`
2. The saved search may already be loaded if it was the last used search
3. Look for `Search Results "search001"` heading to confirm
4. If not loaded: click "Saved Searches" dropdown -> "View Saved Searches" modal -> click "search001"

## Preferred: Export CSV from Saved Search

**This is faster than JS pagination.** From the Saved Searches modal:
1. Click "Saved Searches" dropdown near the results heading
2. Click "View Saved Searches" to open the modal
3. Click the download icon (Export column) next to "search001"
4. This downloads a CSV with ALL results (all pages) in one file
5. Parse the CSV instead of scraping the table

Fallback to JS extraction if export doesn't work or if you need real-time data.

**Alternative if saved search doesn't load:**
Set filters manually:
- TLD: .com only
- Price: $0 - $50
- Auction type: Expiring
- End time: Today
- Majestic TF: min 10

## Table Column Mapping (Beta UI)

The beta results table has these columns (0-indexed `<td>` cells):

| Index | Column | Notes |
|-------|--------|-------|
| 0 | Eye icon | Watch/unwatch |
| 1 | Checkbox | Selection |
| 2 | Name | Domain name (contains `<a>` link) |
| 3 | Bids | Number of bids |
| 4 | Price* | Current price or "Buy Now" price |
| 5 | Traffic | Est. monthly traffic (usually N/A) |
| 6 | Age | Domain age in years |
| 7 | Enter Bid | Input field + Bid button |
| 8 | Estimated Value | GoDaddy's estimated value (has warning icon) |
| 9 | Taken TLDs | Number of TLD variants registered |
| 10 | Exact Match TLDs | TLDs with exact match |
| 11 | Developed TLDs | TLDs with developed sites |
| 12 | Time Left | Countdown (e.g., "15h 26m") |
| 13 | Majestic TF | Trust Flow |
| 14 | Majestic CF | Citation Flow |
| 15 | Backlinks | Total backlinks count |
| 16 | Referring Domains | Unique referring domains |

## Extracting Domain Data (JavaScript)

Use this JS snippet via `mcp__claude-in-chrome__javascript_tool` to extract all domains from the current page:

```javascript
(() => {
  const rows = document.querySelectorAll('table.searchResults tbody tr, table.gridContent tbody tr, [class*="auction"] tr[data-domain], .result-row');
  const domains = [];
  rows.forEach(row => {
    const cells = row.querySelectorAll('td');
    if (cells.length >= 13) {
      const domain = (cells[2]?.textContent || '').trim();
      if (domain && domain.includes('.')) {
        domains.push({
          domain: domain,
          bids: parseInt((cells[3]?.textContent || '0').trim()) || 0,
          price: parseFloat((cells[4]?.textContent || '0').replace(/[$,]/g, '')) || 0,
          age: parseInt((cells[6]?.textContent || '0').trim()) || 0,
          estValue: parseFloat((cells[8]?.textContent || '0').replace(/[$,]/g, '')) || 0,
          timeLeft: (cells[12]?.textContent || '').trim(),
          tf: parseInt((cells[13]?.textContent || '0').trim()) || 0,
          cf: parseInt((cells[14]?.textContent || '0').trim()) || 0,
          tfcf: parseFloat((cells[15]?.textContent || '0').trim()) || 0,
          refDomains: parseInt((cells[16]?.textContent || '0').replace(/,/g, '')) || 0
        });
      }
    }
  });
  return JSON.stringify(domains, null, 2);
})()
```

## Pagination

- Default shows 150 results per page
- Look for pagination controls at bottom of results
- Click "Next" or page numbers to navigate
- Repeat extraction for each page
- Typical search yields ~600 domains across 4 pages

**Pagination JS:**
```javascript
(() => {
  const nextBtn = document.querySelector('.pagination .next a, [class*="next"] a, a[aria-label="Next"]');
  if (nextBtn) { nextBtn.click(); return 'navigated'; }
  return 'no-next-button';
})()
```

## Placing a Bid

1. Click on the domain name to open the auction detail page
2. Take a screenshot to verify the current price matches expected price
3. Find the "Enter Bid" input field
4. Clear and type the bid amount
5. Click the "Bid" button
6. Take a screenshot to verify bid was placed
7. Check for confirmation message or error

**CRITICAL: Always screenshot before and after bidding to create an audit trail.**

## Buy It Now

For fixed-price (closeout) domains:
1. Click domain name to open detail page
2. Screenshot to verify price
3. Click "Buy It Now" button
4. Confirm purchase in the modal
5. Screenshot confirmation

## Common Issues

- **Session timeout**: GoDaddy sessions expire after ~30 minutes of inactivity. Always check login state first.
- **Bid too low**: Minimum bid increment is usually $1. If your bid is too low, the page will show an error.
- **Auction ended**: Time Left shows "Closed" - skip this domain.
- **Price changed**: Between scraping and bidding, the price may have changed due to other bidders. Always re-verify.

## Rate Limiting
- Don't navigate pages too quickly - add 2-3 second waits between page loads
- GoDaddy may show CAPTCHA if you scrape too aggressively
- If CAPTCHA appears -> Slack alert and EXIT

---

## Supplementary Search Strategies

Beyond the primary saved search "search001", run these additional searches to broaden the candidate pool.

### Strategy 2: Hidden Gems (GoDaddy Curated)

GoDaddy's "Hidden Gems" filter surfaces undervalued domains they've identified. Combined with our filters, this catches domains search001 might miss.

**Filters:**
- Top Picks: Hidden Gems (checked)
- Type: Expiring Auctions + Closeouts (Buy Now)
- Extensions: .com
- Price: Max $100
- Majestic TF: Min 10
- No keyword (empty search box)

Typical yield: ~150 results. Many are local businesses (skip), but gems surface — look for brandable names with product potential or niche-match redirect value.

### Strategy 3: High-TF Quality Sweep

Catches the highest-authority domains expiring today regardless of niche. Small result set but highest redirect value potential.

**Filters:**
- Type: Expiring Auctions + Closeouts (Buy Now)
- Extensions: .com
- Price: Max $100
- Majestic TF: Min 20
- No keyword (empty search box)

Typical yield: 5-15 results. Every result is worth evaluating since TF 20+ is rare at this price point.

### Strategy 4: Niche Keyword Searches

Search for keywords matching our existing properties (from niche-map.md) to find 301 redirect candidates.

**Filters:**
- Type: Expiring Auctions + Closeouts (Buy Now)
- Extensions: .com
- Price: Max $100
- Majestic TF: Min 10
- Keyword: rotate through niche terms

**Good keyword groups (typically return 10-50 results):**
- `photo`, `image`, `design` (AI Image niche)
- `study`, `learn`, `quiz` (Education niche)
- `habit`, `tracker`, `reminder` (Habits/Productivity niche)
- `recipe`, `cook`, `food` (Info product potential)
- `fitness`, `workout`, `health` (Proven spending niche)
- `dog`, `pet`, `cat` (Proven spending niche)

**Keywords that don't work well (too narrow with TF filter):**
- `invoice`, `boilerplate`, `flashcard` — too specific, 0 results
- `email` — returns only premium domains out of budget

### Search Execution Order (Morning Pass)

1. **search001** (primary) — the bulk pipeline (~600 domains)
2. **High-TF Sweep** (Strategy 3) — quick, high-value (~5-15 domains)
3. **Hidden Gems** (Strategy 2) — curated supplement (~150 domains)
4. De-duplicate across all searches before Tier 1 filtering

Strategies 2-3 add ~10 minutes to the morning pass but can surface domains that search001 misses (different price range, different TF threshold, GoDaddy curation).

### Advanced Search Filter Setup via Chrome

To set up Advanced Search filters:
1. Click "Advanced Search" next to the search bar
2. Click each filter dropdown to configure:
   - **Type**: Check "Expiring Auctions" and optionally "Closeouts (Buy Now)"
   - **Price**: Enter Max price in "Max price ($)" field
   - **Extensions**: Check ".com" under Common Extensions
   - **Majestic**: Enter Min TF in "Majestic TF" Min field
   - **Top Picks**: Check "Hidden Gems" (for Strategy 2 only)
3. Click "Apply Filters" (button turns black when filters are ready)
4. Active filters show as teal/green buttons
5. "Clear Filters" resets all filters

**Note:** Changing the search keyword and clicking the search icon preserves active filters. You can swap keywords without re-setting filters.

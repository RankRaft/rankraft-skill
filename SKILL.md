---
name: rankraft
description: Use when writing code against the RankRaft AI API or its SDKs (npm `rankraft`, PyPI `rankraft`) - reading AI visibility, citation, sentiment, crawler and referral data, managing tracked prompts, choosing between the REST API and the MCP server, and handling its filters, cursors, rate limits and error codes.
---

# RankRaft AI - API and SDKs

RankRaft AI measures how AI answer engines (ChatGPT, Google AI Overviews / AI Mode,
Gemini, Copilot, Claude, Perplexity) and AI crawlers see a brand. This skill is
for building against its API.

## Decide first: REST or MCP?

| | REST API (`api.rankraft.ai/v1`) | MCP server (`mcp.rankraft.ai`) |
|---|---|---|
| For | code: dashboards, warehouses, automations | chat: Claude, ChatGPT, Cursor asking questions |
| Plan | **Enterprise only** | every paid plan |
| Auth | organization API key `rr_api_…` in `X-API-Key` | OAuth, sign in with the dashboard account |
| Can write | yes - manage prompts | no, read-only |

If the user wants a program to pull data or manage prompts → REST, through an
SDK. If they want to *ask* about their data in a chat client → point them at
the MCP server; there is nothing to code.

## Use an SDK, not raw HTTP

```bash
npm install rankraft          # Node 20+, Workers, Deno, Bun. Zero deps.
pip install 'rankraft[pandas]' # Python 3.10+. One dep (httpx). pandas optional.
```

Both SDKs encode six things that are easy to get wrong by hand - see
[references/why-the-sdks.md](references/why-the-sdks.md). Reach for raw
`fetch`/`requests` only for a route an SDK does not model yet; both expose a
`request()` escape hatch for that.

### Node

```ts
import { RankRaft, f } from "rankraft";

const rr = new RankRaft();                       // RANKRAFT_API_KEY
const [site] = await rr.sites.list();

for await (const row of rr.reports.visibility({
  site_id: site!.id,
  start_date: "2026-09-01",
  end_date: "2026-09-30",
  group_by: ["date", "platform"],
  metrics: ["visibility_score", "mention_rate"],
  filter: f.and(f.in("platform", ["chatgpt", "ai_mode"]), f.not(f.is("category", "Brand"))),
})) {
  console.log(row.date, row.platform, row.visibility_score);
}
```

Report methods are **awaitable for page one and `for await`-able for every
row**. Non-paginated reads return the payload directly.

### Python

```python
from rankraft import RankRaft, F

with RankRaft() as rr:                           # RANKRAFT_API_KEY
    site = rr.sites.list()[0]
    page = rr.reports.visibility(
        site_id=site["id"],
        start_date="2026-09-01",
        end_date="2026-09-30",
        group_by=["date", "platform"],
        filter=F("platform").in_(["chatgpt", "ai_mode"]) & ~F("category").is_("Brand"),
    )
    df = page.to_pandas(all_pages=True)
```

`for row in page` is **this page only**; `page.auto_paging()` crosses pages.
Everything is keyword-only.

## The surface

| SDK method (Node / Python) | Endpoint |
|---|---|
| `me()` | `GET /v1/me` - key, org, plan, rate limits; use as a connection test |
| `sites.list()` · `sites.get()` | `GET /v1/sites` · `GET /v1/sites/{site_id}` |
| `sites.competitors()` | `GET /v1/sites/{site_id}/competitors` |
| `sites.actions({status})` | `GET /v1/sites/{site_id}/actions?status=open\|done\|all` |
| `platforms.list()` | `GET /v1/platforms` |
| `prompts.list / create / update / setStatus` (`set_status`) | `GET / POST / PATCH /v1/sites/{site_id}/prompts`, `PATCH …/prompts/status` |
| `reports.visibility / citations / sentiment` | `POST /v1/reports/{visibility,citations,sentiment}` |
| `answers.query()` | `POST /v1/answers` (raw answers; pages ≤ 50) |
| `reports.bots / referrals` | `POST /v1/reports/{bots,referrals}` - from the customer's server logs |
| `openapi()` | `GET /v1/openapi.json` - public, no key |

Parameter and field names are the wire names in both languages - `site_id`,
`start_date`, `group_by` - never camelCase. Full request/response shapes:
[references/api-reference.md](references/api-reference.md).

## Rules that bite

1. **Never in a browser.** The API sends no CORS headers and a key reads every
   site in the organization. The Node SDK throws at construction in a browser.
   Server only: route handlers, server actions, Workers, jobs.
2. **The key is a header.** `X-API-Key: rr_api_…` (or `Authorization: Bearer`).
   A key in a query string is a 400 and the API tells you to revoke it.
   `rr_live_…` is a *site* key for sending traffic - a different thing.
3. **Dates are inclusive `YYYY-MM-DD` in UTC.** Answer reports cover ≤ 92 days,
   traffic reports ≤ 400. A warehouse backfill is a loop over windows - [references/recipes.md](references/recipes.md#backfill).
4. **Cursors are bound to the query.** Every field except `cursor` and `limit`
   is fingerprinted; change the filter mid-pagination and you get 400
   `invalid_cursor`. The SDKs freeze the body for you - do not rebuild it from
   `info`.
5. **Filter values are strings** (or lists of strings), ops are
   case-insensitive, depth ≤ 3, lists ≤ 100. The SDK builders stringify
   numbers/booleans; raw dicts must already be strings.
6. **Unknown fields are a 422**, not ignored. Every request object is strict.
7. **Rate limits: 120 requests/min per key, 20 writes/min.** A 429 carries
   `Retry-After: 60` and no remaining-count header, so pacing is reactive only.
   The SDKs honour `Retry-After` exactly and bound total sleep (70 s default).
8. **Prompts cannot be deleted and their text cannot be edited.** Disable
   instead; create a new prompt for new wording. Both keep history comparable.
   Writes need a key with `write` permission.
9. **A 404 for a site means "not in this organization"** - the API never says
   403 for someone else's site, so ids cannot be enumerated.
10. **Numbers equal the dashboard.** Visibility Score is 0–100 (45% mention
    rate, 35% citation rate, 20% prompt coverage), scored by the same package
    the dashboard uses. Quote it with its denominator (`answers`).

## Errors

Every error is `{ "error": { "code", "message", "details"? }, "request_id" }`.
Switch on `code`; `request_id` goes in any support message. Full table and the
SDK class for each: [references/errors.md](references/errors.md).

## Recipes

Visibility over time, competitor leaderboard, citation share by domain,
bulk-loading prompts from a CSV, daily bot traffic to a warehouse, a 92-day
backfill loop, and `curl` equivalents: [references/recipes.md](references/recipes.md).

## Checking a key or a route quickly

```bash
RANKRAFT_API_KEY=rr_api_… bash scripts/smoke.sh
```

Calls `/v1/me` and `/v1/sites` and prints the plan, the key's permission and
the site ids - the three things most "it doesn't work" reports come down to.

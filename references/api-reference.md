# API reference - shapes that matter when writing code

Base URL `https://api.rankraft.ai/v1`. Header `X-API-Key: rr_api_…`. All
bodies `application/json`, all objects strict. The machine-readable contract is
`GET /v1/openapi.json` (public, no key); this page is the parts you need while
typing.

## Conventions

- **Dates** - inclusive `YYYY-MM-DD`, UTC. Answer reports: span ≤ 92 days.
  Traffic reports: ≤ 400 days, and accept an IANA `timezone` (default `UTC`)
  which sets day boundaries and `date`/`hour` buckets.
- **Pagination** - `info.next_cursor` (null on the last page) goes back as
  `cursor` with an otherwise identical body. `limit` may change between pages.
- **Filters** - see below. Which fields each endpoint accepts is listed per
  endpoint.
- **Sort** - `{ "field": "<a requested metric or group_by>", "dir": "asc"|"desc" }`.
- **Site ids** - UUIDs from `GET /v1/sites`. Another organization's id is a
  404.

## Discovery

**`GET /me`** → `{ data: { key: { id, name, permission: "read"|"write", expires_at }, organization: { id, name, plan }, rate_limits: { requests_per_minute, writes_per_minute } } }`

**`GET /sites`** → `{ data: Site[] }` · **`GET /sites/{site_id}`** → `{ data: Site }`

```
Site { id, name, domain, created_at, platforms: string[], last_answer_scan: { date, status } | null }
```

**`GET /sites/{site_id}/competitors`** → `{ data: [{ id, name, domains: string[], confirmed, source }] }`
Only `confirmed` competitors count in leaderboards and share of voice.

**`GET /platforms`** → `{ data: [{ id, name, available }] }` - `available` is
whether RankRaft AI collects answers from that engine today.

**`GET /sites/{site_id}/actions?status=open|done|all`** (default `open`) → `{ data: Action[] }`

```
Action { id, title, why, detail, category, impact: High|Medium|Low, effort,
         target_metric: mention|citation|coverage, kind: one_off|ongoing, cadence, period,
         status: open|done|dismissed, target_prompts: [{id,text}], target_platforms, target_url,
         created_at, outcome: { marked_done_at, result_due, verdict, summary } | null }
```
Read-only; never regenerates cards. Fresh as of the last dashboard open.

## Prompts (`write` permission for everything but GET)

**`GET /sites/{site_id}/prompts?status=&category=&limit=≤500&cursor=`** → `{ info, data: Prompt[] }`, oldest first.

```
Prompt { id, text, category, market: string|null, status: active|disabled, created_at, updated_at }
category ∈ Discovery | Comparison | Alternatives | How-to | Pricing | Brand
```

**`POST /sites/{site_id}/prompts`**
```json
{ "prompts": [{ "text": "best mixed pickle brand", "category": "Discovery", "market": "Pakistan", "active": true }], "dry_run": false }
```
1–100 prompts; `text` 3–300 chars; `category` defaults Discovery; `active` defaults true.
→ `{ dry_run, created: number, existing: number, data: Prompt[] }`.
Existing text (case- and whitespace-insensitive) is returned, not duplicated.
Exceeding the plan's active-prompt cap refuses the **whole** request with
`422 prompt_limit_reached`.

**`PATCH /sites/{site_id}/prompts`** - `{ "prompts": [{ "id", "category"?, "market"? }], "dry_run" }`
→ `{ dry_run, not_found: string[], data: Prompt[] }`. Text is immutable.

**`PATCH /sites/{site_id}/prompts/status`** - `{ "prompt_ids": [≤500], "status": "active"|"disabled", "dry_run" }`
→ `{ dry_run, changed: string[], unchanged: string[], not_found: string[] }`.
There is no delete: disabled prompts keep their history.

## Answer reports (POST)

Shared body: `site_id, start_date, end_date, filter?, limit?, cursor?`.
Every row carries the requested `group_by` dimensions; `prompt` as a dimension
is `{ id, text }`. `info` adds `site_id, start_date, end_date, count,
total_results, next_cursor`.

**`/reports/visibility`**
- `group_by` ≤ 2 of `date | platform | prompt | category`
- `metrics` ⊆ `visibility_score | mention_rate | citation_rate | prompt_coverage | average_position | share_of_voice | answers` (default all)
- `brands`: `"owned"` (default, your brand) · `"all"` (you + confirmed competitors, ranked) · `[names]` (≤ 20)
- `sort: { field: <metric>, dir }` · `limit` ≤ 100 (default 50)
- filter fields: `platform`, `prompt` (id or text), `category`
- row: `{ …dims, brand: { name, owned }, rank, …metrics }`. `average_position` is null when never named.

**`/reports/citations`**
- `entity`: `"domain"` (default) | `"page"`
- `group_by` ≤ 2 of `date | platform | prompt`
- `metrics` ⊆ `answers | citations | citation_share` · `limit` ≤ 100
- filter fields: `platform`, `prompt`, `category`, `domain`, `owner` (`own|competitor|third_party`), `source_kind`
- row: `{ …dims, domain, page?, owner, source_kind, rank, …metrics }`

**`/reports/sentiment`**
- `group_by` ≤ 2 of `date | platform | prompt | category` · `limit` ≤ 100
- row: `{ …dims, positive, neutral, negative, answers_mentioning, answers }` - shares are of answers that name you; unjudged counts as neutral.

**`/answers`** (raw answers, newest first)
- `platforms?` ≤ 10 · `prompt_ids?` ≤ 100 · `include?` ⊆ `prompt | platform | date | text | brand_mentioned | brand_position | sentiment | mentions | citations` (default all) · `limit` ≤ 50 (default 20)
- no `filter`, no `group_by`
- row: `{ id, date?, platform?, prompt?: {id,text}, text?, brand_mentioned?, brand_position?, sentiment?, mentions?: string[], citations?: [{ url, domain, title, position, own_site }] }`

## Traffic reports (POST) - Agent Analytics, from the customer's server logs

Shared body: `site_id, start_date, end_date, timezone?, group_by? (≤3), metrics? (≥1), filter?, sort?, limit? (≤500, default 100), cursor?`.
Needs an integration (WordPress plugin, Cloudflare Worker, snippet or log
drain) installed on the site. Spoofed crawler hits are excluded unless you
filter on `verified` yourself.
Filter fields: `bot_name, bot_provider, bot_type, verified, path, page_type, referral_source`.

**`/reports/bots`**
- `group_by` ⊆ `date | hour | bot_name | bot_provider | bot_type | path | page_type`
- `metrics` ⊆ `hits | pages | verified_share | error_hits | last_visit` (default hits, pages, verified_share)
- `bot_type` ∈ `ai_assistant | ai_training | index | ai_agent`; `hour` is `YYYY-MM-DDTHH:00` in the requested zone; `verified_share` is 0–1.

**`/reports/referrals`**
- `group_by` ⊆ `date | hour | referral_source | path | page_type`
- `metrics` ⊆ `visits | landing_pages | last_visit` (default visits, landing_pages)

## Filter grammar

```json
{ "and": [
    { "field": "platform", "op": "in", "value": ["chatgpt", "ai_mode"] },
    { "not": { "field": "category", "op": "is", "value": "Brand" } }
] }
```

- Nodes: a leaf `{ field, op, value }`, `{ "and": [1–20] }`, `{ "or": [1–20] }`, `{ "not": node }`. Depth ≤ 3.
- Ops: `is | not_is | in | not_in | contains | not_contains`, all case-insensitive. `in`/`not_in` take a list (≤ 100); the others a single value.
- Values: strings, 1–300 chars. Booleans as `"true"`/`"false"`.
- Answer reports evaluate the tree in memory; traffic reports translate it to allow-listed SQL. Nothing a caller sends ever becomes SQL text.

## Limits at a glance

| | |
|---|---|
| Requests | 120 / 60 s per key · 20 writes / 60 s per key · 30 failed auths / 60 s per IP |
| Body | ≤ 256 KB, JSON only |
| Spans | answers ≤ 92 days · traffic ≤ 400 days |
| Page size | visibility/citations/sentiment ≤ 100 · answers ≤ 50 · traffic ≤ 500 · prompts ≤ 500 |
| Filters | depth ≤ 3 · group children 1–20 · list 1–100 · value 1–300 chars |
| Prompts | 100 per create/update · 500 per status change · text 3–300 chars · plan cap on active prompts |
| Keys | expire after 30/90/180/365 days (chosen at creation) · `read` or `write` |
| Response headers | `X-Request-Id`, `X-RateLimit-Limit: 120`, `X-RateLimit-Policy: 120;w=60`, `Cache-Control: no-store`; **no** `Access-Control-*` |

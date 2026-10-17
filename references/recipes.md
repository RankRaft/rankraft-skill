# Recipes

Each one in Node, Python and `curl`. All assume `RANKRAFT_API_KEY` is set and
`SITE` is a site id from `GET /v1/sites`.

## Visibility over time, per engine

```ts
const rows = await rr.reports.visibility({
  site_id: SITE, start_date: "2026-07-01", end_date: "2026-09-30",
  group_by: ["date", "platform"], metrics: ["visibility_score", "answers"],
}).all();
```
```python
df = rr.reports.visibility(site_id=SITE, start_date="2026-07-01", end_date="2026-09-30",
                           group_by=["date", "platform"], metrics=["visibility_score", "answers"]).to_pandas(all_pages=True)
pivot = df.pivot(index="date", columns="platform", values="visibility_score")
```
```bash
curl -s https://api.rankraft.ai/v1/reports/visibility -H "X-API-Key: $RANKRAFT_API_KEY" -H 'content-type: application/json' \
  -d '{"site_id":"'$SITE'","start_date":"2026-07-01","end_date":"2026-09-30","group_by":["date","platform"],"metrics":["visibility_score","answers"]}'
```
Always carry `answers` alongside a rate: a 100% mention rate over two answers
is not a result.

## Competitor leaderboard for the month

```ts
const board = await rr.reports.visibility({
  site_id: SITE, start_date: "2026-09-01", end_date: "2026-09-30",
  brands: "all", metrics: ["visibility_score", "share_of_voice", "mention_rate"],
}).all();
// rows carry brand.name, brand.owned and rank; rank 1 is the leader
```
```python
board = rr.reports.visibility(site_id=SITE, start_date="2026-09-01", end_date="2026-09-30",
                              brands="all", metrics=["visibility_score", "share_of_voice"]).all()
you = next(r for r in board if r["brand"]["owned"])
```
Only competitors **confirmed** in the dashboard are ranked. Unconfirmed ones
(found in answers) appear in `GET …/competitors` with `confirmed: false`.

## Who the engines cite, by domain - competitors only

```ts
const cited = await rr.reports.citations({
  site_id: SITE, start_date, end_date,
  filter: f.is("owner", "competitor"), metrics: ["answers", "citation_share"],
}).all();
```
```python
cited = rr.reports.citations(site_id=SITE, start_date=s, end_date=e,
                             filter=F("owner").is_("competitor"), metrics=["answers", "citation_share"]).all()
```
`entity: "page"` gives URLs instead of domains. `source_kind` tells you whether
a cited page is a forum, review, roundup, video, marketplace, etc. - the
cheapest way to see which *kind* of page wins a category.

## Bulk-load prompts from a CSV, safely

```ts
import { parse } from "csv-parse/sync";
const rows = parse(await fs.readFile("prompts.csv"), { columns: true }) as { text: string; category: string }[];
for (let i = 0; i < rows.length; i += 100) {                       // 100 per call is the API's cap
  const batch = rows.slice(i, i + 100).map((r) => ({ text: r.text, category: r.category }));
  const preview = await rr.prompts.create({ site_id: SITE, prompts: batch, dry_run: true });
  console.log(`batch ${i / 100}: ${preview.created} new, ${preview.existing} already tracked`);
  await rr.prompts.create({ site_id: SITE, prompts: batch });
}
```
```python
import csv
rows = list(csv.DictReader(open("prompts.csv")))
for i in range(0, len(rows), 100):
    batch = [{"text": r["text"], "category": r["category"]} for r in rows[i:i+100]]
    preview = rr.prompts.create(site_id=SITE, prompts=batch, dry_run=True)
    print(f"batch {i//100}: {preview['created']} new, {preview['existing']} already tracked")
    rr.prompts.create(site_id=SITE, prompts=batch)
```
Dry-run first, every time: it shows duplicates (free) and trips the plan cap
(`PromptLimitError`, with `remaining`) before anything is written. Re-running
the loop is safe - existing text is returned, not duplicated. Writes need a key
with `write` permission and count against 20/min.

## Daily AI-crawler traffic into a warehouse

```ts
for await (const row of rr.reports.bots({
  site_id: SITE, start_date: "2026-09-01", end_date: "2026-09-30", timezone: "Europe/London",
  group_by: ["date", "bot_provider"], metrics: ["hits", "pages", "verified_share", "error_hits"], limit: 500,
})) {
  await warehouse.insert("rankraft_bot_hits", row);
}
```
```python
page = rr.reports.bots(site_id=SITE, start_date="2026-09-01", end_date="2026-09-30", timezone="Europe/London",
                       group_by=["date", "bot_provider"], metrics=["hits", "pages", "verified_share", "error_hits"], limit=500)
page.to_pandas(all_pages=True).to_sql("rankraft_bot_hits", engine, if_exists="append", index=False)
```
`verified_share` < 1 means some hits came from IPs the provider does not
publish - possibly spoofed. To see only genuine hits add
`filter: f.is("verified", true)`.

## <a id="backfill"></a>Backfilling more than 92 days

Answer reports are capped at 92 days per call; traffic at 400. A backfill is a
loop over windows, and the SDKs deliberately do **not** hide that - silently
splitting would make `info.total_results` meaningless.

```ts
function* windows(from: string, to: string, days = 92) {
  let start = new Date(`${from}T00:00:00Z`);
  const end = new Date(`${to}T00:00:00Z`);
  while (start <= end) {
    const stop = new Date(Math.min(start.getTime() + (days - 1) * 86_400_000, end.getTime()));
    yield [start.toISOString().slice(0, 10), stop.toISOString().slice(0, 10)] as const;
    start = new Date(stop.getTime() + 86_400_000);
  }
}
for (const [start_date, end_date] of windows("2025-10-01", "2026-09-30")) {
  for await (const row of rr.reports.visibility({ site_id: SITE, start_date, end_date, group_by: ["date"] })) store(row);
}
```
```python
from datetime import date, timedelta
def windows(start: date, end: date, days: int = 92):
    while start <= end:
        stop = min(start + timedelta(days=days - 1), end)
        yield start, stop
        start = stop + timedelta(days=1)

for s, e in windows(date(2025, 10, 1), date(2026, 9, 30)):
    for row in rr.reports.visibility(site_id=SITE, start_date=s, end_date=e, group_by=["date"]).auto_paging():
        store(row)
```
Group by `date` so windows concatenate without overlap. Four quarters of daily
rows is four calls plus pagination - well inside 120/min.

## Read the raw answers behind a number

```ts
const page = await rr.answers.query({
  site_id: SITE, start_date, end_date, platforms: ["chatgpt"],
  include: ["prompt", "text", "brand_mentioned", "citations"], limit: 50,
});
```
```python
page = rr.answers.query(site_id=SITE, start_date=s, end_date=e, platforms=["chatgpt"],
                        include=["prompt", "text", "brand_mentioned", "citations"], limit=50)
```
Pages are ≤ 50 because answers are long. `text` is the answer exactly as the
engine returned it.

## Check what a key can do

```bash
curl -s https://api.rankraft.ai/v1/me -H "X-API-Key: $RANKRAFT_API_KEY" | jq .data
```
Or `bash scripts/smoke.sh`, which also lists the site ids.

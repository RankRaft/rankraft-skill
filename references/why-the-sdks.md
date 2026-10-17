# Why use the SDKs instead of raw HTTP

Six things the API does that a hand-rolled client gets wrong by default. Both
SDKs handle all six identically; if you must call the API directly, this is
the checklist.

## 1. Retrying a POST is correct here

Six report endpoints and `/v1/answers` are POST requests that **only read** - the body is a date range and a filter tree, too much for a query string. A
"never retry POST" policy will fail your nightly job on the first transient
502. The SDKs carry a per-operation `retryable` flag, not a method heuristic.

Every write (`POST/PATCH …/prompts`) is also idempotent: existing text is
returned rather than duplicated, and re-applying a patch yields the same state.

## 2. A 429 is always retryable, and `Retry-After` is exact

The rate limiter rejects *before* the handler runs, so nothing happened. The
response carries `Retry-After: 60` and `X-RateLimit-Limit: 120` but **no
remaining count** - the window is fixed, so retrying early is guaranteed to
fail and spends another request. Wait the full number of seconds.

The SDKs also bound the *total* time a single call may sleep (70 s by default)
and then raise `RateLimitError`, so a library never silently stalls a job for
minutes.

## 3. The cursor is bound to the query

`info.next_cursor` encodes an offset plus a fingerprint of the request body - every field except `cursor` and `limit`, with keys canonicalised. Re-send the
same body with the new cursor. Change anything else and you get
`400 invalid_cursor`.

The SDKs freeze the body on page one and substitute only `cursor`. Do not
rebuild the request from the echoed `info.filter`.

## 4. Filter values are strings

`{"field": "verified", "op": "is", "value": true}` is a 422. The wire type is
`string | string[]`, 1–300 characters each, lists 1–100 long, groups 1–20
children, depth ≤ 3. The SDK builders stringify numbers and booleans.

## 5. Every request object is strict

An unknown field is `422 invalid_request` with `details` listing each problem,
not silently ignored. `null` where a string belongs is also a 422 - omit the
key instead. The SDKs drop undefined/None keys before serialising.

## 6. Three response shapes

| Routes | Shape |
|---|---|
| Reports, prompts list | `{ info: { count, total_results, next_cursor, … }, data: [...] }` |
| Discovery, actions | `{ data: ... }` |
| Prompt writes | `{ dry_run, created, existing, data }` · `{ dry_run, not_found, data }` · `{ dry_run, changed, unchanged, not_found }` |

The counts beside `data` on the write routes are the point of the call; a
client that always unwraps `data` loses them. The SDKs return the whole body
for writes and unwrap everything else.

## Also

- `X-Request-Id` (also `request_id` in every error body) is a Cloudflare ray
  id and changes per attempt. Keep all of them when retrying.
- No CORS headers, deliberately. There is no browser story and must not be.
- `GET /v1/openapi.json` is public and is the contract. The SDKs vendor it and
  run a conformance test against it in CI.

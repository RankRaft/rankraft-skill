# Errors

Every failure has one shape:

```json
{ "error": { "code": "invalid_filter", "message": "…", "details": [ … ] }, "request_id": "8a1f2c3d4e5f6071" }
```

Switch on `code` - the message is for humans and may change. Put `request_id`
in any support message; it is also sent as the `X-Request-Id` header, which is
how you get it when a 502 comes back from Cloudflare with no JSON body at all.

| Status | `code` | Meaning | Node class | Python class |
|---|---|---|---|---|
| 400 | `invalid_json` | body is not JSON | `BadRequestError` | `BadRequestError` |
| 400 | `invalid_cursor` | cursor from a different query - start again without one | `InvalidCursorError` | `InvalidCursorError` |
| 400 | `api_key_in_url` | key was in the query string. **Revoke it**; it is in logs now | `BadRequestError` | `BadRequestError` |
| 401 | `invalid_api_key` | missing, malformed, unknown, revoked or expired - one message for all five, on purpose | `AuthenticationError` | `AuthenticationError` |
| 403 | `plan_required` | organization is not on a live Enterprise plan | `PlanRequiredError` | `PlanRequiredError` |
| 403 | `insufficient_permission` | a read-only key tried a write route | `PermissionDeniedError` | `PermissionDeniedError` |
| 404 | `not_found` | no such site/resource **in this organization**. Never 403 for someone else's - ids are not enumerable | `NotFoundError` | `NotFoundError` |
| 409 | `site_not_set_up` | the site has no brand profile yet; finish onboarding in the dashboard | `ConflictError` | `ConflictError` |
| 413 | `payload_too_large` | body over 256 KB | `PayloadTooLargeError` | `PayloadTooLargeError` |
| 415 | `unsupported_media_type` | send `Content-Type: application/json` | `BadRequestError` | `BadRequestError` |
| 422 | `invalid_request` | schema validation; `details` = `[{path, message}]` | `ValidationError` | `ValidationError` |
| 422 | `invalid_filter` | depth > 3, unknown field for this report, or list/scalar mismatch for the op | `ValidationError` | `ValidationError` |
| 422 | `invalid_date_range` | end before start, or span over 92 (answers) / 400 (traffic) days | `ValidationError` | `ValidationError` |
| 422 | `invalid_timezone` | not an IANA zone | `ValidationError` | `ValidationError` |
| 422 | `invalid_sort` | sort field is not one of the requested metrics/dimensions | `ValidationError` | `ValidationError` |
| 422 | `prompt_limit_reached` | would exceed the plan's active-prompt cap; `details` = `{limit, active, requested, remaining}` | `PromptLimitError` (`.remaining`, `.limit`) | `PromptLimitError` |
| 429 | `rate_limited` | 120 req/min per key or 20 writes/min; `Retry-After: 60` | `RateLimitError` (`.retryAfterSeconds`) | `RateLimitError` (`.retry_after_seconds`) |
| 500 | `internal_error` | ours; already reported; retry later | `InternalServerError` | `InternalServerError` |

Unauthenticated requests that fail are also limited per IP (30/min), which is
what makes key guessing expensive. After that, even a *valid* key from that IP
gets a 429 for a minute.

## Which ones to retry

- **Always:** 429 (after `Retry-After`), 500/502/503/504, timeouts, connection
  errors - on every endpoint, because every endpoint is safe to replay.
- **Never:** 400, 401, 403, 404, 409, 413, 415, 422. They are deterministic; a
  retry burns your 120/min budget for nothing.

## Handling in the SDKs

```ts
import { RateLimitError, PromptLimitError, InvalidCursorError } from "rankraft";
try { … } catch (err) {
  if (err instanceof RateLimitError)   schedule(err.retryAfterSeconds);
  if (err instanceof PromptLimitError) console.log(`only ${err.remaining} slots left`);
  if (err instanceof InvalidCursorError) restartWithoutCursor();
}
```

```python
from rankraft import RateLimitError, PromptLimitError, InvalidCursorError
try: ...
except RateLimitError as e:   schedule(e.retry_after_seconds)
except PromptLimitError as e: print(f"only {e.remaining} slots left")
except InvalidCursorError:    restart_without_cursor()
```

Every `APIError` also has `status`, `code`, `details`, `request_id` and
`attempt_request_ids` (one per attempt - the ray id changes each time). A code
the SDK does not know falls back to the class for its status, so a new
server-side code never crashes a pinned install.

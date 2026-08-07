# Debugging Fastly Stats

Symptom-keyed fixes for the stats/metrics APIs and `fastly stats` CLI. Each heading is what you
observe; the body is the cause and the fix.

## 401 Unauthorized

The `Fastly-Key` header is missing, malformed, or the token is invalid/expired. Confirm the CLI
is authenticated (`fastly whoami`) and that raw calls send the header:
`-H "Fastly-Key: $(fastly auth token --quiet)"`. Do not wrap the token in quotes inside the header value,
and do not send it as a query param.

### 401 (or `curl: (43)`) while `fastly whoami` succeeds — the missing `--quiet`

If the CLI is clearly authenticated but every raw `curl` fails, the cause is almost always a **bare
`$(fastly auth token)` without `--quiet`**. When a CLI upgrade is pending, that command appends an
"A new version of the Fastly CLI is available" notice to stdout — measured at 6 lines / 174 bytes,
versus 32 bytes with `--quiet`. Captured in a substitution, the extra lines land inside the header
value and produce one of two confusing failures:

- `curl: (43) A libcurl function was given a bad argument` — embedded newlines in the header, so the
  request is never even sent (HTTP code `000`).
- HTTP 401 `{"msg":"Provided credentials are missing or invalid"}` — or, on `rt.fastly.com`,
  HTTP 403 `{"Error":"invalid authentication"}`.

```bash
curl -sS -H "Fastly-Key: $(fastly auth token)"           ...   # 401/curl:(43) when an update is pending
curl -sS -H "Fastly-Key: $(fastly auth token --quiet)"   ...   # correct
```

`--quiet` means "silence all output except direct command output", which is exactly the guarantee you
need in a substitution. The failure is **intermittent** — it appears only while an update happens to
be pending — so identical code can work one day and fail the next. Verify with a cheap authenticated
call before blaming your query:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H "Fastly-Key: $(fastly auth token --quiet)" https://api.fastly.com/current_user   # expect 200
```

## 403 Forbidden (but the token works elsewhere)

The token authenticates but lacks scope for this resource. Historical service stats need read
access to that service; `usage`/`usage_by_service`/`usage_by_month` need account-level read. A
token scoped to a single service will 403 on account-wide usage endpoints. Use a token with the
right scope, or query per-service instead of account-wide.

## Inspector returns an error instead of data (or 404 / "not enabled")

Origin Inspector and Domain Inspector are **paid add-ons enabled per service**. If the service
is not entitled, `/metrics/origins/...` or `/metrics/domains/...` returns an error rather than an
empty series. Verify the product is enabled for the service (via the Fastly UI or products API)
before assuming your query is wrong. This is the most common Inspector surprise.

## Empty `data` / zero rows

Usually one of:

- **Window too narrow or in the future.** Check `from`/`to` (or `start`/`end`) resolve to a real
  past range. Relative strings only work on classic `/stats*`, not Inspector.
- **`by=minute` too far back.** Minute granularity is only retained for roughly the last day.
  Widen to `hour` or `day` for older windows.
- **Zero-traffic service.** A service with no traffic in the window legitimately returns nothing.
- **Over-filtered.** A `region`/`datacenter`/`host`/`domain` filter that matches no traffic
  yields empty results — drop filters to confirm data exists.

## Missing services when aggregating across an account

Stats responses can omit services that had zero traffic in the window, so iterating over a stats
response misses them. Always enumerate from `fastly service list --json` and default missing sums
to 0 (`jq '... | add // 0'`). See the cross-service workflow in the main SKILL.md.

## `fastly stats ... --json` output won't parse as one JSON document

The CLI emits **NDJSON**: one JSON object per line, with no surrounding array. Piping it straight
into a tool that expects a single document fails. Slurp first:

```bash
fastly stats historical -s "$SID" --by day --json | jq -s '.'        # -> array
fastly stats historical -s "$SID" --by day --json | jq -s 'add'      # aggregate
```

This is a CLI artifact only — the raw HTTP API returns a normal JSON array in `data`.

## Inspector rejects `--by` or `--field`

The Inspector subcommands (`domain-inspector`, `origin-inspector`) and their HTTP endpoints use a
**different vocabulary** from classic stats:

- granularity is `--downsample` / `downsample=` (not `--by` / `by=`)
- fields are `--metric` / `metric=` (not `--field` / `field=`), repeatable, max 10

Using the classic flag names against an inspector command/endpoint fails or is ignored.

## Only partial Inspector results

Inspector paginates. A response returns at most `limit` timeseries rows (max 200) and a
`meta.next_cursor`. If you read only the first page you silently truncate. Loop, feeding
`next_cursor` back as `cursor`, until it is null — see
[inspector-api.md](inspector-api.md#cursor-pagination).

## Real-time: 404, or the same second forever

Two distinct mistakes:

- **First call must use `ts/0`.** Guessing a timestamp can 404 or return nothing.
- **Chain the response `Timestamp`; don't increment your own counter.** Reusing an old timestamp
  replays or stalls; computing `ts+1` drifts off the server's clock. Always set the next path
  segment from the previous response's `Timestamp` field.

## Real-time throttling / slow responses

The endpoint long-polls (it blocks until new data) and is cached with a 1-second TTL. That is
normal — a request can take up to ~1s to return. Poll **one request at a time**; firing several
concurrent polls for the same service can be rate-limited. Respect `AggregateDelay` — the newest
second isn't final until that many seconds have passed.

## Numbers look "too low" for the most recent bucket

Historical aggregation lags. The latest `hour`/`minute` bucket keeps growing for a few minutes
after its period ends, so a just-closed bucket can under-report. For up-to-the-second accuracy
use the [real-time API](realtime-api.md); for stable historical numbers, don't read the final
in-progress bucket.

## `region` or `datacenter` filter returns nothing

Region codes are lowercase tokens (`usa`, `europe`, `asia_india`, …) — get the live list from
`GET /stats/regions` or `fastly stats regions`. POP/datacenter codes are **uppercase** (`SJC`,
`LHR`); list them with `fastly pops` or `GET /datacenters`. A bad POP code fails loudly rather than
silently: lowercase (`datacenter=den`) or unknown (`datacenter=ZZZ`) both return
`{"status":"error","msg":"invalid datacenter"}`.

Note the **`region=` param takes `stats_region` values** (`usa`, `europe`), not the `region` values
from `/datacenters` (`US-East`, `North-America`). They are different taxonomies — see
[historical-stats-api.md](historical-stats-api.md#three-different-groupings-easily-confused).

## Numbers look plausible but the scope is wrong (HTTP 200, right shape, wrong data)

The dangerous filter failure is not the one that returns nothing — it is the one that returns a
full, plausible `data` array at a scope you did not ask for. Known cases:

- **`region` silently overrides `datacenter`.** Send both and the POP filter is dropped: HTTP 200,
  `meta.datacenter: null`, and whole-region numbers. `?datacenter=DEN` gave 214 requests;
  `?datacenter=DEN&region=usa` gave 392 — the unfiltered total. Never send both.
- **Wrong taxonomy in `region=`.** Passing a `/datacenters` `region` value like `North-America` is
  not the same scope as you'd guess even when it is accepted — and `North-America` contains only
  four Canadian POPs, no US POPs at all.

**The defense: assert `meta` echoes the filter you sent.** The numbers themselves will not tell you.

```bash
curl -sS -H "Fastly-Key: $(fastly auth token --quiet)" \
  "https://api.fastly.com/stats/service/$SID?from=$FROM&to=$TO&by=day&datacenter=DEN" \
  | jq 'if .meta.datacenter == "DEN" then .data else error("filter dropped: \(.meta)") end'
```

Cross-check when the stakes are high: sum a per-POP series and compare it to the unfiltered total,
or to a region-level series. Sweeping every POP code reconciled exactly (392 = 392) on a live
service; agreement within a couple of percent is normal for region-vs-POP-sum comparisons, and you
should state the agreement you got rather than assume it.

## I changed something and cannot recover the pre-change per-POP state

Per-POP history **does** exist — `datacenter=` is a real filter on `/stats/service/{id}` and works
with `by=minute|hour|day` (see
[historical-stats-api.md](historical-stats-api.md#per-pop-history-works--datacenter-is-a-real-filter)).
But `by=minute` is retained only for roughly the last day, and real-time holds only the last 120
seconds, so minute-resolution "before" data ages out fast.

**Capture a per-POP baseline before you change anything.** Make it step 1 of any change
verification, not an afterthought — after the window passes, the fine-grained pre-change state is
gone and you are left arguing from `by=hour` or from memory.

```bash
# Step 1 of any change: snapshot every POP at minute resolution, with the window recorded
KEY="Fastly-Key: $(fastly auth token --quiet)"
CODES=$(curl -sS -H "$KEY" https://api.fastly.com/datacenters | jq -r '.[].code' | paste -sd, -)
NOW=$(date -u +%s)
curl -sS -H "$KEY" \
  "https://api.fastly.com/stats/service/$SID?from=$((NOW-3600))&to=$NOW&by=minute&datacenter=$CODES" \
  > "baseline-$NOW.json"     # timestamp in the filename; the window is not recoverable later
```

## A before/after comparison moved — but did the change cause it?

Three checks that separate signal from drift, in order of how much they buy you:

- **Use untouched control POPs in the same window.** POPs you did not change should hold flat. If
  controls moved as much as the treatment POPs, you measured something ambient, not your change.
- **Quantify the step in σ against a measured baseline, not in percent.** Take several baseline
  samples, compute the standard deviation, and express the change as multiples of it. A step of
  "+21.8%" is unpersuasive when an unrelated POP drifted +9.0% in the same window; the same step
  stated as 12σ against a measured σ is not arguable.
- **Prefer a zero-to-nonzero transition where one exists.** A metric going 0 → nonzero needs no
  baseline model and has no confound. When designing a change, decide *in advance* which metric will
  give the cleanest before/after.

Two confounds worth naming explicitly:

- **Cache warm-up.** A newly-added tier's hit ratio shortly after deployment is a floor, not a
  steady state. Re-read at T+24 h before treating it as the new normal.
- **Unreplicated headline numbers.** Take two samples a few minutes apart and confirm they agree
  before publishing; a single real-time sample can catch a transient.

## `from`/`to` parsing errors

Classic `/stats*` accepts Unix timestamps and Chronic relative strings (`yesterday`,
`two weeks ago`); URL-encode spaces (`from=two%20weeks%20ago`). Inspector `start`/`end` accept
ISO-8601 (`2026-07-01T00:00:00Z`) or Unix timestamps but **not** relative strings. Using a
relative string against Inspector is a common cause of a 400.

## A relative window silently covers the wrong hours

`from=yesterday` resolves to **12:00:00 UTC** of the previous day, not midnight — so it silently
excludes that morning and any total you report is short. `from=today` likewise means "now", not
`00:00`. Measured live at 03:17 UTC on 2026-08-07:

```text
from=yesterday   -> meta.from = 2026-08-06 12:00:00 UTC   # noon
from=today       -> meta.from = 2026-08-07 03:17:54 UTC   # now
from=1 day ago   -> meta.from = 2026-08-06 03:17:55 UTC   # exactly -24h, as expected
```

`N days ago` / `N hours ago` behave as you'd expect (exact offsets from now); the calendar words are
the surprise. **Read back `meta.from`/`meta.to`** — the response always tells you the window it
actually used — and prefer computed Unix timestamps for anything scripted or published.

## Token accidentally printed

If a token reached the transcript (e.g. via `fastly auth show --reveal` or `curl -v`), treat it
as compromised and rotate it: revoke via the Fastly UI / auth API and re-authenticate. Prevent
recurrence by using `$(fastly auth token --quiet)` inline and never `-v` on authenticated calls.

# Stats debugging

Each heading is what you observe.

## 401, or `curl: (43)`, while `fastly whoami` succeeds

A bare `$(fastly auth token)` without `--quiet`. When a CLI upgrade is pending that command
appends an "A new version is available" notice to stdout, which lands inside the header value:
embedded newlines give `curl: (43)` and the request is never sent, or the server sees a mangled
key and returns 401 (403 `{"Error":"invalid authentication"}` on `rt.fastly.com`). It is
intermittent, so identical code works one day and fails the next.

```bash
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H "Fastly-Key: $(fastly auth token --quiet)" https://api.fastly.com/current_user   # expect 200
```

## 403 while the token works elsewhere

Scope. Historical service stats need read access to that service; `usage`, `usage_by_service` and
`usage_by_month` need account-level read. A service-scoped token 403s on account-wide usage.

## Empty data or zero rows

- Day buckets and a relative window. A bucket is emitted only for a period wholly inside the
  window, so `from=1 day ago&by=day` returns nothing at all and `7 days ago` returns 6 rows.
  Pass explicit UTC boundaries for calendar windows, or use `by=hour`.
- A Compute service, read through `requests`. Compute traffic lands in `compute_requests` and
  leaves `requests` at 0, so a healthy service looks idle. Sum both. Status codes too: `status_5xx`
  is 0 and the count is in `all_status_5xx`, which also works on a VCL service.
- `by=minute` too far back. Minute granularity is retained roughly one day; widen to `hour`.
- Inspector not enabled. See below, this one does not look like an error.
- Zero-traffic service. A service with no traffic in the window legitimately returns nothing, and
  is omitted entirely from account-wide responses. Enumerate from `fastly service list --json`.
- Over-filtered. A `region`, `datacenter`, `host` or `domain` filter matching no traffic yields
  empty results; drop filters to confirm data exists.
- Window in the future.

## Inspector returns success with an empty array

Origin Inspector and Domain Inspector are paid add-ons enabled per service. When the product is
off the endpoint still answers HTTP 200 with `"status":"success"` and `"data":[]`, which is
indistinguishable from a service that had no traffic. Check the entitlement before concluding
there is nothing to see:

```bash
fastly products -s "$SID"     # look for Domain Inspector / Origin Inspector = true
```

## Inspector answers 400 with a `type` and no `msg`

RFC 7807 body, not the classic `{status, msg}`:

```json
{"type":"https://fastly.help/metrics/validation-error","title":"Request parameters were invalid.",
 "status":400,"errors":[{"property":"start","reason":"failed to parse 'start' time"}],
 "detail":"Parameters with invalid values: 'start'"}
```

`status` is `400` here and the string `"success"` on the happy path, so branch on
`.status == "success"`. Cause is in `errors[].reason`; there is no `msg` either way. Two failures
land here rather than in the empty-data list above:

- Relative string in `start` or `end`. ISO-8601 with `Z` or a Unix timestamp only:
  `failed to parse 'start' time`. The CLI rejects it earlier with
  `invalid --from value: cannot parse "1 day ago" as RFC3339 or Unix timestamp`.
- Unrecognized `metric` name: `Unrecognized metric names: '...'`. Validated even where the product
  is disabled, so this says nothing about entitlement.

## `--json` output will not parse as one document

The CLI emits NDJSON, one object per line, no surrounding array. Slurp first:

```bash
fastly stats historical -s "$SID" --by day --json | jq -s '.'
```

This is a CLI artifact. The raw HTTP API returns a normal JSON array in `data`.

## Inspector rejects `--by` or `--field`

Inspector uses `--downsample` / `downsample=` for granularity and `--metric` / `metric=`
(repeatable) for fields. Classic stats uses `--by` and `--field`. `historical` has no
`--datacenter`; the inspectors do. Mixing the vocabularies fails with a usage error.
`fastly stats regions` takes no flags at all, not even `--json`. The documented `--metric` cap of 10
is not enforced; 20 names in one call go through, so do not split a request to stay under it.

## Only partial Inspector results

Inspector paginates at `limit` rows, max 200, and returns `meta.next_cursor`. Reading only the
first page silently truncates. Loop, feeding `next_cursor` back as `cursor`, until it is empty.

## Real-time: 404, or the same second forever

First call must use `ts/0`. After that, chain the response's `Timestamp` into the next path
segment; reusing an old timestamp replays or stalls, and computing `ts+1` drifts off the server
clock. The endpoint long-polls with a 1-second TTL, so a request taking about a second is normal.
Poll one request at a time; concurrent polls for the same service can be throttled.

On a service with no live traffic the answer is HTTP 200 with
`{"Data":[],"Timestamp":...,"Error":"No data available, please retry"}`. That `Error` is in the
body, not the status line, so a check that only inspects the HTTP code sees success and then
divides by an empty array.

## `fastly stats realtime` prints nothing and never returns

It emits only seconds that carried traffic and polls forever, so on a quiet service `| head -20`
never reaches its count and the pipeline deadlocks. Bound it by wall clock:

```bash
OUT=$(mktemp)
fastly stats realtime -s "$SID" --json > "$OUT" & P=$!
sleep 20; kill "$P" 2>/dev/null; wait "$P" 2>/dev/null
jq -s 'length' "$OUT"     # 0 is a legitimate answer
```

One-shot alternative that returns immediately: `GET rt.fastly.com/v1/channel/{id}/ts/h`. If a
stream does end empty, `max - min` over `recorded` fails with
`null (null) cannot be subtracted`; guard it or divide by the window you chose.

## The newest bucket looks too low

Historical aggregation lags: the latest bucket keeps growing after its period ends. Minute data is
usually available within 2-15 minutes, hourly within 15 minutes of the hour, daily around 2am UTC
the following day. Do not read the final in-progress bucket, and note that below `by=day` the row
count is not stable between two identical calls. Use real-time for up-to-the-second numbers.

## A relative window covers the wrong hours

`from=yesterday` resolves to 12:00:00 UTC of the previous day, not midnight, so any total is
short by a morning. `from=today` means now, not `00:00`. `N days ago` and `N hours ago` are exact
offsets from now. Read back `meta.from` / `meta.to`, and prefer computed Unix timestamps or
explicit ISO-8601 for anything published.

## HTTP 200, right shape, wrong data

The dangerous filter failure returns a full plausible array at a scope you did not ask for.

- `region` silently overrides `datacenter` when both are sent: HTTP 200, whole-region numbers, and
  a `meta` that echoes `region` while omitting the `datacenter` key entirely. Never send both.
- `region=` takes `stats_region` values (`usa`, `europe`), not the `region` values from
  `/datacenters` (`US-East`, `North-America`). Different taxonomies.
- `region=` is ignored outright on `/stats/usage` and `/stats/usage_by_service`. All eleven regions
  return, `data` byte-identical to unfiltered, `meta.region` echoing what you sent, so the `meta`
  assertion below does not catch this one. `fastly stats usage --region` filters client-side, so CLI
  and raw URL differ; filter the response yourself.

The defense is to assert `meta` echoes the filter you sent; the numbers themselves will not tell
you.

```bash
curl -sS -H "Fastly-Key: $(fastly auth token --quiet)" \
  "https://api.fastly.com/stats/service/$SID?from=$FROM&to=$TO&by=day&datacenter=DEN" \
  | jq 'if .meta.datacenter == "DEN" then .data else error("filter dropped: \(.meta)") end'
```

Cross-check when the stakes are high: a per-POP sum reconciles exactly with the unfiltered total
on classic historical stats.

## `region` or `datacenter` returns nothing

Region codes are lowercase tokens; get the live list from `fastly stats regions`. POP codes are
uppercase; list them with `fastly pops`. A lowercase or unknown POP code fails loudly with
`{"status":"error","msg":"invalid datacenter"}` rather than silently.

## `invalid start_time` on the per-POP summary endpoint

`/service/{id}/stats/summary` requires epoch seconds for `start_time` and `end_time`; ISO-8601 is
rejected even though every other endpoint accepts it. It is minutely-backed, so the window cannot
start more than 35 days back.

## A before/after comparison moved, but did the change cause it

Per-POP history exists, but `by=minute` is retained roughly one day and real-time only 120
seconds, so capture the baseline before you change anything: it is the only irreversible step.

```bash
KEY="Fastly-Key: $(fastly auth token --quiet)"
CODES=$(curl -sS -H "$KEY" https://api.fastly.com/datacenters | jq -r '.[].code' | paste -sd, -)
NOW=$(date -u +%s)
curl -sS -H "$KEY" \
  "https://api.fastly.com/stats/service/$SID?from=$((NOW-3600))&to=$NOW&by=minute&datacenter=$CODES" \
  > "baseline-$NOW.json"
```

Then, in order of how much they buy you:

- Include untouched control POPs in the same window. If they moved as much as the treatment POPs,
  you measured something ambient.
- Quantify the step in sigma against several baseline samples, not in percent. A percentage
  silently treats ambient drift as zero.
- Prefer a metric that goes from zero to nonzero: no baseline model, no confound.
- Replicate every headline number in a second sample a few minutes later.
- Sanity-check derived values against their valid range. A negative byte offload or an
  `origin_offload` of 119.99 means the arithmetic is wrong.
- Note cache warm-up. A new tier's hit ratio shortly after deployment is a floor, not a steady
  state; re-read at T+24h.

## Token printed into the transcript

Treat it as compromised and rotate it. Prevent recurrence with `$(fastly auth token --quiet)`
inline, never `fastly auth show --reveal` bare, never `-v` on an authenticated call.

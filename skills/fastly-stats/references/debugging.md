# Debugging Fastly Stats

Symptom-keyed fixes for the stats/metrics APIs and `fastly stats` CLI. Each heading is what you
observe; the body is the cause and the fix.

## 401 Unauthorized

The `Fastly-Key` header is missing, malformed, or the token is invalid/expired. Confirm the CLI
is authenticated (`fastly whoami`) and that raw calls send the header:
`-H "Fastly-Key: $(fastly auth token)"`. Do not wrap the token in quotes inside the header value,
and do not send it as a query param.

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
`LHR`); list them with `fastly pops`. Mismatched casing or an invalid code yields empty results.

## `from`/`to` parsing errors

Classic `/stats*` accepts Unix timestamps and Chronic relative strings (`yesterday`,
`two weeks ago`); URL-encode spaces (`from=two%20weeks%20ago`). Inspector `start`/`end` accept
ISO-8601 (`2026-07-01T00:00:00Z`) or Unix timestamps but **not** relative strings. Using a
relative string against Inspector is a common cause of a 400.

## Token accidentally printed

If a token reached the transcript (e.g. via `fastly auth show --reveal` or `curl -v`), treat it
as compromised and rotate it: revoke via the Fastly UI / auth API and re-authenticate. Prevent
recurrence by using `$(fastly auth token)` inline and never `-v` on authenticated calls.

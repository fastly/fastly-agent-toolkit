# Real-Time Analytics API

Base: `https://rt.fastly.com` | Auth: `Fastly-Key: $FASTLY_API_TOKEN` | Docs: <https://www.fastly.com/documentation/reference/api/metrics-stats/realtime/>

Live, per-second traffic for a service — one aggregated record per elapsed second, plus a
per-POP breakdown. Use this when you need up-to-the-second numbers (a dashboard, a live error
watch); use the [Historical Stats API](historical-stats-api.md) for anything older than a couple
of minutes.

## Endpoint and polling model

```text
GET /v1/channel/{service_id}/ts/{timestamp}
```

The endpoint is a **long-poll**, not a one-shot query. It works like a cursor over seconds:

1. First request uses `timestamp = 0`. The server returns the most recent complete second and a
   `Timestamp` field.
2. Each subsequent request passes the **`Timestamp` from the previous response** as the new path
   value. The server blocks until at least one newer second is available, then returns every
   second that elapsed since — usually one record, more if you fell behind.
3. Keep chaining `Timestamp` forever for a continuous stream.

`AggregateDelay` (seconds) in each response tells you how far behind real time the newest data
is — the server waits this long before a second is considered final. The response is cached with
a 1-second TTL, so **one outstanding request at a time** never hits rate limits; issuing several
concurrent polls for the same service can be throttled.

## Response shape

```json
{
  "AggregateDelay": 5,
  "Timestamp": 1751328001,
  "Data": [
    {
      "recorded": 1751328000,
      "aggregated": {
        "requests": 128,
        "hits": 120,
        "miss": 6,
        "pass": 2,
        "errors": 0,
        "hit_ratio": 0.9375,
        "bandwidth": 2097152,
        "status_2xx": 126,
        "status_4xx": 2,
        "status_5xx": 0
      },
      "datacenter": {
        "SJC": { "requests": 80, "hits": 76, "bandwidth": 1310720 },
        "LHR": { "requests": 48, "hits": 44, "bandwidth": 786432 }
      }
    }
  ]
}
```

- `Data` is an array of one-second records (multiple only if you polled slower than real time).
- `recorded` is the Unix timestamp of the second.
- `aggregated` holds all-POP totals for that second, keyed by metric name (see [fields.md](fields.md)).
- `datacenter` holds the same metrics broken down by POP code (`SJC`, `LHR`, …). POP codes come
  from `fastly pops`.
- `Timestamp` is the value to send in the **next** request — do not compute it yourself.

## Poll loop

A minimal, correct loop that never busy-waits and never parallel-polls:

```bash
KEY="Fastly-Key: $(fastly auth token)"
ts=0
while :; do
  resp=$(curl -sS -H "$KEY" "https://rt.fastly.com/v1/channel/$SID/ts/$ts")
  echo "$resp" | jq -c '.Data[] | {recorded, rps: .aggregated.requests, e5xx: .aggregated.status_5xx}'
  ts=$(echo "$resp" | jq -r '.Timestamp')   # chain, don't increment manually
done
```

To sample once instead of streaming, just request `ts/0` and read `Data[0].aggregated`.

If you format `recorded` into a clock time, use UTC (`strftime`) unless the user asked for local
time, so timestamps are comparable across machines: `jq -r '.Data[] | (.recorded|strftime("%H:%M:%SZ"))'`.

## CLI equivalent

For a quick live view without writing a poll loop, the CLI wraps this same feed and chains
`Timestamp` for you:

```bash
fastly stats realtime --service-id "$SID" --json \
  | jq -r '.Data[]? | [(.recorded|strftime("%H:%M:%SZ")), .aggregated.requests, .aggregated.status_5xx] | @tsv'
```

`fastly stats realtime` streams **NDJSON** — one JSON object per line — so process it line by line
(no `jq -s` needed here, unlike the historical `--json` commands). The raw `curl` loop above is
worth it when you want a derived error rate or the per-POP `datacenter` breakdown, which the CLI
does not surface as cleanly.

## Convenience history forms

The origin/domain real-time endpoints also offer `ts/h` (last 120 seconds) and
`ts/h/limit/{n}` (last `n` entries, `n` ≤ 120) — handy for backfilling a chart without a poll
loop. See [inspector-api.md](inspector-api.md#real-time-rtfastlycom). The service-level
`/v1/channel` endpoint is intended to be polled from `ts/0`.

## Real-time vs historical field differences

Real-time exposes largely the same measurements as historical stats, plus a few live-only
counters (e.g. Fanout and KV-store operation counts). It does **not** offer arbitrary `by`/region
query filtering — you get every second for the whole service and filter client-side using the
`datacenter` breakdown. For flexible time windows, regions, or fields, use historical. Field
meanings are catalogued in [fields.md](fields.md).

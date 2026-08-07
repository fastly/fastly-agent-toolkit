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
  from `fastly pops`. **Prefer reading this per-POP map, not just `aggregated`** — a spike or
  error surge is usually concentrated in one or a few POPs, and the aggregate hides it. If the
  service is shielded, the **shield POP** also appears here but carries origin-shielding
  (edge-to-shield) traffic rather than client traffic — identify it via `fastly pops` (`SHIELD`
  column) and flag it separately so it isn't read as a client edge.
- `Timestamp` is the value to send in the **next** request — do not compute it yourself.

## Poll loop

A minimal, correct loop that never busy-waits and never parallel-polls:

```bash
KEY="Fastly-Key: $(fastly auth token --quiet)"
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

> **Never infer a time base from an endpoint name.** `ts/h` is **120 seconds**, not an hour. Derive
> the window from the payload's own `recorded` timestamps (`min`/`max`) and print it next to every
> absolute figure you report. Reading the `h` as "hour" inflates any per-unit-time figure by 30×.

All three real-time endpoints — `/v1/channel`, `/v1/origins`, `/v1/domains` — support:

```text
GET /v1/channel/{service_id}/ts/h            # up to the last 120 seconds
GET /v1/channel/{service_id}/ts/h/limit/{n}  # last n entries, n <= 120
```

`ts/h` on `/v1/channel` is **verified working** — it returns up-to-120 one-second records in a single
call, which makes it the cheapest way to grab a two-minute per-POP snapshot without running a poll
loop. `h` is a recognized token, not a coincidence of parsing: a bogus value returns HTTP 400
`"unable to convert timestamp to int"`, whereas `ts/h` on an idle service returns HTTP 200 with
`"Error": "No data available, please retry"`.

`ts/h` returns only seconds that **had traffic** — a low-traffic service yields far fewer than 120
records, so never assume `Data` has 120 entries or that `length` is your window in seconds.

**Always derive and print the window.** Do it from the payload, never from the endpoint name:

```bash
curl -sS -H "Fastly-Key: $(fastly auth token --quiet)" \
  "https://rt.fastly.com/v1/channel/$SID/ts/h" \
  | jq '{samples: (.Data|length),
         from: ([.Data[].recorded]|min|strftime("%H:%M:%SZ")),
         to:   ([.Data[].recorded]|max|strftime("%H:%M:%SZ")),
         span_s: (([.Data[].recorded]|max) - ([.Data[].recorded]|min) + 1),
         requests: ([.Data[].aggregated.requests // 0]|add)}'
```

```json
{ "samples": 5, "from": "03:04:13Z", "to": "03:04:46Z", "span_s": 34, "requests": 125 }
```

125 requests over a **34-second** span — reporting that as an hourly rate, or dividing by 120, are
both wrong. Only `span_s` from the payload gets it right.

**Prefer ratios and same-window comparisons over extrapolated rates.** A hit ratio, a share of total
traffic, or an A-vs-B split taken from one payload is immune to misjudging the window, because
numerator and denominator come from the same samples. Only absolute per-unit-time framing breaks.
When you must publish an absolute rate, show the derived window beside it.

See also [inspector-api.md](inspector-api.md#real-time-rtfastlycom) for the origin/domain forms.

## Real-time vs historical field differences

Real-time exposes largely the same measurements as historical stats, plus a few live-only
counters (e.g. Fanout and KV-store operation counts). It does **not** offer arbitrary `by`/region
query filtering — you get every second for the whole service and filter client-side using the
`datacenter` breakdown. For flexible time windows, regions, or fields, use historical — including
**per-POP history**, which the `datacenter=` filter does support (see
[historical-stats-api.md](historical-stats-api.md#per-pop-history-works--datacenter-is-a-real-filter));
real-time is not your only route to per-POP numbers, it is only the route to *live* ones.

Field meanings and — critically for real-time — **aggregation shape** are catalogued in
[fields.md](fields.md). Before summing anything across a `ts/h` series, check whether the field is a
counter or a gauge: summing `origin_offload` or `hit_ratio` across samples produces a plausible-looking
number that is meaningless. See
[Aggregation shape](fields.md#aggregation-shape-counter-vs-gauge-vs-histogram).

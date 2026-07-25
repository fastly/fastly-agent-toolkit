# Origin & Domain Inspector API

Base (historical): `https://api.fastly.com` | Base (real-time): `https://rt.fastly.com` | Auth: `Fastly-Key: $FASTLY_API_TOKEN`
Docs: <https://www.fastly.com/documentation/reference/api/metrics-stats/origin-inspector/> · <https://www.fastly.com/documentation/reference/api/metrics-stats/domain-inspector/>

Origin Inspector reports metrics per **origin/backend**; Domain Inspector reports metrics per
**domain**. They share one request/response model — only the resource in the path and the
available `group_by` dimensions differ. Both are **paid add-ons enabled per service**; if a
service is not entitled, the endpoint returns an error (see [debugging.md](debugging.md)), not
empty data.

- Origin vs Domain: use Origin Inspector to answer "which backend is slow / erroring / busy",
  Domain Inspector to answer "how much traffic is each hostname taking".

**Where latency/timing lives (this matters):** Origin Inspector's latency histograms measure
**origin response time** — how slow your backends are. That is *not* the same as edge
performance. If the question is "how long is Fastly taking to serve requests at the edge", that
comes from the classic Historical Stats fields `hits_time` / `miss_time` / `pass_time`
(aggregate processing seconds) — see [historical-stats-api.md](historical-stats-api.md) and
[fields.md](fields.md). Both are useful and often examined together: a fast edge with a slow
origin, or vice versa, are diagnosed from different sources. Domain Inspector additionally exposes
edge cache/offload metrics (`edge_hit_ratio`, `origin_offload`) per domain. Timestamps in
`start`/`end` are UTC — pass `Z`-suffixed ISO-8601 or Unix seconds.

## Historical (api.fastly.com)

```text
GET /metrics/origins/services/{service_id}
GET /metrics/domains/services/{service_id}
```

### Query parameters

| Param | Type | Notes |
| --- | --- | --- |
| `start` | string | Inclusive start. ISO-8601 datetime (`2026-07-01T00:00:00Z`) or Unix timestamp. |
| `end` | string | Exclusive end. Same formats as `start`. |
| `downsample` | string | Bucket size: `minute`, `hour`, or `day`. (This is the Inspector's `by`.) |
| `metric` | string | Comma-separated metric names to return. Omit for a default set; naming below. |
| `group_by` | string | Dimensions to split by. Origin: `host`, `region`, `datacenter`. Domain: `domain`, `region`, `datacenter`. Comma-separate to nest. Add `datacenter` (or `region`) when diagnosing — per-POP granularity surfaces issues local to one POP that the host/domain aggregate hides. |
| `region` | string | Comma-separated region filter (same codes as historical stats). |
| `datacenter` | string | Comma-separated uppercase POP codes. |
| `host` | string | Origin Inspector only: comma-separated origin hosts to filter. |
| `domain` | string | Domain Inspector only: comma-separated domains to filter. |
| `limit` | string | Max timeseries rows per page. Max 200. |
| `cursor` | string | Pagination cursor from a previous response's `meta.next_cursor`. |

### Response shape

```json
{
  "status": "ok",
  "meta": {
    "start": "2026-07-01T00:00:00Z",
    "end": "2026-07-02T00:00:00Z",
    "downsample": "hour",
    "metrics": ["responses", "status_5xx"],
    "limit": 100,
    "next_cursor": "eyJvZmZzZXQiOjEwMH0="
  },
  "data": [
    {
      "dimensions": { "host": "origin.example.com", "region": "usa", "datacenter": "SJC" },
      "values": [
        { "responses": 1200, "status_2xx": 1180, "status_5xx": 4, "resp_body_bytes": 5242880 },
        { "responses": 1310, "status_2xx": 1300, "status_5xx": 2, "resp_body_bytes": 5570560 }
      ]
    }
  ]
}
```

- `data[]` is one entry per unique dimension combination (per `group_by`).
- `data[].values[]` is a **sparse** array aligned to the time buckets between `start` and `end` at
  `downsample` granularity — metrics that are zero for a bucket are omitted from that object, so
  do not assume every key is present in every element.
- `data[].dimensions` labels which origin/domain/region/POP the series belongs to.

### Cursor pagination

Responses return at most `limit` timeseries rows. If `meta.next_cursor` is non-null, request the
next page with that value as `cursor`; stop when it is null.

```bash
KEY="Fastly-Key: $(fastly auth token)"
url="https://api.fastly.com/metrics/origins/services/$SID?start=2026-07-01T00:00:00Z&end=2026-07-02T00:00:00Z&downsample=hour&group_by=host&limit=200"
cursor=""
while :; do
  resp=$(curl -sS -H "$KEY" "${url}${cursor:+&cursor=$cursor}")
  echo "$resp" | jq -c '.data[]'
  cursor=$(echo "$resp" | jq -r '.meta.next_cursor // empty')
  [ -z "$cursor" ] && break
done
```

## Metric naming (Inspector-specific)

Inspector metrics are prefixed by **source**, so the same underlying quantity appears up to three
times:

- `all_` — all traffic to the origin/domain.
- `compute_` — traffic originating from Fastly Compute.
- `waf_` — traffic seen by the WAF.

Within each prefix you get response counts and status breakdowns (`*_responses`, `*_status_2xx`
… `*_status_5xx`, specific codes like `*_status_503`), byte counters (`*_resp_body_bytes`,
`*_resp_header_bytes`), and — for Origin Inspector — **latency histogram buckets** spanning ~0–1 ms
through 60,000 ms+ (e.g. `all_latency_0_to_1ms`, …, `all_latency_60000ms`). Domain Inspector also
exposes edge/cache metrics (`edge_requests`, `edge_hit_ratio`, `origin_offload`), protocol
(`http2`, `http3`), and TLS versions. Request the exact ones you need via `metric=` to keep
responses small. Full catalog in [fields.md](fields.md).

## Real-time (rt.fastly.com)

```text
GET /v1/origins/{service_id}/ts/{start_timestamp}
GET /v1/domains/{service_id}/ts/{start_timestamp}
GET /v1/origins/{service_id}/ts/h            # last 120 seconds
GET /v1/domains/{service_id}/ts/h
GET /v1/origins/{service_id}/ts/h/limit/{n}  # last n entries, n <= 120
GET /v1/domains/{service_id}/ts/h/limit/{n}
```

Same polling model as the [real-time analytics API](realtime-api.md): start at `ts/0` for the
last complete second, then pass the response's `Timestamp` back on each subsequent request.
One-second granularity, ~1–2s processing delay reported as `AggregateDelay`.

### Real-time response shape

```json
{
  "AggregateDelay": 2,
  "Timestamp": 1751328001,
  "Data": [
    {
      "recorded": 1751328000,
      "aggregated": {
        "origin.example.com": { "all_responses": 42, "all_status_2xx": 40, "all_resp_body_bytes": 131072 }
      },
      "datacenter": {
        "SJC": { "origin.example.com": { "all_responses": 20, "all_status_2xx": 19 } }
      }
    }
  ]
}
```

- `aggregated` is keyed by **origin host** (Origin Inspector) or **domain** (Domain Inspector),
  then by metric name.
- `datacenter` is keyed by POP, then by origin/domain, then by metric.
- Metrics use the same `all_`/`compute_`/`waf_` prefixes as the historical inspector.

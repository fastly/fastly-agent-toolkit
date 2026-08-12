# Stats HTTP APIs

Two hosts, all `GET`, all authenticated with `Fastly-Key: <token>`.

- `https://api.fastly.com` for historical data.
- `https://rt.fastly.com` for live per-second data.

Three response shapes, and the parameter names differ between them. Sending the wrong vocabulary
is rejected.

| Shape     | Endpoints                              | Envelope                                                                 | Time params                    | Paging             |
| --------- | -------------------------------------- | ------------------------------------------------------------------------ | ------------------------------ | ------------------ |
| Classic   | `/stats*`                              | `{status, meta, msg, data}`, flat row per period                         | `from` / `to` / `by`           | none               |
| Inspector | `/metrics/{origins,domains}/services/` | `{status, meta, data}`, `dimensions` + `values[]`                        | `start` / `end` / `downsample` | `meta.next_cursor` |
| Real-time | `/v1/...` on `rt.fastly.com`           | `{Data:[{recorded, aggregated, datacenter}], Timestamp, AggregateDelay}` | poll `ts/{timestamp}`          | chain `Timestamp`  |

## Classic historical, api.fastly.com

| Purpose                          | Path                                        |
| -------------------------------- | ------------------------------------------- |
| All services, grouped by service | `/stats`                                    |
| All services, one summed series  | `/stats/aggregate`                          |
| One field across all services    | `/stats/field/{field}`                      |
| One service                      | `/stats/service/{service_id}`               |
| One service, one field           | `/stats/service/{service_id}/field/{field}` |
| Account usage, by region         | `/stats/usage`                              |
| Account usage, by service        | `/stats/usage_by_service`                   |
| Month-to-date usage              | `/stats/usage_by_month`                     |
| Per-POP summary, last 35 days    | `/service/{service_id}/stats/summary`       |
| Region codes                     | `/stats/regions`                            |
| POP catalog                      | `/datacenters`                              |

Query parameters on `/stats`, `/stats/aggregate`, `/stats/field/{field}` and the
`/stats/service/*` forms:

| Param        | Notes                                                                                          |
| ------------ | ---------------------------------------------------------------------------------------------- |
| `from`       | Unix timestamp, ISO-8601, or a Chronic string (`1 day ago`). `yesterday` resolves to noon UTC. |
| `to`         | Same formats. Defaults to now.                                                                 |
| `by`         | `minute`, `hour` or `day`. No `month`. Minute data is retained roughly one day.                |
| `region`     | One `stats_region` code. Silently overrides `datacenter` when both are sent.                   |
| `datacenter` | Comma-separated uppercase POP codes. A real filter; composes with any `by`.                    |
| `services`   | `/stats` only: comma-separated service IDs.                                                    |

`data` grouping depends on the endpoint: `/stats` gives an object keyed by service ID,
`/stats/aggregate` a single array, `/stats/service/{id}` an array of period rows. Each row carries
`start_time` plus the measurement fields.

## Usage and billing endpoints

`/stats/usage` and `/stats/usage_by_service` take `from` / `to` / `by` / `region` and answer with
an object keyed by `stats_region`, each region carrying only `bandwidth`, `requests` and
`compute_requests`. Raw units, and `requests` excludes Compute traffic, so an account total must add
`compute_requests` per region.

`region` is accepted here and ignored. `?region=europe` returns all eleven regions, `data`
byte-identical to the unfiltered response, `meta.region` echoing `europe`. Same on
`/stats/usage_by_service`, whose `data` is keyed by region then by service ID. Only
`fastly stats usage --region` filters, client-side.

`/stats/usage_by_month` takes `year` (4-digit), `month` (2-digit) and `billable_units`. Its `data`
is `{customer_id, services, total}`, both `services` and `total` keyed by region.

`billable_units=true` rescales and nothing else: `bandwidth` / 1e9, `requests` and
`compute_requests` / 10,000, so a `requests` of `1.4452` means 14,452. For one month
`/stats/usage`, the per-service `/stats` sum and `/stats/usage_by_month` report the same byte total.
`bandwidth` already counts origin-bound request bytes, so the billable figure is not larger. See
<https://docs.fastly.com/products/how-we-calculate-your-delivery-bill>.

`/service/{id}/stats/summary` follows none of the conventions above. `start_time` and `end_time`
are required and must be epoch seconds; ISO-8601 returns `{"status":"error","msg":"invalid
start_time"}`. It is minutely-backed, so the window cannot start more than 35 days back, and it
answers `{"stats": {"<POP>": {...}}}` with no `data` / `meta` / `status` envelope. One aggregate
per POP, not a time series, so it does not replace `datacenter=`.

## POP catalog

`/datacenters` returns a flat array with `code`, `name`, `group`, `region`, `stats_region`,
`billing_region`, `coordinates`, and `shield` (the string a backend's `shield` setting takes).
`shield` is absent, not null, on POPs not offered as shields, so test with `.shield // "-"`.

Each POP carries four independent taxonomies and only one of them is what `region=` accepts:

| Field            | Example values                           | Use                                           |
| ---------------- | ---------------------------------------- | --------------------------------------------- |
| `stats_region`   | `usa`, `europe`, `asia`, `anzac`         | What `region=` takes                          |
| `region`         | `US-East`, `EU-Central`, `North-America` | POP topology label, not accepted by `region=` |
| `group`          | `United States`, `Europe`, `India`       | Coarse reporting grouping                     |
| `billing_region` | `North America`, `Europe`, `Australia`   | Invoice grouping                              |

`North-America` holds four Canadian POPs (`YYC`, `YUL`, `YYZ`, `YVR`) and no US POPs, and every
one of them reports `stats_region = usa`. Region-level stats cannot isolate Canada, so filter by
POP code instead.

The `stats_region` values accepted by `region=`, from `GET /stats/regions`: `africa_std`, `anzac`,
`asia`, `asia_india`, `asia_southkorea`, `europe`, `latam`, `mexico`, `saudi_arabia`,
`southamerica_std`, `usa`.

## Inspector, api.fastly.com

```text
GET /metrics/origins/services/{service_id}
GET /metrics/domains/services/{service_id}
```

| Param        | Notes                                                                             |
| ------------ | --------------------------------------------------------------------------------- |
| `start`      | Inclusive. ISO-8601 with `Z`, or Unix timestamp. No relative strings.             |
| `end`        | Exclusive. Same formats.                                                          |
| `downsample` | `minute`, `hour` or `day`. This is the Inspector's `by`.                          |
| `metric`     | Comma-separated metric names. This is the Inspector's `field`.                    |
| `group_by`   | Origin: `host`, `region`, `datacenter`. Domain: `domain`, `region`, `datacenter`. |
| `region`     | Comma-separated region filter.                                                    |
| `datacenter` | Comma-separated uppercase POP codes.                                              |
| `host`       | Origin Inspector only.                                                            |
| `domain`     | Domain Inspector only.                                                            |
| `limit`      | Rows per page, max 200.                                                           |
| `cursor`     | From the previous response's `meta.next_cursor`.                                  |

`data[]` is one entry per dimension combination; `data[].values[]` is sparse, aligned to the time
buckets, with zero metrics omitted from an element. Loop on `next_cursor` until it is empty or
you silently truncate the result.

Both Inspectors are paid add-ons enabled per service. When the product is off the endpoint still
answers HTTP 200 with `"status":"success"` and `"data":[]`, indistinguishable from a service that
had no traffic. Check `fastly products -s ID` first.

The two paths do not share an envelope. Success is `{data, meta, status:"success"}`, `status` a
string, `meta` echoing the defaults `limit: 100`, `sort`, `group_by`, `filters: {}`,
`next_cursor: ""`. Rejection is HTTP 400 with an RFC 7807 body, `status` a number, no `msg` either
way:

```json
{"type":"https://fastly.help/metrics/validation-error","title":"Request parameters were invalid.",
 "status":400,"errors":[{"property":"start","reason":"failed to parse 'start' time"}],
 "detail":"Parameters with invalid values: 'start'"}
```

Branch on `.status == "success"`, not on `.status`. Read causes from `errors[].reason`. Content-Type
is `application/json` on both paths.

Metric names take a source prefix (`all_`, `compute_`, `waf_`) or none: `metric=responses` and
`metric=all_responses` both validate. Strip the prefix to look a name up in
[fields.md](fields.md). An unknown name is a 400, `Unrecognized metric names: '...'`, and names are
validated even where the product is off, so a 400 says nothing about entitlement. No cap on how
many: 20 in one call come back echoed in `meta.metric`, despite the CLI help's 10.

Origin Inspector adds latency histogram buckets (`all_latency_0_to_1ms` through
`all_latency_60000ms`), which is where origin response time lives. Edge processing time is a
different measurement and comes from classic `hits_time` / `miss_time` / `pass_time`.

Real-time per-domain and per-origin data lives on `rt.fastly.com` instead:
`/v1/domains/{id}/ts/{ts}` and `/v1/origins/{id}/ts/{ts}`, both taking the `ts/h` and
`ts/h/limit/{n}` forms below.

## Real-time, rt.fastly.com

```text
GET /v1/channel/{service_id}/ts/{timestamp}      # 0 for the most recent complete second
GET /v1/channel/{service_id}/ts/h                # up to the last 120 seconds in one call
GET /v1/channel/{service_id}/ts/h/limit/{n}      # last n entries, n <= 120
```

`/v1/origins/{id}/...` and `/v1/domains/{id}/...` take the same forms.

It is a long poll, not a one-shot query. Start at `ts/0`, then pass the response's `Timestamp`
back as the next path value; do not compute `ts+1` yourself. The response is cached with a
1-second TTL, so keep one request outstanding at a time. `AggregateDelay` says how many seconds
behind real time the newest data is. On a quiet service the payload is
`{"Data":[],"Timestamp":...,"Error":"No data available, please retry"}` with HTTP 200: an `Error`
field, not an HTTP error.

`Data[]` holds one record per elapsed second: `recorded`, `aggregated` (all-POP totals keyed by
metric name), and `datacenter` (the same metrics keyed by POP code). `ts/h` returns only seconds
that had traffic, so `Data | length` is a sample count, not a window in seconds, and the `recorded`
span is not one either: it stops at the last second that had traffic. Divide a rate by 120, the
lookback `ts/h` covers. The span is still worth reading, as the tell for how bursty the traffic is:

```bash
curl -sS -H "Fastly-Key: $(fastly auth token --quiet)" \
  "https://rt.fastly.com/v1/channel/$SID/ts/h" \
  | jq 'if (.Data|length) == 0 then {samples: 0, window_s: 120, requests: 0, rps: 0, error: .Error}
        else {samples: (.Data|length), window_s: 120,
              span_s: (([.Data[].recorded]|max) - ([.Data[].recorded]|min) + 1),
              requests: ([.Data[] | (.aggregated.requests // 0)
                                    + (.aggregated.compute_requests // 0)]|add)}
             | . + {rps: (.requests / .window_s)} end'
```

Guard the empty case first: on a quiet service `max` and `min` over an empty array both return
`null` and the subtraction aborts the filter with `null (null) cannot be subtracted`. The newest
`recorded` runs about 8 seconds behind the wall clock, which is `AggregateDelay`, so the window is
the 120 seconds ending then rather than ending now.

Real-time offers no `by` or region filtering: you get every second for the whole service and
filter client-side from the `datacenter` map. For flexible windows, regions or fields, including
per-POP history, use classic historical with `datacenter=`.

`fastly stats realtime --json` reshapes this. It emits one flat object per second,
`{recorded, aggregated, datacenter}`, with no `Data` array and no `Timestamp`, and it chains the
poll for you. A `jq` filter written for the raw payload (`.Data[]`) matches nothing against CLI
output, and with `.Data[]?` it fails silently.

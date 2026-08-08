# Fastly Observability

Base: `https://api.fastly.com` | Auth: `Fastly-Key: $FASTLY_API_TOKEN` | Docs: https://www.fastly.com/documentation/reference/api/observability

## Key Concepts

**Real-time vs historical timing.** Real-time endpoints (`rt.fastly.com`) provide per-second data with an `AggregateDelay`. Historical endpoints (`api.fastly.com/stats`) support `minute`, `hour`, and `day` resolution. Minute data is usually available within 2-15 minutes; hourly within 15 minutes of the hour; daily around 2am UTC the following day.

**120-second real-time window.** The `/ts/h` endpoints return data for the 120 seconds preceding the latest available timestamp. Use `/ts/{timestamp}` with the returned `Timestamp` for continuous polling beyond this window.

**Metric aggregation.** `bandwidth` is bytes delivered over the bucket, summed from several byte fields: not bits, not a rate. Fastly reports and bills decimal units, so GB here means 10^9 bytes, not GiB.

**Ratios are per-bucket gauges.** `hit_ratio` is `hits / (hits + miss)`, not hits over misses. `origin_offload` is the fraction of bytes served from cache. The API computes both per bucket; to cover several buckets, sum the counters and recompute. Never sum or average the ratios.

**Relative `from` drops buckets.** A bucket is returned only if it falls wholly inside the window and has already been aggregated. Relative values are offsets from the request time, so the window opens and closes mid-bucket and both ragged ends are discarded: `from=N+days+ago&by=day` returns N-1 buckets, never N. Below `day`, publication lag costs the newest buckets on top of that, so the count is not even stable between two identical calls. Explicit UTC boundaries return every bucket in the range. `from=yesterday` is 12:00 UTC, not midnight; `from=today` is now, so the window is empty. Confirm with `meta.from` and `meta.to`.

**Domain Inspector, Origin Inspector, and Log Explorer & Insights require enablement.** These are optional upgrades that must be enabled per service before their endpoints return data.

## Enablement

Product slugs: `domain_inspector`, `origin_inspector`, `log_explorer_insights`. See `products.md` for the universal enablement pattern.

## Historical Stats

Use `fastly stats` from the `fastly-cli` skill: `historical` for one service (`--field` to narrow to one metric), `aggregate` across the account, `usage` and `usage --by-service` for usage totals, `regions` for the region codes. It covers the whole `/stats` surface except the four cases below.

| Need                          | Request                                                           |
| ----------------------------- | ----------------------------------------------------------------- |
| Per-POP history               | `/stats/service/{id}?datacenter=SJC,LHR&by=day`                   |
| Billable usage for a month    | `/stats/usage_by_month?year=2026&month=07&billable_units=true`    |
| Every service in one call     | `/stats` or `/stats/field/{field}`                                |
| Per-POP summary, last 35 days | `/service/{id}/stats/summary?start_time={epoch}&end_time={epoch}` |

`datacenter=` is missing from the CLI's SDK input type, not just from its flags, so no flag combination reaches it. `stats historical` always resolves a service ID and errors without one, which is why the two account-wide paths need `curl`. `usage_by_month` is the only source of billable units, which count delivery plus origin traffic and differ from raw edge bandwidth.

`/service/{id}/stats/summary` follows none of the conventions above: `start_time` and `end_time` are required and must be epoch seconds (ISO-8601 returns `invalid start_time`), it is minutely-backed so the window cannot start more than 35 days back, and it answers `{"stats": {"<POP>": {...}}}` with no `data`/`meta`/`status` envelope. One aggregate per POP, not a time series, so it does not replace `datacenter=`.

```bash
# Per-POP daily history for a closed month
curl -s -H "Fastly-Key: $FASTLY_API_TOKEN" \
  "https://api.fastly.com/stats/service/$SERVICE_ID?from=2026-07-01T00:00:00Z&to=2026-08-01T00:00:00Z&by=day&datacenter=SJC"
```

## Real-Time Stats

Per-second stats for a single service, hosted on `rt.fastly.com` (not `api.fastly.com`).

`fastly stats realtime` handles the common case: it does the `ts/0` then poll-with-returned-`Timestamp` loop for you and streams one flat JSON object per second, so it needs no filtering flags and takes none. Two things it does not do:

| Need                            | Request                                                                  |
| ------------------------------- | ------------------------------------------------------------------------ |
| 120 s of per-POP data, one call | `https://rt.fastly.com/v1/channel/{service_id}/ts/h`                     |
| Bounded batch                   | `https://rt.fastly.com/v1/channel/{service_id}/ts/h/limit/{max_entries}` |

`ts/h` is the 120 seconds preceding the latest available timestamp, not an hour, and the `h` invites exactly that mistake. Entries arrive under `Data[]` (each `{recorded, aggregated, datacenter}`), one per second that carried traffic, so neither the entry count nor the covered span reaches 120 on a quiet service. Compute the span from the `recorded` values and report it beside any rate derived from them; a rate divided by an assumed 120 is wrong by whatever the gap happens to be.

## Metrics Platform

Time-series TTFB (time-to-first-byte) percentile metrics at edge, origin, and shield. Uses RFC 8339 timestamps and path-based granularity (`minutely`, `hourly`, `daily`). Supports `group_by`, `region`, `datacenter`, and cursor pagination.

Metric set: `ttfb` -- metrics include `ttfb_edge_p50_us`, `ttfb_origin_p95_us`, `ttfb_shield_p99_us`, etc.

| Action                    | Method | Endpoint                                                |
| ------------------------- | ------ | ------------------------------------------------------- |
| Get metrics for a service | `GET`  | `/metrics/platform/services/{service_id}/{granularity}` |

## Domain Inspector

Per-domain edge metrics (requests, bytes, status codes, hit ratio, origin offload). **Must be enabled per service via the enablement API.** Uses `start`/`end` (ISO 8601) and `downsample` (`minute`, `hour`, `day`). Can `group_by` domain, region, or datacenter. Absolute times in historical API are UTC.

Historical is `fastly stats domain-inspector`. Only the real-time side needs the API:

| Action                                   | Method | Endpoint                                                                 |
| ---------------------------------------- | ------ | ------------------------------------------------------------------------ |
| Get real-time domain data from timestamp | `GET`  | `https://rt.fastly.com/v1/domains/{service_id}/ts/{start_timestamp}`     |
| Get real-time domain data (last 120s)    | `GET`  | `https://rt.fastly.com/v1/domains/{service_id}/ts/h`                     |
| Get real-time domain data (limited)      | `GET`  | `https://rt.fastly.com/v1/domains/{service_id}/ts/h/limit/{max_entries}` |

## Origin Inspector

Per-origin metrics (responses, bytes, status codes, latency buckets). **Must be enabled per service via the enablement API.** Can `group_by` host, region, or datacenter. Includes latency histogram buckets (0-1ms through 60000ms+). Absolute times in historical API are UTC.

Historical is `fastly stats origin-inspector`. Only the real-time side needs the API:

| Action                                   | Method | Endpoint                                                                 |
| ---------------------------------------- | ------ | ------------------------------------------------------------------------ |
| Get real-time origin data from timestamp | `GET`  | `https://rt.fastly.com/v1/origins/{service_id}/ts/{start_timestamp}`     |
| Get real-time origin data (last 120s)    | `GET`  | `https://rt.fastly.com/v1/origins/{service_id}/ts/h`                     |
| Get real-time origin data (limited)      | `GET`  | `https://rt.fastly.com/v1/origins/{service_id}/ts/h/limit/{max_entries}` |

## Alerts

Metric-based alert definitions that trigger notifications via integrations. Sources: `origins`, `domains`, or `stats`. Evaluation strategies: `above_threshold`, `all_above_threshold`, `below_threshold`, `percent_absolute`, `percent_decrease`, `percent_increase`. Periods: `2m`, `3m`, `5m`, `15m`, `30m`.

| Action                  | Method   | Endpoint                              |
| ----------------------- | -------- | ------------------------------------- |
| List alert definitions  | `GET`    | `/alerts/definitions`                 |
| Create alert definition | `POST`   | `/alerts/definitions`                 |
| Get alert definition    | `GET`    | `/alerts/definitions/{definition_id}` |
| Update alert definition | `PUT`    | `/alerts/definitions/{definition_id}` |
| Delete alert definition | `DELETE` | `/alerts/definitions/{definition_id}` |
| List alert history      | `GET`    | `/alerts/history`                     |

```bash
# List all alert definitions
curl -s -H "Fastly-Key: $FASTLY_API_TOKEN" \
  "https://api.fastly.com/alerts/definitions"
```

## Log Explorer

Query sampled log records for a service. Requires `service_id`, `start`, and `end` (RFC 3339). Supports field-based filters with operators (`=`, `ends-with`, `in`, `not_in`, `gt`, `gte`, `lt`, `lte`). Filterable fields: `domain`, `request_path`, `fastly_pop`, `response_time`, `response_status`, `fastly_is_shield`, `fastly_is_edge`, `client_os_name`, `client_device_type`, `client_browser_name`, `fastly_is_cache_hit`.

| Action               | Method | Endpoint                      |
| -------------------- | ------ | ----------------------------- |
| Retrieve log records | `GET`  | `/observability/log-explorer` |

```bash
# Query log records for a service
curl -s -H "Fastly-Key: $FASTLY_API_TOKEN" \
  "https://api.fastly.com/observability/log-explorer?service_id=$SERVICE_ID&start=2024-01-01T00:00:00Z&end=2024-01-02T00:00:00Z&limit=10"
```

## Documentation

URLs below serve Markdown (use the `Accept: text/markdown` header). Pages contain lists of available metrics and stats respectively.

| Source                             | URL                                                                                  |
| ---------------------------------- | ------------------------------------------------------------------------------------ |
| Historical stats API reference     | `https://www.fastly.com/documentation/reference/api/metrics-stats/historical-stats`  |
| Real-time stats API reference      | `https://www.fastly.com/documentation/reference/api/metrics-stats/realtime`          |
| Domain Inspector API reference     | `https://www.fastly.com/documentation/reference/api/metrics-stats/domain-inspector`  |
| Origin Inspector API reference     | `https://www.fastly.com/documentation/reference/api/metrics-stats/origin-inspector`  |
| Observability guides               | `https://www.fastly.com/documentation/guides/observability`                          |
| Alert configuration and management | `https://www.fastly.com/documentation/guides/observability/alerts`                   |
| Observability dashboards setup     | `https://www.fastly.com/documentation/guides/observability/observability-dashboards` |

For general Fastly platform guidance, documentation source index, and other specialized skills, see the `fastly` skill.

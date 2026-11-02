# Fastly Observability

Base: `https://api.fastly.com` | Auth: `Fastly-Key: $FASTLY_API_TOKEN` | Docs: https://www.fastly.com/documentation/reference/api/observability

Traffic numbers themselves (historical stats, real-time, Origin and Domain Inspector) belong to
the `fastly-stats` skill, which owns those endpoints, their parameters and their unit conventions.
This file covers the observability surfaces `fastly-stats` does not: metrics platform, alerts, and
Log Explorer & Insights.

## Enablement

Domain Inspector, Origin Inspector and Log Explorer & Insights are optional upgrades that must be
enabled per service. Product slugs: `domain_inspector`, `origin_inspector`,
`log_explorer_insights`. See `products.md` for the universal enablement pattern, or check with
`fastly products --service-id SERVICE_ID`.

## Metrics Platform

Time-series TTFB (time-to-first-byte) percentile metrics at edge, origin, and shield. Uses RFC 8339 timestamps and path-based granularity (`minutely`, `hourly`, `daily`). Supports `group_by`, `region`, `datacenter`, and cursor pagination.

Metric set: `ttfb` -- metrics include `ttfb_edge_p50_us`, `ttfb_origin_p95_us`, `ttfb_shield_p99_us`, etc.

| Action                    | Method | Endpoint                                                |
| ------------------------- | ------ | ------------------------------------------------------- |
| Get metrics for a service | `GET`  | `/metrics/platform/services/{service_id}/{granularity}` |

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
fastly service alert list [--service-id SERVICE_ID] --json   # {data, meta}; page with --cursor
fastly service alert history [--service-id SERVICE_ID] [--status active|resolved] --json
# --type takes the evaluation strategy
fastly service alert create --service-id SERVICE_ID --name NAME --description TEXT \
  --source SOURCE --metric METRIC --type above_threshold --threshold N --period 5m
```

## Log Explorer & Insights

Use the API: `fastly service logging log-explorer` fails on any non-empty result (`origin_host` is an array, the
CLI expects a string), and `fastly service logging insights --json` drops fields such as `status_code`.

```bash
# Raw records. filter[FIELD][OP]=VALUE, repeatable, ANDed. limit max 100; page with meta.next_cursor.
curl -s -G -H "Fastly-Key: $FASTLY_API_TOKEN" https://api.fastly.com/observability/log-explorer \
  --data-urlencode service_id="$SERVICE_ID" \
  --data-urlencode start=2026-11-01T00:00:00Z --data-urlencode end=2026-11-02T00:00:00Z \
  --data-urlencode limit=100 --data-urlencode 'filter[response_status][gte]=500' \
  | jq -c '.data[]? | {timestamp, request_path, response_status, fastly_pop, origin_host}'

curl -s -G -H "Fastly-Key: $FASTLY_API_TOKEN" https://api.fastly.com/observability/log-insights \
  --data-urlencode service_id="$SERVICE_ID" \
  --data-urlencode start=2026-11-01T00:00:00Z --data-urlencode end=2026-11-02T00:00:00Z \
  --data-urlencode visualization=top-5xx-urls --data-urlencode limit=20
```

No match returns `"data": null`, hence `.data[]?`.

Filter fields: `domain`, `request_path`, `fastly_pop`, `response_time`, `response_status`, `fastly_is_shield`,
`fastly_is_edge`, `client_os_name`, `client_device_type`, `client_browser_name`, `fastly_is_cache_hit`.
Records name the booleans `is_shield`, `is_edge`, `is_cache_hit`.
Operators: `eq`, `ends-with`, `in`, `not_in` (comma-separated values), `gt`, `gte`, `lt`, `lte`.
The API reference documents `=` for equality, but the API rejects it as an unknown operator; use `eq`.

Insights visualizations: `top-url-by-requests`, `top-url-by-bandwidth`, `top-url-by-misses`,
`top-url-by-duration-sum`, `top-url-by-cache-hit-ratio`, `bottom-url-by-cache-hit-ratio`, `top-4xx-urls`,
`top-5xx-urls`, `top-503-responses`, `response-status-codes`, `country-statistics`, `top-browser-by-requests`,
`top-content-type-by-requests`, `top-device-by-requests`, `top-os-by-requests`.
Narrow with `domain` (plus `domain_exact_match=true`) and `pops=IAD,DFW`; `limit` caps rows at 100.

## Documentation

URLs below serve Markdown (use the `Accept: text/markdown` header).

| Source                             | URL                                                                                  |
| ---------------------------------- | ------------------------------------------------------------------------------------ |
| Observability guides               | `https://www.fastly.com/documentation/guides/observability`                          |
| Alert configuration and management | `https://www.fastly.com/documentation/guides/observability/alerts`                   |
| Observability dashboards setup     | `https://www.fastly.com/documentation/guides/observability/observability-dashboards` |

For general Fastly platform guidance, documentation source index, and other specialized skills, see the `fastly` skill.

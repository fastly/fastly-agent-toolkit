# Fastly Observability

Base: `https://api.fastly.com` | Auth: `Fastly-Key: $FASTLY_API_TOKEN` | Docs: https://www.fastly.com/documentation/reference/api/observability

Traffic numbers themselves (historical stats, real-time, Origin and Domain Inspector) belong to
the `fastly-stats` skill, which owns those endpoints, their parameters and their unit conventions.
This file covers the observability surfaces `fastly-stats` does not: metrics platform, alerts, and
log explorer.

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

URLs below serve Markdown (use the `Accept: text/markdown` header).

| Source                             | URL                                                                                  |
| ---------------------------------- | ------------------------------------------------------------------------------------ |
| Observability guides               | `https://www.fastly.com/documentation/guides/observability`                          |
| Alert configuration and management | `https://www.fastly.com/documentation/guides/observability/alerts`                   |
| Observability dashboards setup     | `https://www.fastly.com/documentation/guides/observability/observability-dashboards` |

For general Fastly platform guidance, documentation source index, and other specialized skills, see the `fastly` skill.

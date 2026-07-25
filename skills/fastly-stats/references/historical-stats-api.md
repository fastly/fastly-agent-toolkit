# Historical Stats API

Base: `https://api.fastly.com` | Auth: `Fastly-Key: $FASTLY_API_TOKEN` | Docs: <https://www.fastly.com/documentation/reference/api/metrics-stats/historical-stats/>

Aggregated, historical traffic counters for one service, all services, or the whole account.
Every endpoint is `GET` and returns the **classic flat envelope** `{status, meta, msg, data}`.
For the metric field names that appear inside `data`, see [fields.md](fields.md).

## Endpoints

| Purpose | Method + path |
| --- | --- |
| All services, grouped by service | `GET /stats` |
| All services, single aggregated series | `GET /stats/aggregate` |
| One field across all services | `GET /stats/field/{field}` |
| One service | `GET /stats/service/{service_id}` |
| One service, one field | `GET /stats/service/{service_id}/field/{field}` |
| Account usage (grouped by region) | `GET /stats/usage` |
| Account usage grouped by service | `GET /stats/usage_by_service` |
| Month-to-date usage | `GET /stats/usage_by_month` |
| Valid region codes | `GET /stats/regions` |
| Legacy per-service summary (superseded) | `GET /service/{service_id}/stats/summary` |

## Query parameters

Apply to `/stats`, `/stats/aggregate`, `/stats/field/{field}`, and the `/stats/service/*`
variants:

| Param | Type | Notes |
| --- | --- | --- |
| `from` | string | Start of window (inclusive). Unix timestamp, or a Chronic relative string (`yesterday`, `two weeks ago`, `1 hour ago`). Default depends on `by`. |
| `to` | string | End of window. Same formats as `from`. Defaults to now. |
| `by` | string | Sample granularity: `minute`, `hour`, or `day`. (No `month`.) |
| `region` | string | Restrict to one region — see region codes below. |
| `datacenter` | string | Comma-separated uppercase POP codes (e.g. `SJC,LHR`). |
| `services` | string | `/stats` only: comma-separated service IDs to limit the set. |

Path params: `{service_id}` is the alphanumeric service ID; `{field}` is any measurement name
from [fields.md](fields.md) (e.g. `bandwidth`, `requests`, `status_5xx`).

`minute` granularity is retained for a limited window (roughly the last day); `hour`/`day` reach
much further back. If a query returns empty for old data at `by=minute`, widen `by`.

## Response shape

```json
{
  "status": "success",
  "meta": { "from": "2026-07-01 00:00:00 UTC", "to": "2026-07-02 00:00:00 UTC", "by": "day", "region": "all" },
  "msg": null,
  "data": [
    {
      "service_id": "SU1Z...",
      "start_time": 1751328000,
      "requests": 1048576,
      "hits": 999000,
      "miss": 40000,
      "pass": 9576,
      "errors": 12,
      "hit_ratio": 0.961,
      "bandwidth": 734003200,
      "status_2xx": 1040000,
      "status_4xx": 8000,
      "status_5xx": 576
    }
  ]
}
```

How `data` is grouped depends on the endpoint:

- `/stats` — `data` is an **object keyed by service ID**, each value an array of period rows.
- `/stats/aggregate` — `data` is a **single array** of period rows summed across all services.
- `/stats/service/{id}` — `data` is an **array** of period rows for that one service.
- `/stats/field/{field}` and `/stats/service/{id}/field/{field}` — same grouping as above, but
  each row carries only `start_time` + that one field.

`start_time` is the Unix timestamp for the start of each bucket. `hit_ratio` and `origin_offload`
are ratios in `[0,1]`; everything else is an integer counter or a byte count. Reading the raw
API you get a normal JSON array in `data` — the NDJSON one-object-per-line behavior is a
**CLI-only** artifact of `fastly stats ... --json`, not the HTTP API.

## Usage & billing endpoints

- `GET /stats/usage` — params `from`, `to`. Totals across all services, grouped by region.
- `GET /stats/usage_by_service` — params `from`, `to`. Same totals split per service and region.
- `GET /stats/usage_by_month` — params `year` (4-digit string), `month` (2-digit string), and
  `billable_units` (boolean). With `billable_units=true`, bandwidth is converted to GB and
  requests divided by 10,000 — i.e. the units you are billed in. Grouped by service and region.

Usage responses nest `data` by region (and by service for the `_by_service`/`_by_month` forms),
each leaf holding usage measurements such as `requests` and `bandwidth`.

```bash
# This month's billable usage
curl -sS -H "Fastly-Key: $(fastly auth token)" \
  "https://api.fastly.com/stats/usage_by_month?year=2026&month=07&billable_units=true"
```

## Region codes

`GET /stats/regions` returns the authoritative live list:

```json
{ "status": "success", "meta": {}, "msg": null,
  "data": ["africa_std","anzac","asia","asia_india","asia_southkorea","europe","mexico","southamerica_std","usa"] }
```

Pass any of these as `region=`. Run the endpoint (or `fastly stats regions`) rather than
hardcoding — Fastly adds regions over time.

## Legacy summary endpoint

`GET /service/{service_id}/stats/summary` returns an older per-POP summary. Params: `start_time`
and `end_time` (integer epoch), or a `month`+`year` pair. It is superseded by the endpoints
above — prefer `/stats/service/{id}` for anything new; the field names mirror the catalog in
[fields.md](fields.md).

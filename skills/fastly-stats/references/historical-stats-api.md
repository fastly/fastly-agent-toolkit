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
| POP catalog (code → region, group, shield name) | `GET /datacenters` |
| Legacy per-service summary (superseded) | `GET /service/{service_id}/stats/summary` |

## Query parameters

Apply to `/stats`, `/stats/aggregate`, `/stats/field/{field}`, and the `/stats/service/*`
variants:

| Param | Type | Notes |
| --- | --- | --- |
| `from` | string | Start of window (inclusive). Unix timestamp, or a Chronic relative string (`1 day ago`, `two weeks ago`, `1 hour ago`). Default depends on `by`. **`yesterday` means noon UTC, not midnight** — see [debugging.md](debugging.md#a-relative-window-silently-covers-the-wrong-hours). |
| `to` | string | End of window. Same formats as `from`. Defaults to now. |
| `by` | string | Sample granularity: `minute`, `hour`, or `day`. (No `month`.) |
| `region` | string | Restrict to one region — see region codes below. **Silently overrides `datacenter`** if both are sent. |
| `datacenter` | string | Comma-separated **uppercase** POP codes (e.g. `SJC,LHR`). Genuinely filters; see below. |
| `services` | string | `/stats` only: comma-separated service IDs to limit the set. |

Path params: `{service_id}` is the alphanumeric service ID; `{field}` is any measurement name
from [fields.md](fields.md) (e.g. `bandwidth`, `requests`, `status_5xx`).

`minute` granularity is retained for a limited window (roughly the last day); `hour`/`day` reach
much further back. If a query returns empty for old data at `by=minute`, widen `by`.

### Per-POP history works — `datacenter` is a real filter

**Per-POP historical data exists.** `datacenter=` is honored, not ignored, and it composes with
`by=minute|hour|day`, so you can reconstruct per-POP history rather than being limited to the
real-time API's 120-second window. Verified against a live three-tier service, one week, `by=day`:

```text
unfiltered                       requests = 392
datacenter=DEN                   requests = 214
datacenter=IAD                   requests = 165
datacenter=DEN,IAD               requests = 379   # 214 + 165, comma-separation works
datacenter=<all 179 POP codes>   requests = 392   # reconciles exactly with unfiltered
```

Two confirmations that it is not silently ignored: the response `meta` echoes back
`"datacenter": "DEN"`, and per-POP sums reconcile with the unfiltered total. Failure modes are
**loud**, which is what you want:

- lowercase code (`datacenter=den`) → `{"status":"error","msg":"invalid datacenter"}`
- unknown code (`datacenter=ZZZ`) → `{"status":"error","msg":"invalid datacenter"}`

**The one silent failure: `region` beats `datacenter`.** Sending both returns HTTP 200, a plausible
`data` array, and `"datacenter": null` in `meta` — the POP filter is dropped and you get whole-region
data at the wrong scope:

```text
?datacenter=DEN                 -> meta.datacenter="DEN",  requests = 214   # POP-scoped
?datacenter=DEN&region=usa      -> meta.datacenter=null,   requests = 392   # region won, unfiltered
```

Never send both. **Always check `meta` echoes the filter you asked for** before trusting the scope of
a filtered response — that check is the whole defense, since the numbers themselves look fine.

Even so, capture a baseline: per-POP history is retained at `by=minute` only for roughly the last
day, so a change you want to compare at minute resolution needs its "before" snapshot taken
**before** you make the change. See [debugging.md](debugging.md#i-changed-something-and-cannot-recover-the-pre-change-per-pop-state).

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
curl -sS -H "Fastly-Key: $(fastly auth token --quiet)" \
  "https://api.fastly.com/stats/usage_by_month?year=2026&month=07&billable_units=true"
```

**Billable units vs raw stats.** Fastly bills in decimal SI units — 1 GB = 10^9 bytes,
1 TB = 10^12 bytes — and presents requests in units of 10,000. The billed figure is *not* the same
as summing the raw `bandwidth` field from `/stats`: billing counts the size of each response
(header + body) delivered to clients **and** bandwidth from Fastly to your origins. With
`billable_units=true`, `usage_by_month` returns bandwidth already converted to GB and requests
already divided by 10,000, so it lines up with your invoice. For a rough GB figure from a raw
`bandwidth` byte count, divide by `1e9` (decimal GB), never `2^30`. Details:
<https://docs.fastly.com/products/how-we-calculate-your-delivery-bill>.

## Region codes

`GET /stats/regions` returns the authoritative live list:

```json
{ "status": "success", "meta": {}, "msg": null,
  "data": ["africa_std","anzac","asia","asia_india","asia_southkorea","europe","mexico","southamerica_std","usa"] }
```

Pass any of these as `region=`. Run the endpoint (or `fastly stats regions`) rather than
hardcoding — Fastly adds regions over time.

## POP catalog — `GET /datacenters`

The authoritative POP list: code → name, region, group, billing region, coordinates, and **the POP's
shield name** (the string you put in a backend's `shield` setting). Takes no parameters and returns a
flat array — 179 POPs at the time of writing.

```bash
curl -sS -H "Fastly-Key: $(fastly auth token --quiet)" "https://api.fastly.com/datacenters" \
  | jq -r '.[] | [.code, .region, .stats_region, (.shield // "-")] | @tsv'
```

```json
{
  "code": "AMS", "name": "Amsterdam", "group": "Europe",
  "region": "EU-Central", "stats_region": "europe", "billing_region": "Europe",
  "coordinates": { "x": 0, "y": 0, "latitude": 52.308613, "longitude": 4.763889 },
  "shield": "amsterdam-nl"
}
```

`fastly pops` prints the same data (`CODE`, `GROUP`, `SHIELD` columns) but omits `region` and
`stats_region` — use the API when you need those.

### Three different groupings, easily confused

Each POP carries **four** independent taxonomies. Filtering by the wrong one is a silent scope error.

| Field | Values | What it is for |
| --- | --- | --- |
| `region` | `US-East`, `EU-Central`, `Asia-South`, `North-America`, … (18 values) | POP-topology label. **Not accepted by `region=`.** |
| `stats_region` | `usa`, `europe`, `asia`, `anzac`, … (10 values) | The stats/billing grouping — **this is what `region=` takes**. |
| `group` | `United States`, `Europe`, `India`, `Asia/Pacific`, … (7 values) | Coarse UI/reporting grouping. |
| `billing_region` | `North America`, `Europe`, `Australia`, … | Invoice grouping. |

**`region` ≠ `stats_region`.** The `region` values are a many-to-one input to `stats_region`, and the
collapse loses information you may be trying to query:

```text
US-East, US-West, US-Central, North-America  ->  stats_region = usa
EU-West, EU-Central, EU-East                 ->  stats_region = europe
SA-East, SA-North, SA-South, SA-West         ->  stats_region = southamerica_std
Asia                                         ->  asia, asia_southkorea
```

**Trap: `North-America` excludes every US POP.** Read casually the name implies the opposite. It
contains exactly four POPs, all Canadian, and every US POP lives in `US-East`/`US-West`/`US-Central`:

```text
YYC  Calgary    region=North-America  stats_region=usa  group=United States  shield=-
YUL  Montreal   region=North-America  stats_region=usa  group=United States  shield=yul-montreal-ca
YYZ  Toronto    region=North-America  stats_region=usa  group=United States  shield=yyz-on-ca
YVR  Vancouver  region=North-America  stats_region=usa  group=United States  shield=-
```

**Consequence: region-level stats cannot isolate Canada.** Canadian POPs report `stats_region = usa`
and `group = United States`, so `region=usa` lumps them in with US traffic. To scope to Canada, filter
by POP: `datacenter=YYZ,YUL,YVR,YYC`. The same reasoning applies to any country whose POPs share a
`stats_region` with a larger neighbour — derive the POP list from `/datacenters`, don't assume the
region name means what it says.

### Reading the `shield` key

`shield` is **absent** on POPs not offered as shields (59 of 179 carry it; none carry an explicit
`null`), so test with `has("shield")` or default it — `.shield // "-"`, not `.shield == null`.

Caveat from practice: a POP can be **missing** `shield` in this public list yet still be in
production use as a shield. Treat its absence as "verify with your account team", not "invalid".

## Legacy summary endpoint

`GET /service/{service_id}/stats/summary` returns an older per-POP summary. Params: `start_time`
and `end_time` (integer epoch), or a `month`+`year` pair. It is superseded by the endpoints
above — prefer `/stats/service/{id}` for anything new; the field names mirror the catalog in
[fields.md](fields.md).

---
name: fastly-stats
description: "Use when working with Fastly traffic metrics, analytics, or usage data: retrieving cache hit ratio, bandwidth, request counts, error and status-code rates, edge-vs-origin traffic, real-time requests-per-second, origin latency, per-domain traffic, or billing/usage totals. Covers both the Fastly CLI `fastly stats` commands and the raw Historical Stats, Real-Time analytics, and Origin/Domain Inspector HTTP APIs on api.fastly.com and rt.fastly.com, documenting exact endpoints, query parameters, and response schemas. Use it for any task that needs numbers about how a Fastly service is performing or how much it is being used, whether via CLI, curl, or a direct HTTP integration, including bare requests to check Fastly 'stats', 'metrics', 'analytics', 'traffic', or 'usage' that do not name a specific endpoint."
---

# Fastly Stats & Metrics

Get to Fastly traffic/usage numbers fast — via the `fastly` CLI or by building raw HTTP
requests for `curl` or a direct integration. This skill documents every stats endpoint, its
parameters, and its response shape inline so you rarely need to open Fastly's docs.

## Trigger and scope

Trigger on: cache hit ratio, bandwidth/data-transfer, request counts, hits/misses/passes,
status-code or error rates (`status_4xx`/`status_5xx`), edge vs origin traffic, origin
offload, real-time requests-per-second, origin latency/health (Origin Inspector), per-domain
traffic (Domain Inspector), account usage/billing totals, `api.fastly.com/stats`,
`rt.fastly.com`, or any request phrased as "stats / metrics / analytics / traffic / usage" for
a Fastly service.

Do NOT use for: creating or configuring services, backends, VCL, or WAF (use `fastly-cli` /
`fastly`); streaming raw request logs or analyzing log content (stats are pre-aggregated
counters, not log lines); NGWAF request-level security events (use `fastly-ngwaf`). For general
`fastly stats` CLI ergonomics this skill is authoritative; `fastly-cli/references/stats.md` has a
shorter CLI-only quick reference.

## The spine: two hosts, three response shapes

Almost every mistake with Fastly stats comes from mixing these up. Internalize this first.

**Two hosts (all requests are `GET` with `Fastly-Key: <token>`):**

- `https://api.fastly.com` — all **historical** endpoints (aggregated over past time windows).
- `https://rt.fastly.com` — all **real-time** endpoints (per-second, live, long-polled).

**Three response shapes:**

| Shape | Endpoints | Envelope | Time params | Pagination |
| --- | --- | --- | --- | --- |
| **Classic historical** | `/stats*` | `{status, meta, msg, data}`, `data` is a flat wide row per period | `from`/`to`/`by` | none |
| **Inspector** (Origin/Domain historical) | `/metrics/{origins,domains}/services/{id}` | `{status, meta, data}`, `data[].dimensions` + `data[].values[]` (sparse) | `start`/`end`/`downsample` | cursor (`meta.next_cursor`) |
| **Real-time** | `/v1/...` on `rt.fastly.com` | `{Data:[{recorded, aggregated, datacenter}], Timestamp, AggregateDelay}` | poll `ts/{timestamp}` | chain `Timestamp` |

Note the naming split: classic historical uses `from`/`to`/`by`; Inspector uses
`start`/`end`/`downsample`. Same idea, different words — the API rejects the wrong one.

One worked call per shape:

```bash
KEY="Fastly-Key: $(fastly auth token)"   # see Authentication below

# Classic historical — one service, by day
curl -sS -H "$KEY" \
  "https://api.fastly.com/stats/service/$SID?from=yesterday&by=day"

# Inspector — domain traffic grouped by domain, hourly
curl -sS -H "$KEY" \
  "https://api.fastly.com/metrics/domains/services/$SID?start=2026-07-01T00:00:00Z&end=2026-07-02T00:00:00Z&downsample=hour&group_by=domain"

# Real-time — start at 0, then chain the returned Timestamp
curl -sS -H "$KEY" "https://rt.fastly.com/v1/channel/$SID/ts/0"
```

Full endpoint/parameter/field detail lives in the references:

| Topic | File | Use when… |
| --- | --- | --- |
| Historical Stats API | [references/historical-stats-api.md](references/historical-stats-api.md) | Aggregated stats, usage/billing, regions — `/stats*` on `api.fastly.com` |
| Origin & Domain Inspector | [references/inspector-api.md](references/inspector-api.md) | Per-origin or per-domain metrics, latency, `group_by`, cursor pagination |
| Real-Time analytics API | [references/realtime-api.md](references/realtime-api.md) | Live per-second data, poll loops, `rt.fastly.com` |
| Measurement field catalog | [references/fields.md](references/fields.md) | Looking up what a metric name means or which API exposes it |
| Debugging | [references/debugging.md](references/debugging.md) | 401/403, empty data, inspector-not-enabled, NDJSON, stale Timestamp |

## Authentication

Every raw API call needs the header `Fastly-Key: <API_TOKEN>`. The CLI reads `--token` or the
`FASTLY_API_TOKEN` environment variable. Historical stats need a token with read access to the
services; usage/billing endpoints need account-level read access.

Feed a token to `curl` without leaking it into the conversation. `fastly auth token` prints the
active token only to a pipe/substitution (it refuses a TTY), which is exactly what you want:

```bash
curl -sS -H "Fastly-Key: $(fastly auth token)" "https://api.fastly.com/stats/regions"
```

Token-safety rules (they exist because agent transcripts are logged and often shared):

- Never run `fastly auth show --reveal` bare — it prints the raw token into the transcript. If
  you need a specific stored token by name, capture it inside a substitution:
  `TOKEN=$(fastly auth show TOKEN_NAME --reveal --quiet | awk '/^Token:/ {print $2}')`.
- Omit `curl -v` on authenticated calls — verbose mode echoes the `Fastly-Key` header.
- Never `echo` the token or paste it into a message. Prefer `$(fastly auth token)` inline.

## Choose the right API

Pick the row that matches the question, then jump to the linked reference.

| You need… | Host + endpoint | CLI |
| --- | --- | --- |
| One service's traffic over a past window | `api` `GET /stats/service/{id}` | `fastly stats historical -s ID` |
| One field only (e.g. just `bandwidth`) | `api` `GET /stats/service/{id}/field/{field}` | `fastly stats historical -s ID --field bandwidth` |
| All services, one row of totals per period | `api` `GET /stats/aggregate` | `fastly stats aggregate` |
| All services, split out per service | `api` `GET /stats` (`services=` optional) | (loop the CLI per service) |
| Account usage/billing totals | `api` `GET /stats/usage` | `fastly stats usage` |
| Usage broken down per service | `api` `GET /stats/usage_by_service` | `fastly stats usage --by-service` |
| Month-to-date billable usage | `api` `GET /stats/usage_by_month` | (API only) |
| Valid region codes | `api` `GET /stats/regions` | `fastly stats regions` |
| Per-origin metrics / origin latency | `api` `GET /metrics/origins/services/{id}` | `fastly stats origin-inspector -s ID` |
| Per-domain metrics | `api` `GET /metrics/domains/services/{id}` | `fastly stats domain-inspector -s ID` |
| Live per-second service data | `rt` `GET /v1/channel/{id}/ts/{ts}` | `fastly stats realtime -s ID` |
| Live per-second per-origin data | `rt` `GET /v1/origins/{id}/ts/{ts}` | (API only) |
| Live per-second per-domain data | `rt` `GET /v1/domains/{id}/ts/{ts}` | (API only) |

`api` = `https://api.fastly.com`, `rt` = `https://rt.fastly.com`.

## Fastly CLI quick reference

The CLI is the fastest path for interactive/one-off queries; use raw URLs for integrations or
when you need endpoints the CLI does not expose (e.g. `usage_by_month`, real-time origin/domain).

`fastly stats <subcommand> [flags]`. All subcommands accept `--json`, `--token`, and the global
flags. Service-scoped subcommands take `--service-id`/`-s` (falls back to `FASTLY_SERVICE_ID`
then `fastly.toml`) or `--service-name`.

| Subcommand | Scope | Key flags |
| --- | --- | --- |
| `historical` | service | `--from`, `--to`, `--by minute\|hour\|day`, `--region`, `--field` |
| `aggregate` | account | `--from`, `--to`, `--by`, `--region` |
| `usage` | account | `--from`, `--to`, `--by`, `--region`, `--by-service` |
| `regions` | account | (none) |
| `realtime` | service | (streams; `--json`) — no time flags |
| `domain-inspector` | service | `--from`, `--to`, `--downsample`, `--metric`, `--domain`, `--datacenter`, `--region`, `--group-by`, `--limit`, `--cursor` |
| `origin-inspector` | service | `--from`, `--to`, `--downsample`, `--metric`, `--host`, `--datacenter`, `--region`, `--group-by`, `--limit`, `--cursor` |

Two flag gotchas that waste the most time:

- The **inspector** subcommands use `--downsample` (not `--by`) and `--metric` (repeatable, max
  10; not `--field`). They also add `--group-by`, `--limit`, `--cursor`, and `--domain`/`--host`
  filters that the classic subcommands do not have. Mixing the two vocabularies fails.
- **`--json` emits NDJSON**, not a JSON array: one JSON object per line, no wrapping envelope.
  Slurp with `jq -s` before aggregating:

```bash
# Sum bandwidth across days — note jq -s to collect the newline-delimited objects
fastly stats historical -s "$SID" --by day --from "7 days ago" --json \
  | jq -s '[.[].bandwidth] | add'
```

## Building raw request URLs

When you are not using the CLI (a script, another language, or handing a URL to someone), build
the URL from three parts: host + path + query string. The references give the exact path and
query params per endpoint; the pattern is always:

```bash
# Historical: api.fastly.com, from/to/by, flat {status,meta,msg,data}
curl -sS -H "Fastly-Key: $(fastly auth token)" \
  "https://api.fastly.com/stats/service/$SID?from=2026-07-01T00:00:00Z&to=2026-07-08T00:00:00Z&by=day&region=europe"

# Inspector: api.fastly.com, start/end/downsample/metric/group_by, cursor paginated
curl -sS -H "Fastly-Key: $(fastly auth token)" \
  "https://api.fastly.com/metrics/origins/services/$SID?start=2026-07-01T00:00:00Z&end=2026-07-02T00:00:00Z&downsample=hour&metric=responses,status_5xx&group_by=host"

# Real-time: rt.fastly.com, poll ts/{n}, chain the returned Timestamp
curl -sS -H "Fastly-Key: $(fastly auth token)" "https://rt.fastly.com/v1/channel/$SID/ts/0"
```

`from`/`to`/`start`/`end` accept a Unix timestamp; the classic `/stats*` endpoints also accept
Chronic-style relative strings like `yesterday` or `two weeks ago`. URL-encode any spaces in
relative strings (`from=two%20weeks%20ago`).

## Common workflows

**Cache hit ratio (last 24h, one service).** `hit_ratio` is already a 0–1 ratio:

```bash
curl -sS -H "Fastly-Key: $(fastly auth token)" \
  "https://api.fastly.com/stats/service/$SID?from=yesterday&by=hour" \
  | jq '.data[] | {start_time, hit_ratio}'
```

**5xx error rate (last hour).** Classic historical exposes `status_5xx` and `requests`:

```bash
fastly stats historical -s "$SID" --by hour --from "1 hour ago" --json \
  | jq -s '.[-1] | {requests, status_5xx, pct: (.status_5xx / .requests * 100)}'
```

**Bandwidth across all services (last month).** The CLI has no cross-service rollup; loop
`fastly service list`. Zero-traffic services still appear in the list but may be omitted by the
stats response — always drive the loop from the service list, defaulting missing sums to 0:

```bash
fastly service list --json | jq -r '.[] | "\(.ServiceID)|\(.Name)"' | while IFS='|' read -r id name; do
  bw=$(fastly stats historical -s "$id" --by day --from "30 days ago" --json \
    | jq -s '[.[].bandwidth] | add // 0')
  printf '%s\t%s\n' "$bw" "$name"
done | sort -rn
```

**Real-time requests-per-second.** Poll `ts/0` once, then feed the returned `Timestamp` back in
a loop; each response yields one entry per elapsed second. Full loop in
[references/realtime-api.md](references/realtime-api.md).

**Per-domain traffic with pagination.** Inspector responses cap at `limit` rows (max 200) and
return `meta.next_cursor`; pass it back as `cursor` until it is null. See
[references/inspector-api.md](references/inspector-api.md).

## Limits and cautions

- **Origin Inspector and Domain Inspector are paid add-ons** and must be enabled per service. If
  they are not, the endpoints return an error rather than empty data — see
  [references/debugging.md](references/debugging.md).
- **Real-time: one outstanding request at a time.** The endpoint long-polls and is cached with a
  1-second TTL; sequential polling never hits limits, but parallel polling can be throttled.
- **Zero-traffic services may be absent from stats responses.** Enumerate services from
  `fastly service list`, not from a stats response, when you need full coverage.
- **Historical data lags slightly and is subject to late aggregation.** The most recent bucket
  can grow for a few minutes after its period ends; prefer real-time for up-to-the-second numbers.

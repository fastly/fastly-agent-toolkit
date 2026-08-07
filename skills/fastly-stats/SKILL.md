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

> **Never infer a time base from an endpoint name.** `ts/h` is the last **120 seconds**, not an hour
> — reading the `h` as "hour" inflates every per-unit-time figure by 30×. Derive the window from the
> payload's own `recorded` timestamps and **print it beside every absolute figure**. Prefer ratios and
> same-window comparisons over extrapolated rates: they survive a misjudged window, rates don't.
>
> **Check the aggregation shape before you sum.** Ratio fields (`hit_ratio`, `edge_hit_ratio`,
> `origin_offload`) are **gauges** — summing them across samples yields a plausible-looking but
> meaningless number. Recompute from the underlying counters:
> [Aggregation shape](references/fields.md#aggregation-shape-counter-vs-gauge-vs-histogram).

One worked call per shape:

```bash
KEY="Fastly-Key: $(fastly auth token --quiet)"   # see Authentication below

# Classic historical — one service, by day
curl -sS -H "$KEY" \
  "https://api.fastly.com/stats/service/$SID?from=1%20day%20ago&by=day"

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
| Measurement field catalog | [references/fields.md](references/fields.md) | Looking up what a metric name means, its aggregation shape, or shield/tier field directions |
| Change verification method | [references/verification-method.md](references/verification-method.md) | Proving a config change did what you intended — baselines, controls, σ, cross-checks |
| Debugging | [references/debugging.md](references/debugging.md) | 401/403, empty data, inspector-not-enabled, NDJSON, stale Timestamp, silently wrong scope |

## Authentication

Every raw API call needs the header `Fastly-Key: <API_TOKEN>`. The CLI reads `--token` or the
`FASTLY_API_TOKEN` environment variable. Historical stats need a token with read access to the
services; usage/billing endpoints need account-level read access.

Feed a token to `curl` without leaking it into the conversation. `fastly auth token` prints the
active token only to a pipe/substitution (it refuses a TTY), which is exactly what you want — but
**always add `--quiet`**:

```bash
curl -sS -H "Fastly-Key: $(fastly auth token --quiet)" "https://api.fastly.com/stats/regions"
```

**`--quiet` is not optional.** Without it, a pending CLI upgrade appends an "A new version…" notice
to stdout, contaminating the header and causing `curl: (43)` or a spurious HTTP 401 even though
`fastly whoami` works. Intermittent, so it breaks scripts that worked yesterday — see
[debugging.md](references/debugging.md#401-unauthorized).

Token-safety rules (they exist because agent transcripts are logged and often shared):

- Never run `fastly auth show --reveal` bare — it prints the raw token into the transcript. If
  you need a specific stored token by name, capture it inside a substitution:
  `TOKEN=$(fastly auth show TOKEN_NAME --reveal --quiet | awk '/^Token:/ {print $2}')`.
- Omit `curl -v` on authenticated calls — verbose mode echoes the `Fastly-Key` header.
- Never `echo` the token or paste it into a message. Prefer `$(fastly auth token --quiet)` inline.

## Time and units conventions

Two things trip up otherwise-correct queries.

**Time — default to UTC.** All endpoints interpret Unix timestamps as UTC, and ISO-8601 values
should carry a `Z`/offset. When you *format* results, prefer UTC unless the user asked for local
time: use `date -u`, and in `jq` use `strftime` (UTC) rather than `strflocaltime` (machine-local).
Reporting local time silently when the user didn't ask for it makes numbers hard to compare across
machines and regions.

**Units — raw bytes are not your bill.** `bandwidth` and every `*_bytes` field are **raw bytes**
(response header + body). Two consequences:

- To show GB/TB, use **decimal SI units** the way Fastly bills: 1 GB = 10^9 bytes, 1 TB = 10^12
  bytes (`bytes / 1e9`), **not** binary GiB (`2^30`). Mixing the two is a common reporting error.
- Raw `bandwidth` is edge traffic, not billable usage. Billing counts delivery to clients **and**
  traffic to origins, presents requests in units of 10,000, and reports bandwidth in decimal GB.
  For anything billing-related use the usage endpoints (`fastly stats usage` /
  `GET /stats/usage*`) with `billable_units=true`, which does that conversion for you. See
  [references/historical-stats-api.md](references/historical-stats-api.md#usage--billing-endpoints)
  and Fastly's <https://docs.fastly.com/products/how-we-calculate-your-delivery-bill>.

**Latency/timing lives in three places**, answering different questions — pick by which side you're
investigating:

- *Edge* — `hits_time`, `miss_time`, `pass_time` (aggregate seconds Fastly spent serving requests).
- *Origin* — Origin Inspector's per-origin latency histograms (~0 ms to 60 s+ buckets).
- *Per-POP* — `miss_histogram`, a `{millisecond_bucket: count}` dict. Often the **only** per-POP
  latency source, since `miss_time` is frequently unpopulated per POP.

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
| POP catalog: code → region, shield name | `api` `GET /datacenters` | `fastly pops` |
| One POP's history | `api` `GET /stats/service/{id}?datacenter=SJC` | (API only — no `--datacenter`) |
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
| `historical` | service | `--from`, `--to`, `--by minute\|hour\|day`, `--region`, `--field` (**no `--datacenter`** — use the API for per-POP) |
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

Build from host + path + query string — see the worked call per shape above, and the references for
exact params. `from`/`to`/`start`/`end` accept a Unix timestamp; the classic `/stats*` endpoints also
accept Chronic-style relative strings (`yesterday`, `two weeks ago`), URL-encoding any spaces
(`from=two%20weeks%20ago`).

**`from=yesterday` does not mean midnight** — it resolves to 12:00:00 UTC of the previous day,
silently excluding that morning (`1 day ago` is a correct −24h). **Always read back
`meta.from`/`meta.to`** to see the window the server used, and prefer computed timestamps when
scripting. See [debugging.md](references/debugging.md#a-relative-window-silently-covers-the-wrong-hours).

## Common workflows

**Cache hit ratio (last 24h, one service).** `hit_ratio` is already a 0–1 ratio. Use `1 day ago`, not
`yesterday` — the latter starts at noon:

```bash
curl -sS -H "Fastly-Key: $(fastly auth token --quiet)" \
  "https://api.fastly.com/stats/service/$SID?from=1%20day%20ago&by=hour" \
  | jq '.data[] | {start_time, hit_ratio}'
```

For a **window** hit ratio rather than per-bucket values, recompute from the `hits`/`miss` counters —
do not average the per-bucket `hit_ratio` values. Copy-paste snippet in
[fields.md](references/fields.md#aggregation-shape-counter-vs-gauge-vs-histogram).

**5xx error rate (last hour).** Classic historical exposes `status_5xx` and `requests`:

```bash
fastly stats historical -s "$SID" --by hour --from "1 hour ago" --json \
  | jq -s '.[-1] | {requests, status_5xx, pct: (.status_5xx / .requests * 100)}'
```

**Bandwidth across all services (last month).** The CLI has no cross-service rollup. Drive the loop
from `fastly service list`, not from a stats response — zero-traffic services are omitted from stats
but must still be counted (hence `add // 0`). Report decimal GB (`/1e9`), not GiB:

```bash
fastly service list --json | jq -r '.[] | "\(.ServiceID)|\(.Name)"' | while IFS='|' read -r id name; do
  gb=$(fastly stats historical -s "$id" --by day --from "30 days ago" --json \
        | jq -s '([.[].bandwidth] | add // 0) / 1e9')
  printf '%.3f GB\t%s\n' "$gb" "$name"     # 3dp: a low-traffic service is not 0
done | sort -rn
```

This is raw edge `bandwidth`. If the goal is the **bill**, query billable usage instead:
`fastly stats usage --by-service` or `GET /stats/usage_by_service` (add `billable_units=true` on
`usage_by_month`) — bandwidth already in GB, requests already in units of 10,000.

**Real-time requests-per-second.** Quickest path is `fastly stats realtime -s ID --json` (NDJSON, one
second per line; chains `Timestamp` for you). For a per-POP breakdown or derived error rate, poll the
raw endpoint — or grab the last 120 s in one call with `ts/h`. See
[references/realtime-api.md](references/realtime-api.md).

**Per-domain traffic with pagination.** Inspector caps at `limit` rows (max 200) and returns
`meta.next_cursor`; feed it back as `cursor` until null.
See [references/inspector-api.md](references/inspector-api.md).

## Pinpoint issues with POP-level (datacenter) data

Default to pulling the **per-POP breakdown** when diagnosing, not just the aggregate. A
service-wide number that looks healthy routinely hides a single POP erroring or a regional latency
spike — the aggregate averages it away. Every source exposes POP-level granularity:

- Real-time: the `datacenter` map in each record (metrics keyed by POP code).
- Historical stats: `datacenter=SJC,LHR` filters — a **real filter**, so per-POP *history* exists too,
  at `by=minute|hour|day`. Never send `region=` alongside it: `region` silently wins and you get
  whole-region numbers with `meta.datacenter: null`. Assert `meta` echoes your filter.
- Inspector: `group_by=datacenter` (or `region`) alongside `host`/`domain`.

So when the question is "why is X bad", reach for POP granularity first — it turns "5xx are up"
into "5xx are up *at LHR*", which is usually the actual lead.

**Capture a per-POP baseline *before* changing anything.** `by=minute` is retained only ~1 day and
real-time only 120 seconds, so fine-grained "before" data ages out. Make the snapshot step 1 of any
change verification — see
[debugging.md](references/debugging.md#i-changed-something-and-cannot-recover-the-pre-change-per-pop-state).

**Watch for Shield POPs.** A shield POP's `datacenter` entry carries edge-to-shield traffic, not
client traffic, so it reads very differently from an edge POP. Identify candidates via `fastly pops`
(`SHIELD` column) or `GET /datacenters` plus the backend `shield` settings, and call them out when
presenting per-POP numbers.

**To read the tier topology, compare `shield_fetches` against `origin_fetches` per POP** — nothing
else says whether a POP forwards upstream to another tier (`shield_fetches` dominant) or terminates at
origin (`origin_fetches` dominant). Three traps produce confidently wrong answers here, all documented
with worked live numbers in the references:

- **`shield_resp_body_bytes` vs `shield_fetch_resp_body_bytes`** differ by *direction* — bytes served
  **as** a shield vs received **from** one. Conflating them yields a negative byte offload.
  ([fields.md](references/fields.md#shield--tier-fields))
- **`region` (`US-East`, `North-America`) is not `stats_region` (`usa`, `europe`)**, and `region=`
  takes the latter. `North-America` holds only four Canadian POPs and **no US POPs**, so region-level
  stats cannot isolate Canada — filter by POP code.
  ([historical-stats-api.md](references/historical-stats-api.md#three-different-groupings-easily-confused))
- **Verifying a change?** Baselines, control POPs, σ, and cross-checks are in
  [verification-method.md](references/verification-method.md).

## Limits and cautions

- **Origin/Domain Inspector are paid add-ons**, enabled per service; if not entitled the endpoints
  error rather than return empty data ([debugging.md](references/debugging.md)).
- **Real-time: one outstanding request at a time.** It long-polls with a 1-second TTL — sequential
  polling is fine, parallel polling can be throttled.
- **Zero-traffic services may be absent from stats responses.** Enumerate from
  `fastly service list` when you need full coverage.
- **Historical data lags.** The most recent bucket keeps growing for a few minutes after its period
  ends — don't read the final in-progress bucket; use real-time for up-to-the-second numbers.
- **A per-POP baseline is unrecoverable after the fact.** `by=minute` is retained ~1 day, real-time
  120 s. Snapshot before you change anything.

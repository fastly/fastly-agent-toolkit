---
name: fastly-stats
description: "Fastly traffic numbers: cache hit ratio, bandwidth, request counts, status-code and error rates, edge vs origin traffic, real-time requests-per-second, origin latency, per-domain traffic, account usage and billing totals. Owns the `fastly stats` CLI commands and the Historical Stats, Real-Time and Origin/Domain Inspector HTTP APIs. Use for any question that needs a number about how a Fastly service is performing or how much it is being used."
---

# Fastly stats

Prefer the `fastly` CLI. Drop to `curl` only for the five things the CLI cannot do, listed under
Raw API below.

## Rules that decide whether the answer is right

1. Bytes to GB is decimal SI: `bytes / 1e9`. TB is `/ 1e12`. Never `2^30`. Fastly bills in
   decimal units, so a GiB figure is wrong by 7.4% and still reads as a plausible number.
2. For a calendar window, pass explicit UTC boundaries: `--from 2026-07-01T00:00:00Z
   --to 2026-08-01T00:00:00Z` returns every day bucket in July. A bucket is emitted only when the
   whole period falls inside the window, and a relative window opens and closes mid-bucket, so
   `--from "N days ago" --by day` returns N-1 buckets, never N, and `"1 day ago"` returns none at
   all. Relative strings are safe at `--by hour`, not at `--by day`.
3. On the raw API, `from=yesterday` means 12:00:00 UTC, not midnight, and `from=today` means now.
   `N days ago` / `N hours ago` are exact offsets. Read back `meta.from` / `meta.to`.
4. `hit_ratio`, `edge_hit_ratio` and `origin_offload` are gauges. Never sum or average them
   across buckets. Recompute from the summed counters: `hits / (hits + miss)`.
5. `ts/h` on `rt.fastly.com` is the last 120 seconds, not an hour. Derive the window from the
   payload's own `recorded` timestamps and print it beside any absolute rate.
6. `fastly stats ... --json` emits NDJSON, one object per line, no array. Slurp with `jq -s`
   before aggregating. The raw HTTP API returns a normal array in `data`.
7. Stats responses omit services with zero traffic in the window. Enumerate from
   `fastly service list --json` and default sums with `add // 0`.
8. Do not read the newest bucket. Historical aggregation keeps growing for a few minutes after
   a period closes.
9. On a Compute service the traffic lands in `compute_requests` and `requests` stays 0. Summing
   `requests` alone reports zero traffic for a service that is serving fine. Check both.

## Pick the command

| You need                             | Command                                                                   |
| ------------------------------------ | ------------------------------------------------------------------------- |
| One service over a past window       | `fastly stats historical -s ID --from T --to T --by day`                   |
| One field only                       | `fastly stats historical -s ID --field bandwidth`                          |
| All services, one row of totals      | `fastly stats aggregate --from T --to T --by day`                          |
| Account usage totals, by region      | `fastly stats usage --from T --to T --json`                                |
| Account usage split per service      | `fastly stats usage --by-service --json`                                   |
| Valid region codes                   | `fastly stats regions`                                                     |
| POP codes and shield names           | `fastly pops`                                                              |
| Is Inspector enabled on this service | `fastly products -s ID`                                                    |
| Per-origin metrics, origin latency   | `fastly stats origin-inspector -s ID --downsample hour --metric responses` |
| Per-domain metrics                   | `fastly stats domain-inspector -s ID --downsample hour --group-by domain`  |
| Live per-second data                 | `fastly stats realtime -s ID --json`                                       |

`historical`, `aggregate` and `usage` take `--by minute|hour|day` and `--field`. The two
inspectors take `--downsample` and `--metric` (repeatable, max 10) instead, plus `--group-by`,
`--datacenter`, `--limit`, `--cursor`, and `--domain` or `--host`. Mixing the two vocabularies
fails with a usage error. `historical` has no `--datacenter`; `realtime` takes no filters at all,
and `regions` takes no flags whatsoever, not even `--json`. Full flag matrix:
`fastly-cli/references/stats.md`.

Service-scoped subcommands take `-s` / `--service-id` or `--service-name`, falling back to
`FASTLY_SERVICE_ID` then `fastly.toml`.

## Worked answers

Cache hit ratio over a whole month, recomputed from counters rather than averaged:

```bash
fastly stats historical -s "$SID" --by day \
  --from 2026-07-01T00:00:00Z --to 2026-08-01T00:00:00Z --json \
  | jq -s '(map(.hits)|add // 0) as $h | (map(.miss)|add // 0) as $m
           | {hits:$h, miss:$m, hit_ratio: (if $h+$m > 0 then $h/($h+$m) else null end)}'
```

5xx count and its share of requests over a month:

```bash
fastly stats historical -s "$SID" --by day \
  --from 2026-07-01T00:00:00Z --to 2026-08-01T00:00:00Z --json \
  | jq -s '{requests: (map((.requests // 0) + (.compute_requests // 0))|add // 0),
            status_5xx: (map(.status_5xx)|add // 0)}
           | . + {pct: (if .requests > 0 then .status_5xx/.requests*100 else null end)}'
```

Bandwidth in GB per service, ranked. Drive the loop from the service list, not from a stats
response, so zero-traffic services are still counted:

```bash
fastly service list --json | jq -r '.[] | "\(.ServiceID)|\(.Name)"' | while IFS='|' read -r id name; do
  gb=$(fastly stats historical -s "$id" --by day \
        --from 2026-07-01T00:00:00Z --to 2026-08-01T00:00:00Z --json \
        | jq -s '([.[].bandwidth] | add // 0) / 1e9')
  printf '%.3f\t%s\n' "$gb" "$name"
done | sort -rn
```

Account-wide totals for a month. `fastly stats usage --json` returns one object keyed by region,
so sum the leaves:

```bash
fastly stats usage --from 2026-07-01T00:00:00Z --to 2026-08-01T00:00:00Z --json \
  | jq '{bandwidth_gb: (([.[].bandwidth]|add)/1e9), requests: ([.[].requests]|add)}'
```

That is raw edge bandwidth. For the invoice figure use `GET /stats/usage_by_month` with
`billable_units=true`: it counts delivery to clients plus traffic to origins, returns bandwidth
already in GB and requests already in units of 10,000, so a `requests` of `1.4452` means 14,452.

Live request rate with the window it is averaged over. `fastly stats realtime --json` streams one
flat object per second, `{recorded, aggregated, datacenter}`, with no `Data` wrapper and no
`Timestamp`; that wrapper exists only on the raw `rt.fastly.com` payload. Take a bounded sample
and divide by the span you actually observed:

```bash
fastly stats realtime -s "$SID" --json | head -20 \
  | jq -s '{samples: length,
            span_s: (([.[].recorded]|max) - ([.[].recorded]|min) + 1),
            requests: (map((.aggregated.requests // 0) + (.aggregated.compute_requests // 0))|add)}
           | . + {rps: (.requests / .span_s)}'
```

Report the span next to the rate. Ratios and same-window comparisons survive a misjudged window;
extrapolated rates do not.

## Raw API

Five things the CLI cannot do. Everything else has a CLI command above.

| Need                                 | Request                                                                          |
| ------------------------------------ | -------------------------------------------------------------------------------- |
| Per-POP history on classic stats     | `GET api.fastly.com/stats/service/{id}?datacenter=SJC,LHR&by=day`                 |
| Month-to-date billable usage         | `GET api.fastly.com/stats/usage_by_month?year=2026&month=07&billable_units=true`  |
| POP `region` / `stats_region` fields | `GET api.fastly.com/datacenters`                                                  |
| Live per-origin or per-domain data   | `GET rt.fastly.com/v1/{origins,domains}/{id}/ts/0`                                |
| 120 s per-POP snapshot in one call   | `GET rt.fastly.com/v1/channel/{id}/ts/h`                                          |

`datacenter=` is missing from the CLI's SDK input type, not just from its flags, so no flag
combination reaches per-POP history. Account-wide `/stats` and `/stats/field/{field}` also need
`curl`, because `stats historical` always resolves a service ID and errors without one.

Auth is the header `Fastly-Key: <token>`. Feed it from the CLI and keep `--quiet`: without it a
pending upgrade notice lands inside the header value and produces `curl: (43)` or a spurious 401.

```bash
curl -sS -H "Fastly-Key: $(fastly auth token --quiet)" \
  "https://api.fastly.com/stats/service/$SID?from=2026-07-01T00:00:00Z&to=2026-08-01T00:00:00Z&by=day&datacenter=SJC"
```

Never run `fastly auth show --reveal` bare and never pass `-v` on an authenticated call; both
print the token into the transcript.

Endpoint paths, parameters and response shapes: [references/api.md](references/api.md).
Field names and aggregation shape: [references/fields.md](references/fields.md).
Errors, empty data and wrong-scope symptoms: [references/debugging.md](references/debugging.md).

## Scope traps

- `region=` takes `stats_region` values (`usa`, `europe`), not the `region` values from
  `/datacenters` (`US-East`, `North-America`). Get the live list from `fastly stats regions`.
- Sending `region` and `datacenter` together returns HTTP 200 with the POP filter dropped
  silently: `meta` echoes `region` and omits `datacenter` entirely, and the numbers are
  whole-region. Never send both, and assert `meta` carries the filter you sent.
- POP codes are uppercase. A lowercase or unknown code fails loudly with `invalid datacenter`.
- Origin and Domain Inspector are paid add-ons. When not enabled the endpoints return HTTP 200,
  `"status":"success"` and an empty `data` array, which reads exactly like a service with no
  traffic. Check `fastly products -s ID` before concluding there is nothing to see.
- A shield POP's `datacenter` entry carries edge-to-shield traffic, not client traffic. Identify
  shields from the `SHIELD` column of `fastly pops` and label them separately.
- When diagnosing rather than reporting, pull the per-POP breakdown. A healthy service-wide
  number routinely hides one POP erroring: `datacenter=` on classic stats, `--group-by datacenter`
  on the inspectors, the `datacenter` map in real-time.

## Not this skill

Creating or configuring services, backends, VCL or WAF: `fastly-cli` and `fastly`. Raw request
logs: stats are pre-aggregated counters, not log lines. NGWAF security events: `fastly-ngwaf`.

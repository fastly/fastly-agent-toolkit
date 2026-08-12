# Measurement fields

`all_`, `compute_` and `waf_` are source prefixes, not an Inspector convention. Classic historical
and real-time carry them beside the bare names. A bare name counts VCL delivery only, the `all_`
twin counts every source: that is why `status_5xx` reads 0 on a Compute service while
`all_status_5xx` reads the real count. Inspector takes either form (`metric=responses`,
`metric=all_responses`).

Classic `/stats` carries `all_status_1xx` through `all_status_5xx`, `all_hit_requests`,
`all_miss_requests`, `all_pass_requests`, `all_error_requests`, `all_edge_hit_requests`,
`all_edge_miss_requests`. No `all_requests`, no `all_bandwidth`.

Presence, which decides whether a filter needs a default:

| Field                                                | Present                                                |
| ---------------------------------------------------- | ------------------------------------------------------ |
| `requests`, `compute_requests`, `status_1xx`..`5xx`  | Every row, 0 when the service type cannot produce them |
| `all_status_1xx`..`all_status_5xx`                   | Only when that class saw traffic; always add `// 0`    |
| `compute_resp_status_*`                              | Compute rows only, absent on VCL                       |
| Anything else sparse or zero                         | Omitted rather than returned as 0                      |

To test whether a name is real, ask for it alone:
`GET /stats/service/{id}/field/{name}` returns `{"status":"error","msg":"Unknown field: ..."}`
for a name that does not exist. 200 for `all_status_5xx`, 400 for `all_bandwidth`. Full list:
<https://www.fastly.com/documentation/reference/api/metrics-stats/historical-stats/>

## Aggregation shape

Read this before summing anything. Getting it wrong produces numbers that are silently,
plausibly wrong.

| Agg         | How to combine                                             | Examples                                        |
| ----------- | ---------------------------------------------------------- | ----------------------------------------------- |
| `counter`   | Sum across samples and across POPs                         | `requests`, `hits`, `shield_fetches`, `*_bytes` |
| `gauge`     | Never sum. Recompute from the underlying counters          | `hit_ratio`, `edge_hit_ratio`, `origin_offload` |
| `seconds`   | Sum for a total; divide by the matching counter for a mean | `hits_time`, `miss_time`, `pass_time`           |
| `histogram` | Merge by adding per-bucket counts                          | `miss_histogram`                                |

Ratio fields are floats in `[0,1]` per sample, so summing a series of them yields a number near
the sample count, which reads as a plausible figure rather than an error. Summing `origin_offload`
over 120 real-time samples gives about 120, not a percentage.

Averaging is wrong too for a window figure: a mean of per-second ratios weights a quiet second the
same as a busy one. Sum the numerator and denominator counters and divide once.

```bash
fastly stats historical -s "$SID" --by day \
  --from 2026-07-01T00:00:00Z --to 2026-08-01T00:00:00Z --json \
  | jq -s '(map(.hits)|add // 0) as $h | (map(.miss)|add // 0) as $m
           | {hits:$h, miss:$m, hit_ratio: (if $h+$m > 0 then $h/($h+$m) else null end)}'
```

The `// 0` and the zero guard matter: an empty window otherwise fails with
`null and null cannot be divided`.

`origin_offload` is defined over header plus body bytes, not body alone:
`1 - (origin_fetch_resp_body_bytes + origin_fetch_resp_header_bytes) / (edge_resp_body_bytes + edge_resp_header_bytes)`.

## Traffic and cache

| Field                                           | Agg       | Meaning                                                                      |
| ----------------------------------------------- | --------- | ---------------------------------------------------------------------------- |
| `requests`                                      | counter   | Total client requests. Stays 0 on a Compute service                          |
| `compute_requests`                              | counter   | Client requests to a Compute service. Stays 0 on a VCL service               |
| `hits` / `miss` / `pass`                        | counter   | Cache hits, misses, requests passed to origin                                |
| `hits_time` / `miss_time` / `pass_time`         | seconds   | Aggregate edge processing time                                               |
| `errors`                                        | counter   | Error responses generated                                                    |
| `restarts` / `synth` / `uncacheable`            | counter   | VCL restarts, synthetic responses, uncacheable responses                     |
| `hit_ratio`                                     | gauge     | `hits / (hits + miss)`, in `[0,1]`                                           |
| `edge_requests`                                 | counter   | Requests received acting as an edge; 0 on a pure shield POP                  |
| `edge_hit_requests` / `edge_miss_requests`      | counter   | Of those, hits and misses                                                    |
| `edge_hit_ratio`                                | gauge     | Edge hit ratio, in `[0,1]`                                                   |
| `origin_fetches`                                | counter   | Requests sent to a true origin, the last hop                                 |
| `origin_cache_fetches` / `origin_revalidations` | counter   | Cacheable origin fetches, and conditional ones that revalidated              |
| `origin_offload`                                | gauge     | Fraction of header + body bytes served without reaching origin               |
| `miss_histogram`                                | histogram | `{millisecond_bucket: count}` latency distribution for misses                |
| `request_collapse_usable_count`                 | counter   | Collapsed requests that reused the in-flight fetch; note the `_count` suffix |
| `request_collapse_unusable_count`               | counter   | Collapsed requests that became separate origin fetches                       |

On a Compute service `compute_requests` carries the traffic and `requests` is 0, in historical rows
and real-time `aggregated` alike; add both counters. Status codes arrive as `all_status_4xx` and
`compute_resp_status_4xx`, `status_4xx` at 0. Use `all_status_*`: `compute_resp_status_*` is absent
from VCL rows and fails there the way `status_*` fails on Compute.

`miss_histogram` is often the only per-POP latency source, since `miss_time` is frequently
unpopulated per POP. It is not exposed by `/stats/service/{id}/field/miss_histogram`, which
returns `Unknown field`; read it from a full row or a real-time payload.

## Bytes

All byte fields are counters, so sum them freely.

`bandwidth` (headers plus body, the usual answer for data transferred), `body_size`,
`header_size`, `resp_body_bytes`, `resp_header_bytes`, `req_body_bytes`, `req_header_bytes`,
`bereq_body_bytes`, `bereq_header_bytes`, `edge_resp_body_bytes`, `edge_resp_header_bytes`,
`origin_fetch_resp_body_bytes`, `origin_fetch_resp_header_bytes`, `billed_body_bytes`,
`billed_header_bytes`.

Convert with decimal SI: `/1e9` for GB, `/1e12` for TB. Never `2^30`.

`bandwidth` = client response bytes + upstream request bytes. It reconciles exactly on a VCL
service: `resp_header_bytes` + `resp_body_bytes` + `bereq_header_bytes` + `bereq_body_bytes`, or
equivalently `header_size` + `body_size` + `bereq_header_bytes`. Inbound `req_header_bytes` is not
in it. The origin-bound side is already counted, so the billable total does not exceed `bandwidth`.
What `billable_units=true` changes is in the usage section of api.md.

## Status codes

Class summaries `status_1xx` through `status_5xx`, plus specific counters `status_200`,
`status_204`, `status_206`, `status_301`, `status_302`, `status_304`, `status_400`, `status_401`,
`status_403`, `status_404`, `status_416`, `status_429`, `status_500`, `status_501`, `status_502`,
`status_503`, `status_504`, `status_505`. A class total counts every code in that class, including
ones without a dedicated field.

Every class summary has an `all_` twin, `all_status_1xx` through `all_status_5xx`. Use it unless you
specifically want the VCL-only figure. Per-code counters have no twin (`all_status_503` is
`Unknown field`), so per-code detail on a Compute service comes from `compute_resp_status_503`.

## Shield and tier fields

Each name is relative to the POP whose row you are reading, so the same byte count appears as an
outbound number on one POP and an inbound number on another.

| Field                                                             | Meaning for the POP in this row                          |
| ----------------------------------------------------------------- | -------------------------------------------------------- |
| `shield`                                                          | Requests received because this POP is acting as a shield |
| `shield_hit_requests` / `shield_miss_requests`                    | Of those, served from this tier's cache or fetched       |
| `shield_fetches`                                                  | Requests forwarded to another shield, outbound           |
| `origin_fetches`                                                  | Requests sent to a true origin, outbound and terminal    |
| `shield_resp_body_bytes` / `shield_resp_header_bytes`             | Bytes served as a shield, outbound to an edge            |
| `shield_fetch_resp_body_bytes` / `shield_fetch_resp_header_bytes` | Bytes received when fetching from a shield, inbound      |
| `shield_fetch_body_bytes` / `shield_fetch_header_bytes`           | Bytes of the request sent upstream, not the response     |

Comparing `shield_fetches` against `origin_fetches` is the only way to tell whether a POP forwards
to another tier or terminates at origin. A POP's outbound count is the next tier's inbound count
(`shield_fetches` upstream equals `shield` downstream), so a topology hypothesis makes a
falsifiable numeric prediction.

`shield_resp_body_bytes` and `shield_fetch_resp_body_bytes` differ by direction, not scope.
Conflating them inverts the flow and yields a negative byte offload, which is the only tell. Use
the adjacency as a self-check: a downstream POP's `shield_fetch_resp_body_bytes` must equal the
upstream POP's `shield_resp_body_bytes`.

## Other families

Protocol and TLS: `http2`, `http3`, `tls`, `tls_v10` through `tls_v13`, `ipv6`.

Media and features: `video`, `imgopto`, `imgopto_transforms`, `imgopto_shield`, `logging`,
`log_bytes`, `pci`, `segblock_shield_fetches`, `segblock_origin_fetches`.

Compute: `compute_requests`, `compute_execution_time_ms`, `compute_request_time_ms`,
`compute_request_time_billed_ms`, `compute_ram_used`, `compute_sandboxes`, `compute_bereqs`,
`compute_bereq_errors`, `compute_resp_body_bytes`, `compute_resp_header_bytes`,
`compute_req_header_bytes`.

Security: `bot_requests_total_count`, `bot_challenges_issued`, `bot_challenges_succeeded`,
`bot_challenges_failed`, `ddos_protection_requests_allow_count`,
`ddos_protection_requests_detect_count`, `ngwaf_requests_total_count`,
`ngwaf_requests_blocked_count`, `ngwaf_requests_allowed_count`, `waf_blocked`, `waf_logged`,
`waf_passed`, `attack_req_body_bytes`, `attack_req_header_bytes`, `attack_resp_synth_bytes`.

Real-time only: `fanout_conn_time_ms`, `fanout_recv_publishes`, `fanout_send_publishes`,
`kv_store_class_a_operations`, `kv_store_class_b_operations`.

Origin Inspector adds latency buckets per source prefix, `all_latency_0_to_1ms` through
`all_latency_60000ms`. Summing a source's buckets gives its total responses.

Row identifiers rather than measurements: `start_time` (historical bucket start), `recorded`
(real-time second), `service_id`, `customer_id`, `dimensions` (Inspector labels).

## Types

Counters are non-negative integers. Byte fields are bytes. `*_time` is seconds, `*_time_ms` is
milliseconds. Ratios are floats in `[0,1]`; multiply by 100 for a percentage.

A field that is absent or `null` in a row means "not applicable to this POP's role", not zero:
`edge_hit_requests` is null on a pure shield POP, `origin_offload` is null on a POP with no
client-facing traffic. Do not coerce null to 0 inside a ratio.

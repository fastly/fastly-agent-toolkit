# Measurement Field Catalog

Docs: <https://www.fastly.com/documentation/reference/api/metrics-stats/historical-stats/> (measurements)

What each stats field means and which API exposes it. Use this when a response contains a metric
you don't recognize, or when picking `field=`/`metric=` values.

## Contents

- [How the three APIs name fields](#how-the-three-apis-name-fields)
- [Traffic & cache](#traffic--cache)
- [Bandwidth & bytes](#bandwidth--bytes)
- [Status codes](#status-codes)
- [Protocol & TLS](#protocol--tls)
- [Media & features](#media--features)
- [Compute](#compute)
- [Security (bot, DDoS, NGWAF, WAF)](#security-bot-ddos-ngwaf-waf)
- [Real-time-only counters](#real-time-only-counters)
- [Meta / dimension fields](#meta--dimension-fields)
- [Types and units](#types-and-units)

## How the three APIs name fields

- **Classic historical** (`/stats*`) and **real-time** (`/v1/...`) use the **bare** names below
  (`requests`, `bandwidth`, `status_5xx`).
- **Inspector** (Origin/Domain) prefixes each name by source: `all_`, `compute_`, or `waf_`
  (e.g. `all_status_5xx`, `compute_resp_body_bytes`). Strip the prefix to look a name up here.

Not every field exists on every service or in every API; sparse/zero fields are omitted from a
response rather than returned as 0 (especially in Inspector `values[]`).

## Traffic & cache

| Field | Meaning |
| --- | --- |
| `requests` | Total client requests. |
| `hits` | Cache hits served from Fastly. |
| `hits_time` | Aggregate time (s) spent processing hits. |
| `miss` | Cache misses (fetched from origin). |
| `miss_time` | Aggregate time (s) spent processing misses. |
| `pass` | Requests passed to origin, uncached by design. |
| `pass_time` | Aggregate time (s) spent on passes. |
| `errors` | Error responses generated. |
| `restarts` | VCL `restart` invocations. |
| `hit_ratio` | Hits ÷ (hits + misses), in `[0,1]`. |
| `uncacheable` | Responses deemed uncacheable. |
| `synth` | Synthetic responses generated in VCL. |
| `edge_requests` | Requests received at the edge. |
| `edge_hit_requests` | Requests that were edge hits. |
| `edge_miss_requests` | Requests that were edge misses. |
| `edge_hit_ratio` | Edge hit ratio, in `[0,1]`. |
| `shield` | Requests handled by a shield POP. |
| `origin_fetches` | Fetches sent to origin. |
| `origin_offload` | Fraction of bytes served without hitting origin, in `[0,1]`. |
| `miss_histogram` | Distribution of miss latencies across time buckets. |

## Bandwidth & bytes

| Field | Meaning |
| --- | --- |
| `bandwidth` | Total bytes delivered (headers + body). |
| `body_size` | Total response body bytes. |
| `header_size` | Total response header bytes. |
| `resp_body_bytes` | Response body bytes to clients. |
| `resp_header_bytes` | Response header bytes to clients. |
| `req_body_bytes` | Request body bytes from clients. |
| `req_header_bytes` | Request header bytes from clients. |
| `bereq_body_bytes` | Backend request body bytes. |
| `bereq_header_bytes` | Backend request header bytes. |
| `edge_resp_body_bytes` | Edge response body bytes. |
| `edge_resp_header_bytes` | Edge response header bytes. |
| `origin_fetch_resp_body_bytes` | Origin-fetch response body bytes. |
| `origin_fetch_resp_header_bytes` | Origin-fetch response header bytes. |

## Status codes

Class summaries: `status_1xx`, `status_2xx`, `status_3xx`, `status_4xx`, `status_5xx`.

Specific codes (each a counter): `status_200`, `status_204`, `status_206`, `status_301`,
`status_302`, `status_304`, `status_400`, `status_401`, `status_403`, `status_404`,
`status_416`, `status_429`, `status_500`, `status_501`, `status_502`, `status_503`,
`status_504`, `status_505`.

A class total (e.g. `status_5xx`) counts every code in that class, including ones without a
dedicated field.

## Protocol & TLS

| Field | Meaning |
| --- | --- |
| `http2` | Requests over HTTP/2. |
| `http3` | Requests over HTTP/3. |
| `tls` | Requests over TLS (any version). |
| `tls_v10` / `tls_v11` / `tls_v12` / `tls_v13` | Requests by TLS version. |
| `ipv6` | Requests over IPv6. |

## Media & features

| Field | Meaning |
| --- | --- |
| `video` | Responses tagged as video. |
| `imgopto` | Image Optimizer responses. |
| `imgopto_transforms` | Image Optimizer transformations performed. |
| `imgopto_shield` | Image Optimizer responses from a shield. |
| `logging` / `log` | Logging events emitted. |
| `log_bytes` | Bytes sent to logging endpoints. |
| `pci` | Requests handled under PCI configuration. |

## Compute

| Field | Meaning |
| --- | --- |
| `compute_requests` | Requests handled by Compute. |
| `compute_execution_time_ms` | Compute execution time (ms). |
| `compute_request_time_ms` | Total Compute request time (ms). |
| `compute_request_time_billed_ms` | Billed Compute request time (ms). |
| `compute_ram_used` | RAM used by Compute (bytes). |
| `compute_bereqs` | Backend requests issued from Compute. |
| `compute_bereq_errors` | Backend request errors from Compute. |
| `compute_resp_body_bytes` | Compute response body bytes. |
| `compute_resp_header_bytes` | Compute response header bytes. |

## Security (bot, DDoS, NGWAF, WAF)

| Field | Meaning |
| --- | --- |
| `bot_requests_total_count` | Requests evaluated by Bot Management. |
| `bot_challenges_issued` | Bot challenges issued. |
| `bot_challenges_succeeded` | Challenges passed. |
| `bot_challenges_failed` | Challenges failed. |
| `ddos_protection_requests_allow_count` | Requests allowed by DDoS protection. |
| `ddos_protection_requests_detect_count` | Requests flagged by DDoS protection. |
| `ngwaf_requests_total_count` | Requests inspected by Next-Gen WAF. |
| `ngwaf_requests_blocked_count` | Requests blocked by NGWAF. |
| `ngwaf_requests_allowed_count` | Requests allowed by NGWAF. |
| `waf_blocked` | Requests blocked by (legacy) WAF. |
| `waf_logged` | Requests logged by WAF. |
| `waf_passed` | Requests passed by WAF. |
| `attack_req_body_bytes` | Request body bytes in attacks. |
| `attack_req_header_bytes` | Request header bytes in attacks. |
| `attack_resp_synth_bytes` | Synthetic response bytes for blocked attacks. |

## Real-time-only counters

These appear in real-time responses but not historical stats:

| Field | Meaning |
| --- | --- |
| `fanout_conn_time_ms` | Fanout connection time (ms). |
| `fanout_recv_publishes` | Fanout messages received. |
| `fanout_send_publishes` | Fanout messages sent. |
| `kv_store_class_a_operations` | KV Store class-A (write-like) operations. |
| `kv_store_class_b_operations` | KV Store class-B (read-like) operations. |

## Inspector latency histograms

Origin Inspector adds response-latency buckets (per `all_`/`compute_`/`waf_` source), e.g.
`all_latency_0_to_1ms`, `all_latency_1_to_5ms`, … up through `all_latency_60000ms` for the
slowest band. Summing a source's buckets gives its total responses; the distribution is how you
spot origin slowdowns.

## Meta / dimension fields

Not measurements — they identify a row:

| Field | Meaning |
| --- | --- |
| `start_time` | Unix timestamp for the start of a historical bucket. |
| `recorded` | Unix timestamp of a real-time second. |
| `service_id` | Service the row belongs to. |
| `customer_id` | Account the row belongs to. |
| `dimensions` | Inspector: `{host\|domain, region, datacenter}` labels for a series. |

## Types and units

- Counters (`requests`, `hits`, `status_*`, …) are non-negative integers.
- Byte fields (`bandwidth`, `*_bytes`, `compute_ram_used`) are bytes.
- Time fields (`*_time`, `*_time_ms`) are seconds or milliseconds as the suffix indicates.
- Ratios (`hit_ratio`, `edge_hit_ratio`, `origin_offload`) are floats in `[0,1]` — multiply by
  100 for a percentage.
- To convert byte fields to GB/TB, use **decimal SI** units (÷`1e9` for GB, ÷`1e12` for TB), the
  way Fastly bills — not binary GiB (`2^30`). Raw `bandwidth` (header + body) is edge traffic and
  is not your invoice; billable figures come from the usage endpoints — see
  [historical-stats-api.md](historical-stats-api.md#usage--billing-endpoints).
- `hits_time` / `miss_time` / `pass_time` are **edge** processing seconds (how long Fastly spent
  serving requests). For **origin** response latency, use Origin Inspector's latency histograms
  ([inspector-api.md](inspector-api.md)) — a different measurement.

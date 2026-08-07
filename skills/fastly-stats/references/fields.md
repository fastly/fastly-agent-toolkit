# Measurement Field Catalog

Docs: <https://www.fastly.com/documentation/reference/api/metrics-stats/historical-stats/> (measurements)

What each stats field means and which API exposes it. Use this when a response contains a metric
you don't recognize, or when picking `field=`/`metric=` values.

## Contents

- [How the three APIs name fields](#how-the-three-apis-name-fields)
- [Aggregation shape: counter vs gauge vs histogram](#aggregation-shape-counter-vs-gauge-vs-histogram)
- [Traffic & cache](#traffic--cache)
- [Shield & tier fields](#shield--tier-fields)
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

To check whether a name is real without reading a whole payload, ask for it alone —
`GET /stats/service/{id}/field/{name}` returns `{"status":"error","msg":"Unknown field: ..."}` for a
name that does not exist. Cheaper than guessing, and it catches near-miss spellings (the real fields
are `request_collapse_usable_count`, not `request_collapse_usable`).

## Aggregation shape: counter vs gauge vs histogram

**Read this before you sum anything.** The `Agg` column in every table below is how a field combines
across samples or POPs. Getting it wrong produces numbers that are silently, plausibly wrong.

| Agg | Meaning | How to combine | Examples |
| --- | --- | --- | --- |
| `counter` | Monotonic count or byte total for the sample | **Sum** across samples and across POPs | `requests`, `hits`, `shield_fetches`, `*_bytes` |
| `gauge` | A ratio/fraction already derived for that sample | **Never sum.** Recompute from the underlying counters, or take the mean | `hit_ratio`, `edge_hit_ratio`, `origin_offload` |
| `seconds` | Aggregate processing time for the sample | Sum for total; divide by the matching counter for a mean | `hits_time`, `miss_time`, `pass_time` |
| `histogram` | Dict of `{bucket: count}` | Merge by adding per-bucket counts | `miss_histogram` |

**The gauge trap.** Ratio fields are floats in `[0,1]` per sample, so summing a `by=second` series
of them yields a number near the sample count — which reads as a plausible large figure rather than
an error. Summing `origin_offload` over 120 real-time samples gives ≈120, not a percentage. Measured
on a live service, two samples:

```text
origin_offload samples: 0.2307, 0.6362
sum  = 0.8669   <- meaningless
mean = 0.4334   <- the answer
```

**Prefer recomputing a ratio over averaging it.** A mean of per-second ratios weights a quiet second
the same as a busy one. For a window figure, sum the numerator and denominator counters and divide
once:

```bash
# Window hit ratio across buckets — recomputed from counters, not averaged
curl -sS -H "Fastly-Key: $(fastly auth token --quiet)" \
  "https://api.fastly.com/stats/service/$SID?from=1%20day%20ago&by=hour" \
  | jq '[.data[]] | (map(.hits)|add // 0) as $h | (map(.miss)|add // 0) as $m
        | {hits: $h, miss: $m,
           window_hit_ratio: (if $h + $m > 0 then $h / ($h + $m) else null end)}'
```

The `// 0` and the zero guard are not decoration: an empty window (quiet service, or `by=minute` too
far back) otherwise fails with `null and null cannot be divided`.

`origin_offload` is defined over **header + body** bytes, verified against a live payload:

```text
1 - (origin_fetch_resp_body_bytes + origin_fetch_resp_header_bytes)
  / (edge_resp_body_bytes        + edge_resp_header_bytes)        = 0.29825
reported origin_offload                                          = 0.29825   # exact match
body bytes only                                                  = 0.11107   # wrong
```

## Traffic & cache

| Field | Agg | Meaning |
| --- | --- | --- |
| `requests` | counter | Total client requests. |
| `hits` | counter | Cache hits served from Fastly. |
| `hits_time` | seconds | Aggregate time (s) spent processing hits. |
| `miss` | counter | Cache misses (fetched from origin). |
| `miss_time` | seconds | Aggregate time (s) spent processing misses. |
| `pass` | counter | Requests passed to origin, uncached by design. |
| `pass_time` | seconds | Aggregate time (s) spent on passes. |
| `errors` | counter | Error responses generated. |
| `restarts` | counter | VCL `restart` invocations. |
| `hit_ratio` | **gauge** | Hits ÷ (hits + misses), in `[0,1]`. Never sum. |
| `uncacheable` | counter | Responses deemed uncacheable. |
| `synth` | counter | Synthetic responses generated in VCL. |
| `edge_requests` | counter | Requests received at this POP **acting as an edge** (client-facing). `0` on a POP serving only as a shield. |
| `edge_hit_requests` | counter | Of those, edge cache hits. |
| `edge_miss_requests` | counter | Of those, edge cache misses. |
| `edge_hit_ratio` | **gauge** | Edge hit ratio, in `[0,1]`. Never sum. |
| `origin_fetches` | counter | Requests this POP sent to a **true origin** (the last hop). |
| `origin_cache_fetches` | counter | Origin fetches that were cacheable. |
| `origin_revalidations` | counter | Conditional origin fetches that revalidated a stored object. |
| `origin_offload` | **gauge** | Fraction of **header + body** bytes served without reaching origin, in `[0,1]`. Recompute from counters rather than averaging — see [Aggregation shape](#aggregation-shape-counter-vs-gauge-vs-histogram). |
| `miss_histogram` | histogram | Dict of `{millisecond_bucket: count}` — a **latency** distribution for misses, not a time series. See [Latency from `miss_histogram`](#latency-from-miss_histogram). |
| `request_collapse_usable_count` | counter | Collapsed requests that could reuse the in-flight fetch. Real-time and `/stats` only; note the `_count` suffix. |
| `request_collapse_unusable_count` | counter | Collapsed requests that could **not** reuse it (they became separate origin fetches). |

## Shield & tier fields

These answer "what is my shielding topology actually doing", and they are the easiest fields in the
API to misread, because **each name is relative to the POP whose row you are reading.** The same
byte count appears as an outbound number on one POP and an inbound number on another.

| Field | Agg | Meaning **for the POP in this row** |
| --- | --- | --- |
| `shield` | counter | Requests received **at** this POP because it is acting as a shield. Nonzero ⇒ this POP is a tier, not an edge. |
| `shield_hit_requests` | counter | Of those, served from this tier's own cache. |
| `shield_miss_requests` | counter | Of those, this tier had to fetch. |
| `shield_fetches` | counter | Requests this POP forwarded **to another shield** (upstream, outbound). |
| `origin_fetches` | counter | Requests this POP sent to a **true origin** (outbound, terminal). |
| `shield_cache_fetches` | counter | Cacheable fetches issued to a shield. |
| `shield_revalidations` | counter | Conditional fetches to a shield that revalidated. |
| `shield_resp_body_bytes` | counter | Body bytes this POP **served as** a shield (outbound, downstream to an edge). |
| `shield_resp_header_bytes` | counter | Header bytes served as a shield. |
| `shield_fetch_resp_body_bytes` | counter | Body bytes this POP **received when fetching from** a shield (inbound, from upstream). |
| `shield_fetch_resp_header_bytes` | counter | Header bytes received from a shield. |
| `shield_fetch_body_bytes` / `shield_fetch_header_bytes` | counter | Bytes of the **request** this POP sent upstream (not the response). |
| `origin_fetch_resp_body_bytes` | counter | Body bytes received from a **true origin**. |

### Is this POP a tier, or the last hop?

**`shield_fetches` vs `origin_fetches` is the single most useful comparison in the set.** Nothing else
in the API tells you whether a POP terminates at origin or forwards to another tier — i.e. whether
there is another tier above it.

- `shield_fetches` ≫ `origin_fetches` → this POP forwards upstream; **there is another tier**.
- `origin_fetches` ≫ `shield_fetches` → this POP terminates at origin; **it is the last hop**.
- `shield == 0` and `edge_requests > 0` → pure client edge.
- `shield > 0` and `edge_requests == 0` → pure shield tier, no client traffic.

Measured on a live three-tier service (client → DEN edge → IAD shield → BOS shield → origin), one
week, `by=day`, per-POP via `datacenter=`:

```text
POP  shield  shield_fetches  origin_fetches  edge_requests   role
DEN       0             165               2            214   edge, forwards upstream
IAD     165              13             152              0   tier, mostly terminal
BOS      13               0              13              0   tier, fully terminal (last hop)
```

Read the chain off the columns: DEN's 165 `shield_fetches` arrive as IAD's 165 `shield`; IAD's 13
`shield_fetches` arrive as BOS's 13 `shield`. **A POP's outbound count is the next tier's inbound
count** — that adjacency is how you reconstruct a topology you were not told about.

### The `*_resp_body_bytes` direction trap

`shield_resp_body_bytes` and `shield_fetch_resp_body_bytes` differ by **direction**, not by scope:

- `shield_resp_body_bytes` — bytes going **out** of this POP, *as* a shield, down to an edge.
- `shield_fetch_resp_body_bytes` — bytes coming **in** to this POP, *from* a shield above it.

Conflating them inverts the flow and yields a **negative byte offload** — which is the only tell,
since a plausible-looking positive number would pass unnoticed. From the same live service:

```text
DEN.shield_fetch_resp_body_bytes = 339,506   (DEN received from IAD)
IAD.shield_resp_body_bytes       = 339,506   (IAD served to DEN)   <- same bytes, both directions named
IAD.shield_fetch_resp_body_bytes =  15,507   (IAD received from BOS)
BOS.shield_resp_body_bytes       =  15,507   (BOS served to IAD)
```

Use the equality as a self-check: if your reading of a tier pair does not make the downstream POP's
`shield_fetch_resp_body_bytes` equal the upstream POP's `shield_resp_body_bytes`, the reading is wrong.

### Latency from `miss_histogram`

`miss_histogram` is a dict of `{millisecond_bucket: count}` (e.g. `{"400": 1}` — one miss in the
400 ms bucket), so it supports percentiles and bucket-weighted means. Two practical notes:

- **`miss_time` is often unpopulated per POP while `miss_histogram` is populated**, which makes the
  histogram the only per-POP latency source you have. It is not exposed by
  `/stats/service/{id}/field/miss_histogram` (that returns `Unknown field`) — read it from a full
  row or a real-time payload.
- A bucket-weighted mean is an **approximation** — bucket width bounds its precision.
- Any before/after latency claim needs **untouched control POPs in the same window**. Treatment POPs
  moving while controls hold flat is what makes the claim defensible; both moving means you measured
  something else.

## Bandwidth & bytes

All byte fields are counters — sum them freely across samples and POPs.

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
| `edge_resp_body_bytes` | Edge response body bytes (client-facing, outbound). |
| `edge_resp_header_bytes` | Edge response header bytes. |
| `origin_fetch_resp_body_bytes` | Origin-fetch response body bytes (inbound from a true origin). |
| `origin_fetch_resp_header_bytes` | Origin-fetch response header bytes. |
| `billed_body_bytes` / `billed_header_bytes` | Bytes as counted for billing. |

Shield byte fields are direction-sensitive and live in
[Shield & tier fields](#shield--tier-fields) — do not pair them by guesswork.

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
| `segblock_shield_fetches` | Segmented Caching block fetches to a shield. |
| `segblock_origin_fetches` | Segmented Caching block fetches to origin. |
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
  100 for a percentage. They are **gauges**: recompute them from counters over your window rather
  than summing or averaging the per-sample values. See
  [Aggregation shape](#aggregation-shape-counter-vs-gauge-vs-histogram).
- A field that is absent or `null` in a row means "not applicable to this POP's role", not zero —
  e.g. `edge_hit_requests` is `null` on a pure shield POP, and `origin_offload` is `null` on a POP
  with no client-facing traffic to offload. Do not coerce `null` to 0 inside a ratio.
- To convert byte fields to GB/TB, use **decimal SI** units (÷`1e9` for GB, ÷`1e12` for TB), the
  way Fastly bills — not binary GiB (`2^30`). Raw `bandwidth` (header + body) is edge traffic and
  is not your invoice; billable figures come from the usage endpoints — see
  [historical-stats-api.md](historical-stats-api.md#usage--billing-endpoints).
- `hits_time` / `miss_time` / `pass_time` are **edge** processing seconds (how long Fastly spent
  serving requests). For **origin** response latency, use Origin Inspector's latency histograms
  ([inspector-api.md](inspector-api.md)) — a different measurement.

# Fastly Edge Phase Model

An approximate model of Fastly edge traffic processing from a user's perspective. Scope: public edge network only. Only phases that users can independently configure and observe are modeled.

**Ordering rule:** Phases must **begin** in canonical order, but a phase can reappear after later phases have begun. This matters for shielding, service chaining, and async origin fetches where `edge_app_request_processing` creates additional requests that re-enter the phase sequence.

## Request Processing

Phases begin in order when a request is received.

| #   | Phase                             | Features                                                                                                                                                                           |
| --- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `client_transport_negotiation`    | HTTP/3, QUIC                                                                                                                                                                       |
| 2   | `client_tls_handshake`            | TLS config, mTLS                                                                                                                                                                   |
| 3   | `domain_request_routing`§         | Domains, request routing rules (service selection)                                                                                                                                 |
| 4   | `adaptive_threat_engine`          | DDoS Protection                                                                                                                                                                    |
| 5   | `api_discovery`                   | API Discovery (passive traffic cataloging)                                                                                                                                         |
| 6   | `pre_cache_bot_inspection`        | Bot Management (pre-cache detection / ContentGuard)                                                                                                                                |
| 7   | `edge_app_request_processing`\*†  | VCL, Compute, ACLs, IP blocklists, edge rate limiting, WebSockets passthrough, Fanout pub/sub, health checks, caching, request collapsing, clustering, shielding, service chaining |
| 8   | `api_enforcement`                 | API Enforcement (schema validation; logs or blocks non-conforming requests)                                                                                                        |
| 9   | `edge_waf_request_inspection`     | Edge WAF, Bot Management (post-cache)                                                                                                                                              |
| 10  | `external_origin_fetch`           | Backends, Origin Inspector, On-The-Fly Packager                                                                                                                                    |
| 11  | `on_prem_waf_request_inspection`‡ | WAF module-agent (on-prem)                                                                                                                                                         |

## Response Processing

Phases begin in order when a response is received.

| #   | Phase                              | Features                              |
| --- | ---------------------------------- | ------------------------------------- |
| 12  | `on_prem_waf_response_inspection`‡ | WAF module-agent (on-prem)            |
| 13  | `image_optimization`               | Image Optimizer                       |
| 14  | `edge_waf_response_inspection`     | Edge WAF, Bot Management (post-cache) |
| 15  | `edge_app_response_processing`\*   | VCL, Compute, static compression      |
| 16  | `dynamic_response_compression`     | Dynamic gzip/brotli                   |

\* `edge_app_request_processing` and `edge_app_response_processing` may create additional requests. These execute as separate phase sequences.

† For Compute services, `edge_waf_request_inspection` can be configured to execute after `external_origin_fetch` for a given request.

‡ Origin logic often executes before the on-prem WAF phase. Phases are skipped entirely if the feature is not deployed/configured.

§ Internal requests may carry an already-selected service and skip this phase.

## Key Insights

- **DDoS before app logic**: `adaptive_threat_engine` runs before VCL/Compute, so VCL cannot block requests before DDoS detection
- **Bot detection before app logic (pre-cache)**: ContentGuard (`pre_cache_bot_inspection`, phase 6) detects and classifies bot traffic before VCL/Compute; VCL can then act on the classification
- **API Enforcement after app logic**: `api_enforcement` runs after VCL/Compute request processing and before `edge_waf_request_inspection`
- **WAF after app logic (post-cache)**: `edge_waf_request_inspection` runs after VCL/Compute request processing, so WAF sees headers as modified by app logic
- **Shielding/chaining creates new sequences**: Handled within `edge_app_request_processing`, spawns additional requests that traverse their own phase sequences
- **Image optimization before app response**: Runs before response reaches VCL/Compute response handlers
- **Caching is part of app processing**: Cache lookup/storage is within `edge_app_request_processing`
- **Phases 1-2 and 4-5 are external-only**: Do not execute for Fastly-internal requests (shielding, service chaining, async origin fetch). `domain_request_routing` (phase 3) is skipped when an internal request already carries a selected service. Other phases like `edge_waf_request_inspection` run in their normal position before `external_origin_fetch` — in shielded deployments, this means Edge WAF runs at the shield POP where the origin fetch occurs
- **Phases scope to external clients/origins**: TLS handshake and transport negotiation phases refer to external web clients, not Fastly-internal connections

## Common Questions

**Why didn't my VCL block stop the request before DDoS detection?**
DDoS (`adaptive_threat_engine`) executes before `edge_app_request_processing`.

**Why does WAF see modified headers?**
`edge_waf_request_inspection` runs after VCL/Compute can modify the request.

**Where does caching fit?**
Cache lookup/storage is part of `edge_app_request_processing` (VCL/Compute).

**Does DDoS protection apply to shielded/chained requests?**
No. `adaptive_threat_engine` only processes external web client requests, not Fastly-internal requests from shielding or service chaining.

**What's the difference between pre-cache and post-cache bot management?**
Pre-cache (`pre_cache_bot_inspection`, phase 6) detects and classifies bot traffic before VCL/Compute — VCL can then act on the classification using bot VCL variables. Post-cache (`edge_waf_request_inspection`, phase 9) runs after VCL/Compute and can use NGWAF signals, challenges, and rules to take action.

# Fastly Edge Phase Model

An approximate model of Fastly edge traffic processing from a user's perspective. Scope: public edge network only. Only phases that users can independently configure and observe are modeled.

**Ordering rule:** Phases must **begin** in canonical order, but a phase can reappear after later phases have begun. This matters for shielding, service chaining, and async origin fetches where `edge_app_request_processing` creates additional requests that re-enter the phase sequence.

## Request Processing

Phases begin in order when a request is received.

| #   | Phase                             | Features                                                                                                                                                                           |
| --- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `client_transport_negotiation`    | HTTP/3, QUIC                                                                                                                                                                       |
| 2   | `client_tls_handshake`            | TLS config, mTLS                                                                                                                                                                   |
| 3   | `adaptive_threat_engine`          | DDoS Protection                                                                                                                                                                    |
| 4   | `api_discovery`                   | API Discovery (passive traffic cataloging)                                                                                                                                         |
| 5   | `bot_detection`                   | Bot Management (pre-cache detection / ContentGuard)                                                                                                                                |
| 6   | `edge_app_request_processing`\*†  | VCL, Compute, ACLs, IP blocklists, edge rate limiting, WebSockets passthrough, Fanout pub/sub, health checks, caching, request collapsing, clustering, shielding, service chaining |
| 7   | `edge_waf_request_inspection`     | Edge WAF, Bot Management (post-cache)                                                                                                                                              |
| 8   | `external_origin_fetch`           | Backends, Origin Inspector, On-The-Fly Packager                                                                                                                                    |
| 9   | `on_prem_waf_request_inspection`‡ | WAF module-agent (on-prem)                                                                                                                                                         |

## Response Processing

Phases begin in order when a response is received.

| #   | Phase                              | Features                              |
| --- | ---------------------------------- | ------------------------------------- |
| 10  | `on_prem_waf_response_inspection`‡ | WAF module-agent (on-prem)            |
| 11  | `image_optimization`               | Image Optimizer                       |
| 12  | `edge_waf_response_inspection`     | Edge WAF, Bot Management (post-cache) |
| 13  | `edge_app_response_processing`\*   | VCL, Compute, static compression      |
| 14  | `dynamic_response_compression`     | Dynamic gzip/brotli                   |

\* `edge_app_request_processing` and `edge_app_response_processing` may create additional requests. These execute as separate phase sequences.

† While atypical, a Compute program may call `edge_waf_request_inspection` after `external_origin_fetch` for a given request.

‡ Origin logic often executes before the on-prem WAF phase. Phases are skipped entirely if the feature is not deployed/configured.

## Key Insights

- **DDoS before app logic**: `adaptive_threat_engine` runs before VCL/Compute, so VCL cannot block requests before DDoS detection
- **Bot detection before app logic (pre-cache)**: ContentGuard (`bot_detection`, phase 5) detects and classifies bot traffic before VCL/Compute; VCL can then act on the classification
- **WAF after app logic (post-cache)**: `edge_waf_request_inspection` runs after VCL/Compute request processing, so WAF sees headers as modified by app logic
- **Shielding/chaining creates new sequences**: Handled within `edge_app_request_processing`, spawns additional requests that traverse their own phase sequences
- **Image optimization before app response**: Runs before response reaches VCL/Compute response handlers
- **Caching is part of app processing**: Cache lookup/storage is within `edge_app_request_processing`
- **Phases 1-5 are external-only**: Do not execute for Fastly-internal requests (shielding, service chaining). Other phases like `edge_waf_request_inspection` run in their normal position before `external_origin_fetch` — in shielded deployments, this means Edge WAF runs at the shield POP where the origin fetch occurs
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
Pre-cache (`bot_detection`, phase 5) detects and classifies bot traffic before VCL/Compute — VCL can then act on the classification using bot VCL variables. Post-cache (`edge_waf_request_inspection`, phase 7) runs after VCL/Compute and can use NGWAF signals, challenges, and rules to take action.

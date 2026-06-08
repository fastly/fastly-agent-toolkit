# Fastly Bot Management

Base: `https://api.fastly.com` | Auth: `Fastly-Key: $FASTLY_API_TOKEN` | Docs: https://www.fastly.com/documentation/reference/api/products/bot_management

## How It Works

Bot Management uses server-side fingerprinting, client challenges, and client-side detections to distinguish legitimate users from automated traffic. Two deployment options exist: **pre-cache** (ContentGuard) and **post-cache** (requires NGWAF).

### Deployment Options

| Deployment                   | Phase                                                      | Requires NGWAF                   | Use Case                                                                   |
| ---------------------------- | ---------------------------------------------------------- | -------------------------------- | -------------------------------------------------------------------------- |
| **Pre-cache (ContentGuard)** | Phase 5 (`bot_detection`), before VCL/Compute              | No — any Fastly delivery product | Content scraping detection and classification                              |
| **Post-cache**               | Phase 7 (`edge_waf_request_inspection`), after VCL/Compute | Yes                              | Full bot management with NGWAF signals, challenges, client-side detections |

### Detection Mechanisms

- **Client fingerprinting**: JA3/JA4 TLS fingerprinting at the edge. Identifies client types from TLS handshake signatures without origin-side configuration. Detects credential stuffing, credential cracking, and IP rotation bots.
- **Client challenges** (post-cache only): Three types -- *dynamic* (auto-selects best method: PATs, non-interactive PoW, or interactive), *interactive* (CAPTCHA-like), and *non-interactive* (JavaScript Proof-of-Work). Challenges present an interstitial page while processing.
- **Private Access Tokens (PATs)** (post-cache only): Cryptographic device attestation that verifies humans without puzzles or revealing identity. Apple devices only (iOS 16+, macOS Ventura+). Rate-limited to 10 tokens/min per device. Selected automatically by dynamic challenges when available.
- **Client-side detections** (post-cache only): JavaScript snippet that detects headless browsers by collecting browser signals. Must be **manually embedded** in your HTML pages -- not injected automatically.
- **Verified bots**: Allowlisting for known legitimate bots (search crawlers, etc.). Adds an NGWAF signal for use in rule conditions (post-cache) or classification data (pre-cache).
- **ContentGuard** (pre-cache only): Detects and classifies content scraping activity. Categorizes bot traffic (AI crawlers, search engines, SEO tools, etc.); customers control responses via bot VCL variables.

### Execution Ordering

**Pre-cache (ContentGuard)** runs in the `bot_detection` phase (phase 5), **before** `edge_app_request_processing` (VCL/Compute):

```
client -> adaptive_threat_engine -> api_discovery -> bot_detection (ContentGuard)
       -> edge_app_request_processing (VCL/Compute) -> ...
```

**Post-cache** runs in the `edge_waf_request_inspection` phase (phase 7), **after** `edge_app_request_processing`:

```
client -> ... -> edge_app_request_processing (VCL/Compute)
       -> edge_waf_request_inspection (Bot Management post-cache, Edge WAF)
       -> external_origin_fetch
```

Key implications:
- **Pre-cache ContentGuard** detects and classifies bot traffic before VCL/Compute; VCL acts on the classification using bot VCL variables
- **Post-cache: VCL/Compute executes before Bot Management**, so bot decisions occur after app logic has run
- **VCL/Compute can set headers** that post-cache Bot Management reads, but should not manipulate challenge cookies (`Set-Cookie`/`Cookie` headers) as these are essential for challenge processing
- **Post-cache Bot Management sees the request as modified by VCL/Compute**, including any header rewrites or URL changes
- Post-cache Bot Management shares the `edge_waf_request_inspection` phase with Edge WAF (NGWAF)

### Prerequisites

**Pre-cache (ContentGuard):**
- Any Fastly delivery product (does not require NGWAF)

**Post-cache:**
- Active **NGWAF (Next-Gen WAF) subscription** -- post-cache Bot Management is an add-on to NGWAF
- The client-side detection JavaScript snippet must be deployed in your HTML pages

## Enablement

Product slug: `bot_management`. See `products.md` for the universal enablement pattern.

### Configuration

| Action     | Method  | Endpoint                                                                  |
| ---------- | ------- | ------------------------------------------------------------------------- |
| Get config | `GET`   | `/enabled-products/v1/bot_management/services/{service_id}/configuration` |
| Set config | `PATCH` | `/enabled-products/v1/bot_management/services/{service_id}/configuration` |

Configuration property: `contentguard` — `"on"` or `"off"`. Controls whether ContentGuard (pre-cache bot detection) is active on the service.

```bash
# Enable ContentGuard on a service with Bot Management
curl -X PATCH -H "Fastly-Key: $FASTLY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"contentguard": "on"}' \
  "https://api.fastly.com/enabled-products/v1/bot_management/services/$SERVICE_ID/configuration"
```

## Documentation

URLs below serve Markdown (use the `Accept: text/markdown` header).

| Source                                           | URL                                                                                                         |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| Product overview, prerequisites, billing         | `https://docs.fastly.com/products/bot-management`                                                           |
| Setup guides, configuration, challenge tuning    | `https://www.fastly.com/documentation/guides/security/bot-management`                                       |
| API endpoints, request/response schemas          | `https://www.fastly.com/documentation/reference/api/products/bot_management`                                |
| ContentGuard (pre-cache) setup and usage         | `https://www.fastly.com/documentation/guides/security/bot-management/about-contentguard`                    |
| Client challenge types, embedding, configuration | `https://www.fastly.com/documentation/guides/security/bot-management/client-challenges`                     |
| Advanced client-side detection setup             | `https://www.fastly.com/documentation/guides/security/bot-management/using-advanced-client-side-detections` |

For general Fastly platform guidance, documentation source index, and other specialized skills, see the `fastly` skill.

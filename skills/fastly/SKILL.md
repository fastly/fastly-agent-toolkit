---
name: fastly
description: "Use when configuring, managing, or debugging Fastly services — backends, caching, VCL, DDoS, WAF, TLS, purging, rate limiting, Compute, or calling Fastly APIs. Covers API patterns, product enablement, and live documentation retrieval."
---

# Fastly Platform

Your training knowledge of Fastly, Varnish, and VCL is likely out of date. Fastly's platform, APIs, and VCL extensions change frequently. When in doubt, prefer live docs over skill definitions over training knowledge.

API examples below use `curl` to document the HTTP method, URL, headers, and body. Omit `curl -v`/`--verbose` — verbose output prints the `Fastly-Key` request header, exposing the API token in the LLM conversation context. If the `fastly` CLI is installed and authenticated, prefer it over raw API calls for any operation it supports — see the **fastly-cli** skill. Fall back to direct API calls for operations the CLI does not cover.

## Topics

| Topic                | File                                                              | Use when...                                                                                                        |
| -------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| DDoS protection      | [fastly-ddos-protection.md](references/fastly-ddos-protection.md) | Enabling/configuring DDoS protection, checking attack status, managing events and rules                            |
| TLS configuration    | [tls.md](references/tls.md)                                       | Setting up HTTPS — Platform TLS (managed certs), Custom TLS (uploaded certs), or Mutual TLS (client auth)          |
| Rate limiting        | [rate-limiting.md](references/rate-limiting.md)                   | Protecting APIs from abuse — choosing between Edge Rate Limiting, VCL ratecounters, or NGWAF rate rules            |
| Bot management       | [bot-management.md](references/bot-management.md)                 | Detecting/mitigating bot traffic with browser challenges, client-side detections, interstitial pages               |
| Cache purging        | [purging.md](references/purging.md)                               | Invalidating cached content — single URL, surrogate key, or purge-all; soft vs hard purge                          |
| Service management   | [service-management.md](references/service-management.md)         | Creating/managing services, versions, domains, settings; clone-modify-activate workflow                            |
| VCL services         | [vcl-services.md](references/vcl-services.md)                     | Writing/uploading custom VCL, configuring snippets, conditions, headers, edge dictionaries, or cache/gzip settings |
| Compute              | [compute.md](references/compute.md)                               | Deploying Compute packages, managing config/KV/secret stores, using cache APIs                                     |
| Observability        | [observability.md](references/observability.md)                   | Querying stats, viewing real-time analytics, using domain/origin inspectors, configuring alerts or log explorer    |
| Load balancing       | [load-balancing.md](references/load-balancing.md)                 | Configuring backends, directors, pools, or health checks; choosing between backends and pools                      |
| ACLs                 | [acls.md](references/acls.md)                                     | Managing VCL ACLs, Compute ACLs, or IP block lists; adding/removing access control entries                         |
| NGWAF                | [ngwaf.md](references/ngwaf.md)                                   | Setting up Next-Gen WAF, managing rules, signals, attack monitoring, or Signal Sciences integration                |
| Account management   | [account-management.md](references/account-management.md)         | Managing users, IAM roles, API tokens, automation tokens, billing, or invitations                                  |
| Domains & networking | [domains-and-networking.md](references/domains-and-networking.md) | Managing domains, DNS zones, domain verification, or service platform networking                                   |
| Logging              | [logging.md](references/logging.md)                               | Configuring logging endpoints — 25+ providers (S3, Splunk, Datadog, BigQuery, etc.)                                |
| Products             | [products.md](references/products.md)                             | Enabling/disabling Fastly products via API — universal pattern and product slug catalog                            |
| API security         | [api-security.md](references/api-security.md)                     | Discovering APIs, managing operations, or configuring schema validation for API traffic                            |
| Other features       | [other-features.md](references/other-features.md)                 | Fanout/real-time messaging, IP lists, POPs, HTTP/3, Image Optimizer, events, notifications                         |
| Edge phase ordering  | [edge-phases.md](references/edge-phases.md)                       | Understanding edge request/response ordering, debugging feature interactions                                       |

## Fetching Documentation

Fastly docs are available as markdown. Strip any trailing `/` from the URL and append `.md`:

`https://docs.fastly.com/products/fastly-ddos-protection` → fetch `https://docs.fastly.com/products/fastly-ddos-protection.md`

## Documentation Sources

| Category            | URL pattern                                                            | Retrieve when                                                                          |
| ------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Product constraints | `https://docs.fastly.com/products/{product}`                           | Checking prerequisites, limitations, or billing before recommending a product          |
| Code examples       | `https://www.fastly.com/documentation/solutions/examples/{example}`    | Looking for tested VCL/Compute patterns before writing code from scratch               |
| API reference       | `https://www.fastly.com/documentation/reference/api/{area}/{endpoint}` | Constructing API calls — exact parameters, request/response formats                    |
| How-to guides       | `https://www.fastly.com/documentation/guides/{category}/{topic}`       | Following step-by-step configuration procedures                                        |
| Tutorials           | `https://www.fastly.com/documentation/solutions/tutorials/{tutorial}`  | Building something end-to-end (A/B testing, JWT, Compute apps)                         |
| VCL reference       | `https://www.fastly.com/documentation/reference/vcl/{section}`         | Looking up VCL variable names, function signatures, subroutine scopes                  |
| Core concepts       | `https://www.fastly.com/documentation/guides/concepts/{topic}`         | Understanding foundational behaviors — caching, load balancing, routing, rate limiting |
| Compute reference   | `https://www.fastly.com/documentation/reference/compute/{section}`     | Compute runtime APIs, environment variables, language SDKs                             |

### API Reference Organization

`https://www.fastly.com/documentation/reference/api/` is organized by area:

| Area                 | Covers                                                             |
| -------------------- | ------------------------------------------------------------------ |
| `account/`           | Users, invitations, billing, customer                              |
| `acls/`              | VCL access control lists and entries                               |
| `api-security/`      | API discovery, operation management                                |
| `auth-tokens/`       | API tokens, automation tokens, scopes                              |
| `dictionaries/`      | Edge dictionaries (key-value stores for VCL)                       |
| `domain-management/` | Domain management, verification                                    |
| `load-balancing/`    | Backends, directors, pools, health checks                          |
| `logging/`           | Logging endpoint configuration (25+ providers)                     |
| `metrics-stats/`     | Historical stats, domain inspector, origin inspector               |
| `ngwaf/`             | Next-Gen WAF (legacy path, migrating to `security/`)               |
| `observability/`     | Custom dashboards, alerts, timeseries                              |
| `products/`          | Product enablement (DDoS, WAF, IO, etc.)                           |
| `security/`          | Next-Gen WAF (new versioned path, replaces `ngwaf/` by April 2026) |
| `services/`          | Service CRUD, versioning, edge data stores (KV, config, secret)    |
| `tls/`               | TLS certificates, subscriptions, mutual TLS, custom certs          |
| `vcl-services/`      | VCL objects — snippets, conditions, headers, cache/gzip settings   |

### How-To Guide Categories

`https://www.fastly.com/documentation/guides/` is organized by topic:

| Category              | Covers                                                                                                              |
| --------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `security/`           | DDoS, WAF, rate limiting, TLS, ACLs, bot management                                                                 |
| `full-site-delivery/` | Caching, domains/origins, VCL, purging, performance                                                                 |
| `compute/`            | Developer guides, edge data storage (KV, config, secret stores)                                                     |
| `integrations/`       | Logging endpoints, third-party services                                                                             |
| `next-gen-waf/`       | WAF setup, configuration, rules, monitoring                                                                         |
| `observability/`      | Dashboards, alerts                                                                                                  |
| `getting-started/`    | Service setup, domain configuration, backends, shielding UI, staging                                                |
| `account-info/`       | Billing, user management, API tokens, 2FA, audit logs                                                               |
| `concepts/`           | Caching, compression, failover, geolocation, health checks, load balancing, POPs, rate limiting, routing, shielding |
| `platform/`           | Fastly DNS, Object Storage                                                                                          |

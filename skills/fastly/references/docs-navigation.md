# Fastly Documentation Navigation

## Searching the Docs

To find pages by topic, query the docs search endpoint (no auth required):

```
https://api.fastly.com/public-search/docs?query=bot%20management&limit=10
```

| Parameter | Notes                                            |
| --------- | ------------------------------------------------ |
| `query`   | Search term (URL-encode spaces as `%20`)         |
| `limit`   | Max results (default: 100)                       |

Returns JSON: `{ "record_count": N, "records": [...] }`. Each record has `term` (title), `url` (HTML page URL), and `group` (Guides, Reference, Products, etc.). To fetch a result as Markdown, use the `Accept: text/markdown` header — see "Fetching Documentation" in the parent SKILL.md. Apex `fastly.com` URLs redirect to `www.fastly.com` on their own, but rewriting the host yourself avoids the extra hop and keeps the `Accept` header on clients that drop it across a redirect (leave `docs.fastly.com` as-is).

Use the tables below for orientation when you already know the area. Use search to locate a specific page.

## API Reference Organization

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

## How-To Guide Categories

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

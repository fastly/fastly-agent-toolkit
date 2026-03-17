---
name: fastly-cli
description: "Executes Fastly CLI commands for managing CDN services, Compute deploys, and edge infrastructure. Use when running `fastly` CLI commands, creating or managing Fastly services from the terminal, deploying Fastly Compute applications, managing backends/domains/VCL snippets via command line, purging cache, configuring log streaming, setting up TLS certificates, managing KV/config/secret stores, checking service stats, authenticating with Fastly SSO, or working with fastly.toml. Also applies when working with Fastly service IDs in CLI context, or with `fastly service`, `fastly compute`, `fastly auth`, or any Fastly CLI subcommand. Covers service CRUD, version management, autocloning, and troubleshooting common CLI errors."
---

## Trigger and scope

CRITICAL: many subcommands have unintuitive paths (e.g. `fastly domain create` fails with 403, correct is `fastly service domain create`; logging is under `fastly service logging`; alerts under `fastly service alert`; rate limits under `fastly service rate-limit`).

Covers: services, backends, domains, VCL snippets, cache purging, Compute/WASM deploys, log streaming (S3/Datadog/Splunk/Kafka/25+ providers), NGWAF/WAF, TLS/mTLS, KV/config/secret stores, stats, alerts, rate limiting, ACLs, and auth tokens.

# Fastly CLI Overview

## References

| Topic          | File                                  | Use when...                                                                              |
| -------------- | ------------------------------------- | ---------------------------------------------------------------------------------------- |
| Authentication | [auth.md](references/auth.md)         | Login, stored tokens, service auth, CI/CD auth setup                                     |
| Compute        | [compute.md](references/compute.md)   | Building/deploying edge applications, local dev server                                   |
| Services       | [services.md](references/services.md) | Service CRUD, backends, domains, ACLs, dictionaries, VCL, purging, rate limiting         |
| Logging        | [logging.md](references/logging.md)   | Log streaming to S3, GCS, Datadog, Splunk, Kafka, 25+ providers                          |
| NGWAF          | [ngwaf.md](references/ngwaf.md)       | Next-Gen WAF workspaces, IP/country lists, rules, signals, thresholds, alerts            |
| Stats          | [stats.md](references/stats.md)       | Historical/real-time metrics, cache hit ratios, error rates, bandwidth, regional traffic |
| Stores         | [stores.md](references/stores.md)     | KV Stores, Config Stores, Secret Stores, resource links                                  |
| TLS            | [tls.md](references/tls.md)           | Platform TLS, Let's Encrypt subscriptions, custom certs, mutual TLS                      |

## Command Structure

```
fastly <command> <subcommand> [flags]
```

### Top-Level Commands

| Category     | Commands                                                                                |
| ------------ | --------------------------------------------------------------------------------------- |
| **Compute**  | `compute` - Build and deploy edge applications                                          |
| **Services** | `service` - Manage CDN services, logging, backends, VCL, ACLs, purging                  |
| **Security** | `ngwaf` - Web application firewall                                                      |
| **TLS**      | `tls-subscription`, `tls-custom`, `tls-platform`, `tls-config` - Certificate management |
| **Storage**  | `kv-store`, `config-store`, `secret-store` - Edge data stores                           |
| **Auth**     | `auth` - Login, stored tokens; `auth-token` (deprecated)                                |
| **Info**     | `stats`, `ip-list`, `pops`, `whoami` - Information queries                              |
| **Other**    | `dashboard`, `domain`, `products`, `object-storage`, `tools`                            |

## Global Flags

Available on most commands:

```bash
# Service targeting
--service-id SERVICE_ID    # Target service by ID
--service-name NAME        # Target service by name
-s SERVICE_ID              # Short form

# Version targeting (version-scoped commands like `fastly service domain/backend/...`)
# NOTE: `fastly domain create` does NOT accept --version (it uses a different API)
--version VERSION          # Specific version number
--version active           # Currently active version
--version latest           # Most recent version

# Authentication
--token TOKEN              # API token or stored token name (use 'default' for default)

# Output (--json is per-command, not global)
--verbose                  # Detailed output
--quiet                    # Minimal output

# Automation
--accept-defaults          # Accept default values
--auto-yes                 # Skip confirmations
--non-interactive          # No prompts
```

## Key Patterns

- Target by ID (`-s SERVICE_ID`) or name (`--service-name NAME`)
- Version targeting: `--version active`, `--version latest`, or `--version N`
- Use `--autoclone` to auto-clone locked versions
- Use `--json` for scripted output, `--non-interactive --accept-defaults` for CI/CD
- **JSON output uses PascalCase fields** (`.Name`, `.ServiceID`, `.ActiveVersion`), not lowercase
- Auth: `fastly auth login --sso` to login, or set `FASTLY_API_TOKEN` env var
- For API token in scripts, use `$(fastly auth show --reveal --quiet | awk '/^Token:/ {print $2}')` only when the current credential is a stored Fastly CLI token; if auth comes from `FASTLY_API_TOKEN` or another non-stored source, read the token from the environment instead and never reveal it in conversation
- Logging is under `service logging` (e.g. `fastly service logging s3 create`)
- Config: `~/.config/fastly/config.toml` (stored tokens), `fastly.toml` (project)

## Propagation Delays

Changes propagate across Fastly's network in seconds to minutes (up to 10 min for version activations, up to 5 min for TLS). Cache purges are 1-2 seconds. Retry with backoff when verifying changes.

**New service activation sequence**: After activating a brand new service, expect 500 "Domain Not Found" for 10-60 seconds while the domain propagates to edge POPs. This is normal — do not change configuration. Wait and retry. After version updates (e.g., fixing backend settings), allow 15-30 seconds for the new version to propagate.

## Troubleshooting

See [troubleshooting.md](references/troubleshooting.md) for the full list. The most common pitfalls:

- **503 SSL mismatch**: When `--override-host` differs from `--address`, always set `--ssl-cert-hostname` and `--ssl-sni-hostname` to the origin's actual hostname.
- **403/400 on domain create**: Use `fastly service domain create`, not `fastly domain create`.
- **"version is locked"**: Use `--autoclone` or clone first.
- **New service setup**: Version 1 is unlocked — add domain, backend, snippets on `--version 1`, then activate once.
- **VCL commands**: Under `fastly service vcl` (e.g. `fastly service vcl snippet create`), not `fastly vcl`.
- **Token safety**: Never use `fastly auth show --reveal` bare in an AI context — it exposes tokens.

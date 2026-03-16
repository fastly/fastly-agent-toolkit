---
name: fastly-cli
description: "Use when running any `fastly` CLI command or the user mentions the Fastly CLI, Fastly service IDs, fastly.toml, or CDN operations via CLI. CRITICAL: many subcommands have unintuitive paths (e.g. `fastly domain create` fails with 403, correct is `fastly service domain create`; logging is under `fastly service logging`; alerts under `fastly service alert`; rate limits under `fastly service rate-limit`). Covers: services, backends, domains, VCL snippets, cache purging, Compute/WASM deploys, log streaming (S3/Datadog/Splunk/Kafka/25+ providers), NGWAF/WAF, TLS/mTLS, KV/config/secret stores, stats, alerts, rate limiting, ACLs, and auth tokens."
---

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

- **503 "hostname doesn't match against certificate"**: When `--override-host` differs from `--address`, you MUST set `--ssl-cert-hostname` and `--ssl-sni-hostname` to the origin's actual hostname (the one its TLS certificate covers), NOT the override-host value. Without these flags, Fastly validates the cert against the override-host and fails. **Always set all four flags together**: `--address`, `--override-host`, `--ssl-cert-hostname`, `--ssl-sni-hostname`. Check the origin's certificate SANs with: `echo | openssl s_client -connect ORIGIN:443 2>/dev/null | openssl x509 -noout -text | grep -A1 "Subject Alternative Name"`
- **403/400 on domain create**: Use `fastly service domain create` (version-scoped API), not `fastly domain create`. The versionless `fastly domain create` returns 403 for most accounts, and returns 400 for `*.global.ssl.fastly.net` / `*.edgecompute.app` test domains with "Invalid value for fqdn". Always use `fastly service domain create`.
- **"version is locked"**: Use `--autoclone` or clone first with `fastly service version clone`
- **New service setup**: Version 1 is unlocked — add domain, backend, and snippets all on `--version 1`, then activate once. Do NOT use `--autoclone` or `--version latest` on a new service — it causes unnecessary version cloning and scattered configuration.
- **VCL commands**: Snippet/custom VCL commands are under `fastly service vcl` (e.g. `fastly service vcl snippet create`, `fastly service vcl custom create`), NOT `fastly vcl snippet create`
- **`--content` is inline**: The `--content` flag on snippet/custom VCL commands takes inline VCL code, not a file path. To load from a file: `--content "$(cat file.vcl)"`
- **Test domains**: Use a name you choose (e.g. `my-app.global.ssl.fastly.net`), not the service ID. `SERVICE_ID.global.ssl.fastly.net` does NOT work. Adding `foo.global.ssl.fastly.net` automatically makes `foo.freetls.fastly.net` available (HTTP/2).
- **`--json` not supported on all commands**: `fastly service create` does not support `--json`. Parse the text output (e.g. `SUCCESS: Created service XXXXX`) instead. Always check if `--json` is accepted before relying on JSON output.
- **Propagation error sequence**: After activating a new service, expect this progression: 500 "Domain Not Found" (10-30s, domain not yet known at edge) → 503 backend errors (if backend config is wrong) → 200 (working). If you see 503 right after 500 clears, check the backend configuration. If you see 503 "hostname doesn't match against certificate", fix the SSL hostname settings. A 503 that appears after a working 200 usually means a backend issue, not propagation.
- **TLS subscription flags**: The CLI flag for certificate authority is `--cert-auth` (not `--certificate-authority`). Always check CAA records with `dig CAA DOMAIN +short` before choosing a CA — mismatched CAA records cause `blocked` authorization state. To get DNS challenge details, you must use `--include tls_authorizations --json` — without `--include`, challenges are null. The `--include` flag only affects JSON output; text output always omits challenges.
- **Token for REST API calls**: NEVER use `fastly auth show --reveal` in an AI agent context — it exposes the API token in the conversation. Use `$(fastly auth show TOKEN_NAME --reveal --quiet | awk '/^Token:/ {print $2}')` with an explicit stored token name. Without a name, it fails when the CLI is authenticated via `FASTLY_API_TOKEN` or another non-stored source. Similarly, `--debug-mode` prints secrets to stdout — avoid it unless the user requests it.
- Debug with `fastly --debug-mode <command>` or `FASTLY_DEBUG_MODE=true` (prints API token in output)

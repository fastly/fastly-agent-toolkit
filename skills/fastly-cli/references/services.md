# Fastly Service Management

Manage Fastly CDN services and their configurations.

## Choosing a Service Type

| Type    | Flag                   | Best for                                                                            |
| ------- | ---------------------- | ----------------------------------------------------------------------------------- |
| VCL     | `--type vcl` (default) | Caching proxies, CDN configs, header manipulation. No build step, no runtime costs. |
| Compute | `--type wasm`          | Custom logic in Rust/JS/Go at the edge. Requires build and has per-request costs.   |

For tasks like "create a caching frontend" or "set up a reverse proxy," always use VCL.

## Service CRUD Operations

```bash
fastly service list
fastly service create --name "My Service"
fastly service create --name "My Service" --type wasm
fastly service describe --service-id SERVICE_ID
fastly service search --name "production"
fastly service update --service-id SERVICE_ID --name "New Name" --comment "Updated"
fastly service delete --service-id SERVICE_ID
```

## Service Versions

Every service has versions. Only one version can be active at a time. Active versions are automatically locked and cannot be modified — you must clone them first.

```bash
fastly service version list --service-id SERVICE_ID
fastly service version clone --service-id SERVICE_ID --version 1
fastly service version activate --service-id SERVICE_ID --version 2
fastly service version deactivate --service-id SERVICE_ID --version 2
fastly service version lock --service-id SERVICE_ID --version 2
fastly service version update --service-id SERVICE_ID --version 2 --comment "Production release"
fastly service version stage --version=VERSION --service-id SERVICE_ID
fastly service version unstage --version=VERSION --service-id SERVICE_ID
```

To modify a live service: clone the active version, make changes on the new version, validate, then activate. Many CLI commands accept `--autoclone` to do this automatically.

Via the REST API, clone with:

```bash
curl -s -X PUT "https://api.fastly.com/service/$SERVICE_ID/version/$VERSION/clone" \
  -H "Fastly-Key: $FASTLY_API_TOKEN"
```

## Backends (Origins)

```bash
fastly service backend list --service-id SERVICE_ID --version 1

fastly service backend create \
  --service-id SERVICE_ID \
  --version 1 \
  --name origin \
  --address origin.example.com \
  --port 443 \
  --use-ssl \
  --override-host origin.example.com \
  --ssl-cert-hostname origin.example.com \
  --ssl-sni-hostname origin.example.com

fastly service backend update \
  --service-id SERVICE_ID \
  --version 1 \
  --name origin \
  --autoclone \
  --weight 100

fastly service backend delete --service-id SERVICE_ID --version 1 --name origin
```

### Backend SSL

When connecting to HTTPS origins, use `--use-ssl` and set both `--ssl-cert-hostname` and `--ssl-sni-hostname`:

- `--use-ssl`: Enable SSL/TLS for connections to this backend
- `--ssl-cert-hostname`: Hostname used to verify the origin's TLS certificate
- `--ssl-sni-hostname`: Hostname sent in the TLS SNI extension during the handshake
- `--override-host`: Sets the Host header sent to the origin

Certificate verification (`ssl_check_cert`) is enabled by default — do not pass `--ssl-check-cert` (it's deprecated). Use `--no-ssl-check-cert` only if you need to disable verification.

All three hostnames should typically match the origin's hostname. Omitting `--ssl-sni-hostname` causes TLS handshake failures when the origin uses SNI-based certificate selection (shared hosting, CDNs, cloud load balancers).

For simple HTTP origins that don't require TLS, omit SSL flags and use `--port 80`:

```bash
fastly service backend create \
  --service-id SERVICE_ID \
  --version 1 \
  --name origin \
  --address origin.example.com \
  --port 80 \
  --override-host origin.example.com
```

## Domains

Domains control which hostnames route to your service.

**IMPORTANT**: There are two CLI command families with similar names but completely different behavior:

- `fastly service domain create` — version-scoped, calls `/service/{id}/version/{v}/domain`. **Use this one.**
- `fastly domain create` — calls the newer `/domain-management/v1/domains` API, uses `--fqdn` instead of `--name`, and **returns 403 Forbidden** for most accounts. Never use it.

### Test Domains

For quick testing without DNS setup, use a subdomain of `global.ssl.fastly.net`. Any name under this wildcard resolves to Fastly edge IPs and routes through the CDN, so pick any unique name and add it to your service:

```
my-project.global.ssl.fastly.net
```

This gives you a working HTTPS URL immediately — no DNS or TLS setup needed. Do not use `*.edgecompute.app` (Compute/wasm only, rejected for VCL services).

### CLI (Recommended)

Use the version-scoped `fastly service domain` commands:

```bash
fastly service domain list --service-id SERVICE_ID --version 1

fastly service domain create \
  --service-id SERVICE_ID \
  --version 1 \
  --name my-project.global.ssl.fastly.net

fastly service domain delete \
  --service-id SERVICE_ID \
  --version 1 \
  --name my-project.global.ssl.fastly.net

fastly service domain validate --version=VERSION --service-id SERVICE_ID
```

### REST API (Fallback)

Only needed if `fastly service domain create` is unavailable:

```bash
curl -s -X POST "https://api.fastly.com/service/$SERVICE_ID/version/$VERSION/domain" \
  -H "Fastly-Key: $FASTLY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"my-project.global.ssl.fastly.net"}'
```

To get `$FASTLY_API_TOKEN`, use `fastly profile token` or check the `FASTLY_API_TOKEN` environment variable.

## Healthchecks

```bash
fastly service healthcheck list --service-id SERVICE_ID --version 1

fastly service healthcheck create \
  --service-id SERVICE_ID \
  --version 1 \
  --name origin-health \
  --host origin.example.com \
  --path /health \
  --check-interval 30000 \
  --threshold 3

fastly service healthcheck update \
  --service-id SERVICE_ID \
  --version 1 \
  --name origin-health \
  --threshold 5

fastly service healthcheck delete --service-id SERVICE_ID --version 1 --name origin-health
```

## Cache Purging

```bash
fastly service purge --service-id SERVICE_ID --all
fastly service purge --service-id SERVICE_ID --key "product-123"
fastly service purge --service-id SERVICE_ID --url "https://www.example.com/page"
fastly service purge --service-id SERVICE_ID --key "product-123" --soft
fastly service purge --service-id SERVICE_ID --file=keys.txt
```

The `--file` flag accepts a path to a newline-delimited list of surrogate keys to purge.

## ACLs (Access Control Lists)

```bash
fastly service acl list --version=VERSION --service-id SERVICE_ID [--json]
fastly service acl create --version=VERSION --service-id SERVICE_ID [--name NAME] [--autoclone]
fastly service acl delete --name=NAME --version=VERSION --service-id SERVICE_ID [--autoclone]
fastly service acl describe --name=NAME --version=VERSION --service-id SERVICE_ID [--json]
fastly service acl update --name=NAME --new-name=NEW-NAME --version=VERSION --service-id SERVICE_ID [--autoclone]

fastly service acl-entry create \
  --service-id SERVICE_ID \
  --acl-id ACL_ID \
  --ip 192.168.1.0 \
  --subnet 24

fastly service acl-entry list --service-id SERVICE_ID --acl-id ACL_ID
fastly service acl-entry delete --service-id SERVICE_ID --acl-id ACL_ID --id ENTRY_ID
```

## Edge Dictionaries

```bash
fastly service dictionary list --version=VERSION --service-id SERVICE_ID [--json]
fastly service dictionary create --version=VERSION --service-id SERVICE_ID [--name NAME] [--autoclone] [--write-only]
fastly service dictionary delete --name=NAME --version=VERSION --service-id SERVICE_ID [--autoclone]
fastly service dictionary describe --name=NAME --version=VERSION --service-id SERVICE_ID [--json]
fastly service dictionary update --name=NAME --version=VERSION --service-id SERVICE_ID [--new-name] [--autoclone] [--write-only]

fastly service dictionary-entry create --dictionary-id=DICT_ID --key=KEY --value=VALUE --service-id SERVICE_ID
fastly service dictionary-entry delete --dictionary-id=DICT_ID --key=KEY --service-id SERVICE_ID
fastly service dictionary-entry describe --dictionary-id=DICT_ID --key=KEY --service-id SERVICE_ID
fastly service dictionary-entry list --dictionary-id=DICT_ID --service-id SERVICE_ID [--json]
fastly service dictionary-entry update --dictionary-id=DICT_ID --service-id SERVICE_ID [--file] [--id] [--key] [--value]
```

## Rate Limiting

```bash
fastly service rate-limit list --version=VERSION --service-id SERVICE_ID

fastly service rate-limit create \
  --service-id SERVICE_ID \
  --version 1 \
  --name api-limit \
  --rps-limit 100 \
  --window-size 60 \
  --action response \
  --response-status 429

fastly service rate-limit describe --id=ID [--json]
fastly service rate-limit update --id=ID --rps-limit 200
fastly service rate-limit delete --id=ID
```

## VCL Snippets

VCL snippets inject small blocks of VCL logic into your service without writing a full custom VCL file. The `type` controls where in the request lifecycle the snippet runs.

| Type      | Runs in       | Use for                                           |
| --------- | ------------- | ------------------------------------------------- |
| `recv`    | `vcl_recv`    | URL rewrites, redirects, access control           |
| `fetch`   | `vcl_fetch`   | Cache TTL overrides, response header manipulation |
| `deliver` | `vcl_deliver` | Add/remove response headers sent to clients       |
| `miss`    | `vcl_miss`    | Modify backend requests on cache miss             |
| `pass`    | `vcl_pass`    | Modify backend requests that bypass cache         |

### CLI

```bash
fastly vcl custom list --service-id SERVICE_ID --version 1

fastly vcl custom create \
  --service-id SERVICE_ID \
  --version 1 \
  --name main \
  --content "$(cat main.vcl)" \
  --main

fastly vcl snippet create \
  --service-id SERVICE_ID \
  --version 1 \
  --name redirect-old \
  --type recv \
  --content 'if (req.url ~ "^/old") { set req.url = "/new"; }'

fastly vcl snippet create \
  --service-id SERVICE_ID \
  --version 1 \
  --name cache-30min \
  --type fetch \
  --content 'set beresp.ttl = 1800s; set beresp.grace = 3600s;' \
  --dynamic \
  --priority 100

fastly vcl condition list --service-id SERVICE_ID --version 1
```

The `--dynamic` flag creates a dynamic snippet that can be updated without activating a new version. The `-p`/`--priority` flag controls the execution order of snippets (lower values run first).

### REST API

When creating snippets via the REST API, the `dynamic` field is **required**. Use `0` for regular (version-locked) snippets, `1` for dynamic snippets that can be updated without activating a new version.

```bash
curl -s -X POST "https://api.fastly.com/service/$SERVICE_ID/version/$VERSION/snippet" \
  -H "Fastly-Key: $FASTLY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cache-30min",
    "type": "fetch",
    "dynamic": 0,
    "priority": 100,
    "content": "set beresp.ttl = 1800s;\nset beresp.grace = 300s;"
  }'
```

## Service Alerts

```bash
fastly service alert list [--json] [--service-id] [--cursor] [--limit] [--name] [--order] [--sort]

fastly service alert create \
  --name "High Error Rate" \
  --description "Alert when 5xx errors exceed threshold" \
  --source stats \
  --type percent \
  --metric status_5xx \
  --threshold 5 \
  --period 5m \
  [--service-id SERVICE_ID] \
  [--dimensions] [--ignoreBelow] [--integrations] [--json]

fastly service alert describe --id=ID [--json]
fastly service alert delete --id=ID [--json]
fastly service alert history [--json] [--after] [--before] [--cursor] [--definition-id] [--limit] [--order] [--sort] [--service-id] [--status]

fastly service alert update \
  --id=ID \
  --name "High Error Rate" \
  --description "Alert when 5xx errors exceed threshold" \
  --source stats \
  --type percent \
  --metric status_5xx \
  --threshold 5 \
  --period 5m \
  [--dimensions] [--ignoreBelow] [--integrations] [--json]
```

## Resource Links

```bash
fastly service resource-link list --version=VERSION --service-id SERVICE_ID
fastly service resource-link create --resource-id=ID --version=VERSION --service-id SERVICE_ID [--name]
fastly service resource-link describe --id=ID --version=VERSION --service-id SERVICE_ID
fastly service resource-link update --id=ID --name=NAME --version=VERSION --service-id SERVICE_ID
fastly service resource-link delete --id=ID --version=VERSION --service-id SERVICE_ID
```

## Image Optimizer Defaults

```bash
fastly service imageoptimizer get --service-id SERVICE_ID --version 1

fastly service imageoptimizer update \
  --service-id SERVICE_ID \
  --version 1 \
  --jpeg-quality 85 \
  --webp auto
```

## Validating a Version

Always validate before activating. The CLI doesn't have a validate command, so use the REST API:

```bash
curl -s "https://api.fastly.com/service/$SERVICE_ID/version/$VERSION/validate" \
  -H "Fastly-Key: $FASTLY_API_TOKEN"
```

Returns `{"status":"ok"}` on success, or a list of errors explaining what's missing (e.g., no domain, no backend).

## Common Workflows

### Create a Caching Proxy

Set up a VCL service that caches all responses from an HTTPS origin for 30 minutes:

```bash
fastly service create --name "my-proxy" --non-interactive
# note the service ID from the output

fastly service domain create \
  --service-id $SERVICE_ID \
  --version 1 \
  --name my-proxy.global.ssl.fastly.net

fastly service backend create \
  --service-id $SERVICE_ID \
  --version 1 \
  --name origin \
  --address origin.example.com \
  --port 443 \
  --use-ssl \
  --override-host origin.example.com \
  --ssl-cert-hostname origin.example.com \
  --ssl-sni-hostname origin.example.com

fastly vcl snippet create \
  --service-id $SERVICE_ID \
  --version 1 \
  --name cache-30min \
  --type fetch \
  --content 'set beresp.ttl = 1800s; set beresp.grace = 300s;'

fastly service version activate --service-id $SERVICE_ID --version 1

# wait ~15s for propagation, then test
curl -sI https://my-proxy.global.ssl.fastly.net/
curl -sI https://my-proxy.global.ssl.fastly.net/  # should show X-Cache: HIT
```

### Create New Service with Backend

```bash
fastly service create --name "My CDN" --non-interactive
# note the service ID from the output

fastly service domain create \
  --service-id $SERVICE_ID \
  --version 1 \
  --name my-cdn.global.ssl.fastly.net

fastly service backend create \
  --service-id $SERVICE_ID \
  --version 1 \
  --name origin \
  --address origin.example.com

fastly service version activate --service-id $SERVICE_ID --version 1
```

### Update Live Service Safely

```bash
fastly service backend update \
  --service-id SERVICE_ID \
  --version active \
  --autoclone \
  --name origin \
  --address new-origin.example.com
fastly service version activate --service-id SERVICE_ID --version latest
```

### Rollback to Previous Version

```bash
fastly service version activate --service-id SERVICE_ID --version 1
```

## Propagation Delays

After activating a service version, allow time for changes to propagate across Fastly's network before testing. New service activations typically propagate within 15-30 seconds, but changes can take up to 10 minutes to reach all POPs. If a request returns "Domain Not Found" or "Service Not Found" right after activation, retry after a few seconds.

## Dangerous Operations

Ask the user for explicit confirmation before running these commands:

- `fastly service delete` - Permanently deletes a service and all its versions
- `fastly service purge --all` - Purges entire cache, causing origin load spike
- `fastly service version deactivate` - Takes a live service offline

These operations are irreversible or have significant production impact.

## Global Flags

These flags work with most service commands:

- `--service-id SERVICE_ID` or `-s SERVICE_ID`: Target service
- `--version VERSION`: Target version (use "active" or "latest" as shortcuts)
- `--autoclone`: Automatically clone if version is locked/active
- `--json`: Output in JSON format
- `--verbose`: Detailed output

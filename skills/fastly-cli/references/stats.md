# Fastly Statistics and Analytics

Access historical, real-time, and aggregated metrics for Fastly services.

## Command Overview

| Command                  | Description                    |
| ------------------------ | ------------------------------ |
| `stats aggregate`        | Aggregated historical stats    |
| `stats domain-inspector` | Domain inspector stats         |
| `stats historical`       | Historical stats for a service |
| `stats origin-inspector` | Origin inspector stats         |
| `stats realtime`         | Real-time stats for a service  |
| `stats regions`          | List stats regions             |
| `stats usage`            | Usage stats                    |

## Two Flag Families

`fastly stats` fronts two unrelated APIs. `historical`, `aggregate` and `usage` speak the Historical Stats API;
`domain-inspector` and `origin-inspector` speak the Inspector metrics API. They share `--from`, `--to`, `--region`
and `--json`, but nothing else: granularity and selection use different flag names on each side.
Reaching for `--by` or `--field` on an inspector, or `--datacenter` on `historical`, fails with a usage error.

| Flag                       | historical | aggregate | usage | domain-inspector | origin-inspector |
| -------------------------- | ---------- | --------- | ----- | ---------------- | ---------------- |
| `--from` / `--to`          | yes        | yes       | yes   | yes              | yes              |
| `--by` (minute/hour/day)   | yes        | yes       | yes   | no               | no               |
| `--downsample`             | no         | no        | no    | yes              | yes              |
| `--field` (single field)   | yes        | no        | no    | no               | no               |
| `--metric` (repeatable)    | no         | no        | no    | yes              | yes              |
| `--region`                 | one value  | one value | one value | repeatable   | repeatable       |
| `--datacenter`             | no         | no        | no    | repeatable       | repeatable       |
| `--domain`                 | no         | no        | no    | repeatable       | no               |
| `--host`                   | no         | no        | no    | no               | repeatable       |
| `--group-by`               | no         | no        | no    | repeatable       | repeatable       |
| `--limit` / `--cursor`     | no         | no        | no    | yes              | yes              |
| `--by-service`             | no         | no        | yes   | no               | no               |
| `--service-id` / `--service-name` | yes | no        | no    | yes              | yes              |
| `--json`                   | yes        | yes       | yes   | yes              | yes              |

`stats realtime` takes no filtering flags at all: only `--service-id` / `--service-name` and `--json`.
`stats regions` takes no flags whatsoever, not even `--json`.

## Aggregate Statistics

Query aggregated historical stats across every service on the account. There is no `--service-id` here, and no
`--field`: the only filters are `--from`, `--to`, `--by` and `--region`.

```bash
# Aggregated stats
fastly stats aggregate

# Specific time range
fastly stats aggregate \
  --from "2024-01-01T00:00:00Z" \
  --to "2024-01-02T00:00:00Z"

# JSON output
fastly stats aggregate --json
```

## Historical Statistics

Query aggregated metrics over time periods.

```bash
# Basic historical stats
fastly stats historical --service-id SERVICE_ID

# Specific time range
fastly stats historical \
  --service-id SERVICE_ID \
  --from "2024-01-01T00:00:00Z" \
  --to "2024-01-02T00:00:00Z"

# Filter by region
fastly stats historical --service-id SERVICE_ID --region europe

# Filter to a single stats field
fastly stats historical --service-id SERVICE_ID --field bandwidth

# Aggregation period: minute, hour, or day (no "month")
fastly stats historical --service-id SERVICE_ID --by day

# JSON output for processing
fastly stats historical --service-id SERVICE_ID --json
```

There is no `--datacenter` on `historical`: `--region` is as narrow as the CLI goes. Per-POP history is only
reachable through the Historical Stats API directly, which the CLI does not expose. The inspectors do take
`--datacenter`, but they cover domain and origin metrics rather than plain service traffic.

### Available Fields

These are the values accepted by `--field` on `stats historical`, and a small excerpt of the keys present in the JSON
output of `historical` and `aggregate` (which carry well over a hundred each). They are not inspector metric names:
`domain-inspector` and `origin-inspector` take their own vocabulary via `--metric`.

`stats usage` is shaped differently again: its JSON is an object keyed by region, and each region carries only
`bandwidth`, `compute_requests` and `requests`.

| Field        | Description               |
| ------------ | ------------------------- |
| `requests`   | Total requests            |
| `hits`       | Cache hits                |
| `miss`       | Cache misses              |
| `pass`       | Requests passed to origin |
| `bandwidth`  | Total bandwidth (bytes)   |
| `status_1xx` | 1xx responses             |
| `status_2xx` | 2xx responses             |
| `status_3xx` | 3xx responses             |
| `status_4xx` | 4xx responses             |
| `status_5xx` | 5xx responses             |
| `hit_ratio`  | Cache hit ratio           |
| `errors`     | Error count               |

## Domain Inspector Statistics

Inspect domain-level metrics for your service. Useful for understanding traffic patterns and performance on a
per-domain basis.

Flags: `--from`, `--to`, `--downsample` (minute/hour/day), `--metric` (repeatable, up to 10), `--domain`,
`--datacenter`, `--region`, `--group-by`, `--limit`, `--cursor`, `--json`. The repeatable flags are joined with commas
before the request goes out, so repeating the flag and passing one comma-separated value are equivalent.

```bash
# Domain inspector stats
fastly stats domain-inspector --service-id SERVICE_ID

# Specific time range, hourly buckets
fastly stats domain-inspector --service-id SERVICE_ID \
  --from "2026-08-01T00:00:00Z" \
  --to "2026-08-02T00:00:00Z" \
  --downsample hour

# Pick metrics and break them down per domain
fastly stats domain-inspector --service-id SERVICE_ID \
  --metric requests --metric bandwidth \
  --group-by domain --json

# Narrow to one domain served from one POP
fastly stats domain-inspector --service-id SERVICE_ID \
  --domain www.example.com --datacenter BWI

# Page through a large result set
fastly stats domain-inspector --service-id SERVICE_ID --limit 100 --json
fastly stats domain-inspector --service-id SERVICE_ID --limit 100 --cursor CURSOR --json
```

Read `meta.next_cursor` from the JSON response and feed it back as `--cursor` until it comes back empty.

## Origin Inspector Statistics

Inspect origin-level metrics for your service. Helps identify origin health issues, latency, and request volume per
origin.

Same flag set as the domain inspector, except that the per-entity filter is `--host` (origin hostname) rather than
`--domain`.

```bash
# Origin inspector stats
fastly stats origin-inspector --service-id SERVICE_ID

# Daily responses grouped by origin host
fastly stats origin-inspector --service-id SERVICE_ID \
  --from "2026-08-01T00:00:00Z" \
  --to "2026-08-07T00:00:00Z" \
  --downsample day --metric responses --group-by host --json

# One origin, one region
fastly stats origin-inspector --service-id SERVICE_ID \
  --host origin.example.com --region europe
```

### Inspectors Return Empty Data When the Product Is Off

Domain Inspector and Origin Inspector are paid add-ons. If they are not enabled on the service, the API still answers
`"status": "success"` with an empty `data` array, which reads exactly like a service that had no traffic. Check the
entitlement before concluding there is nothing to see:

```bash
fastly products --service-id SERVICE_ID
```

## Real-time Statistics

Stream live metrics from your service.

```bash
# Real-time stats (updates every second)
fastly stats realtime --service-id SERVICE_ID

# JSON output
fastly stats realtime --service-id SERVICE_ID --json
```

Real-time stats show:
- Requests per second
- Bandwidth
- Cache hit ratio
- Error rates
- Response times

## Usage Statistics

View usage stats across your account, including bandwidth and request totals.

```bash
# Usage stats
fastly stats usage

# Specific time range
fastly stats usage \
  --from "2024-01-01T00:00:00Z" \
  --to "2024-01-02T00:00:00Z"

# Break down usage by service
fastly stats usage --by-service

# JSON output
fastly stats usage --json
```

## Regional Statistics

`historical`, `aggregate`, `usage` and both inspectors accept `--region`. On the first three it takes a single value;
on the inspectors it is repeatable. `realtime` and `regions` accept no filtering flags at all.

```bash
# List available regions
fastly stats regions

# Filter stats to a specific region
fastly stats historical --service-id SERVICE_ID --region europe --json --by day

# Inspectors: repeat the flag for several regions
fastly stats origin-inspector --service-id SERVICE_ID --region europe --region usa
```

### Regions

| Region             | Description           |
| ------------------ | --------------------- |
| `usa`              | United States         |
| `europe`           | Europe                |
| `asia`             | Asia Pacific          |
| `asia_india`       | India                 |
| `asia_southkorea`  | South Korea           |
| `anzac`            | Australia/New Zealand |
| `africa_std`       | Africa                |
| `latam`            | Latin America         |
| `mexico`           | Mexico                |
| `saudi_arabia`     | Saudi Arabia          |
| `southamerica_std` | South America         |

## Infrastructure Information

```bash
# List Fastly datacenter POPs. No `pops list`; no `pops --json`.
# For shielding, copy the SHIELD column value, not the CODE column.
fastly pops

# List Fastly public IP ranges
fastly ip-list
```

Use IP ranges for:
- Firewall allowlists at origin
- Identifying Fastly traffic
- Security group configuration

## Common Use Cases

### Check Cache Performance

```bash
# Get hit ratio over last day
fastly stats historical \
  --service-id SERVICE_ID \
  --from "24 hours ago" \
```

### Monitor Error Rates

```bash
# Check 5xx errors over the last day
fastly stats historical --service-id SERVICE_ID --json --by hour \
  | jq -s '[.[].status_5xx] | add'

# Real-time error monitoring
fastly stats realtime --service-id SERVICE_ID
```

### Bandwidth Analysis

```bash
# Total bandwidth over last 7 days
fastly stats historical --service-id SERVICE_ID --json --by day \
  --from "7 days ago" | jq -s '[.[].bandwidth] | add'
```

### Regional Traffic Analysis

```bash
# Bandwidth from Europe
fastly stats historical --service-id SERVICE_ID --json --by day \
  --region europe | jq -s '[.[].bandwidth] | add'
```

## JSON Output Format

With `--json`, each line is a separate JSON object (one per aggregation period). Lines are **not** wrapped in an array or envelope. Use `jq -s` (slurp) to collect them into an array for aggregation:

```bash
# Human-readable (default)
fastly stats historical --service-id SERVICE_ID

# JSON output — one JSON object per line
fastly stats historical --service-id SERVICE_ID --json --by day

# Sum bandwidth across all days
fastly stats historical --service-id SERVICE_ID --json --by day \
  --from "2026-02-01" --to "2026-03-01" \
  | jq -s '[.[].bandwidth] | add'

# Extract per-day request counts
fastly stats historical --service-id SERVICE_ID --json --by day \
  | jq -s '.[] | {start_time, requests}'
```

## Cross-Service Aggregation

The CLI has no built-in cross-service stats. Loop over services to compare:

```bash
fastly service list --json | jq -r '.[] | "\(.ServiceID)|\(.Name)"' | while IFS='|' read -r id name; do
  bw=$(fastly stats historical -s "$id" --json --by day \
    --from "2026-02-01" --to "2026-03-01" \
    | jq -s '[.[].bandwidth] | add // 0')
  echo "${bw} ${name}"
done | sort -rn
```

## Integration Examples

### Export to CSV

```bash
fastly stats historical \
  --service-id SERVICE_ID \
  --json --by day | jq -rs '
  .[] | [.start_time, .requests, .hits, .miss, .bandwidth] | @csv
' > stats.csv
```

### Monitor with Watch

```bash
# Update stats every 5 seconds
watch -n 5 'fastly stats realtime --service-id SERVICE_ID'
```

### Alert on High Error Rate

```bash
#!/bin/bash
errors=$(fastly stats historical --service-id SERVICE_ID --json --by hour \
  | jq -s '.[-1].status_5xx')
if [ "$errors" -gt 100 ]; then
  echo "High error rate: $errors"
fi
```

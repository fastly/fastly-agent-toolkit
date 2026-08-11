# Fastly Statistics and Analytics

`fastly stats` fronts two unrelated APIs and their flags do not overlap. This file is the flag
reference. For choosing an endpoint, unit conventions, window handling and worked queries, use the
`fastly-stats` skill, which owns those.

| Command                  | Description                    |
| ------------------------ | ------------------------------ |
| `stats aggregate`        | Aggregated historical stats    |
| `stats domain-inspector` | Domain inspector stats         |
| `stats historical`       | Historical stats for a service |
| `stats origin-inspector` | Origin inspector stats         |
| `stats realtime`         | Real-time stats for a service  |
| `stats regions`          | List stats regions             |
| `stats usage`            | Usage stats                    |

`historical`, `aggregate` and `usage` speak the Historical Stats API; `domain-inspector` and
`origin-inspector` speak the Inspector metrics API. They share `--from`, `--to`, `--region` and
`--json`, but nothing else: granularity and selection use different flag names on each side.
Reaching for `--by` or `--field` on an inspector, or `--datacenter` on `historical`, fails with a
usage error.

| Flag                              | historical | aggregate | usage     | domain-inspector | origin-inspector |
| --------------------------------- | ---------- | --------- | --------- | ---------------- | ---------------- |
| `--from` / `--to`                 | yes        | yes       | yes       | yes              | yes              |
| `--by` (minute/hour/day)          | yes        | yes       | yes       | no               | no               |
| `--downsample`                    | no         | no        | no        | yes              | yes              |
| `--field` (single field)          | yes        | no        | no        | no               | no               |
| `--metric` (repeatable, max 10)   | no         | no        | no        | yes              | yes              |
| `--region`                        | one value  | one value | one value | repeatable       | repeatable       |
| `--datacenter`                    | no         | no        | no        | repeatable       | repeatable       |
| `--domain`                        | no         | no        | no        | repeatable       | no               |
| `--host`                          | no         | no        | no        | no               | repeatable       |
| `--group-by`                      | no         | no        | no        | repeatable       | repeatable       |
| `--limit` / `--cursor`            | no         | no        | no        | yes              | yes              |
| `--by-service`                    | no         | no        | yes       | no               | no               |
| `--service-id` / `--service-name` | yes        | no        | no        | yes              | yes              |
| `--json`                          | yes        | yes       | yes       | yes              | yes              |

`stats realtime` takes no filtering flags at all: only `--service-id` / `--service-name` and
`--json`. `stats regions` takes no flags whatsoever, not even `--json`.

The repeatable flags are joined with commas before the request goes out, so repeating the flag and
passing one comma-separated value are equivalent.

`--json` emits NDJSON, one object per line with no wrapping array. Use `jq -s` to slurp before
aggregating.

Read `meta.next_cursor` from an inspector response and feed it back as `--cursor` until it comes
back empty, or the result is silently truncated at `--limit` rows.

## Infrastructure Information

```bash
# List Fastly datacenter POPs. No `pops list`; no `pops --json`.
# For shielding, copy the SHIELD column value, not the CODE column.
fastly pops

# List Fastly public IP ranges
fastly ip-list
```

Use IP ranges for firewall allowlists at origin, identifying Fastly traffic, and security group
configuration.

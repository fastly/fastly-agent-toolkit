# Notification Integrations and Audit Log Event Mappings

Two command groups work together: `fastly integration` defines *where* a notification goes, and `fastly audit-log event-mapping` defines *what* triggers one.
Create the integration first, then map audit events to its ID.

These are account-level and do not take `--service-id` or `--version`.

## Integrations

```bash
# What integration types this account supports
fastly integration list-types --json

# List, describe, delete
fastly integration list --type=slack --limit=50 --json
fastly integration describe INTEGRATION_ID --json
fastly integration delete INTEGRATION_ID
```

`describe`, `delete`, `update` and the webhook signing-key commands take the integration ID as a **positional argument**, not a flag.
`list` paginates with `--cursor` and `--limit`.

### Creating an integration

Each type is its own subcommand with its own required flags:

```bash
fastly integration slack create --name=sec-alerts --webhook="https://hooks.slack.com/..."
fastly integration webhook create --name=internal --webhook="https://example.com/hook"
fastly integration mail create --name=oncall --address=oncall@example.com
fastly integration pagerduty create --name=pd --key=PAGERDUTY_INTEGRATION_KEY
fastly integration datadog create --name=dd --api-key=DD_API_KEY --site=datadoghq.eu
fastly integration msteams create --name=teams --webhook="https://outlook.office.com/webhook/..."
fastly integration newrelic create --name=nr --account-id=ACCOUNT_ID --api-key=NR_API_KEY
fastly integration opsgenie create --name=og --api-key=OPSGENIE_API_KEY
fastly integration splunkoncall create --name=voc --url="https://alert.victorops.com/..."
fastly integration jsm create --name=jsm --api-key=JSM_API_KEY
fastly integration jiraissue create --name=jira \
  --base-url=https://example.atlassian.net \
  --username=bot@example.com --api-token=JIRA_API_TOKEN \
  --project-key=SEC --issue-type=Task
```

Every type also has `update`, taking the ID positionally: `fastly integration slack update INTEGRATION_ID --webhook=...`.

A mailing list address has to confirm before it receives anything: `fastly integration mail confirm someone@example.com`.

Webhook integrations sign their payloads. Fetch or rotate the key with:

```bash
fastly integration webhook get-signing-key INTEGRATION_ID --json
fastly integration webhook rotate-signing-key INTEGRATION_ID --json
```

## Audit log event mappings

```bash
# Discover the valid scope and event types before creating a mapping
fastly audit-log event-mapping list-scope-types --json
fastly audit-log event-mapping list-event-types --scope-type=vcl --json

# Create a mapping
fastly audit-log event-mapping create \
  --name="prod service changes" \
  --scope-type=vcl \
  --scope-id=SERVICE_ID \
  --event-type=version.activate,backend.delete \
  --integration-id=INTEGRATION_ID \
  --json

# List and filter
fastly audit-log event-mapping list --scope-type=vcl --integration-id=INTEGRATION_ID --json

# Describe and delete take --id, not a positional argument
fastly audit-log event-mapping describe --id=MAPPING_ID --json
fastly audit-log event-mapping delete --id=MAPPING_ID
```

`--scope-type` is one of `account`, `vcl`, `wasm`, `ngwaf`.
Omit `--scope-id` to cover every resource of that scope type; repeat the flag (or pass a comma-separated list) to cover several.
`--event-type` and `--integration-id` work the same way.

**`update` replaces the whole mapping.** It requires `--id`, `--name`, `--scope-type`, `--event-type` and `--integration-id` even when only one of them changes, so read the current mapping with `describe --json` first and pass everything back:

```bash
fastly audit-log event-mapping update \
  --id=MAPPING_ID \
  --name="prod service changes" \
  --scope-type=vcl \
  --scope-id=SERVICE_ID \
  --event-type=version.activate,backend.delete,domain.create \
  --integration-id=INTEGRATION_ID
```

## Dangerous Operations

Ask the user for explicit confirmation before running these commands:

- `fastly integration delete` - Silently stops every mapping pointing at that integration from delivering
- `fastly audit-log event-mapping delete` - Stops notifications for those events
- `fastly integration webhook rotate-signing-key` - Breaks any receiver still verifying with the old key

# Notification Integrations and Audit Log Event Mappings

`fastly integration` defines where a notification goes. `fastly audit-log event-mapping` defines what triggers one.
Create the integration first, then map audit events to its ID.

Both are account-level. Neither takes `--service-id` or `--version`.

## Integrations

```bash
fastly integration list-types --json
fastly integration list --type=slack --limit=50 --cursor=CURSOR --json
fastly integration describe INTEGRATION_ID --json
fastly integration delete INTEGRATION_ID
```

`describe`, `delete`, `update`, `get-signing-key` and `rotate-signing-key` take the ID as a positional argument, not a flag.

### Create

One subcommand per type, each with its own required flags:

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

Every type has a matching `update`, ID positional: `fastly integration slack update INTEGRATION_ID --webhook=...`.

`--description` is optional on every `create` and `update`. `--site` on datadog defaults to the US site.

### Mailing lists and webhook signing

```bash
# A mailing list address receives nothing until it confirms
fastly integration mail confirm someone@example.com

# Webhook integrations sign their payloads
fastly integration webhook get-signing-key INTEGRATION_ID --json
fastly integration webhook rotate-signing-key INTEGRATION_ID --json
```

## Audit log event mappings

```bash
# Valid values for --scope-type and --event-type
fastly audit-log event-mapping list-scope-types --json
fastly audit-log event-mapping list-event-types --scope-type=vcl --json

fastly audit-log event-mapping create \
  --name="prod service changes" \
  --scope-type=vcl \
  --scope-id=SERVICE_ID \
  --event-type=version.activate,backend.delete \
  --integration-id=INTEGRATION_ID \
  --json

fastly audit-log event-mapping list --scope-type=vcl --integration-id=INTEGRATION_ID --json
fastly audit-log event-mapping describe --id=MAPPING_ID --json
fastly audit-log event-mapping delete --id=MAPPING_ID
```

`describe`, `delete` and `update` take `--id`, not a positional argument. This is the opposite of `fastly integration`.

`--scope-type` is one of `account`, `vcl`, `wasm`, `ngwaf`.

`--scope-id`, `--event-type` and `--integration-id` are repeatable and also accept comma-separated lists.
Omit `--scope-id` to cover every resource of that scope type.

`list` filters on `--integration-id`, `--mapping-status`, `--name`, `--scope-id`, `--scope-type` and `--sort`.

### update replaces the whole mapping

It requires `--id`, `--name`, `--scope-type`, `--event-type` and `--integration-id` even to change one field.
Read the current mapping first and pass everything back:

```bash
fastly audit-log event-mapping describe --id=MAPPING_ID --json

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

- `fastly integration delete` - Every mapping pointing at that integration silently stops delivering
- `fastly audit-log event-mapping delete` - Stops notifications for those events
- `fastly integration webhook rotate-signing-key` - Breaks receivers still verifying with the old key

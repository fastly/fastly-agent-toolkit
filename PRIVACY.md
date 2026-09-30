# Privacy and data handling

Fastly Agent Toolkit packages instructions, reference files, examples, and two shell helpers for coding agents.

It has no hosted toolkit backend or telemetry collector.
The data used by a workflow depends on the task you authorize and the tools you run.

## Local files and credentials

Coding workflows may read project source, VCL, service configuration, and test fixtures, and may create build outputs or reports on your machine.

Your coding agent handles the prompts, files, and command results you share with it under that agent provider's policies and your settings.

Review those settings before working with private project or account data.

Configure Fastly credentials yourself through interactive CLI login, the CLI's local configuration, or environment variables.

The NGWAF helper reads `FASTLY_API_KEY` from its environment and uses it to authenticate requests to Fastly.

API examples use locally configured credentials in the same way.
Never paste credentials into chat, commit them, or include them in public examples or reports.

The toolkit does not maintain a separate credential store.
Stored CLI credentials remain subject to your local configuration and Fastly token settings.

You can remove them locally or revoke them through Fastly's account controls.

Local project files and saved reports remain until you remove them.

## Fastly account operations

Authenticated workflows send the parameters needed for the requested operation to Fastly and may return service identifiers, configuration, traffic statistics, protection rules, or request-log details.

Those results can contain private account information or personal data from your existing services.
Share only the data needed for the task and avoid including unrelated records in conversation output or support reports.

Operations that modify a service or deploy an application change the Fastly account you have selected.

Fastly's [privacy policy](https://www.fastly.com/privacy), [terms of service](https://www.fastly.com/terms), and your service agreement describe Fastly's data practices and the terms applicable to your account.

This toolkit does not set a separate retention period for data held by Fastly or by your coding agent provider.

## Public Fastly Fiddle uploads

Creating or updating a fiddle uploads VCL, request specifications, and any supplied test data to Fastly Fiddle.

Fiddles are public by default and can be opened through their shareable URLs.
Execution may also send the configured requests to the origin endpoints in the specification.

Use Fiddle only when public publication is part of the task you authorize.
Do not upload credentials, private origin addresses, personal data, or confidential code.

For private fixtures, use local Falco tests instead.

A local helper's temporary-file cleanup does not remove a published fiddle from Fastly.

## Support and privacy questions

Use the [toolkit issue tracker](https://github.com/fastly/fastly-agent-toolkit/issues) for questions and bugs, and remove private data from public reports.

Report security issues privately as described in [SECURITY.md](SECURITY.md).

For Fastly privacy questions or requests about data held by Fastly, use the contact information in [Fastly's privacy policy](https://www.fastly.com/privacy).

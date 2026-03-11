# Fastly TLS Certificate Management

Configure TLS/HTTPS for Fastly services with custom certificates or Fastly-managed TLS.

## TLS Options Overview

| Option       | Description                        | Best For                          |
| ------------ | ---------------------------------- | --------------------------------- |
| Platform TLS | Fastly-managed shared certificates | Quick setup, standard domains     |
| Custom TLS   | Your own certificates              | Enterprise, specific requirements |
| Subscription | Auto-renewed Let's Encrypt         | Automated certificate management  |

## Platform TLS

Fastly-managed TLS for large numbers of domains.

```bash
# List platform TLS configurations
fastly tls-platform list [--json]

# Upload platform TLS certificate
fastly tls-platform upload \
  --cert-blob "$(cat certificate.crt)" \
  --intermediates-blob "$(cat chain.crt)"

# Describe configuration
fastly tls-platform describe --id PLATFORM_ID [--json]

# Update platform TLS certificate
fastly tls-platform update \
  --id PLATFORM_ID \
  --cert-blob "$(cat new-certificate.crt)" \
  --intermediates-blob "$(cat new-chain.crt)"

# Delete platform TLS
fastly tls-platform delete --id PLATFORM_ID
```

## TLS Subscriptions (Let's Encrypt)

Automatically provisioned and renewed certificates.

```bash
# List subscriptions
fastly tls-subscription list [--json]

# Create subscription
fastly tls-subscription create \
  --domain www.example.com \
  --certificate-authority lets-encrypt

# Describe subscription
fastly tls-subscription describe --id SUBSCRIPTION_ID [--json]

# Update subscription
fastly tls-subscription update --id SUBSCRIPTION_ID

# Delete subscription
fastly tls-subscription delete --id SUBSCRIPTION_ID
```

## Custom TLS Certificates

Upload and manage your own certificates.

### Private Keys

```bash
# List private keys
fastly tls-custom private-key list [--json]

# Upload private key
fastly tls-custom private-key create \
  --name my-key \
  --key "$(cat private.key)"

# Describe key
fastly tls-custom private-key describe --id KEY_ID [--json]

# Delete key
fastly tls-custom private-key delete --id KEY_ID
```

### Certificates

```bash
# List certificates
fastly tls-custom certificate list [--json]

# Upload certificate
fastly tls-custom certificate create \
  --cert-blob "$(cat certificate.crt)" \
  --name my-cert

# Describe certificate
fastly tls-custom certificate describe --id CERT_ID [--json]

# Update certificate (replace)
fastly tls-custom certificate update \
  --id CERT_ID \
  --cert-blob "$(cat new-certificate.crt)"

# Delete certificate
fastly tls-custom certificate delete --id CERT_ID
```

### TLS Activations

Link certificates to domains.

```bash
# List activations
fastly tls-custom activation list [--json]

# Enable activation (link cert to domain)
fastly tls-custom activation enable \
  --cert-id CERT_ID \
  --tls-config-id CONFIG_ID \
  --tls-domain www.example.com

# Describe activation
fastly tls-custom activation describe --id ACTIVATION_ID [--json]

# Update activation (switch to a different certificate)
fastly tls-custom activation update \
  --cert-id NEW_CERT_ID \
  --id ACTIVATION_ID

# Disable activation (remove TLS from domain)
fastly tls-custom activation disable --id ACTIVATION_ID
```

### TLS Domains

```bash
# List TLS domains
fastly tls-custom domain list

# Filter by certificate
fastly tls-custom domain list --filter-tls-certificate-id CERT_ID
```

## TLS Configuration Options

Configure TLS settings per domain.

```bash
# List TLS configs
fastly tls-config list [--json]

# Describe TLS config
fastly tls-config describe --id CONFIG_ID [--json]

# Update TLS config
fastly tls-config update \
  --id CONFIG_ID \
  --name updated-config
```

## Common Workflows

### Setup Let's Encrypt TLS

```bash
# 1. Add domain to your service
fastly service domain create --service-id SERVICE_ID --version 1 --name www.example.com
fastly service version activate --service-id SERVICE_ID --version 1

# 2. Create TLS subscription
fastly tls-subscription create --domain www.example.com --certificate-authority lets-encrypt

# 3. Complete DNS validation (follow instructions in output)
# Add CNAME record as instructed

# 4. Wait for certificate issuance (usually minutes)
fastly tls-subscription describe --id SUBSCRIPTION_ID
```

### Upload Custom Certificate

```bash
# 1. Upload private key
fastly tls-custom private-key create --name my-key --key "$(cat private.key)"

# 2. Upload certificate
fastly tls-custom certificate create \
  --cert-blob "$(cat certificate.crt)" \
  --name my-cert

# 3. Enable certificate for domain
# First, find the TLS config ID
fastly tls-config list

# Then enable activation
fastly tls-custom activation enable \
  --cert-id CERT_ID \
  --tls-config-id CONFIG_ID \
  --tls-domain www.example.com
```

### Renew Custom Certificate

```bash
# 1. Upload new certificate (same key)
fastly tls-custom certificate update \
  --id CERT_ID \
  --cert-blob "$(cat new-certificate.crt)"

# Certificate is automatically used for existing activations
```

### Replace Certificate and Key

```bash
# 1. Upload new private key
fastly tls-custom private-key create --name new-key --key "$(cat new-private.key)"

# 2. Upload new certificate
fastly tls-custom certificate create \
  --cert-blob "$(cat new-certificate.crt)" \
  --name new-cert

# 3. Update activation to use new certificate
fastly tls-custom activation update \
  --cert-id NEW_CERT_ID \
  --id ACTIVATION_ID

# 4. Clean up old resources
fastly tls-custom certificate delete --id OLD_CERT_ID
fastly tls-custom private-key delete --id OLD_KEY_ID
```

### Add Domain to Existing Subscription

```bash
# Get current subscription details
fastly tls-subscription describe --id SUBSCRIPTION_ID

# Update subscription
fastly tls-subscription update --id SUBSCRIPTION_ID
```

## Certificate Requirements

### Custom Certificate Format
- PEM-encoded X.509 certificate
- RSA (2048-bit minimum) or ECDSA key
- Include intermediate certificates for platform TLS via `--intermediates-blob`

### Domain Validation
- DNS CNAME validation for Let's Encrypt
- Domain must be routed through Fastly before activation

## Propagation Delays

TLS changes can take up to 5 minutes to propagate globally:
- Certificate uploads and activations: 1-5 minutes
- TLS subscription creation: Minutes to hours (includes DNS validation and certificate issuance)
- Certificate renewals: Automatic, no propagation delay once issued

Automation scripts should poll subscription/activation status rather than assuming immediate availability. For certificate activations, verify HTTPS connectivity with retries before considering the operation complete.

## Dangerous Operations

Ask the user for explicit confirmation before running these commands:

- `fastly tls-platform delete` - Removes TLS for all domains in the configuration
- `fastly tls-subscription delete` - Deletes Let's Encrypt certificate subscription
- `fastly tls-custom certificate delete` - Deletes a custom certificate
- `fastly tls-custom private-key delete` - Deletes a private key
- `fastly tls-custom activation disable` - Removes TLS from a domain

These operations can cause HTTPS to stop working for affected domains.

## Troubleshooting

**Certificate not working**: Ensure domain points to Fastly (CNAME to `*.global.fastly.net`)

**Subscription pending**: DNS validation incomplete. Check CNAME records.

**Chain validation error**: Include intermediate certificates with `--intermediates-blob` when using platform TLS

**Private key mismatch**: Ensure certificate matches uploaded private key

# Caching and delivery reference architectures

## vcl_shielding — custom origin shielding topology
- **Repo:** github.com/bharwani/vcl_shielding
- **Source:** community (bharwani)
- **Demonstrates:** shielding topology decisions driven by network peering/IX considerations, not just Fastly's default shield selection.
- **Watch out for:** none known as of last verification.
- **Last verified:** 2026-08-19

## fastly-bulk-redirects — bulk redirect / delivery routing
- **Repo:** github.com/Fcuervo21/fastly-bulk-redirects
- **Source:** community (Fcuervo21)
- **Demonstrates:** storing a large source-to-destination redirect table in Config Store and serving lookups from a Compute edge worker, instead of an origin-side `map` block, app middleware, or per-redirect VCL rules.
- **Watch out for:** none known as of last verification.
- **Last verified:** 2026-08-19

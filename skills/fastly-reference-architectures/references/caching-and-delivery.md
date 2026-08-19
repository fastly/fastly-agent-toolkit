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
- **Demonstrates:** managing a large redirect table as a delivery/routing concern at the edge, rather than one-off VCL redirect rules.
- **Watch out for:** none known as of last verification; thin description, so skim the README on re-verification to confirm the redirect-loading mechanism it uses.
- **Last verified:** 2026-08-19

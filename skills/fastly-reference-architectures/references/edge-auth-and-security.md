# Edge auth and security reference architectures

### google-apple-github-auth — OAuth via Compute
- **Repo:** github.com/bharwani/google-apple-github-auth
- **Source:** community (bharwani)
- **Demonstrates:** OAuth/social-login authentication implemented at the edge in Compute — the JWT/edge-auth pattern this file exists for.
- **Watch out for:** none known as of last verification (thin README beyond the description; verify the OAuth flow still matches current provider requirements before modeling new code closely after it).
- **Last verified:** 2026-08-19

### fastly-compute-news-with-content-paywall — access control / paywall at the edge
- **Repo:** github.com/saschanowak/fastly-compute-news-with-content-paywall
- **Source:** community (saschanowak)
- **Demonstrates:** authorization/paywall gating of content at the edge — an access-control pattern distinct from authentication.
- **Watch out for:** none known as of last verification.
- **Last verified:** 2026-08-19

### injection-classifier-poc — ML-based security classifier at the edge
- **Repo:** github.com/fastly/injection-classifier-poc
- **Source:** official (fastly org)
- **Demonstrates:** running a quantized ML model for security classification directly in a Compute WASM service — a distinct pattern from rule-based WAF/NGWAF.
- **Watch out for:** explicitly a "proof of concept," not a maintained product — check the linked model card/HuggingFace model is still the recommended one before reuse.
- **Last verified:** 2026-08-19

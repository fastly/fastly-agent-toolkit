# Edge auth and security reference architectures

## google-apple-github-auth — OAuth via Compute
- **Repo:** github.com/bharwani/google-apple-github-auth
- **Source:** community (bharwani)
- **Demonstrates:** verifying two distinct federated-login flows (OIDC JWT for Google/Apple, OAuth2 for GitHub) entirely in Compute, with no origin server.
- **Watch out for:** verify the OAuth/OIDC flows still match current provider requirements before modeling new code closely after it — identity-provider integration details shift over time.
- **Last verified:** 2026-08-19

## fastly-compute-news-with-content-paywall — access control / paywall at the edge
- **Repo:** github.com/saschanowak/fastly-compute-news-with-content-paywall
- **Source:** community (saschanowak)
- **Demonstrates:** authorization/paywall gating of content at the edge — an access-control pattern distinct from authentication.
- **Watch out for:** none known as of last verification.
- **Last verified:** 2026-08-19

## injection-classifier-poc — ML-based prompt-injection classifier at the edge
- **Repo:** github.com/fastly/injection-classifier-poc
- **Source:** official (fastly org)
- **Demonstrates:** running a quantized ML model for prompt-injection classification (SAFE vs. INJECTION on LLM-bound text) directly in a Compute WASM service — a distinct pattern from rule-based WAF/NGWAF, and distinct from request-level attack detection (SQLi/XSS).
- **Watch out for:** explicitly a "proof of concept," not a maintained product — check the linked model card/HuggingFace model is still the recommended one before reuse.
- **Last verified:** 2026-08-19

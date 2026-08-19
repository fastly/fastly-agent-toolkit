# Compute application pattern reference architectures

## fastly-edge-ab-testing — A/B testing at the edge
- **Repo:** github.com/Fcuervo21/fastly-edge-ab-testing
- **Source:** community (Fcuervo21)
- **Demonstrates:** variant assignment and routing for A/B tests done in Compute, not in application code behind the origin.
- **Watch out for:** none known as of last verification; thin description — skim the README on re-verification for the bucketing mechanism used.
- **Last verified:** 2026-08-19

## compute-mcp-demo — protocol gateway pattern
- **Repo:** github.com/bharwani/compute-mcp-demo
- **Source:** community (bharwani)
- **Demonstrates:** wrapping a third-party HTTP API as an MCP server entirely in Compute, using edge caching to cut per-call latency roughly 15x.
- **Watch out for:** none known as of last verification.
- **Last verified:** 2026-08-19

## fastly-examples-live-betting-fanout — real-time fan-out at scale
- **Repo:** github.com/dmichael-fastly/fastly-examples-live-betting-fanout
- **Source:** community (dmichael-fastly)
- **Demonstrates:** using Fastly Fanout to broadcast frequently-updated data to a large concurrent audience without a fan-out multiplier hitting origin.
- **Watch out for:** none known as of last verification.
- **Last verified:** 2026-08-19

## edge-mcp — official reference implementation, explicitly unmaintained
- **Repo:** github.com/fastly/edge-mcp
- **Source:** official (fastly org)
- **Demonstrates:** implementing the stateless MCP protocol revision as a Rust Compute application, from Fastly's own devrel org.
- **Watch out for:** THE REPO ITSELF SAYS IT WILL NOT BE MAINTAINED. This is exactly the "still green, quietly stale" risk the skill's freshness mechanism can't catch on its own (it isn't archived, and pushedAt is recent) — the `Watch out for` field must state this explicitly and verbatim, not just "none known," so nobody models new code against a protocol revision that has since moved on without checking the current MCP spec version first.
- **Last verified:** 2026-08-19

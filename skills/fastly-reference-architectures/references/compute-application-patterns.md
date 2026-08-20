# Compute application pattern reference architectures

## fastly-edge-ab-testing — A/B testing at the edge
- **Repo:** github.com/Fcuervo21/fastly-edge-ab-testing
- **Source:** community (Fcuervo21)
- **Demonstrates:** cookie-based bucket allocation and full response synthesis for A/B tests done entirely in Compute, not in application code behind the origin.
- **Watch out for:** none known as of last verification.
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

## edge-mcp — stateless MCP server in Rust Compute
- **Repo:** github.com/fastly/edge-mcp
- **Source:** official (fastly org)
- **Demonstrates:** implementing the stateless MCP protocol revision as a Rust Compute application.
- **Watch out for:** The README states explicitly this is a "point-in-time example" built against the MCP 2026-07-28 specification and "will not be maintained beyond the initial implementation" — expect no updates, bug fixes, or security patches. Check the current MCP spec version before modeling new code on it.
- **Last verified:** 2026-08-19

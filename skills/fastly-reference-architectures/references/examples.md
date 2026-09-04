# Example projects running on Fastly

| Project | Description | Platform |
| --- | --- | --- |
| [google-apple-github-auth](https://github.com/bharwani/google-apple-github-auth) | Social login via Google/Apple (OIDC) and GitHub (OAuth2), verified entirely at the edge | Compute |
| [fastly-compute-news-with-content-paywall](https://github.com/saschanowak/fastly-compute-news-with-content-paywall) | Paywall / access-control gating for content | Compute |
| [vcl_shielding](https://github.com/bharwani/vcl_shielding) | Custom origin shielding topology via peering/IX | VCL |
| [fastly-bulk-redirects](https://github.com/Fcuervo21/fastly-bulk-redirects) | Bulk redirect table in Config Store, served by an edge worker | Compute |
| [fastly-edge-ab-testing](https://github.com/Fcuervo21/fastly-edge-ab-testing) | Cookie-based A/B test bucket allocation | Compute |
| [compute-mcp-demo](https://github.com/bharwani/compute-mcp-demo) | Turns a Shopify store into an MCP server, edge-cached | Compute |
| [fastly-examples-live-betting-fanout](https://github.com/dmichael-fastly/fastly-examples-live-betting-fanout) | Real-time score/odds fan-out to many concurrent clients | Compute, Fanout |
| [edge-mcp](https://github.com/fastly/edge-mcp) | Stateless MCP protocol server (point-in-time example, unmaintained) | Compute |
| [fastly-serverless-cms](https://github.com/chrisbuckley/fastly-serverless-cms) | Full CMS with no origin servers | Compute, KV Store, Object Storage |
| [fastly-serverless-checkers](https://github.com/chrisbuckley/fastly-serverless-checkers) | Real-time multiplayer checkers, no backend servers | Compute, Fanout, KV Store |
| [infiniteboard](https://github.com/anaramirezmorones/infiniteboard) | Collaborative infinite whiteboard | Compute, Fanout, KV Store, Object Storage |
| [fastly-log-analytics](https://github.com/fastly/fastly-log-analytics) | Request-level log analytics dashboard | Compute, Object Storage |
| [fos-migrator](https://github.com/benjaminshaver/fos-migrator) | Bulk content migration into Object Storage | Compute, Object Storage |
| [pypi-infra](https://github.com/pypi/infra) | PyPI's production Fastly config: origin shielding, purge auth, multi-sink logging | VCL |
| [trusted-server](https://github.com/IABTechLab/trusted-server) | IAB Tech Lab's edge ad/identity runtime: consent decoding, first-party auction orchestration | Compute, KV Store, Secret Store, Config Store |
| [security-use-cases](https://github.com/fastly/security-use-cases) | NGWAF-aware caching and edge rate limiting patterns | VCL, Next-Gen WAF, Edge Rate Limiting |
| [pubsub](https://github.com/fastly/pubsub) | Publish/subscribe broker: SSE and MQTT subscribers, JWT-gated | Compute, Fanout, KV Store, Config Store, Secret Store |
| [terraform-fastly-service](https://github.com/mastodon/terraform-fastly-service) | mastodon.social's VCL pattern library: purge auth, tarpitting, apex redirects | VCL |
| [edgeml-recommender](https://github.com/fastly/edgeml-recommender) | Vector similarity search over KV Store, HNSW graphs precompiled into edge storage | Compute, KV Store |
| [fastly-content-fanout](https://github.com/guardian/fastly-content-fanout) | EventBridge-to-Fanout live content push over WebSocket/SSE | Compute, Fanout |
| [helix-mixer](https://github.com/adobe-rnd/helix-mixer) | Config-driven multi-origin edge composition proxy | Compute |

---
name: fastly-reference-architectures
description: "Curated GitHub repositories — Fastly-official or individually vouched for by a named reviewer — that demonstrate working reference architectures on the Fastly platform, from a single Compute application up through systems combining multiple Fastly products (Compute, Fanout, KV Store, Object Storage, real-time logging). Use when designing a new solution on Fastly and a worked example of the target pattern would help, or when implementing and a concrete assembled reference would clarify the shape of the code. Not for documentation of how a specific Fastly tool or API works on its own — see the tool-specific skills for that."
---

# Fastly reference architectures

This skill points to a small number of GitHub repositories that Fastly, or a named and
accountable reviewer, endorses as good reference examples for building on the Fastly
platform. It is not primitive-level API or CLI documentation — see the tool-specific
skills for that — it is examples of assembled, working systems worth modeling a new
design after.

## Before recommending any entry

Verify the repo is not archived and has commit activity roughly consistent with "still
maintained" — e.g. `gh repo view <org>/<repo> --json isArchived,pushedAt` (or the GitHub
web UI if `gh` isn't available). If a repo is archived or long-dormant, say so explicitly
rather than presenting it as current, and flag it to this skill's maintainers (a PR
comment or issue) rather than editing the entry yourself.

## Pick the reference file

| You're looking for a pattern for... | File |
| --- | --- |
| Authentication, access control, or ML-based security classification at the edge | [references/edge-auth-and-security.md](references/edge-auth-and-security.md) |
| Origin shielding topology and redirect/routing tables at the edge | [references/caching-and-delivery.md](references/caching-and-delivery.md) |
| A single Compute application (A/B testing, protocol gateways, real-time fan-out, MCP servers) | [references/compute-application-patterns.md](references/compute-application-patterns.md) |
| A system combining 3+ Fastly products into one architecture | [references/multi-service-architectures.md](references/multi-service-architectures.md) |
| Log-streaming analytics dashboards and bulk content operations against Object Storage | [references/observability-and-ops.md](references/observability-and-ops.md) |

## Entry format

Every entry in every reference file uses this schema:

```markdown
## <repo name> — <one-line pattern summary>
- **Repo:** github.com/org/repo
- **Source:** official (fastly org / fastly-devrel) | community (name who vetted it)
- **Demonstrates:** the specific pattern worth copying, not just "a Compute app"
- **Watch out for:** known gaps, outdated dependencies, or divergence from current best
  practice — "none known as of last verification" if genuinely none
- **Last verified:** YYYY-MM-DD
```

## Adding or removing an entry

Same process as every other change in this repo: open a PR. The bar for inclusion is
either the repo is from an official Fastly org, or a named person is willing to attach
their judgment to it via the `Source` field. Keep each file to a handful of genuinely
excellent entries — quality and a low re-review burden over exhaustive coverage.

The initial set of `community` entries came from an internal Fastly Solutions
Engineering recommendation list; in every case the `Source` field names the repo's own
author, not an independent third-party reviewer. Treat that as a starting point, not the
bar going forward — a new entry ideally carries a reviewer distinct from the repo's
author, and any existing entry can be re-vetted or removed through the same PR process
as everything else here.

## Not this skill

How a specific Fastly tool, CLI, or API works: see `fastly`, `fastly-cli`,
`fastly-stats`, `fastly-ngwaf`, `falco`, `fastlike`, `viceroy`, `xvcl`, `fastly-fiddle`.
This skill shows assembled, working systems, not primitives.

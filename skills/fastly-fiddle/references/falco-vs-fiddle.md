# Falco vs Fiddle

Both test VCL. They're complementary, not interchangeable. SKILL.md's "When Fiddle, when Falco" table is the quick-decision reference; this file covers the reasoning behind it, the combined workflow, and the DSL differences.

One divergence worth internalizing: falco is a faithful Go reimplementation of Fastly's VCL dialect, not the real compiler. It catches almost everything, but divergences exist — especially around newly shipped VCL features. That gap is the core reason Fiddle stays in the loop despite being slower.

## Practical guidance

**Start in Falco.** Write subroutines, lint, run unit tests with mocks. This is where most bugs are caught and most iteration happens.

**Move to Fiddle when you need reality**:

- A `client.geo.*` branch you can't reasonably mock (mocking works for single-value checks; real geo data is useful when the logic traverses multiple fields).
- ESI logic, rate limiters, WAF rules.
- A bug you can only reproduce against real Fastly behavior — reproduce once in Fiddle, share the URL on a support ticket.
- Integration tests in CI that confirm the deployed-shape VCL behaves correctly end-to-end before you flip a service version live.

**Never use Fiddle for**:

- Fast TDD. You'll lose 15 seconds per iteration to edge sync.
- Any test you can express with falco mocks. The falco test is faster and more deterministic.

## Combined workflow

Ordered pipeline; each stage must pass (green) before the next runs:

1. falco lint — trigger: on edit. Speed: <1s, local.
2. falco test — trigger: lint passes. Speed: <1s per test, watch mode.
3. Fiddle CI run — trigger: falco tests green. Speed: 10-60s, real edge, pre-merge gate.
4. fastly deploy — trigger: Fiddle CI green. Target: staging service.

The Fiddle run is a gate, not an inner loop. Keep its test suite focused on assertions that only Fiddle can verify — don't duplicate every falco unit test in Fiddle form.

## Shared shape, different DSLs

The two tools have **different assertion DSLs**. You cannot reuse test files between them.

| Concept            | Falco                                                | Fiddle                                                                  |
| ------------------ | ---------------------------------------------------- | ----------------------------------------------------------------------- |
| Equality           | `assert.equal(actual, 200)`                          | `clientFetch.status is 200`                                             |
| Substring          | `assert.contains(s, "x")`                            | `clientFetch.bodyPreview includes "x"`                                  |
| Subroutine called  | `assert.subroutine_called("my_helper")`              | `events.where(fnName=my_helper).count() is 1`                           |
| Origin fetch count | n/a (no real fetch)                                  | `originFetches.count() is 0`                                            |
| TTL set in fetch   | `assert.equal(beresp.ttl, 3600s)` in `@scope: fetch` | `events.where(fnName=fetch)[0].ttl isAtLeast 3600`                      |
| State / return     | `assert.state(lookup)`                               | `events.where(fnName=recv)[0].return is "lookup"`                       |
| Error raised       | `assert.error(404)`                                  | `clientFetch.status is 404` + `events.where(fnName=error).count() is 1` |

## One more thing: Fiddle as a remote linter

If your CI host can't install falco (no Go toolchain, no Homebrew, whatever), Fiddle's `POST /fiddle` returns structured lint diagnostics without executing. Costs one HTTP round trip.

```bash
curl -sS -X POST https://fiddle.fastly.dev/fiddle \
  -H 'Content-Type: application/json' \
  --data @fiddle.json | jq '{valid, lintStatus}'
```

Exit non-zero when `.valid == false`. See the `api.md` reference ("Lint-only workflow").

This is a fallback, not a replacement — falco's linter is faster, offline, and has richer rule configuration.

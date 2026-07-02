# Running Fiddle Tests in CI

**Default: the Node + Mocha (`demo-fiddle-ci`) pattern** — it gives proper per-assertion reporting and diff output. The shell-script approach is a fallback for environments without Node (or for one-shot smoke tests). The GitHub Actions snippet builds on the Node pattern.

## 1. Node + Mocha (the `demo-fiddle-ci` pattern)

The reference implementation is at <https://github.com/fastly/demo-fiddle-ci>. Three files:

- `fiddle-client.js` — thin wrapper over `fetch` + `EventSource`, exposes `get`, `publish`, `clone`, `execute`.
- `fiddle-mocha.js` — given a `{spec, scenarios[]}`, publishes once, runs each scenario, creates a Mocha `Suite` per client fetch and a `Test` per assertion.
- `test.js` — your tests.

Install:

```bash
npm install --save-dev mocha node-fetch@2 eventsource assertion-error
```

Your test spec:

```js
const testService = require("./fiddle-mocha");

testService("Service: example.com", {
  debug: false,
  spec: {
    origins: ["https://http-me.fastly.dev"],
    vcl: {
      recv: `set req.url = querystring.sort(req.url);`,
      fetch: `set beresp.ttl = 3600s;`,
    },
  },
  scenarios: [
    {
      name: "Request normalisation",
      requests: [
        {
          path: "/?bbb=2&aaa=1",
          tests: [
            "clientFetch.status is 200",
            'events.where(fnName=recv)[0].url is "/?aaa=1&bbb=2"',
          ],
        },
      ],
    },
    {
      name: "Caching",
      requests: [
        {
          path: "/html",
          tests: [
            "originFetches.count() is 1",
            "events.where(fnName=fetch)[0].ttl isAtLeast 3600",
          ],
        },
        {
          path: "/html",
          tests: [
            "originFetches.count() is 0",
            "events.where(fnName=hit).count() is 1",
          ],
        },
      ],
    },
  ],
});
```

Run:

```bash
mocha src/test.js --exit
```

Mocha reports each assertion as a separate test with a proper diff (the adapter throws `AssertionError` with `actual` / `expected` so mocha renders it).

### How it works, briefly

1. Outer `describe(name)` + single `before()` publishes the fiddle once.
2. Inner `describe(scenario.name)` has a placeholder `it('has some tests', ...)` so Mocha actually runs `before()` (Mocha won't execute lifecycle hooks in a suite with no tests discovered synchronously).
3. Inner `before()` calls `execute(...)` with `{ ...fiddle, requests: scenario.requests }` and waits for `waitFor: 'tests'`.
4. For each `clientFetches[...]`, a new `Suite` is added programmatically; each assertion becomes a `Test` that throws on `pass: false`.

The "sacrificial test" (`this.tests = []` in the inner `before`) removes the placeholder once real suites are attached.

### Key points when reusing the pattern

- The fiddle is published **once**; each scenario re-executes the same fiddle with different `requests[]`. This saves 10–20s per scenario.
- Scenarios are sequential. Don't parallelize — you'll hit both Mocha and Fastly in weird ways.
- `waitFor: 'tests'` is the demo's custom result condition: "all requests with a `tests[]` array have results populated". Without it you'd wait up to `maxWait`.
- Rebuild `node_modules` with a Node version that still supports `node-fetch@2` (CommonJS). Or upgrade the demo to `fetch` native (Node 18+) and `node-fetch@3` / undici.

## 2. Shell fallback (`scripts/run-fiddle.sh`)

When Node isn't available, use the bundled helper (see `SKILL.md`). It publishes, executes, streams, and prints pass/fail JSON — enough for CI smoke tests with non-zero exit on failure:

```bash
scripts/run-fiddle.sh fiddle.json --cache-id $RANDOM \
  | tee fiddle-result.json
```

Limits vs Mocha: no per-assertion diff rendering, single-fiddle scope (publish-once-per-scenario reuse requires a wrapper).

## 3. GitHub Actions

With the Node pattern in place:

```yaml
# .github/workflows/fiddle-tests.yml
name: Fiddle tests

on:
  pull_request:
  push:
    branches: [main]

jobs:
  fiddle:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - run: npm ci
      - run: npx mocha src/test.js --exit --reporter mocha-junit-reporter
        env:
          MOCHA_FILE: test-results/fiddle.xml
      - if: always()
        uses: actions/upload-artifact@v4
        with:
          name: fiddle-results
          path: test-results/
```

Notes:

- `timeout-minutes: 10` is generous. A fiddle with 3 scenarios typically runs in 30–60s: one 15s edge sync, plus ~5–10s per execution.
- No secrets needed. Fiddle is unauthenticated.
- Flakes will come from edge sync delays or shared cache state — give `maxWait` enough headroom (60s) and use distinct `cacheID`s per scenario unless you're deliberately testing cache reuse.
- **Assertions on `originFetches.count()` / `originFetches[0].*` are retry-fragile.** Re-executing against the same `cacheID` (which automatic retries do) turns the second attempt's origin fetch into a cache HIT and the assertion silently flips. Set `useFreshCache: true` on any request that fetches origin and is asserted by origin-fetch count, or assert via `events.where(fnName=fetch).count()` instead. See `SKILL.md` ("Wire-format gotchas" #12).

## Handling failures

The demo adapter throws an `AssertionError` with populated `actual` / `expected`, which mocha renders with a diff. That comes from Fiddle's own fail payload — nothing to do on your side.

When a fiddle fails to publish (invalid VCL), `publish()` resolves with `{valid: false, lintStatus}`. The demo does **not** check this; if your VCL is broken, you'll get an opaque "No test results provided" later. Harden with:

```js
const fiddle = await FiddleClient.publish(data.spec);
if (fiddle.valid === false) {
  throw new Error(`VCL invalid: ${JSON.stringify(fiddle.lintStatus)}`);
}
```

(Or check the raw response — the current demo's `publish()` returns only the `.fiddle` sub-object, losing `valid`. Worth patching.)

## When not to use Fiddle in CI

- Tight inner-loop VCL work. Use `falco test` — milliseconds vs tens of seconds.
- Testing Compute (WASM) services. Use `viceroy` or `fastlike`.
- Load / perf testing. Fiddle is a shared resource; don't.
- Tests that depend on specific POP geography. Fiddle picks the POP; you don't.

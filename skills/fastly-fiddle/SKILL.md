---
name: fastly-fiddle
description: "Use when testing VCL against real Fastly edge infrastructure, writing assertion-based Fiddle tests, producing shareable fiddle URLs for bug reproductions, running VCL integration tests in CI, linting VCL remotely via the Fiddle API, or working with clientFetch/events/originFetches test expressions."
---

# Fastly Fiddle — Real-Edge VCL Testing

## Trigger and scope

Trigger on: Fastly Fiddle, fiddle.fastly.dev URLs, the Fiddle HTTP API, CI testing of VCL services, real-edge VCL tests, shareable VCL reproductions, `clientFetch.*`/`events.*`/`originFetches.*` test expressions, `.test.js` / Mocha specs that target fiddles, SSE `updateResult` / `waitingForSync` events, remote VCL linting via Fiddle, or validating real Fastly behavior (geo, WAF, ESI, clustering, shielding) that local tools cannot simulate.

Do NOT use for: local VCL unit testing (use `falco`), fast TDD loops (Fiddle has a 10-20s edge-sync floor per publish), Fastly Compute/Wasm testing (use `viceroy` or `fastlike`), production service deployment (use `fastly-cli`), or anything requiring authenticated Fastly API access — Fiddle does not use your Fastly API key.

Fastly Fiddle is a web-based sandbox at <https://fiddle.fastly.dev> that compiles and runs VCL on real Fastly edge nodes. Because it uses the production VCL compiler and real POPs, it's the only way outside a real service to test VCL features that depend on edge infrastructure — geolocation data, WAF, ESI, clustering, shielding, rate limiting, real TLS, and real cache behavior.

**Official UI**: <https://fiddle.fastly.dev>
**Demo CI runner**: <https://github.com/fastly/demo-fiddle-ci>
**API base**: `https://fiddle.fastly.dev` (undocumented but stable; no auth required for public fiddles)

## When Fiddle, when Falco

| Need                                                  | Use                                |
| ----------------------------------------------------- | ---------------------------------- |
| Fast local iteration (< 1s), watch mode, offline      | `falco test`                       |
| Real Fastly VCL compiler and semantics                | Fiddle                             |
| Real `client.geo.*`, WAF, ESI, rate limiting, shield  | Fiddle                             |
| Shareable URL for bug repros and support tickets      | Fiddle                             |
| CI against real edge nodes                            | Fiddle                             |
| Structured lint with line/col (no execution required) | Either                             |
| Fastly Compute (WASM)                                 | Neither — use `viceroy`/`fastlike` |

Common workflow: iterate locally with `falco test` for speed, then push edge cases to Fiddle when you need real Fastly behavior or a shareable link. See [falco-vs-fiddle.md](references/falco-vs-fiddle.md) for full trade-offs.

## Minimal round trip

For anything beyond a one-shot smoke test, use the bundled helper which
handles publish → execute → SSE → completion-detection in one call:

```bash
scripts/run-fiddle.sh examples/robots.json
# Prints fiddle URL, then pass/fail JSON per assertion (including body_preview
# and status by default). Exits non-zero on failure. Pass --no-bodies for
# compact output.

# Iterate against an already-published fiddle without paying edge-sync again:
scripts/run-fiddle.sh --id <fiddle-id>                 # re-execute (warmest, ~2s)
scripts/run-fiddle.sh --id <fiddle-id> spec.json       # PUT then execute
```

The equivalent raw-curl flow, for reference or when the helper isn't available:

```bash
UA='fiddle-skill-example/1.0'

# 1. Create. Capture the ID and the validity flag.
RESP=$(curl -sS -X POST https://fiddle.fastly.dev/fiddle \
  -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -H "User-Agent: $UA" \
  --data '{
    "origins": ["https://http-me.fastly.dev"],
    "vcl": {
      "init": "# Synthetic robots.txt response\n# via error restart pattern",
      "recv": "if (req.url.path == \"/robots.txt\") {\n  error 601;\n}",
      "error": "if (obj.status == 601) {\n  set obj.status = 200;\n  synthetic {\"User-agent: BadBot\"};\n  return(deliver);\n}"
    },
    "requests": [
      { "path": "/robots.txt",
        "headers": "X-Custom: value\nX-Other: second",
        "tests": ["clientFetch.status is 200", "clientFetch.bodyPreview includes \"BadBot\""] }
    ]
  }')
FID=$(echo "$RESP" | jq -r '.fiddle.id')
echo "$RESP" | jq '{valid, lintStatus}'   # bail here if valid is false

# 2. Execute. Subscribe to the SSE stream IMMEDIATELY — session IDs expire fast.
SID=$(curl -sS -X POST "https://fiddle.fastly.dev/fiddle/$FID/execute?cacheID=1" \
        -H 'Accept: application/json' -H "User-Agent: $UA" | jq -r '.sessionID')

# 3. Stream results. Emits repeated `event: waitingForSync` (~10-20s on first
#    publish) then `event: updateResult` with full pass/fail data.
curl -sS -N -H "User-Agent: $UA" "https://fiddle.fastly.dev/results/$SID/stream"
```

Full protocol details in [api.md](references/api.md).

## Wire-format gotchas

Non-obvious behavior that will break tools round-tripping fiddles programmatically:

1. **`vcl` on input, `src` on output.** You `POST {"vcl": {"recv": "..."}}` but `GET` returns `{"src": {"recv": "..."}}`. The server renames the key on normalization. Any tool that fetches a fiddle and re-publishes it must map `src` → `vcl` (or send `src` — both work on input). **Update existing fiddles with `PUT /fiddle/:id`** — same body shape as `POST`, but partial updates are not supported; omitted subroutines are cleared.

2. **`tests` is a string on the wire.** You can send `tests: ["a", "b"]` but a subsequent `GET` returns `tests: "a\nb"`. One assertion per line. Split on `\n` when reading.

3. **`headers` is a newline-joined string, not an array.** Unlike `tests` (which accepts both), `headers` must be a string: `"headers": "User-Agent: BadBot/1.0\nX-Custom: value"`. An array will be rejected with a validation error.

4. **Request fields are auto-defaulted by the server.** A `GET` of a fiddle you just created will include fields you didn't send: `method: "GET"`, `connType: "h2"` (HTTP/2 by default — matters for tests that depend on protocol), `enableCluster: true`, `enableShield: false`, `useFreshCache: false`, `sourceIP: "client"`, `followRedirects: false`, `delay: 0`. Set them explicitly if you care.

5. **Invalid VCL still gets a fiddle ID.** `POST` returns `{valid: false, lintStatus: {...}, fiddle: {id, ...}}` for broken VCL. `valid` is authoritative; don't rely on HTTP status.

6. **VCL string concat with `+` rejects parenthesized operands.** `set X = "used=" + (a - b);` fails with a _misleading_ "Remove the trailing `+` operator" suggestion — the `+` is fine, the `(` is what the parser rejects. Compute the sub-expression into a local variable first. See [spec-shape.md](references/spec-shape.md#vcl-string-concatenation).

7. **`error 8NN;` / `error 9NN;` is rejected by Fiddle lint — use 6xx.** Any 800–999 code fails with "8xx and 9xx error codes are used internally by Fastly. Use 6xx instead.", **even inside an `if`/`else`/`switch` block** (an earlier claim that conditional 8xx/9xx passed was wrong). This means the classic `error 801 <url>;` redirect idiom trips Fiddle lint regardless of conditionals — use `error 602 "<url>";` and build the 301 in `vcl_error`. Codes 400–799 are accepted. See [spec-shape.md](references/spec-shape.md#error-codes-and-the-8xx9xx-lint-check).

8. **Some test expressions have built-in delays.** `originFetches.count() is 0` returns `asyncDelay: 2500` — the server waits 2.5s before evaluating "did nothing happen?". Client wait time must accommodate this; 45-60s is a safe ceiling.

9. **SSE session IDs are short-lived.** Subscribe to `/results/<sessionID>/stream` within seconds of receiving the ID from `/execute`. Delayed connections get a 404. Always have the stream open before you start waiting on results.

10. **Test DSL has unusual syntax.** No `.first()`, no `reqHeaderValue()`, no `isnt`/`empty` operators. Event objects expose only `url`/`method`/`return`/`status`/`ttl` — not arbitrary `req.http.*` values. **Read [test-dsl.md](references/test-dsl.md) before writing assertions.**

11. **The server assigns a fresh fiddle ID on every `POST /fiddle`** — even for byte-identical input. IDs are not a content hash; back-to-back POSTs of the same body return different IDs, and each new ID needs its own edge-sync pass before `/execute` can produce results. **`PUT /fiddle/<id>`** keeps the URL stable (good for shared bug-repro links) but the new VCL still recompiles and propagates, so PUTs pay the same edge-sync cost as POSTs. The genuinely warm path is **re-executing an unchanged fiddle ID** — same content, repeat `/execute` calls finish in ~2s. Capture the ID from the first POST and reuse it; vary `cacheID` to force cold caches without re-publishing. (PUT is not partial — omitted subroutines are cleared, see #1.)

12. **`originFetches.count() is N` is fragile under retries and shared `cacheID`.** A retry — automatic in `run-fiddle.sh`, or manual via `--id <fid>` — re-executes against the same `cacheID`, so any origin response cached on the previous attempt is now a HIT and `originFetches.count()` drops to 0. Two reliable fixes: set **`useFreshCache: true`** on the request (forces a fresh cache, ignoring the session `cacheID` — see [spec-shape.md `Request objects`](references/spec-shape.md#request-objects)), or assert via **`events.where(fnName=fetch).count()`** (counts subroutine entries, not network calls). The same goes for `originFetches[0].*` assertions whenever the test runs after a possible warmup.

## Authoring conventions

Fiddles are read by humans in a browser. These aren't surprises, but they make shared fiddles useful:

- **Set a `title`.** Makes fiddles findable in browser tabs, bookmarks, and shared links. Example: `"title": "fastly_info.state: compound values deep dive"`.
- **Use `init` as a header comment.** The `init` subroutine renders first in the UI. Put a short summary there (~55 chars/line): `"init": "# fastly_info.state: compound values\n# Demonstrates MISS-CLUSTER, HIT-CLUSTER, HIT-SYNTH"`.
- **Format VCL with `\n` and indentation** rather than cramming everything onto one line.
- **Send `User-Agent: <tool>/<version>` on every API call.** Fiddle is unauthenticated shared infra; default `curl/x.y` or library UAs are bad citizenship. This is the API call's UA, not the simulated request's `headers`.

## References

| Topic               | File                                                | Use when...                                                        |
| ------------------- | --------------------------------------------------- | ------------------------------------------------------------------ |
| **Helper script**   | [scripts/run-fiddle.sh](scripts/run-fiddle.sh)      | Publishing + executing + streaming a fiddle in one shell command   |
| **Example payload** | [examples/robots.json](examples/robots.json)        | Starting from a known-good minimal fiddle spec                     |
| **HTTP API**        | [api.md](references/api.md)                         | Calling Fiddle endpoints directly, driving it from any language    |
| Fiddle spec shape   | [spec-shape.md](references/spec-shape.md)           | Building the JSON payload: origins, src, requests, defaults        |
| Test DSL            | [test-dsl.md](references/test-dsl.md)               | Writing `clientFetch.*`, `events.where(...)`, `originFetches.*`    |
| CI integration      | [ci-integration.md](references/ci-integration.md)   | Running Fiddle tests from Mocha, GitHub Actions, or a shell script |
| Falco vs Fiddle     | [falco-vs-fiddle.md](references/falco-vs-fiddle.md) | Choosing the right tool, or combining them in one workflow         |

## Limits and cautions

- **No auth required, no quota documented.** Be a good citizen: don't hammer the API in tight loops, and always send a descriptive `User-Agent` on API calls (see Authoring conventions). Use `cacheID` consistently across requests that need to share cache, and vary it to force cold caches.
- **Edge-sync floor is ~10-20s per publish, sometimes much longer.** Applies per fiddle ID, not per unique content — and every `POST /fiddle` mints a new ID (see Wire-format gotchas #11), so re-publishing identical input still pays the full sync cost. Cold publishes regularly take 60-120s in practice. Unusable for TDD. Batch changes; execute once per meaningful delta; reuse IDs via `PUT` when iterating.
- **Execution hops through a real POP** (tests observed running from IAD on node `kiad7000140`). Geographic assertions reflect wherever the fiddle executor landed.
- **Fiddles are public by default.** Don't put secrets in VCL you publish.
- **The API is undocumented.** Field names and behavior can change.

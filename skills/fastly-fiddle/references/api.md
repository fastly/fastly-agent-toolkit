# Fastly Fiddle HTTP API

Undocumented but stable. Base URL: `https://fiddle.fastly.dev`. No auth required for public fiddles.

## Endpoints

| Method | Path                            | Purpose                                   |
| ------ | ------------------------------- | ----------------------------------------- |
| POST   | `/fiddle`                       | Create a fiddle                           |
| PUT    | `/fiddle/:id`                   | Update in place (`srcVersion` increments) |
| GET    | `/fiddle/:id`                   | Fetch normalized fiddle                   |
| POST   | `/fiddle/:id/execute?cacheID=N` | Execute, returns `sessionID`              |
| GET    | `/results/:sessionID/stream`    | SSE event stream of execution progress    |

Headers: send `Content-Type: application/json` on write, `Accept: application/json` on read.

## Create / update

**Request body** (minimum):

```json
{
  "origins": ["https://http-me.fastly.dev"],
  "vcl": {
    "recv": "if (req.url.path == \"/robots.txt\") { error 601; }"
  }
}
```

You can also send `requests[]` with a `tests[]` array per request (see the `spec-shape.md` reference for all fields).

**Response**:

```json
{
  "fiddle": { "id": "0d9bb21e", "src": {"recv": "..."}, "srcVersion": 0, "requests": [...], ... },
  "valid": true,
  "lintStatus": { "recv": [] }
}
```

Key points:

- Fiddle IDs are 8 hex characters.
- You send `vcl:` but the stored/returned key is `src:`. The server renames.
- `srcVersion` starts at 0 and increments on each PUT.
- Response always includes `valid` and `lintStatus` — see [Lint-only workflow](#lint-only-workflow).

**PUT semantics**: send the full fiddle shape. Partial updates are not supported; omitted subroutines are cleared.

## Fetch

```http
GET /fiddle/:id
Accept: application/json
```

**`Accept: application/json` is required.** Without it the server returns the HTML Fiddle web app (a `200` with a `text/html` body), not the fiddle JSON — so a header-less `curl` "succeeds" but yields an unparseable page. Returns:

```json
{ "fiddle": { ... }, "valid": true, "lintStatus": {...} }
```

**`valid` on a `GET` is not the lint result.** On create/update responses `valid` reports compilation (see [Lint-only workflow](#lint-only-workflow)); on a `GET` it reports execution — it stays `false` until the fiddle has run at least once, then turns `true`. A cleanly-linting fiddle you just created reads back as `valid: false` with an empty `lintStatus`, indistinguishable from broken VCL. Never judge compilation from a `GET`; use the create/update response, or re-submit the spec.

Unknown ID: `404` with plain text body `There is no fiddle with ID xxxxxxxx`. Do not parse as JSON.

## Execute

```http
POST /fiddle/:id/execute?cacheID=<int>
```

Returns:

```json
{ "sessionID": "84140a2d16", "streamHost": "" }
```

- `cacheID` is a caller-chosen integer. Requests using the same `cacheID` share cache state across executions. Vary it to force a cold cache (the demo uses `Math.round(Math.random() * 100000)`).
- `streamHost` has been observed empty; use the main base URL for the stream.
- The execution itself runs asynchronously on a real Fastly POP. Results arrive via the SSE stream.

## SSE result stream

```http
GET /results/:sessionID/stream
Accept: text/event-stream
```

Event types observed:

| Event            | Meaning                                                                              |
| ---------------- | ------------------------------------------------------------------------------------ |
| `waitingForSync` | Config still syncing to edge. Emitted repeatedly (1/s) for ~10–20s on first publish. |
| `updateResult`   | New result snapshot. May be emitted multiple times as data accumulates.              |

**`waitingForSync` payload** (informational):

```json
{
  "serviceID": "4rIqy91QC7gMYPJMQJSz16",
  "serviceName": "prod-exec15",
  "savedVersion": 0,
  "publishedVersion": 0,
  "executedVersion": 1,
  "publishedFiddle": "0d9bb21e",
  "executedFiddle": "7847c5a2",
  "reqHost": "<session>-<req>-<fiddle>v<ver>-<cacheID>-100.exec15.fiddle.fastly.dev",
  "status": 982,
  "retryCount": 0
}
```

**`updateResult` payload** top-level keys:

| Key             | Type   | Notes                                                                         |
| --------------- | ------ | ----------------------------------------------------------------------------- |
| `id`            | string | Session ID, echoes the URL                                                    |
| `startTime`     | number | Execution start timestamp                                                     |
| `requestCount`  | number | Total requests defined                                                        |
| `execHost`      | string | The `<session>-...fiddle.fastly.dev` host that served the request             |
| `execVersion`   | number | Which `srcVersion` actually executed                                          |
| `packageFile`   | string | Compute only (empty for VCL fiddles)                                          |
| `insights`      | object | Performance/cache insights                                                    |
| `clientFetches` | object | **Keyed by internal ID**, not array. Each value has `req`/`resp`/`tests`/etc. |
| `originFetches` | object | Same keying. Empty when served from synthetic or cache                        |
| `events`        | array  | Stream of `{type: "vcl-sub", fnName, server, attribs, time, seqIdx, ...}`     |

Iterate fetches with `Object.values(result.clientFetches)`, not array indexing.

## Completion policy

The server keeps streaming `updateResult` indefinitely as more events arrive. Clients decide when to stop. The `demo-fiddle-ci` pattern is:

1. Start a `minWait` timer (e.g. 2000ms) — earliest finalize.
2. Start a `maxWait` timer (e.g. 60000ms) — hard deadline.
3. On every `updateResult`, if `elapsed > minWait` AND (all client fetches have `tests` populated OR `elapsed > maxWait`), close the stream.

For test-driven use, the "all expected `tests` populated" condition is:

```js
Object.values(result.clientFetches).filter((f) => f.tests).length ===
  fiddle.requests.filter((r) => r.tests).length;
```

## Lint-only workflow

Every create/update returns `valid` and `lintStatus` without executing. Cheap remote linter:

```bash
curl -sS -X POST https://fiddle.fastly.dev/fiddle \
  -H 'Content-Type: application/json' \
  -H 'User-Agent: my-vcl-tests/1.0' \
  --data "$PAYLOAD" | jq '{valid, lintStatus}'
```

`lintStatus` is keyed by subroutine name; each value is an array of diagnostics:

```json
{
  "recv": [
    {
      "level": "error",
      "str": "req.bogus_variable",
      "line": 0,
      "startPos": 13,
      "endPos": 31,
      "message": "Unknown variable `req.bogus_variable`"
    }
  ]
}
```

Empty array = no issues for that subroutine. Use `valid === false` as the error gate — but only on the create/update response. On a `GET`, `valid` reports whether the fiddle has executed, not whether it compiles (see [Fetch](#fetch)), so a `GET` cannot be used as a lint gate.

## Cloning

The UI bundle exposes a `POST /fiddle/:id/clone` endpoint, but the simplest portable cloning pattern is still:

1. `GET /fiddle/:id` (with `Accept: application/json`, see [Fetch](#fetch)) → fiddle object
2. Set `id: null` on the returned object
3. `POST /fiddle` with the modified object

The demo client's `FiddleClient.clone()` does exactly this.

## Rate limits and auth

Unauthenticated. No quota is documented. Be conservative — Fiddle is a shared resource backed by real Fastly services. Don't use it for load testing.

Send `User-Agent: <tool>/<version>` on every API call (see Authoring conventions in `SKILL.md`). This is independent of the simulated request's `headers` field.

## Errors

- `404` on unknown fiddle ID (plain text body, not JSON).
- Invalid VCL does **not** return an HTTP error. It returns `200` with `valid: false` and a populated `lintStatus`.
- Malformed request JSON returns `500` with a `text/html` body containing the raw parser error (e.g. `Unterminated string in JSON at position 18`). Schema-invalid bodies (wrong types, missing required keys) also return `500 text/html` with messages like `Fiddle validation error in key 'origins': 42`. There is no structured error response — validate locally before POST/PUT.

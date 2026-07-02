# Fiddle Test DSL

Each request in a fiddle carries a `tests` list. Each line is a single assertion in Fiddle's domain-specific language. The server evaluates them after the request completes and reports `pass` / `actual` / `expected` per assertion.

The DSL is not formally documented by Fastly; these are the patterns observed in `fastly/demo-fiddle-ci` and by direct testing.

## Shape of results

Pass:

```json
{
  "label": "clientFetch.status is 200",
  "testExpr": "clientFetch.status is 200",
  "asyncDelay": 0,
  "pass": true
}
```

Fail:

```json
{
  "label": "clientFetch.bodyPreview includes \"NotPresent\"",
  "testExpr": "clientFetch.bodyPreview includes \"NotPresent\"",
  "asyncDelay": 0,
  "pass": false,
  "expected": "NotPresent",
  "actual": "BadBot"
}
```

`asyncDelay` is server-side wait in ms before evaluation (see [Timing](#timing)).

## Namespaces

Three top-level data sources:

| Namespace       | What it represents                                    |
| --------------- | ----------------------------------------------------- |
| `clientFetch`   | The response the Fiddle's test client saw from Fastly |
| `originFetches` | The requests Fastly made to origin(s)                 |
| `events`        | The stream of VCL subroutine invocations that ran     |

## `clientFetch.*`

Scalar fields of the response Fastly sent back to the test client.

| Expression                      | Type   | Notes                       |
| ------------------------------- | ------ | --------------------------- |
| `clientFetch.status`            | int    | HTTP status code            |
| `clientFetch.bodyPreview`       | string | First N bytes of body       |
| `clientFetch.bodyBytesReceived` | int    | Total body bytes            |
| `clientFetch.resp`              | string | Raw response line + headers |
| `clientFetch.req`               | string | Raw request sent to Fastly  |

Examples:

```text
clientFetch.status is 200
clientFetch.status is 404
clientFetch.resp includes "content-length: 30"
clientFetch.resp includes "x-cache: HIT"
clientFetch.bodyPreview includes "BadBot"
clientFetch.bodyPreview is "hello world"
```

## `originFetches.*`

Collection of requests Fastly forwarded to origin. Use `.count()` and indexing.

| Expression                | Type   | Notes                              |
| ------------------------- | ------ | ---------------------------------- |
| `originFetches.count()`   | int    | How many origin requests were made |
| `originFetches[0].req`    | string | Raw origin request                 |
| `originFetches[0].status` | int    | Origin response status             |

Examples:

```text
originFetches.count() is 0
originFetches.count() is 1
originFetches.count() isAtLeast 1
originFetches[0].status is 200
```

`originFetches.count() is 0` is the standard "served from cache / synthetic" check. The server attaches `asyncDelay: 2500` to these — it has to wait to prove nothing happened.

## `events.*`

The stream of VCL subroutine invocations. Each event has shape:

```json
{
  "type": "vcl-sub",
  "fnName": "recv",
  "time": 1778069487742183,
  "seqIdx": 3,
  "reqID": "6b9bdae2",
  "traceID": "E6wfO",
  "server": { "pop": "IAD", "nodeID": "kiad7000140" },
  "attribs": { "isESI": false, "return": "hash" },
  "isAsync": false,
  "ranBoilerplate": false,
  "isComplete": true,
  "logs": []
}
```

Query events with `.where(...)` filters, index with `[n]`, aggregate with `.count()`.

| Expression                           | Notes                                        |
| ------------------------------------ | -------------------------------------------- |
| `events.where(fnName=recv).count()`  | How many times `vcl_recv` ran                |
| `events.where(fnName=fetch)[0].ttl`  | The TTL set in the first `vcl_fetch`         |
| `events.where(fnName=recv)[0].url`   | `req.url` at the end of the first `vcl_recv` |
| `events.where(fnName=error).count()` | Did `vcl_error` run                          |
| `events.where(fnName=hit).count()`   | Cache hit path taken                         |

Common `fnName` values: `init`, `recv`, `hash`, `hit`, `miss`, `pass`, `fetch`, `error`, `deliver`, `log`.

Within events you can read a fixed set of attributes as they were when the subroutine returned: `url`, `method`, `return`, `status`, `ttl`. Arbitrary VCL variables (`req.http.*`, `beresp.*`, etc.) are **not** exposed — only these snapshot fields. To verify a header value, use `clientFetch.resp includes "header-name:"` on the final response instead.

## Operators

| Operator    | Example                                            | Notes                                                                                                           |
| ----------- | -------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `is`        | `clientFetch.status is 200`                        | Exact equality                                                                                                  |
| `isAtLeast` | `events.where(fnName=fetch)[0].ttl isAtLeast 3600` | Numeric >=                                                                                                      |
| `includes`  | `clientFetch.bodyPreview includes "BadBot"`        | Substring / header-line containment. Case-sensitive (see [Header case under HTTP/2](#header-case-under-http2)). |

Additional operators (observed in wild but not exercised in verification): `isAtMost`, `isLessThan`, `isGreaterThan`, `matches` (regex). Test in a throwaway fiddle before relying on them.

## Timing

Some assertions carry a server-side `asyncDelay` measured in milliseconds:

| Assertion pattern            | `asyncDelay` | Why                                  |
| ---------------------------- | ------------ | ------------------------------------ |
| `originFetches.count() is 0` | 2500ms       | Must wait to confirm no origin fetch |
| Immediate scalar checks      | 0ms          | Evaluated as soon as data arrives    |

Your client's total wait must exceed the largest `asyncDelay` in play. Set `maxWait` to 60000ms and you'll never hit the ceiling for realistic test suites.

## Patterns

**Served entirely from synthetic** (no origin contact):

```text
clientFetch.status is 200
originFetches.count() is 0
events.where(fnName=error).count() is 1
clientFetch.bodyPreview includes "<expected body>"
```

**Cache MISS then HIT** (requires two requests with same `cacheID`):

```text
# First request
originFetches.count() is 1
events.where(fnName=fetch)[0].ttl isAtLeast 3600

# Second request
originFetches.count() is 0
events.where(fnName=hit).count() is 1
```

**Query string sorted in recv**:

```text
clientFetch.status is 200
events.where(fnName=recv).count() is 1
events.where(fnName=recv)[0].url is "/?aaa=1&bbb=2&ccc=3"
```

**Auth bypass to origin**:

```text
originFetches.count() is 1
originFetches[0].req includes "authorization: Bearer"
events.where(fnName=pass).count() is 1
```

**Error path exercised**:

```text
clientFetch.status is 404
events.where(fnName=error).count() is 1
events.where(fnName=deliver)[0].status is 404
```

## Header case under HTTP/2

`clientFetch.resp` is the raw response frame. Under HTTP/2 — the Fiddle default for `connType` (see the `spec-shape.md` reference, "Fields you rarely touch but should know") — header names are **lowercased on the wire**, regardless of how they were written in VCL. `includes` is a case-sensitive substring match, so:

```vcl
set obj.http.X-Country-Code = "US";
```

pairs with

```text
clientFetch.resp includes "x-country-code: US"     # ✅ matches the h2 frame
clientFetch.resp includes "X-Country-Code: US"     # ❌ never matches under h2
```

Values are passed through unchanged, so `"US"` stays uppercase. Two ways to assert in mixed-case form if you need to: set `"connType": "h1"` on the request (HTTP/1.1 preserves header casing), or normalize on the assertion side and write all header-name assertions in lowercase. The latter is what every example in this file does.

## Writing reliable assertions

- Prefer `events.where(fnName=X)[0].<field>` over indirect effects when you want to pin down exactly which VCL phase ran.
- Use `originFetches.count()` aggressively — it's the cleanest signal for "cache / synthetic worked" or "the pass happened".
- Avoid asserting on `clientFetch.resp` containing timestamps or node IDs; they change per execution.
- `includes` is substring, not glob, and case-sensitive. For regex semantics, test in the Fiddle UI first to confirm `matches` behavior in your version of the DSL.

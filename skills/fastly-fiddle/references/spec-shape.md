# Fiddle Spec Shape

The JSON structure you POST to `/fiddle` as the request body. On GET and POST responses, this object is nested inside an envelope (`{fiddle: <this>, valid, lintStatus}`) — see the `api.md` reference for the full response shape. The `vcl` key you send is renamed to `src` in the returned `fiddle` object.

## Top-level fields

```json
{
  "id": "0d9bb21e",
  "title": "",
  "type": "vcl",
  "description": "",
  "origins": ["https://http-me.fastly.dev"],
  "vcl":  { "recv": "...", "fetch": "..." },
  "src":  { "recv": "...", "fetch": "..." },
  "srcVersion": 0,
  "requests": [ ... ],
  "isLocked": false,
  "isFrozen": false,
  "lastEditor": "<hash>",
  "createdAt": "2026-05-05T16:31:11.148Z",
  "updatedAt": "2026-05-05T16:31:11.148Z"
}
```

| Field         | Direction | Notes                                                                                    |
| ------------- | --------- | ---------------------------------------------------------------------------------------- |
| `id`          | R/W       | 8 hex chars. Omit on create; server assigns. Set on PUT to overwrite.                    |
| `type`        | R/W       | `"vcl"` or `"compute"`. Defaults to `"vcl"`.                                             |
| `origins`     | R/W       | Array of up to 5 origin URLs with scheme. Exposed in VCL as `F_origin_0` … `F_origin_4`. |
| `vcl`         | R/W       | Subroutine bodies. Canonical input key; server normalizes to `src` on read.              |
| `src`         | R/W       | Alias for `vcl`. Always returned on GET; also accepted on POST/PUT.                      |
| `srcVersion`  | R only    | Starts at 0, increments on every PUT.                                                    |
| `requests`    | R/W       | See [Request objects](#request-objects).                                                 |
| `isLocked`    | R/W       | Prevents overwrites by other users.                                                      |
| `isFrozen`    | R only    | Server-set; frozen fiddles reject PUT.                                                   |
| `title`       | R/W       | Free text.                                                                               |
| `description` | R/W       | Free text.                                                                               |

## VCL subroutine slots

Keys of `vcl` / `src` map to Fastly VCL state machine phases:

| Key       | Runs in       | Typical use                                             |
| --------- | ------------- | ------------------------------------------------------- |
| `init`    | `vcl_init`    | Backend definitions, ACLs, tables, one-time setup       |
| `recv`    | `vcl_recv`    | Request inspection, routing, auth, early `error`        |
| `hash`    | `vcl_hash`    | Custom cache key composition                            |
| `hit`     | `vcl_hit`     | On cache hit                                            |
| `miss`    | `vcl_miss`    | On cache miss before origin fetch                       |
| `pass`    | `vcl_pass`    | On explicit pass                                        |
| `fetch`   | `vcl_fetch`   | After origin response, before cache insert (`beresp.*`) |
| `error`   | `vcl_error`   | Custom error / synthetic responses                      |
| `deliver` | `vcl_deliver` | Final response mutations (`resp.*`)                     |
| `log`     | `vcl_log`     | Logging endpoints                                       |

You only need to supply the subroutines you care about. Unset slots get Fastly's defaults. The server wraps your body in the standard `sub vcl_<name> { #FASTLY <name> ... }` scaffolding — do not include the `sub` wrapper yourself.

## VCL string concatenation

Fastly VCL concatenates strings either with the `+` operator or by **juxtaposition** (whitespace-separated operands). Both produce identical bytecode and identical workspace allocations — pick one for readability. Operands may be:

- string constants (`"..."` or the heredoc form `{"..."}`),
- variables (`req.http.X`, `workspace.bytes_free`, etc. — INT/BOOL auto-coerce to STRING in concat position),
- function calls (`std.tolower(req.url)`, `regsub(...)`, ...).

Operands may **not** be parenthesized sub-expressions. This is the single most common source of confusing lint errors from the Fastly VCL compiler, including via the Fiddle lint API.

| Form                                                         | Valid? |
| ------------------------------------------------------------ | ------ |
| `set X = "a" + "b";`                                         | ✅     |
| `set X = "a" "b";` (juxtaposition)                           | ✅     |
| `set X = req.http.A + req.http.B;`                           | ✅     |
| `set X = "pre-" + req.http.A + "-post";`                     | ✅     |
| `set X = {"a"} + {"b"};`                                     | ✅     |
| `set X = "free=" + workspace.bytes_free;` (INT auto-coerces) | ✅     |
| `synthetic "a" + req.http.X + "b";`                          | ✅     |
| `set X = "used=" + (1000 - 40);`                             | ❌     |
| `set X = "n=" + (std.atoi(req.http.A) - 1);`                 | ❌     |

The invalid rows produce:

```text
warning  Encountered `+` after string expression.
         Suggested: Remove the trailing `+` operator.
error    Expected string constant, variable, call, or semicolon but got `(`
```

**The "remove the `+`" suggestion is wrong.** The `+` is fine; the `(` is the problem. To embed an arithmetic result in a string, compute it into a variable first.

Note a second, independent constraint: Fastly VCL has no binary arithmetic operator in a `set`, so `set var.used = a - b;` also fails to compile (`Expected ';', got '-'`). Build the value with compound-assignment operators (`+=`, `-=`, …) instead:

```vcl
# Bad: parenthesized expression as a concat operand
set req.http.X = "used=" + (std.atoi(req.http.Total) - std.atoi(req.http.Free));

# Good: compute into a local variable with compound assignment, then concat
declare local var.used INTEGER;
set var.used = std.atoi(req.http.Total);
set var.used -= std.atoi(req.http.Free);
set req.http.X = "used=" + var.used;
```

The same rule applies inside `synthetic`:

```vcl
# Valid: all operands are strings, vars, or calls
synthetic {"free="} + workspace.bytes_free + {"\n"};

# Invalid: parenthesized arithmetic mid-concat
synthetic {"used="} + (workspace.bytes_total - workspace.bytes_free);
```

Workspace impact: every `+` (or juxtaposition) in a `set` allocates a **new** buffer in the per-request workspace; the previous buffer is not freed until end-of-request. Building a large string by repeated self-concatenation (`set X = X + chunk;` in a loop-shaped pattern) is a known way to exhaust workspace and trip `503 WorkspaceOverflow`. See the worked example at <https://fiddle.fastly.dev/fiddle/ecbc9b26>.

## Error codes: use 6xx for synthetics

Fiddle lint rejects `error` codes in the **800–999** range — in any subroutine and in any context (bare, `if`, `else`, `switch`) — with `valid: false` and:

```text
8xx and 9xx error codes are used internally by Fastly.  Use 6xx instead.
```

Codes 400–799 are accepted. Use the **6xx** range for synthetics you raise (`error 601;`, `error 602 "<url>";`).

For redirects, raise `error 602 "<url>";` and build the 301 in `vcl_error`:

```vcl
# vcl_recv
if (req.url.path == "/old") { error 602 "https://www.example.com/new"; }

# vcl_error
if (obj.status == 602) {
  set obj.http.Location = obj.response;
  set obj.status = 301;
  set obj.response = "Moved Permanently";
  synthetic {""};
  return(deliver);
}
```

## Origins

```json
"origins": ["https://http-me.fastly.dev", "https://api.example.com"]
```

- Max 5.
- Include scheme (`https://` or `http://`).
- In VCL, reference as `F_origin_0`, `F_origin_1`, etc. Example:

```vcl
set req.backend = F_origin_0;
```

## Request objects

Each entry in `requests[]`:

```json
{
  "method": "GET",
  "path": "/robots.txt",
  "headers": "",
  "body": "",
  "data": {},
  "enableCluster": true,
  "enableShield": false,
  "useFreshCache": false,
  "connType": "h2",
  "sourceIP": "client",
  "followRedirects": false,
  "tests": "clientFetch.status is 200\noriginFetches.count() is 0",
  "delay": 0
}
```

### Fields you usually set

| Field     | Default | Notes                                                                                                     |
| --------- | ------- | --------------------------------------------------------------------------------------------------------- |
| `method`  | `"GET"` | HTTP method.                                                                                              |
| `path`    | —       | Path + query. The Host header is derived from the fiddle's execHost.                                      |
| `headers` | `""`    | Raw HTTP headers, one per line (`"Header-Name: value\nOther: x"`).                                        |
| `body`    | `""`    | Request body as string.                                                                                   |
| `tests`   | `""`    | Assertion list. Send as array on input; stored as newline-joined string. See the `test-dsl.md` reference. |
| `delay`   | `0`     | Milliseconds to wait after the previous request. Use for cache TTL / rate-limit tests.                    |

### Fields you rarely touch (but should know)

| Field             | Default    | Effect                                                                                                                                                                                                                                                                                             |
| ----------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `enableCluster`   | `true`     | Enables Fastly's cluster fetch (real production behavior).                                                                                                                                                                                                                                         |
| `enableShield`    | `false`    | Enables shielding. Turn on to test shield-related VCL (`fastly.ff.visits_this_service`).                                                                                                                                                                                                           |
| `useFreshCache`   | `false`    | Forces a fresh cache for this request, ignoring the session `cacheID`. **Set to `true` for any request whose assertions look at `originFetches.count()` / `originFetches[0].*` if it might run after a warmup or under retry** — a cache HIT silently turns `originFetches.count() is 1` into `0`. |
| `connType`        | `"h2"`     | `"h2"` or `"h1"`. Matters if your VCL branches on `fastly_info.is_h2` etc.                                                                                                                                                                                                                         |
| `sourceIP`        | `"client"` | `"client"` means Fastly synthesizes one. Can be set to specific IPs for geo tests.                                                                                                                                                                                                                 |
| `followRedirects` | `false`    | Whether the test client follows 3xx.                                                                                                                                                                                                                                                               |

### `tests`: array in, string out

Wire quirk worth repeating. Send:

```json
"tests": ["clientFetch.status is 200", "clientFetch.bodyPreview includes \"OK\""]
```

A subsequent `GET` returns:

```json
"tests": "clientFetch.status is 200\nclientFetch.bodyPreview includes \"OK\""
```

When round-tripping a fiddle, split on `\n` before editing individual assertions.

## Compute fiddles

`type: "compute"` fiddles have a different shape (`src` contains source files keyed by path, plus `manifest`). This skill focuses on VCL fiddles. For Compute, use `viceroy` or `fastlike` locally instead of Fiddle — the iteration loop is much faster.

## Minimal valid fiddle

```json
{
  "origins": ["https://http-me.fastly.dev"],
  "vcl": { "recv": "" }
}
```

Everything else defaults.

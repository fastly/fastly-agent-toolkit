# Profiling Fastlike Guests

Fastlike has a built-in profiler that captures per-request hostcall timings, backend waterfalls, optional native CPU samples, and (in deep mode) body byte counters, cache hit/miss rates, header summaries, and a wasm linear memory size curve. Traces live in a per-`Fastlike` LRU and are served on a separate read-only HTTP listener.

Source: `docs/profiling.md` and `profile*.go` files in `~/src/fastlike`.

## Enabling the Profiler

The single flag you usually need is `-profile-ui`. It enables the viewer on its own listener; the wasm bind is untouched.

```bash
bin/fastlike -backend api=localhost:8080 -profile-ui localhost:6060 app.wasm
```

The default `-profile` mode is `trace`, which captures hostcall spans, backend phases, and outcome classification. Collection runs whether or not the UI is bound — `-profile-ui` only controls the viewer.

## Profile Modes (`-profile MODE`)

| Mode       | What it captures                                                                                                                                                                                                                   |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `off`      | No per-request trace allocation.                                                                                                                                                                                                   |
| `trace`    | (default) Hostcall spans, backend waterfall, header-flush and hijack markers, outcome classification (`normal`, `trap`, `panic`, `loop-fail`, `ctx-canceled`).                                                                     |
| `native`   | `trace` plus wasmtime jitdump for `perf record` (Linux) or `samply` (macOS).                                                                                                                                                       |
| `combined` | Currently identical to `native`. Reserved for future sampling integrations.                                                                                                                                                        |
| `deep`     | `trace` plus body read/write byte totals, cache hit/miss/insert/stale counts, per-named-store access counts, request/response header name + size summaries (with deny-listed names redacted), and a wasm linear memory size curve. |

Deep mode is opt-in. It never captures header values, body bytes, secret/KV/dictionary/cache key values, surrogate keys, URL userinfo, URL query strings, or Go host heap — the in-memory trace has no field for them.

## Endpoints

All paths live on the `-profile-ui` listener. Use the JSON endpoints when consuming traces programmatically.

| Endpoint                       | Purpose                                                                                                            |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `GET /`                        | HTML index of recent traces (newest first). Shows method, URL, status, outcome, wall + hostcall time, span counts. |
| `GET /r/{req_id}`              | Per-request HTML page with waterfall, span table, deep tables, and a canvas timeline.                              |
| `GET /r/{req_id}.json`         | **Canonical native JSON trace.** Parse this for programmatic analysis.                                             |
| `GET /r/{req_id}.chrome.json`  | Chrome Tracing / Perfetto export.                                                                                  |
| `GET /r/{req_id}.firefox.json` | Firefox profiler Gecko export.                                                                                     |
| `GET /r/{req_id}.pprof`        | gzip-compressed `profile.proto`. Pipe through `go tool pprof`.                                                     |

The index is the way to discover a recent `req_id`; there is no search API. Newest trace is first.

## Native JSON Schema

The `/r/{id}.json` payload is the source of truth — other encoders are derived views. Top-level fields:

```jsonc
{
  "req_id": 42,
  "module_id": "abc123...",
  "method": "GET",
  "url": "/path",                       // userinfo + query already redacted
  "status": 200,
  "wall_start": "2026-05-23T...",        // RFC3339 with nanos
  "wall_nanos": 12500000,                // total wall time
  "guest_active_nanos": 8000000,         // wasm execution time
  "hostcall_nanos": 3500000,             // time spent in host functions
  "header_flush_nanos": 1200000,         // optional: TTFB to downstream client
  "native_cpu_nanos": 4200000,           // optional: only when native samples merged
  "hijacked_nanos": null,                // optional: present for websocket / streaming hijacks
  "spans":         [ {"relative_nanos": 0, "function": "req_send"} ],
  "backend_calls": [ /* see below */ ],
  "native_samples": [],                  // populated only after MergeNativeSamples
  "dropped": 0,                          // span overflow count
  "dropped_backend_calls": 0,            // backend overflow count
  "outcome": "normal",                   // normal|trap|panic|loop-fail|ctx-canceled
  "notes": [],
  "deep": { /* present iff -profile=deep, see below */ }
}
```

### Span entries

Spans are hostcall start markers, recorded at their offset from `wall_start`:

```jsonc
{ "relative_nanos": 1234567, "function": "xqd_req_send" }
```

### Backend call entries

```jsonc
{
  "pending_id": 1,
  "name": "api",
  "method": "GET",
  "url_redacted": "https://api.example.com/v1/...",
  "started_nanos": 500000,
  "dns_nanos": 1200000,
  "connect_nanos": 800000,
  "tls_nanos": 1400000,
  "ttfb_nanos": 4500000,
  "total_nanos": 9800000,
  "status": 200,
  "req_header_bytes": 412,
  "resp_header_bytes": 287,
  "outcome": "ok"            // ok|network-error|synthetic-failure|cancelled|incomplete|orphaned
}
```

Phase fields (`dns_nanos`, `connect_nanos`, `tls_nanos`, `ttfb_nanos`) are only populated for backends registered with `WithBackendTraced` (see *Embedder API*). For plain `WithBackend` they are null and only `total_nanos` is set.

### Deep metrics

Present only when `-profile=deep`:

```jsonc
"deep": {
  "body_read_bytes": 0,
  "body_write_bytes": 4096,
  "cache_lookups": 1, "cache_hits": 0, "cache_misses": 1, "cache_inserts": 1, "cache_stale": 0,
  "request_headers":  [ {"name": "user-agent", "count": 1, "bytes": 87} ],
  "response_headers": [ {"name": "<redacted>", "count": 1, "bytes": 312} ],  // Set-Cookie etc.
  "heap_samples":     [ {"relative_nanos": 0, "memory_bytes": 1048576} ],
  "heap_samples_dropped": 0,
  "store_access":     [ {"kind": "kv", "name": "sessions", "count": 3} ]
}
```

Headers redacted to `<redacted>` (case-insensitive): `Cookie`, `Set-Cookie`, `Authorization`, `Proxy-Authorization`, `X-Api-Key`, `Proxy-Authenticate`, `WWW-Authenticate`. Byte sizes still count, so a huge Cookie is still visible in the totals.

Heap samples are wasm linear memory size at request start, finalize, and hostcall boundaries. The series is deduped (only growth is recorded — wasm memory is monotonic). Per-request cap is 1024 samples; overflow lands in `heap_samples_dropped`.

## Security Gates

The CLI refuses to start the UI in unsafe combinations. The rules are evaluated before either listener binds, so a failure prints before "profiler UI at...".

- Loopback bind (`127.0.0.0/8`, `::1`, `localhost`, unix socket path): no auth required.
- Non-loopback bind: **requires** either `-profile-auth TOKEN` (bearer auth enforced on every request) **or** explicit `-profile-insecure-ui`. Missing both is a startup error that names the flag to add.
- `-profile-insecure-ui` is meant for externalised auth (mTLS, authenticating reverse proxy) and prints a prominent startup warning.

The UI listener is never auto-mounted on the wasm `-bind` socket. They are always distinct.

## Full CLI Reference

| Flag                       | Default | Description                                                                                                               |
| -------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------- |
| `-profile MODE`            | `trace` | `off`, `trace`, `native`, `combined`, `deep`.                                                                             |
| `-profile-ui ADDR`         | empty   | Bind UI on ADDR. Empty disables the UI listener; collection still runs.                                                   |
| `-profile-auth TOKEN`      | empty   | Required `Authorization: Bearer TOKEN` on every UI request. Required for non-loopback `-profile-ui` unless insecure flag. |
| `-profile-insecure-ui`     | false   | Permit non-loopback `-profile-ui` without `-profile-auth`. Logs a startup warning.                                        |
| `-profile-dir PATH`        | cwd     | Directory for `wasm-symbols-{pid}.json` (native mode only).                                                               |
| `-profile-retain N`        | 256     | LRU size for completed traces.                                                                                            |
| `-profile-backend-cap N`   | 512     | Per-request cap on recorded backend calls. Overflow still executes; phase data is dropped into `dropped_backend_calls`.   |
| `-profile-async-grace DUR` | 100ms   | Time `finalizeTrace` waits for in-flight async backend goroutines. Pass `0` to disable.                                   |

## Native Sampling Integration

When `-profile native` or `-profile combined` is set on Linux, fastlike configures wasmtime with jitdump so `perf record` attributes samples to wasm functions. On macOS the same jitdump is consumed by [`samply`](https://github.com/mstange/samply). `wasmtime-go` v38 currently only wraps jitdump (no perfmap or vtune).

Fastlike writes `wasm-symbols-{pid}.json` to `-profile-dir` at startup so external samplers can map wasm exports back to names:

```jsonc
{ "pid": 12345, "module_id": "abc123...", "mode": "combined",
  "exports": [ {"name": "_start", "kind": "func"} ] }
```

To join `perf script` output back into in-process traces, **record with `perf record -k CLOCK_REALTIME`**. Without `-k`, perf uses `CLOCK_MONOTONIC`, which has a different epoch and every sample drops at the time-window gate. The merge is via `fastlike.MergeNativeSamples(store, events, pid, moduleID)` and filters on PID + time window + module ID.

## Embedder API

Functional options on `*Fastlike`:

```go
fl := fastlike.New("app.wasm",
    fastlike.WithProfileMode(fastlike.ProfileModeDeep),
    fastlike.WithProfileUI("localhost:6060"),
    fastlike.WithProfileRetain(512),
    fastlike.WithInstanceOptions(
        fastlike.WithBackendTraced("api", apiProxy, sharedTransport),
    ),
)
```

- `WithBackendTraced(name, handler, transport)` opts a backend into per-phase timing (DNS / connect / TLS / TTFB). The `*http.Transport` is embedder-owned — fastlike never clones, mutates, or closes it.
- Plain `WithBackend(name, handler)` keeps total-span timing only; phase fields stay null.
- `fl.ProfileStore()` exposes the store. `store.Recent(n)` returns the most recent `n` `*RequestTrace` values; iterate them for programmatic inspection.
- Encoders are stateless `*RequestTrace → []byte`: `EncodeChromeTrace`, `EncodeFirefoxGecko`, `EncodePprof`. They respect the privacy contract because the trace struct has no field for redacted data.

```go
for _, tr := range fl.ProfileStore().Recent(10) {
    fmt.Printf("req=%d outcome=%s wall=%dns hostcall=%dns\n",
        tr.ReqID, tr.Outcome, tr.WallNanos, tr.HostcallNanos)
}
```

## Practical Patterns

**Quickly inspect the last request as JSON:**

```bash
# Get newest req_id from the index, then pull its JSON.
curl -s http://localhost:6060/ | grep -oE '/r/[0-9]+' | head -1 \
  | xargs -I{} curl -s "http://localhost:6060{}.json" | jq .
```

**pprof analysis:**

```bash
curl -s http://localhost:6060/r/42.pprof | go tool pprof -http=:8081 -
```

**Deep-mode diagnostics for a slow request** — enable `-profile=deep`, then look at:

- `wall_nanos` vs. `hostcall_nanos` — high host time means slow hostcalls; low host time means slow guest computation.
- `backend_calls[].ttfb_nanos` against `total_nanos` — high TTFB share means slow upstream; high non-TTFB tail means slow body read.
- `deep.cache_misses` vs. `cache_hits` — cold cache or poor key reuse.
- `deep.heap_samples` final vs. initial `memory_bytes` — wasm memory growth indicates large in-guest allocations.
- `dropped` / `dropped_backend_calls` non-zero — raise `-profile-backend-cap` or treat the trace as truncated.

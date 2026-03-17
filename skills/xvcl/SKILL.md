---
name: xvcl
description: "Compiles XVCL metaprogramming directives (#const, #for, #def, #inline, #if, #let, #include) into Fastly VCL. Required for .xvcl files — XVCL syntax is not in training data. Workflow: write XVCL, compile with `uvx xvcl`, test with falco."
---

## Trigger and scope

Trigger on: XVCL, .xvcl files, VCL transpiler, VCL metaprogramming, #const/#for/#def/#inline in VCL context, writing a VCL script, writing VCL and running it locally, or any Fastly VCL writing task.

Do NOT trigger for: debugging existing .vcl files without XVCL, Fastly API/CLI ops, Fastly Compute, or Terraform — even if they mention VCL.

# Writing VCL with XVCL

XVCL is a VCL transpiler that adds metaprogramming to Fastly VCL. Write `.xvcl` files, compile to `.vcl`, then test with Falco or deploy to Fastly. All XVCL constructs are resolved at compile time — zero runtime overhead.

## Quick Start

```bash
# Compile (no install needed with uvx)
uvx xvcl main.xvcl -o main.vcl

# Lint the output
falco lint main.vcl

# Run locally — this is how you "run" VCL on your machine
falco simulate main.vcl
# Listens on localhost:3124 by default
# Then test with: curl http://localhost:3124/
```

When the user asks to "run locally" or "test locally", always compile **and** run `falco simulate` — linting alone doesn't run the VCL.

## Minimal Working Example

**Backend naming**: Fastly VCL requires backends to use `F_` prefixed names (e.g., `F_origin`, `F_api`). Never use `backend default` — falco will reject it. Always set `req.backend` explicitly in `vcl_recv`.

```xvcl
#const ORIGIN_HOST = "api.example.com"
#const REGIONS = [("us", "us.example.com"), ("eu", "eu.example.com")]

#for name, host in REGIONS
backend F_{{name}} {
  .host = "{{host}}";
  .port = "443";
  .ssl = true;
}
#endfor

sub vcl_recv {
  #FASTLY recv
  set req.backend = F_us;
  return (lookup);
}

sub vcl_deliver {
  #FASTLY deliver
  set resp.http.X-Served-By = "edge";
  return (deliver);
}
```

## XVCL Directives Summary

Read [xvcl-directives.md](references/xvcl-directives.md) for complete syntax and examples of every directive.

### Constants — `#const`
```xvcl
#const NAME = value              // type auto-inferred
#const NAME TYPE = value         // explicit type
#const TTL INTEGER = 3600
#const ORIGIN = "origin.example.com"
#const ENABLED BOOL = true
#const DOUBLE_TTL = TTL * 2      // expressions supported
#const BACKENDS = ["web1", "web2"] // lists
#const PAIRS = [("api", 8080), ("web", 80)] // tuples
```

Constants are **compile-time only** — they do NOT become VCL variables. Always use `{{NAME}}` to emit their value. A bare constant name in VCL (e.g., `error 200 GREETING;`) passes through as a literal string, producing invalid VCL. Use `error 200 "{{GREETING}}";` instead.

Use in templates: `"{{TTL}}"`, `{{ORIGIN}}`, `backend F_{{name}} { ... }`

### Template Expressions — `{{ }}`
```xvcl
{{CONST_NAME}}                   // constant substitution
{{PORT * 2}}                     // arithmetic
{{hex(255)}}                     // → "0xff"
{{format(42, '05d')}}            // → "00042"
{{len(BACKENDS)}}                // list length
{{value if condition else other}} // ternary
```

Built-in functions: `range()`, `len()`, `str()`, `int()`, `hex()`, `format()`, `enumerate()`, `min()`, `max()`, `abs()`

### For Loops — `#for` / `#endfor`
```xvcl
#for i in range(5)               // 0..4
#for i in range(2, 8)            // 2..7
#for item in LIST_CONST          // iterate list
#for name, host in TUPLES        // tuple unpacking
#for idx, item in enumerate(LIST) // index + value
```

### Conditionals — `#if` / `#elif` / `#else` / `#endif`
```xvcl
#if PRODUCTION
  set req.http.X-Env = "prod";
#elif STAGING
  set req.http.X-Env = "staging";
#else
  set req.http.X-Env = "dev";
#endif
```

Supports: boolean constants, comparisons (`==`, `!=`, `<`, `>`), operators (`and`, `or`, `not`).

### Variable Shorthand — `#let`
```xvcl
#let cache_key STRING = req.url.path;
// expands to:
// declare local var.cache_key STRING;
// set var.cache_key = req.url.path;
```

### Functions — `#def` / `#enddef`
```xvcl
// Single return value
#def normalize_path(path STRING) -> STRING
  declare local var.result STRING;
  set var.result = std.tolower(path);
  return var.result;
#enddef

// Tuple return (multiple values)
#def parse_pair(s STRING) -> (STRING, STRING)
  declare local var.key STRING;
  declare local var.value STRING;
  set var.key = regsub(s, ":.*", "");
  set var.value = regsub(s, "^[^:]*:", "");
  return var.key, var.value;
#enddef

// Call sites
set var.clean = normalize_path(req.url.path);
set var.k, var.v = parse_pair("host:example.com");
```

Functions compile to VCL subroutines with parameters passed via `req.http.X-Func-*` headers.

### Inline Macros — `#inline` / `#endinline`
```xvcl
#inline cache_key(url, host)
digest.hash_md5(url + "|" + host)
#endinline

// Zero-overhead text substitution. Auto-parenthesizes arguments
// containing operators to prevent precedence bugs.
set req.hash += cache_key(req.url, req.http.Host);
```

### Includes — `#include`
```xvcl
#include "includes/backends.xvcl"  // relative path
#include <stdlib/security.xvcl>    // include path (-I)
```

Include-once semantics. Circular includes are detected and reported.

## Compilation

```bash
# Basic
uvx xvcl input.xvcl -o output.vcl

# With include paths
uvx xvcl main.xvcl -o main.vcl -I ./includes -I ./shared

# Debug mode (shows expansion traces)
uvx xvcl main.xvcl -o main.vcl --debug

# Source maps (adds BEGIN/END INCLUDE markers)
uvx xvcl main.xvcl -o main.vcl --source-maps
```

| Option | Description |
|--------|-------------|
| `-o, --output` | Output file (default: replace `.xvcl` with `.vcl`) |
| `-I, --include` | Add include search path (repeatable) |
| `--debug` / `-v` | Show expansion traces |
| `--source-maps` | Add source location comments |

## References

For VCL basics (request lifecycle, return actions, variable types), see the VCL syntax and subroutines references below.

Read the relevant reference file completely before implementing specific features.

| Topic | File | Use when... |
|-------|------|-------------|
| **XVCL Directives** | [xvcl-directives.md](references/xvcl-directives.md) | Writing any XVCL code — complete syntax for all directives |
| VCL Syntax | [vcl-syntax.md](references/vcl-syntax.md) | Working with data types, operators, control flow |
| Subroutines | [subroutines.md](references/subroutines.md) | Understanding request lifecycle, custom subs |
| Headers | [headers.md](references/headers.md) | Manipulating HTTP headers |
| Backends | [backends.md](references/backends.md) | Configuring origins, directors, health checks |
| Caching | [caching.md](references/caching.md) | Setting TTL, grace periods, cache keys |
| Strings | [strings.md](references/strings.md) | String manipulation functions |
| Crypto | [crypto.md](references/crypto.md) | Hashing, HMAC, base64 encoding |
| Tables/ACLs | [tables-acls.md](references/tables-acls.md) | Lookup tables, access control lists |
| Testing VCL | [testing-vcl.md](references/testing-vcl.md) | Writing unit tests, assertions, test helpers |

## Project Structure

```
vcl/
├── main.xvcl
├── config.xvcl          # shared constants
└── includes/
    ├── backends.xvcl
    ├── security.xvcl
    ├── routing.xvcl
    └── caching.xvcl
```

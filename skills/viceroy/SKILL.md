---
name: viceroy
description: "Runs Fastly Compute WASM applications locally with Viceroy. Use when starting a local Compute development server, configuring fastly.toml for local backends/stores, running Rust unit tests with cargo-nextest, or adapting core WASM modules to the Component Model."
---

# Viceroy — Local Fastly Compute Runtime

Viceroy is Fastly's official local testing environment for Compute applications. It emulates the Fastly Compute platform, allowing you to develop and test WASM services locally.

**Viceroy documentation**: https://github.com/fastly/Viceroy

## Quick Start

```bash
# Install Viceroy
cargo install --locked viceroy

# Build your Compute app
fastly compute build

# Start local server (default: 127.0.0.1:7676)
viceroy -C fastly.toml bin/main.wasm

# Or use the Fastly CLI wrapper
fastly compute serve
```

## References

| Topic  | File                                                            | Use when...                                                                    |
| ------ | --------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Serve  | [fastly-compute-serve.md](references/fastly-compute-serve.md)   | Starting local dev server, profiling, advanced server options                  |
| Config | [fastly-compute-config.md](references/fastly-compute-config.md) | Configuring fastly.toml backends, stores, geolocation, device detection, ACLs  |
| Test   | [fastly-compute-test.md](references/fastly-compute-test.md)     | Running Rust unit tests with cargo-nextest, writing tests for Compute services |
| Adapt  | [fastly-compute-adapt.md](references/fastly-compute-adapt.md)   | Converting core WASM modules to Component Model, custom build pipelines        |

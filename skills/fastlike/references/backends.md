# Fastlike Backend Configuration

Backends are origin servers that your Fastly Compute WASM program proxies requests to.

## Backend Syntax

```bash
# Named backend (your WASM references "api" by name)
-backend api=api.example.com:8080

# Catch-all backend (used when name doesn't match)
-backend localhost:8000

# Short form
-b api=api.example.com:8080
```

## Common Patterns

**Single origin:**
```bash
bin/fastlike -wasm app.wasm -backend localhost:3000
```

**Multiple named backends:**
```bash
bin/fastlike -wasm app.wasm \
  -backend api=localhost:3000 \
  -backend static=localhost:4000 \
  -backend auth=localhost:5001
```

**Named + catch-all fallback:**
```bash
bin/fastlike -wasm app.wasm \
  -backend api=api.internal:8080 \
  -backend localhost:8000
```
Requests to backend "api" go to `api.internal:8080`, all others to `localhost:8000`.

**Microservices setup:**
```bash
bin/fastlike -wasm gateway.wasm \
  -backend users=users-service:3001 \
  -backend orders=orders-service:3002 \
  -backend inventory=inventory-service:3003 \
  -backend payments=payments-service:3004
```

## Simulating Flaky Backends

Append `@N` to a backend address to make it succeed only `N` percent of the time. The other requests get a synthetic 502 — the same shape Fastlike returns when a real upstream is unreachable, so the guest's error path runs exactly as it would in production.

```bash
# api succeeds for ~50% of requests, the rest return 502
bin/fastlike -wasm app.wasm -backend api=localhost:8000@50

# cdn always appears down
bin/fastlike -wasm app.wasm -backend cdn=localhost:9000@0

# catch-all backend with simulated reliability
bin/fastlike -wasm app.wasm -backend localhost:8000@75
```

The suffix is only recognized when it is purely numeric and falls in `0..100`, so URLs that legitimately contain `@` (like `http://user:pass@host`) are passed through untouched. A trailing `@<digits>` outside that range is rejected at startup. The same hooks are available programmatically as `fastlike.WithUnreliableBackend` and `fastlike.WithUnreliableDefaultBackend`.

## How Backends Work

1. Your WASM calls the Fastly Compute ABI to make a backend request with a name
2. Fastlike looks up the backend by name
3. If found, proxies to that backend's address
4. If not found and a catch-all exists, uses the catch-all
5. If not found and no catch-all, returns 502 Bad Gateway

## Backend Address Format

- `hostname:port` - Standard format
- `localhost:8000` - Local development servers
- `service-name:port` - Docker Compose service names
- `192.168.1.100:8080` - Direct IP addresses

Backends create HTTP reverse proxies. HTTPS is not directly supported for local backends.

## Testing Backends

Start your backend services first, then run fastlike:

```bash
# Terminal 1: Start your backend
cd backend && npm start  # Runs on :3000

# Terminal 2: Start fastlike
bin/fastlike -wasm app.wasm -backend localhost:3000 -v 2
```

Use `-v 2` for verbose logging to see backend requests.

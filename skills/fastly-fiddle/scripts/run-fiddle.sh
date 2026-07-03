#!/usr/bin/env bash
# Publish a Fastly Fiddle, execute it, stream results, and report pass/fail.
#
# Usage:
#   run-fiddle.sh <fiddle.json>                    # POST (publish) + execute
#   run-fiddle.sh --id <fiddle-id-or-url>          # execute existing, no publish
#   run-fiddle.sh --id <fiddle-id> <fiddle.json>   # PUT (update) + execute
#
#   run-fiddle.sh --lint-only <fiddle.json>        # POST + report lint, no exec
#
#   Common flags: [--cache-id N] [--max-wait SECONDS] [--retries N]
#                 [--lint-only] [--ua STRING] [--no-bodies] [--quiet] [--debug]
#
# Defaults:
#   --cache-id   random per invocation, drawn from /dev/urandom. Two
#                back-to-back runs against the same fiddle do NOT share
#                cache; pass a fixed value (e.g. --cache-id 1) to share.
#   --max-wait   180 seconds, applied per attempt (cold publishes routinely
#                take 60-120s; warm --id re-executes finish in ~2-5s)
#   --retries    2 — re-execute on transient stream-closed/server-timeout
#                without re-publishing. Total attempts = retries + 1.
#   --ua         fastly-fiddle-skill/1.5
#
# Inputs:
#   <fiddle.json>   Fiddle spec (origins, vcl, requests with optional tests[]).
#                   Either `vcl` or `src` keys are accepted on input. `tests`
#                   may be either an array of strings or a "\n"-joined string.
#                   Validated locally for shape and known wire-format gotchas.
#                   Pass `-` to read the spec from stdin.
#   --id <id|url>   Skip POST. Bare ID or full https://fiddle.fastly.dev/...
#                   URL accepted. Without a spec file, just re-execute against
#                   the existing fiddle — by far the fastest path (no resync).
#                   With a spec file, PUT updates the fiddle in place: URL
#                   stays stable, but the new VCL recompiles and propagates,
#                   so expect another ~10-120s edge-sync wait. PUT is not
#                   partial: omitted subroutines are cleared.
#   --lint-only     Publish (POST, or PUT with --id) and report {valid,
#                   lintStatus} only. Skips /execute, the SSE stream, and the
#                   edge-sync wait entirely — a ~1-3s "does this compile?"
#                   check instead of the 10-120s publish+execute round trip.
#                   Use it whenever you don't need runtime assertion results;
#                   the spec on disk is untouched. Requires a spec file.
#   --no-bodies     Omit `status`, `content_type`, and `body_preview` from
#                   each result in the JSON output. The default is to include
#                   them; use this flag for compact machine-readable output.
#   --debug         Retain raw payload + merged-state files; print paths on
#                   exit. Files are also kept on any non-zero exit so failures
#                   are inspectable.
#
# Output (stdout):
#   { "fiddle_id": "...", "url": "...", "valid": true,
#     "complete": true|false,
#     "expected_total": N, "reported_total": N,
#     "attempts": N, "end_reason": "...",
#     "results": [ { "seq": 0, "req": "GET /... HTTP/1.1\n...",
#                    "tests": [...] }, ... ],
#     "summary": { "total": N, "passed": N, "failed": N } }
#
#   `seq` is the row's index in `results[]`, NOT the spec's `requests[i]`
#   index. Rows are ordered lexicographically by the raw HTTP request line
#   (a side effect of jq's sorted object iteration over our request-keyed
#   merge state). That ordering is stable across re-executes of the same
#   fiddle but does not match either declaration order or completion order.
#   Each result row carries the raw HTTP request line in `req` so consumers
#   can correlate output to the spec by matching method/path/headers.
#
#   Each result carries `status` (int), `content_type` (string or null), and
#   `body_preview` (string, truncated by Fiddle) by default. Pass --no-bodies
#   to omit them for compact machine-readable output.
#
# Stderr:
#   Human-readable progress: published URL, edge-sync waits, retry hints,
#   verdict counts. Suppressed by --quiet (errors and warnings still print).
#
# Exit codes:
#   0  all assertions passed (or the fiddle had no assertions)
#   1  usage / IO / HTTP error
#   2  fiddle invalid (lint failure) — see .lintStatus on stderr
#   3  one or more assertions failed
#   4  timed out before all expected assertions reported, even after retries
#
# Requires: curl (>=7.76 for --fail-with-body), jq.

set -euo pipefail

UA='fastly-fiddle-skill/1.5'
MAX_WAIT=180
RETRIES=2
QUIET=0
DEBUG=0
SHOW_BODIES=1
LINT_ONLY=0
BASE='https://fiddle.fastly.dev'
# Cap the JSON round trip on /fiddle endpoints (POST/PUT/GET). Independent
# of the SSE stream's MAX_WAIT budget. Bump if your network is slow.
API_TIMEOUT=30

# Wider entropy than $RANDOM (which is 0-32767, PID+time seeded — concurrent
# invocations regularly collide and silently share cache).
default_cache_id() {
  if [[ -r /dev/urandom ]]; then
    od -An -N4 -tu4 </dev/urandom | tr -d ' \n'
  else
    printf '%s' "${RANDOM:-1}"
  fi
}
CACHE_ID=$(default_cache_id)

# Usage block printed on errors (stderr, exit 1) or explicit help (stdout, exit 0).
_print_usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }
usage() { _print_usage >&2; exit 1; }
help()  { _print_usage;      exit 0; }

SPEC_FILE=""
FID_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --id)       [[ $# -ge 2 ]] || { echo "--id requires a value" >&2; usage; }; FID_OVERRIDE=$2; shift 2 ;;
    --cache-id) [[ $# -ge 2 ]] || { echo "--cache-id requires a value" >&2; usage; }; CACHE_ID=$2; shift 2 ;;
    --max-wait) [[ $# -ge 2 ]] || { echo "--max-wait requires a value" >&2; usage; }; MAX_WAIT=$2; shift 2 ;;
    --retries)  [[ $# -ge 2 ]] || { echo "--retries requires a value" >&2; usage; }; RETRIES=$2; shift 2 ;;
    --ua)       [[ $# -ge 2 ]] || { echo "--ua requires a value" >&2; usage; }; UA=$2; shift 2 ;;
    --quiet|-q) QUIET=1; shift ;;
    --lint-only)  LINT_ONLY=1; shift ;;
    --no-bodies)  SHOW_BODIES=0; shift ;;
    --show-bodies|--verbose|-v) SHOW_BODIES=1; shift ;; # kept for back-compat
    --debug)    DEBUG=1; shift ;;
    -h|--help)  help ;;
    --)         shift; [[ $# -gt 0 && -z $SPEC_FILE ]] && { SPEC_FILE=$1; shift; }; ;;
    -)          if [[ -z $SPEC_FILE ]]; then SPEC_FILE=-; shift
                else echo "unexpected positional arg: $1" >&2; usage; fi ;;
    -*)         echo "unknown arg: $1" >&2; usage ;;
    *)          if [[ -z $SPEC_FILE ]]; then SPEC_FILE=$1; shift
                else echo "unexpected positional arg: $1" >&2; usage; fi ;;
  esac
done

# Accept full fiddle URL anywhere a bare ID is expected. People paste URLs.
# Strip the scheme/host/path prefix, then everything from the first /, ?, or #.
# Reject anything that doesn't look like a fiddle ID (8 lowercase hex chars,
# per references/api.md) so a paste of e.g. https://fiddle.fastly.dev/embedded/abc123
# doesn't silently turn into FID="embedded" and fail later with a 404.
if [[ -n $FID_OVERRIDE ]]; then
  FID_OVERRIDE=${FID_OVERRIDE#http://fiddle.fastly.dev/fiddle/}
  FID_OVERRIDE=${FID_OVERRIDE#https://fiddle.fastly.dev/fiddle/}
  FID_OVERRIDE=${FID_OVERRIDE%%[/?#]*}
  if [[ ! $FID_OVERRIDE =~ ^[0-9a-f]{8}$ ]]; then
    echo "--id does not look like a fiddle ID (expected 8 lowercase hex chars, got: $FID_OVERRIDE)" >&2
    exit 1
  fi
fi

if [[ -z $FID_OVERRIDE && -z $SPEC_FILE ]]; then
  echo "need either <fiddle.json> or --id <fiddle-id>" >&2
  usage
fi
if [[ $LINT_ONLY == 1 && -z $SPEC_FILE ]]; then
  # A bare --id has nothing to lint: GET's `valid` tracks execution, not
  # compilation (see references/spec-shape.md gotcha on the GET valid flag).
  echo "--lint-only needs a <fiddle.json> spec to compile" >&2
  usage
fi
# Stdin support: slurp `-` into a tempfile so we can validate, count tests,
# and pass to curl as a regular file. Cleaned up alongside the other temp
# files in cleanup().
STDIN_SPEC_FILE=""
if [[ $SPEC_FILE == "-" ]]; then
  STDIN_SPEC_FILE=$(mktemp -t fiddle-stdin.XXXXXX)
  cat >"$STDIN_SPEC_FILE"
  SPEC_FILE=$STDIN_SPEC_FILE
fi
if [[ -n $SPEC_FILE && ! -r $SPEC_FILE ]]; then
  echo "cannot read: $SPEC_FILE" >&2; exit 1
fi
if [[ ! $RETRIES =~ ^[0-9]+$ ]]; then
  echo "--retries must be a non-negative integer (got: $RETRIES)" >&2; exit 1
fi
if [[ ! $MAX_WAIT =~ ^[0-9]+$ ]] || (( MAX_WAIT < 1 )); then
  echo "--max-wait must be a positive integer (got: $MAX_WAIT)" >&2; exit 1
fi
command -v curl >/dev/null || { echo "curl required" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq required"   >&2; exit 1; }

log()  { (( QUIET )) || printf '%s\n' "$*" >&2; }
warn() {                printf '%s\n' "$*" >&2; }

# Local spec validation. Catches malformed JSON before we hit the server
# (which returns an unhelpful 500 on bad input) and surfaces known wire-format
# gotchas as warnings — e.g. methods Fiddle's request validator rejects, or
# `headers` sent as an array instead of a newline-joined string. Non-fatal:
# warnings still let the user continue if they think they know better.
validate_spec() {
  local f=$1
  if ! jq -e . "$f" >/dev/null 2>&1; then
    warn "spec is not valid JSON: $f"
    exit 1
  fi
  # `requests` is optional — Fiddle accepts lint-only specs (the API's
  # documented minimum body is just origins + vcl). If present, it must be
  # an array; if absent, downstream code treats EXPECTED_TOTAL=0 as a
  # "no-assertions" run and returns after the first updateResult.
  if ! jq -e 'type == "object"
              and (has("vcl") or has("src"))
              and ((.requests // []) | type == "array")' \
        "$f" >/dev/null 2>&1; then
    warn "spec must be an object with .vcl (or .src); .requests, if present, must be an array"
    exit 1
  fi
  local warnings
  warnings=$(jq -r '
    [
      (.requests[]?
        | select(((.method // "GET") | ascii_upcase) | (. == "TRACE" or . == "CONNECT"))
        | "request method \(.method) is rejected by Fiddle (use GET/HEAD/POST/PUT/DELETE/PATCH)"),
      (.requests[]?
        | select((.headers // null) | type == "array")
        | "request \"headers\" must be a newline-joined string, not an array (path=\(.path // "?"))")
    ] | unique | .[]
  ' "$f" 2>/dev/null || true)
  if [[ -n $warnings ]]; then
    while IFS= read -r w; do warn "warning: $w"; done <<<"$warnings"
  fi
}
[[ -n $SPEC_FILE ]] && validate_spec "$SPEC_FILE"

# curl wrapper for the JSON endpoints (POST/PUT/GET on /fiddle).
# --fail-with-body surfaces HTTP 4xx/5xx as a non-zero exit while still
# letting us read the response body for diagnostics. Without this, a 404 PUT
# silently returns HTML and the failure resurfaces three steps later as
# "no sessionID from /execute".
# --max-time prevents a hung connection from blocking forever; it caps the
# JSON round trip, NOT the SSE stream (which has its own MAX_WAIT budget).
api_call() {
  local label=$1; shift
  local body rc=0
  body=$(curl -sS --fail-with-body --max-time "$API_TIMEOUT" \
           -H "User-Agent: $UA" \
           -H 'Accept: application/json' \
           "$@" 2>&1) || rc=$?
  if (( rc != 0 )); then
    warn "$label failed (curl exit $rc):"
    warn "$body"
    exit 1
  fi
  printf '%s' "$body"
}

# Reusable jq for counting assertions across both wire shapes:
# `tests: ["a", "b"]` (array, what we send) and `tests: "a\nb"` (string, what
# the server returns on GET — see SKILL.md "Wire-format gotchas" #2).
COUNT_TESTS_JQ='
  def count_tests:
    if . == null then 0
    elif type == "array" then length
    elif type == "string" then (if . == "" then 0 else (split("\n") | length) end)
    else 0 end;
  [(.fiddle? // .).requests[]?.tests | count_tests] | add // 0
'

# Cross-attempt merge. Each `event: updateResult` from the server is a full
# snapshot of clientFetches for whatever requests have completed so far. When
# the SSE stream closes early (common — see retry loop below) we may have
# verdicts for a subset of requests. Re-executing the same fiddle returns a
# different subset (Fiddle's clientFetches keys are completion-order, not
# declaration-order). We key by the raw request line — stable per spec
# request, distinct between requests with different headers/methods/paths —
# and merge tests by testExpr, preferring entries that already have a `pass`
# verdict over bare placeholders.
# shellcheck disable=SC2016 # jq program; $-vars are jq syntax, not shell
MERGE_JQ='
def merge_tests(a; b):
  ((a // []) + (b // []))
  | group_by(.testExpr // "")
  | map(
      (map(select(.pass != null)) | last) // last
    );
# Pull content-type out of the raw HTTP response string Fiddle returns in
# `.resp` (the response object can vary; the string form is always present).
# Match case-insensitively on a single header line, stripping CR/LF.
def content_type_of(cf):
  if (cf.resp | type) == "string" then
    (cf.resp
      | split("\n")
      | map(select(test("^[Cc]ontent-[Tt]ype:")))
      | first // ""
      | sub("^[Cc]ontent-[Tt]ype:[[:space:]]*"; "")
      | sub("[\r\n]+$"; "")
      | if . == "" then null else . end)
  else null end;
# Prefer non-null over null when merging body fields across attempts.
def pick(a; b): if b != null then b elif a != null then a else null end;

(.clientFetches // {}) as $cur
| ($prev[0] // {}) as $acc
| reduce ($cur | to_entries[]) as $e (
    $acc;
    ($e.value.req // ("__nil_" + ($e.key|tostring))) as $key
    | (.[$key] // {req: ($e.value.req // null), tests: [],
                   status: null, content_type: null, body_preview: null}) as $existing
    | .[$key] = {
        req: ($e.value.req // $existing.req),
        tests: merge_tests($existing.tests; $e.value.tests),
        status:       pick($existing.status;       ($e.value.status // null)),
        content_type: pick($existing.content_type; content_type_of($e.value)),
        body_preview: pick($existing.body_preview; ($e.value.bodyPreview // null))
      }
  )
'

# 1. Publish (POST), update (PUT), or skip (existing --id without spec).
if [[ -n $FID_OVERRIDE && -n $SPEC_FILE ]]; then
  RESP=$(api_call "PUT /fiddle/$FID_OVERRIDE" \
    -X PUT "$BASE/fiddle/$FID_OVERRIDE" \
    -H 'Content-Type: application/json' \
    --data @"$SPEC_FILE")
  FID=$FID_OVERRIDE
  # PUT returns the same envelope as POST; parse `.valid` strictly so we
  # don't paper over a malformed update by defaulting to true.
  VALID=$(echo "$RESP" | jq -r '.valid')
  ACTION="Updated"
elif [[ -n $FID_OVERRIDE ]]; then
  # Execute-only: pull the stored fiddle so we can compute EXPECTED_TOTAL.
  RESP=$(api_call "GET /fiddle/$FID_OVERRIDE" "$BASE/fiddle/$FID_OVERRIDE")
  if ! echo "$RESP" | jq -e '.id // .fiddle.id' >/dev/null 2>&1; then
    warn "could not parse fiddle $FID_OVERRIDE response:"
    warn "$RESP"
    exit 1
  fi
  FID=$FID_OVERRIDE
  # Don't gate on GET's `.valid`: it means "has executed yet?", not "lints?",
  # so it's false for any un-executed fiddle. Lint already ran at create; a
  # genuine breakage surfaces via the existing "no results" (exit 4) path.
  VALID=true
  ACTION="Reusing"
else
  RESP=$(api_call "POST /fiddle" \
    -X POST "$BASE/fiddle" \
    -H 'Content-Type: application/json' \
    --data @"$SPEC_FILE")
  VALID=$(echo "$RESP" | jq -r '.valid')
  FID=$(echo  "$RESP" | jq -r '.fiddle.id // empty')
  ACTION="Published"
fi

if [[ $VALID != true ]]; then
  if [[ -n $FID ]]; then
    warn "Fiddle invalid: $BASE/fiddle/$FID"
  else
    warn "Fiddle invalid (no ID returned)"
  fi
  echo "$RESP" | jq '.lintStatus // .fiddle.lintStatus' >&2
  exit 2
fi

# --lint-only: the fiddle compiled, and that's all we were asked to confirm.
# Report {valid, lintStatus} and stop here — no /execute, no SSE, no edge-sync
# wait. This is the cheap "does this VCL compile?" check (~1-3s vs the 10-120s
# publish+execute floor); use it whenever you don't need runtime assertion
# results. The spec you POSTed is unchanged on disk.
if [[ $LINT_ONLY == 1 ]]; then
  log "$ACTION: $BASE/fiddle/$FID (lint only, not executed)"
  echo "$RESP" | jq '{fiddle_id: .fiddle.id, url: ("'"$BASE"'/fiddle/" + .fiddle.id), valid, lintStatus: (.lintStatus // .fiddle.lintStatus // {})}'
  exit 0
fi

# Compute EXPECTED_TOTAL. Prefer the local spec when we have one (it's what we
# just sent and reflects intent); otherwise count from the server response,
# whose shape varies (POST nests under .fiddle, GET is top-level).
if [[ -n $SPEC_FILE ]]; then
  EXPECTED_TOTAL=$(jq "$COUNT_TESTS_JQ" "$SPEC_FILE")
else
  EXPECTED_TOTAL=$(echo "$RESP" | jq "$COUNT_TESTS_JQ")
fi

URL="$BASE/fiddle/$FID"
log "$ACTION: $URL"
log "Expecting $EXPECTED_TOTAL assertion(s) across requests."

# Working files: PAYLOAD_FILE holds the most recent raw updateResult,
# MERGED_FILE accumulates merged state across retry attempts. Both are kept
# on any non-zero exit (or with --debug) so failures are inspectable.
PAYLOAD_FILE=$(mktemp -t fiddle-payload.XXXXXX)
MERGED_FILE=$(mktemp -t fiddle-merged.XXXXXX)
echo '{}' >"$MERGED_FILE"

# shellcheck disable=SC2329,SC2317 # invoked via `trap cleanup ...`
cleanup() {
  local rc=$?
  # MERGED_FILE.tmp can leak if the script is killed mid-merge. Always sweep.
  rm -f "${MERGED_FILE:-}.tmp"
  [[ -n ${STDIN_SPEC_FILE:-} ]] && rm -f "$STDIN_SPEC_FILE"
  if (( rc == 0 )) && (( DEBUG == 0 )); then
    rm -f "$PAYLOAD_FILE" "$MERGED_FILE"
  else
    [[ -f $PAYLOAD_FILE ]] && log "debug: last raw payload at $PAYLOAD_FILE"
    [[ -f $MERGED_FILE  ]] && log "debug: merged state    at $MERGED_FILE"
  fi
}
# EXIT trap handles cleanup in all cases. Signal traps just ensure we
# actually exit (trapping a signal suppresses the default "terminate"
# behavior in bash, so without the explicit exit the script continues).
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# State carried across retry attempts.
SAW_RESULT=0
VERDICTS=0
END_REASON=""
ATTEMPTS=0

# Single execute + SSE stream pass. Mutates END_REASON, VERDICTS, SAW_RESULT.
# Returns 0 on a normal stream completion (any END_REASON), non-zero only on
# infrastructure failure (couldn't get a session ID).
stream_attempt() {
  local cache_id=$1
  local exec_resp sid
  # api_call exits the script on hard failure (e.g. HTTP 5xx). The remaining
  # soft-failure path is "200 OK with no sessionID" — surface it as an
  # END_REASON so the retry loop can decide whether to re-attempt, instead
  # of `return 2` tripping `set -e` and aborting with a misleading exit 2.
  exec_resp=$(api_call "POST /fiddle/$FID/execute" \
    -X POST "$BASE/fiddle/$FID/execute?cacheID=$cache_id")
  sid=$(echo "$exec_resp" | jq -r '.sessionID // empty')
  local stream_base
  stream_base=$(echo "$exec_resp" | jq -r '.streamHost // empty')
  stream_base=${stream_base:-$BASE}
  if [[ -z $sid ]]; then
    warn "no sessionID from /execute: $exec_resp"
    END_REASON="no-session"
    return 0
  fi

  : >"$PAYLOAD_FILE"
  END_REASON=""
  local waiting=0 evt="" data_buf=""
  local start now next_tick deadline
  start=$(date +%s)
  deadline=$(( start + MAX_WAIT ))
  next_tick=$(( start + 15 ))

  # Per the SSE spec, an event is dispatched on a blank line; consecutive
  # `data:` lines within one event are concatenated with `\n`. We accumulate
  # into data_buf and only act on the blank-line dispatch. Anything else
  # (parsing on each `data:` line) silently truncates multi-line payloads.
  dispatch_event() {
    case $evt in
      updateResult)
        if [[ -n $data_buf ]]; then
          # Trim the trailing \n we added after the final `data:` line.
          local data=${data_buf%$'\n'}
          printf '%s\n' "$data" >"$PAYLOAD_FILE"
          SAW_RESULT=1
          # Merge into accumulator. If the merge fails (malformed payload),
          # leave the previous merged state intact rather than corrupting it.
          if jq --slurpfile prev "$MERGED_FILE" "$MERGE_JQ" "$PAYLOAD_FILE" \
                >"$MERGED_FILE.tmp" 2>/dev/null; then
            mv "$MERGED_FILE.tmp" "$MERGED_FILE"
          else
            rm -f "$MERGED_FILE.tmp"
          fi
          local v
          v=$(jq '[.[] | .tests[]? | select(.pass != null)] | length' "$MERGED_FILE" 2>/dev/null || echo 0)
          [[ -n $v ]] || v=0
          if (( v > VERDICTS )); then
            VERDICTS=$v
            log "  → $VERDICTS/$EXPECTED_TOTAL assertions reported"
          fi
          if (( EXPECTED_TOTAL > 0 && VERDICTS >= EXPECTED_TOTAL )); then
            END_REASON="complete"
          elif (( EXPECTED_TOTAL == 0 )); then
            # No assertions to wait on — first updateResult is enough.
            END_REASON="no-assertions"
          fi
        fi
        ;;
      timeout|done)
        END_REASON="server-$evt"
        ;;
    esac
    evt=""
    data_buf=""
  }

  # We parse SSE incrementally and exit as soon as we have all expected
  # verdicts, rather than waiting for curl's --max-time. Process substitution
  # keeps the loop in the parent shell so VERDICTS et al. survive past it.
  # IFS=$'\r' strips a trailing CR on CRLF lines (HTTP/1.1 frames frequently
  # use CRLF; without this, `evt` ends up as e.g. "updateResult\r" and the
  # event-name match silently fails, so the script just spins on
  # waitingForSync until --max-wait fires).
  while IFS=$'\r' read -r line; do
    now=$(date +%s)
    if (( now >= deadline )); then
      END_REASON="client-timeout"
      break
    fi

    case $line in
      'event: '*)
        evt="${line#event: }"
        if [[ $evt == waitingForSync ]]; then
          waiting=$((waiting+1))
          if (( waiting == 1 )); then
            log "  ⋯ waiting for edge sync"
          elif (( now >= next_tick )); then
            log "  ⋯ still waiting ($((now - start))s elapsed, $waiting events)"
            next_tick=$(( now + 15 ))
          fi
        fi
        ;;
      'data: '*)
        # Accumulate; the actual processing happens on the blank-line dispatch.
        data_buf+="${line#data: }"$'\n'
        ;;
      '')
        dispatch_event
        case $END_REASON in
          complete|no-assertions|server-timeout|server-done) break ;;
        esac
        ;;
    esac
  done < <(curl -sS -N --max-time "$MAX_WAIT" \
             -H 'Accept: text/event-stream' \
             -H "User-Agent: $UA" "$stream_base/results/$sid/stream" 2>/dev/null || true)

  # If the loop exited via EOF (curl's --max-time fired while we were blocked
  # on read) END_REASON is still empty. Decide between client-timeout and a
  # genuinely server-closed stream by checking the wall clock.
  if [[ -z $END_REASON ]]; then
    now=$(date +%s)
    if (( now >= deadline - 1 )); then
      END_REASON="client-timeout"
    else
      END_REASON="stream-closed"
    fi
  fi
}

# Retry loop. Auto-recover from transient stream closures — the warm
# re-execute path is ~2-5s, and merging across attempts means we can recover
# a complete result set even when each individual attempt drops a different
# subset of requests. We don't retry on client-timeout (bumping --max-wait
# is the only fix) or `complete`/`no-assertions` (we're done).
while :; do
  ATTEMPTS=$(( ATTEMPTS + 1 ))
  stream_attempt "$CACHE_ID"
  case $END_REASON in
    complete|no-assertions) break ;;
  esac
  if (( EXPECTED_TOTAL > 0 && VERDICTS >= EXPECTED_TOTAL )); then
    break
  fi
  if (( ATTEMPTS > RETRIES )); then
    break
  fi
  case $END_REASON in
    stream-closed|server-timeout|server-done|no-session)
      log "  ↻ retrying (attempt $((ATTEMPTS+1)) of $((RETRIES+1)); reason: $END_REASON)"
      continue
      ;;
    *)
      break
      ;;
  esac
done

# Completeness flags drive both the JSON output and the retry-hint stderr.
if (( SAW_RESULT == 0 )); then
  COMPLETE=false
elif (( EXPECTED_TOTAL > 0 && VERDICTS < EXPECTED_TOTAL )); then
  COMPLETE=false
else
  COMPLETE=true
fi

# Hint logic. After auto-retry, the user has already exhausted the cheap
# fixes; surface what's left to try.
case $END_REASON in
  complete|no-assertions)
    RETRY_HINT="" ;;
  client-timeout)
    RETRY_HINT="hit --max-wait ($MAX_WAIT s) on the final attempt; try $0 --id $FID --max-wait $((MAX_WAIT*2))" ;;
  server-timeout)
    RETRY_HINT="server emitted timeout after $((RETRIES+1)) attempt(s); re-execute later: $0 --id $FID" ;;
  stream-closed|server-done)
    RETRY_HINT="stream closed early on all $((RETRIES+1)) attempt(s); raise --retries or re-execute later: $0 --id $FID --retries 5" ;;
  no-session)
    RETRY_HINT="/execute returned no sessionID after $((RETRIES+1)) attempt(s); re-execute later: $0 --id $FID" ;;
  *)
    RETRY_HINT="re-execute: $0 --id $FID" ;;
esac

if (( SAW_RESULT == 0 )); then
  warn "no updateResult after $ATTEMPTS attempt(s) (waited up to ${MAX_WAIT}s each; reason: $END_REASON)"
  warn "fiddle published OK: $URL"
  [[ -n $RETRY_HINT ]] && warn "$RETRY_HINT"
  # Still emit a JSON skeleton so consumers never have to special-case stdout.
  jq -n --arg url "$URL" --arg fid "$FID" \
        --argjson expected "$EXPECTED_TOTAL" \
        --argjson attempts "$ATTEMPTS" \
        --arg end_reason "$END_REASON" '
    { fiddle_id: $fid, url: $url, valid: true,
      complete: false,
      expected_total: $expected, reported_total: 0,
      attempts: $attempts, end_reason: $end_reason,
      results: [],
      summary: { total: 0, passed: 0, failed: 0 } }'
  exit 4
fi

INCOMPLETE=0
if [[ $COMPLETE != true ]]; then
  warn "incomplete: $VERDICTS/$EXPECTED_TOTAL assertions reported across $ATTEMPTS attempt(s) (reason: $END_REASON)"
  warn "fiddle: $URL"
  [[ -n $RETRY_HINT ]] && warn "$RETRY_HINT"
  INCOMPLETE=1
fi

# Build final summary from the merged state. Rows come out sorted by request
# line (jq's `values[]` iterates object keys lexicographically) — stable
# across re-executes, unlike Fiddle's own completion-order clientFetches
# keys. Each row carries the raw request line so consumers can correlate
# output back to the spec by matching method/path/headers.
SUMMARY=$(jq --arg url "$URL" --arg fid "$FID" \
             --argjson expected "$EXPECTED_TOTAL" \
             --argjson reported "$VERDICTS" \
             --argjson attempts "$ATTEMPTS" \
             --arg end_reason "$END_REASON" \
             --argjson complete "$COMPLETE" \
             --argjson show_bodies "$SHOW_BODIES" '
  ((. // {}) | [values[]]) as $arr
  | [ range(0; $arr|length) as $i
      | { seq: $i, req: $arr[$i].req, tests: ($arr[$i].tests // []) }
        + (if $show_bodies == 1 then {
             status:       $arr[$i].status,
             content_type: $arr[$i].content_type,
             body_preview: $arr[$i].body_preview
           } else {} end)
    ] as $results
  | {
      fiddle_id: $fid,
      url: $url,
      valid: true,
      complete: $complete,
      expected_total: $expected,
      reported_total: $reported,
      attempts: $attempts,
      end_reason: $end_reason,
      results: $results,
      summary: {
        total:  ($results | [.[].tests[]? | select(.pass != null)] | length),
        passed: ($results | [.[].tests[]? | select(.pass == true)]  | length),
        failed: ($results | [.[].tests[]? | select(.pass == false)] | length)
      }
    }
' "$MERGED_FILE")

echo "$SUMMARY"

if (( DEBUG )); then
  warn "--- debug: last raw updateResult payload ---"
  jq . "$PAYLOAD_FILE" >&2 || cat "$PAYLOAD_FILE" >&2
fi

(( INCOMPLETE )) && exit 4

FAILED=$(echo "$SUMMARY" | jq -r '.summary.failed')
(( FAILED > 0 )) && exit 3
exit 0

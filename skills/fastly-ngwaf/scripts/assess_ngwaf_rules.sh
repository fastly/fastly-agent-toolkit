#!/bin/bash
set -euo pipefail

for dependency in fastly jq curl; do
  if ! command -v "$dependency" &> /dev/null; then
    echo "Error: '$dependency' is not installed but is required for this script." >&2
    exit 1
  fi
done

# Without a token, fastly commands prompt for one on stdin instead of failing.
if ! fastly auth token > /dev/null 2>&1; then
  echo "Error: no API token configured for the fastly CLI. Set FASTLY_API_TOKEN or run 'fastly auth login' locally." >&2
  exit 1
fi

# Helper: make an authenticated Fastly API call and return the response body,
# exiting with an error on non-200 HTTP status codes.
fastly_api_call() {
  local url="$1"
  local response
  local http_code
  local body

  response=$(curl -sS -w "\n%{http_code}" -H "Fastly-Key: $(fastly auth token)" "$url")
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')

  if [ "$http_code" -ne 200 ]; then
    echo "Error: API call failed with status $http_code for $url" >&2
    echo "Response: $body" >&2
    exit 1
  fi

  echo "$body"
}

# Helper: check and print the status of a single NGWAF signal rule.
check_signal() {
  local signal="$1"
  local rules_data="$2"
  local rule_status
  local recommendation

  rule_status=$(echo "$rules_data" | jq -r ".[] | select(.actions[].signal == \"$signal\") | if .enabled then \"enabled\" else \"disabled\" end")

  if [ -z "$rule_status" ]; then
    recommendation="Configure and enable this rule"
    [[ "$signal" == "LOGINDISCOVERY" ]] && recommendation="CRITICAL: $recommendation to discover unknown login endpoints"
    echo "  - $signal: NOT CONFIGURED (Recommended: $recommendation)"
  elif [[ "$rule_status" != *"enabled"* ]]; then
    recommendation="Enable this rule"
    [[ "$signal" == "LOGINDISCOVERY" ]] && recommendation="CRITICAL: $recommendation"
    echo "  - $signal: IS DISABLED (Recommended: $recommendation)"
  else
    echo "  - $signal: ENABLED"
  fi
}

# 1. Get the list of NGWAF workspaces.
workspaces=$(fastly ngwaf workspace list --json | jq -r '.[].id')

if [ -z "$workspaces" ]; then
  echo "No workspaces found or failed to fetch workspaces."
  exit 0
fi

# 2. For each workspace, check LOGIN, CC, and GC templated rules.
for workspace in $workspaces; do
  echo "### Workspace: $workspace"

  rules_data=$(fastly ngwaf workspace rule list --workspace-id "$workspace" --json)

  echo "  [LOGIN Rules]"
  for signal in "LOGINDISCOVERY" "LOGINATTEMPT" "LOGINSUCCESS" "LOGINFAILURE"; do
    check_signal "$signal" "$rules_data"
  done

  echo "  [CC Rules]"
  for signal in "CC-VAL-ATTEMPT" "CC-VAL-FAILURE" "CC-VAL-SUCCESS"; do
    check_signal "$signal" "$rules_data"
  done

  echo "  [GC Rules]"
  for signal in "GC-VAL-ATTEMPT" "GC-VAL-FAILURE" "GC-VAL-SUCCESS"; do
    check_signal "$signal" "$rules_data"
  done

  # If LOGINATTEMPT is not enabled (missing or disabled), search for login-related requests.
  loginattempt_enabled=$(echo "$rules_data" | jq -r '[.[] | select(.actions[].signal == "LOGINATTEMPT") | select(.enabled == true)] | length')
  if [ "$loginattempt_enabled" -eq 0 ]; then
    echo "  -> LOGINATTEMPT is not enabled. Searching recent request logs for potential login paths..."
    # No CLI command searches requests, so this goes through the API.
    # Decoded query: from:-30min method:POST path:~"*login*"
    login_requests_json=$(fastly_api_call "https://api.fastly.com/ngwaf/v1/workspaces/$workspace/requests?limit=100&page=1&q=from%3A-30min%20method%3APOST%20path%3A~%22%2Alogin%2A%22")
    login_requests=$(echo "$login_requests_json" | jq -r '.data[] | .path' | sort | uniq -c)

    if [ -n "$login_requests" ]; then
      echo "  -> Found potential login paths in last 30 minutes:"
      while IFS= read -r line; do
        echo "     $line"
      done <<< "$login_requests"
    else
      echo "  -> No login-related POST requests found in the last 30 minutes."
    fi
  fi

  echo ""
done

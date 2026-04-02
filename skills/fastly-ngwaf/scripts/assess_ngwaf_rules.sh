#!/bin/bash
set -euo pipefail

# Check dependencies
if ! command -v jq &> /dev/null; then
  echo "Error: 'jq' is not installed but is required for this script."
  exit 1
fi

# Ensure FASTLY_API_KEY is set
if [ -z "${FASTLY_API_KEY:-}" ]; then
  echo "Error: FASTLY_API_KEY environment variable is not set."
  exit 1
fi

# Helper function for API calls with status code check
fastly_api_call() {
  local url="$1"
  local response
  local http_code
  local body

  # Fetch response and status code
  response=$(curl -s -w "\n%{http_code}" -H "Fastly-Key: ${FASTLY_API_KEY}" "$url")
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')

  if [ "$http_code" -ne 200 ]; then
    echo "Error: API call failed with status $http_code for $url" >&2
    echo "Response: $body" >&2
    exit 1
  fi

  echo "$body"
}

# 1. Get the list of ngwaf workspaces
# Note: This fetch is limited to 200 workspaces. For accounts with more, pagination should be followed.
workspaces_json=$(fastly_api_call "https://api.fastly.com/ngwaf/v1/workspaces?limit=200")
workspaces=$(echo "$workspaces_json" | jq -r '.data[].id')

if [ -z "$workspaces" ]; then
  echo "No workspaces found or failed to fetch workspaces."
  exit 0
fi

# 2. For each workspace, check for LOGIN, CC, and GC related templated rules
for workspace in $workspaces; do
  echo "### Workspace: $workspace"
  
  # List rules for the workspace
  # Note: Limited to 200 rules. For workspaces with more, pagination should be followed.
  rules_data=$(fastly_api_call "https://api.fastly.com/ngwaf/v1/workspaces/$workspace/rules?limit=200")
    
  # Assessment groups
  groups=("LOGIN" "CC" "GC")
  signals_LOGIN=("LOGINDISCOVERY" "LOGINATTEMPT" "LOGINSUCCESS" "LOGINFAILURE")
  signals_CC=("CC-VAL-ATTEMPT" "CC-VAL-FAILURE" "CC-VAL-SUCCESS")
  signals_GC=("GC-VAL-ATTEMPT" "GC-VAL-FAILURE" "GC-VAL-SUCCESS")

  loginattempt_enabled=false

  for group in "${groups[@]}"; do
    echo "  [$group Rules]"
    group_signals_var="signals_$group[@]"
    for signal in "${!group_signals_var}"; do
      # Check if a rule exists that triggers this signal in its actions
      rule_status=$(echo "$rules_data" | jq -r ".data[] | select(.actions[].signal == \"$signal\") | if .enabled then \"enabled\" else \"disabled\" end")
      
      if [ -z "$rule_status" ]; then
        recommendation="Configure and enable this rule"
        [ "$signal" == "LOGINDISCOVERY" ] && recommendation="CRITICAL: $recommendation to discover unknown login endpoints"
        echo "  - $signal: NOT CONFIGURED (Recommended: $recommendation)"
      elif [[ "$rule_status" != *"enabled"* ]]; then
        recommendation="Enable this rule"
        [ "$signal" == "LOGINDISCOVERY" ] && recommendation="CRITICAL: $recommendation"
        echo "  - $signal: IS DISABLED (Recommended: $recommendation)"
        # Note: If LOGINATTEMPT is disabled, we still want to search for login paths.
      else
        echo "  - $signal: ENABLED"
        if [[ "$signal" == "LOGINATTEMPT" ]]; then
           loginattempt_enabled=true
        fi
      fi
    done
  done

  # If LOGINATTEMPT is not enabled (missing or disabled), search for login-related requests
  if [ "$loginattempt_enabled" = false ]; then
    echo "  -> LOGINATTEMPT is not enabled. Searching recent request logs for potential login paths..."
    # Search for requests with "login" in path and method POST from last 30 min
    login_requests_json=$(fastly_api_call "https://api.fastly.com/ngwaf/v1/workspaces/$workspace/requests?limit=100&page=1&q=from%3A-30min%20method%3APOST%20path%3A~\"%2Alogin%2A\"")
    login_requests=$(echo "$login_requests_json" | jq -r '.data[] | .path' | sort | uniq -c)
    
    if [ -n "$login_requests" ]; then
      echo "  -> Found potential login paths in last 30 minutes:"
      echo "$login_requests" | sed 's/^/     /'
    else
      echo "  -> No login-related POST requests found in the last 30 minutes."
    fi
  fi

  echo ""
done

#!/usr/bin/env bash
set -euo pipefail

CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.112}"

echo "=== Validating JSON ==="
json_files=("plugin.json")
while IFS= read -r -d '' json_file; do
    json_files+=("$json_file")
done < <(find skills -name "*.json" -print0)
npx --yes "jsonlint-mod@1.7.6" -q "${json_files[@]}"

echo "=== Validating YAML ==="
yaml_files=$(find skills \( -name "*.yml" -o -name "*.yaml" \)) || true
if [[ -n "$yaml_files" ]]; then
    echo "$yaml_files" | xargs uvx yamllint@1.37.0
else
    echo "No YAML files found, skipping"
fi

echo "=== Validating Markdown ==="
npx --yes "markdownlint-cli@0.47.0" 'skills/**/*.md'

echo "=== Validating Shell ==="
shell_files=$(find skills -name "*.sh") || true
if [[ -n "$shell_files" ]]; then
    echo "$shell_files" | xargs shellcheck
else
    echo "No shell files found, skipping"
fi

echo "=== Validating Claude Code plugin ==="
npx --yes "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" plugin validate .

echo "=== Validating Gemini extension ==="
if [[ -f "gemini-extension.json" ]]; then
    npx --yes @google/gemini-cli@0.45.2 extensions validate .
else
    echo "No gemini-extension.json at root, skipping"
fi

echo "=== Cross-checking metadata consistency ==="
errors=0
agent_plugin_json="plugin.json"
plugin_json=".claude-plugin/plugin.json"
gemini_json="gemini-extension.json"

echo "=== Validating Agent Plugins manifest ==="
if [[ ! -f "$agent_plugin_json" ]]; then
    echo "Error: Missing $agent_plugin_json" >&2
    errors=$((errors + 1))
elif ! jq -e '
    type == "object"
    and all(keys[]; . == "$schema" or . == "name" or . == "version" or . == "description" or . == "author" or . == "homepage" or . == "repository" or . == "license" or . == "keywords" or . == "extensions")
    and ."$schema" == "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
    and (if (.name | type) == "string" then (.name | length >= 1 and length <= 64 and test("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$") and (contains("--") | not) and (contains("..") | not)) else false end)
    and (if has("version") then (.version | type) == "string" else true end)
    and (if has("description") then (.description | type) == "string" else true end)
    and (if has("homepage") then (.homepage | type) == "string" else true end)
    and (if has("repository") then (.repository | type) == "string" else true end)
    and (if has("license") then (.license | type) == "string" else true end)
    and (if has("keywords") then (.keywords | if type == "array" then all(.[]; type == "string") else false end) else true end)
    and (if has("author") then (.author | if type == "object" then (all(keys[]; . == "name" or . == "email" or . == "url") and all(.[]; type == "string")) else false end) else true end)
    and (if has("extensions") then (.extensions | type) == "object" else true end)
' "$agent_plugin_json" >/dev/null; then
    echo "Error: $agent_plugin_json does not conform to the Agent Plugins 1.0.0 manifest schema" >&2
    errors=$((errors + 1))
fi

if [[ ! -f "$plugin_json" ]]; then
    echo "Error: Missing $plugin_json" >&2
    errors=$((errors + 1))
else
    pj_name=$(jq -r '.name' "$plugin_json")
    pj_version=$(jq -r '.version // empty' "$plugin_json")
    pj_description=$(jq -r '.description // empty' "$plugin_json")

    # Cross-check with gemini-extension.json if it exists
    if [[ -f "$gemini_json" ]]; then
        ge_name=$(jq -r '.name' "$gemini_json")
        ge_version=$(jq -r '.version // empty' "$gemini_json")
        ge_description=$(jq -r '.description // empty' "$gemini_json")

        if [[ "$pj_name" != "$ge_name" ]]; then
            echo "Error: Name mismatch: plugin.json='$pj_name' gemini-extension.json='$ge_name'" >&2
            errors=$((errors + 1))
        fi
        if [[ -n "$pj_version" && -n "$ge_version" && "$pj_version" != "$ge_version" ]]; then
            echo "Error: Version mismatch: plugin.json='$pj_version' gemini-extension.json='$ge_version'" >&2
            errors=$((errors + 1))
        fi
        if [[ -n "$pj_description" && -n "$ge_description" && "$pj_description" != "$ge_description" ]]; then
            echo "Error: Description mismatch: plugin.json='$pj_description' gemini-extension.json='$ge_description'" >&2
            errors=$((errors + 1))
        fi
    fi

    # Check plugin.json field allowlist
    echo "=== Checking plugin.json field allowlist ==="
    allowed_fields='["name","description","version","author","keywords","license","repository","homepage"]'
    bad_fields=$(jq -r --argjson allowed "$allowed_fields" \
        '[keys[] | select(. as $k | $allowed | index($k) | not)] | .[]' \
        "$plugin_json")
    if [[ -n "$bad_fields" ]]; then
        echo "Error: plugin.json has unrecognized fields: $bad_fields" >&2
        errors=$((errors + 1))
    fi
fi

echo "=== Checking Gemini extension context files ==="
if [[ -f "$gemini_json" ]]; then
    context_file=$(jq -r '.contextFileName // empty' "$gemini_json")
    if [[ -n "$context_file" ]]; then
        if [[ ! -f "$context_file" ]]; then
            echo "Error: gemini-extension.json references '$context_file' but file not found" >&2
            errors=$((errors + 1))
        fi
    else
        if [[ ! -f "GEMINI.md" ]]; then
            echo "Note: No contextFileName and no GEMINI.md (Gemini gets no root context)"
        fi
    fi
fi

echo "=== Checking SKILL.md frontmatter ==="
if [[ -d "skills" ]]; then
    while IFS= read -r -d '' skill_file; do
        skill_dir=$(dirname "$skill_file")
        folder_name=$(basename "$skill_dir")

        # Extract frontmatter name field (between first pair of --- delimiters)
        fm_name=$(awk '/^---$/{if(++c==2)exit} c==1 && /^name:/{sub(/^name:[[:space:]]*/, ""); print}' "$skill_file")
        if [[ -z "$fm_name" ]]; then
            echo "Error: No frontmatter 'name' in $skill_file" >&2
            errors=$((errors + 1))
            continue
        fi
        if [[ "$fm_name" != "$folder_name" ]]; then
            # SKILL.md files sitting directly in a category/tool dir (promoted overviews)
            # get a warning; skills in their own named subdir get an error
            grandparent=$(basename "$(dirname "$skill_dir")")
            if [[ "$grandparent" == "skills" || "$grandparent" == "tools" || "$grandparent" == "fastly" || "$grandparent" == "howto" ]]; then
                echo "Warning: Promoted SKILL.md name doesn't match folder: frontmatter='$fm_name' folder='$folder_name' in $skill_file" >&2
            else
                echo "Error: SKILL.md name mismatch: frontmatter='$fm_name' folder='$folder_name' in $skill_file" >&2
                errors=$((errors + 1))
            fi
        fi

        # Check for required description field
        fm_desc=$(awk '/^---$/{if(++c==2)exit} c==1 && /^description:/{found=1} END{if(found) print "yes"}' "$skill_file")
        if [[ -z "$fm_desc" ]]; then
            echo "Error: No frontmatter 'description' in $skill_file" >&2
            errors=$((errors + 1))
        fi
    done < <(find skills -name "SKILL.md" -print0)
else
    echo "Warning: No skills/ directory found" >&2
    errors=$((errors + 1))
fi

echo "=== Checking for duplicate skill names ==="
if [[ -d "skills" ]]; then
    dupes=$(find skills -name "SKILL.md" -print0 | xargs -0 -I{} \
        awk '/^---$/{if(++c==2)exit} c==1 && /^name:/{sub(/^name:[[:space:]]*/, ""); print}' {} \
        | sort | uniq -d)
    if [[ -n "$dupes" ]]; then
        echo "Error: Duplicate skill names found:" >&2
        echo "$dupes" >&2
        errors=$((errors + 1))
    fi
fi


if [[ $errors -gt 0 ]]; then
    echo "Error: $errors validation failure(s) found" >&2
    exit 1
fi

echo "=== All validations passed ==="

---
name: fastly-ngwaf
description: "Performs an internal assessment of Fastly Next-Gen WAF (NGWAF) workspaces to verify that critical templated protection rules are configured and enabled. Use when auditing NGWAF workspace security posture, checking for missing or disabled login protection rules (LOGINDISCOVERY, LOGINATTEMPT, LOGINSUCCESS, LOGINFAILURE), verifying credit card validation rules (CC-VAL-ATTEMPT, CC-VAL-FAILURE, CC-VAL-SUCCESS), validating gift card protection rules (GC-VAL-ATTEMPT, GC-VAL-FAILURE, GC-VAL-SUCCESS), or identifying potential login endpoints not covered by NGWAF rules."
---

# Fastly Next-Gen WAF Internal Assessment

This skill assesses Fastly NGWAF workspaces to verify the status of critical templated rules related to:
1. **Login Protection**: `LOGINDISCOVERY`, `LOGINATTEMPT`, `LOGINSUCCESS`, and `LOGINFAILURE`.
2. **Credit Card Validation**: `CC-VAL-ATTEMPT`, `CC-VAL-FAILURE`, and `CC-VAL-SUCCESS`.
3. **Gift Card Validation**: `GC-VAL-ATTEMPT`, `GC-VAL-FAILURE`, and `GC-VAL-SUCCESS`.

## Workflow

1. **Retrieve Workspaces**: Fetches all NGWAF workspaces associated with the account.
2. **Inspect Rules**: For each workspace, it retrieves the list of configured rules.
3. **Validate Critical Rules**: Specifically checks for the presence and enablement of the templated rules listed above.
4. **Recommend Actions**: If any of these rules are missing or disabled, it recommends configuring and enabling them to strengthen security posture against Account Takeover (ATO) and carding attacks.

## Usage

Assume that the user has correctly configured their FASTLY_API_KEY environment variable. Run the assessment script provided in the skill:

```bash
# Execute the assessment script
./scripts/assess_ngwaf_rules.sh
```

## API References

- [List Workspaces](https://www.fastly.com/documentation/reference/api/ngwaf/workspaces/#ngwafListWorkspaces)
- [List Workspace Rules](https://www.fastly.com/documentation/reference/api/ngwaf/rules/#ngwafListWorkspaceRules)

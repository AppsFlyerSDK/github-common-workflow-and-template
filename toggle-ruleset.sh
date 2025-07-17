#!/bin/bash
# ------------------------------------------------------------------------------
# toggle-ruleset.sh
#
# Temporarily disables a GitHub organization ruleset, runs a sync script, and
# then re-enables the ruleset. This is useful for bypassing branch protection
# rules during automated operations (e.g., syncing workflows) that would
# otherwise be blocked by the ruleset.
#
# Usage:
#   ORG=your-org RULESET_ID=123456 SYNC_SCRIPT=./your-sync-script.sh ./toggle-ruleset.sh
#
# Required environment variables:
#   ORG         - The GitHub organization name (e.g., AppsFlyerSDK)
#   RULESET_ID  - The ID of the ruleset to temporarily disable/enable
#   SYNC_SCRIPT - Path to the script to run while the ruleset is disabled
#
# Requirements:
#   - gh CLI (https://cli.github.com/) must be installed and authenticated
#   - jq must be installed
#
# Workflow:
#   1. Fetches the current ruleset configuration using gh CLI
#   2. Disables the ruleset (sets enforcement to "disabled")
#   3. Runs the specified sync script
#   4. Re-enables the ruleset (restores enforcement to "active")
#   5. Always re-enables the ruleset, even if the sync script fails
# ------------------------------------------------------------------------------
set -euo pipefail

# Entry point for toggling the ruleset for AppsFlyerSDK org
# This script will always use sync-org-workflows.sh as the sync script

ORG="AppsFlyerSDK"
RULESET_ID="6738534"  # Replace with your actual ruleset ID
SYNC_SCRIPT="sync-org-workflows.sh"


# Required environment variables
: "${ORG:?ORG is required}"
: "${RULESET_ID:?RULESET_ID is required}"
: "${SYNC_SCRIPT:?SYNC_SCRIPT is required}"

API_PATH="/orgs/$ORG/rulesets/$RULESET_ID"

# 1. Get current ruleset config
RULESET_JSON=$(gh api "$API_PATH")

# 2. Disable the ruleset
echo "Disabling ruleset $RULESET_ID for org $ORG..."
DISABLED_JSON=$(echo "$RULESET_JSON" | jq '.enforcement = "disabled"')
echo "$DISABLED_JSON" | gh api --method PUT "$API_PATH" --input - > /dev/null

# 3. Run the sync script, always re-enable ruleset after
set +e
bash "$SYNC_SCRIPT"
RESULT=$?
set -e

# 4. Re-enable the ruleset (restore original enforcement)
echo "Re-enabling ruleset $RULESET_ID for org $ORG..."
ENABLED_JSON=$(echo "$RULESET_JSON" | jq '.enforcement = "active"')
echo "$ENABLED_JSON" | gh api --method PUT "$API_PATH" --input - > /dev/null

if [ $RESULT -eq 0 ]; then
  echo "Sync script succeeded. Ruleset re-enabled."
else
  echo "Sync script failed with exit code $RESULT. Ruleset re-enabled."
fi

exit $RESULT 
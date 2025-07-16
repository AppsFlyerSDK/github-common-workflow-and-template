#!/bin/bash

# Organization and branch settings
ORG="AppsFlyerSDK"
BRANCH_NAME="sync-org-workflows-$(date +%Y%m%d)"
WORKFLOWS_DIR="org-reusable-workflow-stubs"
ISSUE_TEMPLATE_DIR=".github/ISSUE_TEMPLATE"
ISSUE_TEMPLATE_FILE="appsflyer-issue-template.yml"

# Get all repo names in the org (excluding archived repos)
REPOS=$(gh repo list $ORG --json name,isArchived --jq '.[] | select(.isArchived==false) | .name')

for REPO in $REPOS; do
  echo "Processing $REPO..."

  # Clone the repo
  git clone "https://github.com/$ORG/$REPO.git"
  cd "$REPO" || continue

  # Create and checkout new branch
  git checkout -b "$BRANCH_NAME"

  CHANGED=0

  # Ensure .github/workflows exists
  mkdir -p .github/workflows

  # Compare and copy workflow stubs
  for wf in ../$WORKFLOWS_DIR/*.yml; do
    target=".github/workflows/$(basename "$wf")"
    if [ ! -f "$target" ] || ! cmp -s "$wf" "$target"; then
      cp -f "$wf" "$target"
      CHANGED=1
      echo "Updated workflow: $target"
    fi
  done

  # Ensure .github/ISSUE_TEMPLATE exists
  mkdir -p .github/ISSUE_TEMPLATE

  # Delete templates in the repo that are not in the shared project
  for repo_template in .github/ISSUE_TEMPLATE/*.yml; do
    found=0
    for shared_template in ../$ISSUE_TEMPLATE_DIR/*.yml; do
      if [ "$(basename "$repo_template")" = "$(basename "$shared_template")" ]; then
        found=1
        break
      fi
    done
    if [ $found -eq 0 ]; then
      rm -f "$repo_template"
      CHANGED=1
      echo "Deleted obsolete issue template: $repo_template"
    fi
  done

  # Compare and copy all issue templates from shared dir
  for src_iss in ../$ISSUE_TEMPLATE_DIR/*.yml; do
    tgt_iss=".github/ISSUE_TEMPLATE/$(basename "$src_iss")"
    if [ ! -f "$tgt_iss" ] || ! cmp -s "$src_iss" "$tgt_iss"; then
      cp -f "$src_iss" "$tgt_iss"
      CHANGED=1
      echo "Updated issue template: $tgt_iss"
    fi
  done

  # Only continue if something changed
  if [ "$CHANGED" -eq 0 ]; then
    echo "No changes to sync for $REPO. Skipping branch and PR."
    cd ..
    rm -rf "$REPO"
    continue
  fi

  # Add, commit, and push
  git add .github/workflows/*.yml .github/ISSUE_TEMPLATE/*.yml
  git commit -m "Sync org-wide workflows and issue template"
  git push --set-upstream origin "$BRANCH_NAME"

  # Open a PR
  gh pr create --title "Sync org-wide workflows and issue template" \
    --body "This PR updates the repository with the latest shared workflows and issue template from the org standard." \
    --base main

  # Go back and clean up
  cd ..
  rm -rf "$REPO"
done 
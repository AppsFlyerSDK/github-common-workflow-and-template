#!/bin/bash
# ------------------------------------------------------------------------------
# sync-org-workflows.sh
#
# This script synchronizes shared GitHub Actions workflows and issue templates
# from this repository to all active repositories in the AppsFlyerSDK organization.
# It ensures that all repos are up-to-date with the org standards, removes obsolete
# templates, and opens a pull request for any changes.
#
# Usage:
#   ./sync-org-workflows.sh
#
# Requirements:
#   - gh CLI (https://cli.github.com/) must be installed and authenticated
#   - jq must be installed
#   - Write access to all target repositories
#
# What it does:
#   1. Lists all non-archived repos in the org
#   2. Clones each repo and creates a new branch
#   3. Updates workflows and issue templates from the shared source
#   4. Removes obsolete issue templates
#   5. Commits and pushes changes if any
#   6. Opens a pull request for each updated repo
#   7. Approves and merges the PR automatically (with a review comment indicating automation)
#   8. Cleans up local clones
#
# Note: This script is intended to be run by org maintainers or automation systems.
# ------------------------------------------------------------------------------

# Organization and branch settings
ORG="AppsFlyerSDK"
BRANCH_NAME="sync-org-workflows-$(date +%Y%m%d-%H%M%S)"
WORKFLOWS_DIR="org-reusable-workflow-stubs"
ISSUE_TEMPLATE_DIR=".github/ISSUE_TEMPLATE"
ISSUE_TEMPLATE_FILE="appsflyer-issue-template.yml"

# Flag to control whether to include appsflyer-issue-template.yml
INCLUDE_APPSFLYER_TEMPLATE=false  # Set to false to exclude this template

# Get all repo names in the org (excluding archived repos)
REPOS=$(gh repo list $ORG --limit 1000 --json name,isArchived --jq '.[] | select(.isArchived==false) | .name')

for REPO in $REPOS; do

  # Skip the workflow template repository itself
  if [ "$REPO" = "github-common-workflow-and-template" ]; then
    echo "Skipping $REPO (workflow template repository)"
    continue
  fi

  # Check if the repository is public, skip if private/internal
  REPO_VISIBILITY=$(gh repo view "$ORG/$REPO" --json visibility --jq .visibility)
  if [ "$REPO_VISIBILITY" != "PUBLIC" ]; then
    echo "Skipping $REPO (not public, visibility: $REPO_VISIBILITY)"
    continue
  fi

  echo "Processing $REPO..."

  # Clone the repo (shallow clone for speed)
  git clone --depth 1 --single-branch --quiet "https://github.com/$ORG/$REPO.git"
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

  # Delete all .md files in the repo's ISSUE_TEMPLATE directory
  for md_file in .github/ISSUE_TEMPLATE/*.md; do
    if [ -f "$md_file" ]; then
      rm -f "$md_file"
      CHANGED=1
      echo "Deleted obsolete markdown issue template: $md_file"
    fi
  done

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
    template_name=$(basename "$src_iss")
    tgt_iss=".github/ISSUE_TEMPLATE/$template_name"
    
    # Skip appsflyer-issue-template.yml if flag is false
    if [ "$template_name" = "$ISSUE_TEMPLATE_FILE" ] && [ "$INCLUDE_APPSFLYER_TEMPLATE" = false ]; then
      echo "Skipping $template_name (INCLUDE_APPSFLYER_TEMPLATE is false)"
      continue
    fi
    
    if [ ! -f "$tgt_iss" ] || ! cmp -s "$src_iss" "$tgt_iss"; then
      cp -f "$src_iss" "$tgt_iss"
      CHANGED=1
      echo "Updated issue template: $tgt_iss"
    fi
  done

  # Remove appsflyer-issue-template.yml if flag is false and file exists
  if [ "$INCLUDE_APPSFLYER_TEMPLATE" = false ] && [ -f ".github/ISSUE_TEMPLATE/$ISSUE_TEMPLATE_FILE" ]; then
    git rm --ignore-unmatch ".github/ISSUE_TEMPLATE/$ISSUE_TEMPLATE_FILE" 2>/dev/null || rm -f ".github/ISSUE_TEMPLATE/$ISSUE_TEMPLATE_FILE"
    CHANGED=1
    echo "Removed $ISSUE_TEMPLATE_FILE (INCLUDE_APPSFLYER_TEMPLATE is false)"
  fi

  # Only continue if something changed
  if [ "$CHANGED" -eq 0 ]; then
    echo "No changes to sync for $REPO. Skipping branch and PR."
    cd ..
    rm -rf "$REPO"
    continue
  fi

  # Remove all non-yml files from .github/ISSUE_TEMPLATE/
  for file in .github/ISSUE_TEMPLATE/*; do
    if [ -f "$file" ] && [[ "$file" != *.yml ]]; then
      git rm --ignore-unmatch "$file" 2>/dev/null || rm -f "$file"
      CHANGED=1
      echo "Deleted obsolete markdown or non-yml issue template: $file"
    fi
  done

  # Stage deletions of any removed files
  git add -u .github/ISSUE_TEMPLATE/

  git add .github/workflows/*.yml .github/ISSUE_TEMPLATE/*
  git commit -m "Sync org-wide workflows and issue template"
  git push --set-upstream origin "$BRANCH_NAME"

  # Wait a moment for the branch to be available on GitHub
  sleep 5

  # Get the default branch name for the repo
  DEFAULT_BRANCH=$(gh repo view "$ORG/$REPO" --json defaultBranchRef --jq .defaultBranchRef.name)

  # Open a PR to the default branch
  PR_URL=$(gh pr create --title "Sync org-wide workflows and issue template" \
    --body "This PR updates the repository with the latest shared workflows and issue template from the org standard." \
    --base "$DEFAULT_BRANCH" \
    --head "$BRANCH_NAME") || {
    echo "Failed to create PR for $REPO, continuing to next repo"
    cd ..
    rm -rf "$REPO"
    continue
  }

  # Extract PR number from the URL
  PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')

  # Attempt to approve the PR only if the current user is not the author
  PR_AUTHOR=$(gh pr view "$PR_NUMBER" --json author --jq .author.login)
  CURRENT_USER=$(gh api user --jq .login)
  if [ "$PR_AUTHOR" != "$CURRENT_USER" ]; then
    gh pr review "$PR_NUMBER" --approve --body "Approved automatically by sync-org-workflows.sh automation script." || echo "Could not approve PR"
  else
    echo "Skipping approval: cannot approve your own PR ($CURRENT_USER)"
  fi

  # Attempt to merge the PR (squash and delete branch)
  gh pr merge "$PR_NUMBER" --squash --admin --delete-branch || echo "Could not merge PR (maybe branch protection or approval required)"

  # Go back and clean up
  cd ..
  rm -rf "$REPO"
done 
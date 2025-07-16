# GitHub Common Workflow and Template

This repository provides **shared GitHub Actions workflows** and **issue templates** for use across all repositories in the AppsFlyerSDK organization. It also includes automation to keep all repositories in sync with these standards.

## Features

- **Reusable GitHub Actions workflows** for common automation tasks (e.g., closing inactive issues, responding to support issues).
- **Organization-wide issue templates** to standardize issue reporting and improve support.
- **Automation script** to sync these files across all organization repositories and open pull requests for updates.

## Directory Structure

```
.github/
  workflows/                # Shared reusable workflows
  ISSUE_TEMPLATE/           # Shared issue templates (YAML format)
org-reusable-workflow-stubs/ # Example workflow stubs for consuming repos
sync-org-workflows.sh        # Script to sync workflows/templates to all org repos
```

## How to Use

### 1. Use Shared Workflows in Your Repo

Copy the relevant stub from `org-reusable-workflow-stubs/` into your repo's `.github/workflows/` directory. For example:

```yaml
# .github/workflows/close_inactive_issues.yml
jobs:
  close-issues:
    uses: AppsFlyerSDK/github-common-workflow-and-template/.github/workflows/close_inactive_issues.yml@main
    secrets: inherit
```

You can also add triggers (e.g., `schedule`, `workflow_dispatch`) as needed.

### 2. Use Shared Issue Templates

Copy the YAML files from `.github/ISSUE_TEMPLATE/` in this repo to your repo's `.github/ISSUE_TEMPLATE/` directory.

### 3. Sync All Repos Automatically

Run the provided script to update all org repos:

```sh
./sync-org-workflows.sh
```
- Requires [GitHub CLI (`gh`)](https://cli.github.com/) and `jq`.
- The script will:
  - Clone each repo in the org
  - Update workflows and issue templates (only if changed)
  - Remove obsolete templates
  - Create a branch and open a PR for each updated repo

> **Note:** You need write access to all target repos and a valid `gh` authentication.

## Contributing

- Update or add new workflows in `.github/workflows/`.
- Update or add new issue templates in `.github/ISSUE_TEMPLATE/`.
- Update the sync script as needed for new automation requirements.

## License

MIT 
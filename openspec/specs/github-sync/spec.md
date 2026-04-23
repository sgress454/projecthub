# github-sync Specification

## Purpose

Defines ProjectHub's background GitHub synchronization: periodic PR auto-discovery keyed on each project's current git branch, caching of PR metadata (title, state, unresolved review comments), and adaptive polling cadence. All GitHub access is routed through the `gh` CLI, and the capability degrades silently when `gh` is missing or unauthenticated.

## Requirements

### Requirement: PR auto-discovery by branch

The app SHALL periodically discover GitHub PRs associated with each project by querying the `gh` CLI for PRs matching the project's current git branch.

#### Scenario: Discovering PRs for a project's branch

- **GIVEN** a project has a `path` set and the directory is a git repository with a remote
- **WHEN** the GitHub sync cycle runs
- **THEN** the app runs `git branch --show-current` to determine the branch, then queries `gh pr list --head <branch>` to find associated PRs

#### Scenario: Discovered PRs are stored on the project

- **WHEN** `gh pr list` returns one or more PRs
- **THEN** the PR URLs are added to the project's `githubPRs` as auto-discovered entries

#### Scenario: Branch has no PRs

- **WHEN** `gh pr list` returns no results for the branch
- **THEN** no auto-discovered PRs are stored (manually added PRs are unaffected)

#### Scenario: Project path is not a git repository

- **GIVEN** a project's `path` does not contain a `.git` directory or is not inside a git worktree
- **WHEN** the sync cycle runs for that project
- **THEN** the project is skipped without error

### Requirement: PR metadata caching

The app SHALL cache metadata for each discovered or linked PR, including title, state (open/merged/closed), and count of unresolved reviewer comments.

#### Scenario: Fetching PR metadata

- **WHEN** a PR is discovered or manually linked
- **THEN** the app fetches the PR title, state, and review comments via `gh pr view`

#### Scenario: Counting unresolved reviewer comments

- **WHEN** PR metadata is fetched
- **THEN** the unresolved comment count excludes comments authored by the PR author

#### Scenario: Metadata is refreshed on each sync cycle

- **WHEN** the GitHub sync cycle runs
- **THEN** cached metadata for all known PRs is updated with current values

#### Scenario: Metadata cache is in-memory only

- **WHEN** the app is relaunched
- **THEN** PR metadata cache is empty until the next GitHub sync cycle completes

### Requirement: GitHub sync polling schedule

The app SHALL poll GitHub on a schedule, adjusting frequency based on whether any project has open PRs.

#### Scenario: Polling with open PRs

- **GIVEN** at least one project has an open PR
- **WHEN** the previous sync cycle completed
- **THEN** the next sync cycle begins after 5 minutes

#### Scenario: Polling without open PRs

- **GIVEN** no project has any open PR
- **WHEN** the previous sync cycle completed
- **THEN** the next sync cycle begins after 15 minutes

#### Scenario: Sync runs immediately on launch

- **WHEN** the app launches
- **THEN** a GitHub sync cycle begins immediately (not waiting for the first timer interval)

### Requirement: Graceful degradation without gh CLI

The app SHALL function normally when the `gh` CLI is not installed or not authenticated. GitHub-dependent features are silently disabled.

#### Scenario: gh not installed

- **WHEN** the app attempts to run `gh` and the binary is not found on PATH
- **THEN** GitHub sync is disabled, no PRs are auto-discovered, and no error is shown to the user in the menu bar

#### Scenario: gh not authenticated

- **WHEN** `gh auth status` reports that the user is not authenticated
- **THEN** GitHub sync is disabled and the metadata modal shows a hint about authentication

#### Scenario: gh becomes available after launch

- **WHEN** the user installs or authenticates `gh` while the app is running
- **THEN** the next sync cycle detects `gh` availability and begins operating normally

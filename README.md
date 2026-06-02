# Suri

Suri is a native macOS personal assistant app for keeping track of work signals across Slack, email, GitLab, GitHub, Jira, and notes. It is designed to surface messages that need your attention, deadlines that are coming up, and follow-up work that should not get lost.

## Features

- Native macOS SwiftUI app
- `NavigationSplitView` with sidebar, detail surface, and inspector panel
- Dedicated `Settings` scene
- Slack mention tracking regardless of read/unread state
- Slack support for personal mentions, DMs, `@here`, `@channel`, and `@everyone`
- Separate `Important Slack` view for high-priority Slack items
- GitLab review request tracking with `reviews_for_me`
- GitHub review request and assigned issue tracking through the authenticated `gh` CLI
- Jira, local email, and local notes integration structure
- Cached last successful sync result
- Automatic sync when the app becomes active
- Periodic sync while the app is active
- Reviewed items stay visible with a different state instead of disappearing
- Batch deduplication, source health metadata, and a durable AI review queue manifest

## Requirements

- macOS 14 or later
- Xcode Command Line Tools
- Swift Package Manager
- Optional: `agent-slack`
- Optional: GitHub CLI (`gh`) authenticated with `gh auth login`
- Optional: `codex` CLI

## Run

```bash
./script/build_and_run.sh
```

Build and verify launch:

```bash
./script/build_and_run.sh --verify
```

Stream app logs:

```bash
./script/build_and_run.sh --logs
```

## Codex Run Action

For Codex Desktop, `.codex/environments/environment.toml` is wired to run:

```bash
./script/build_and_run.sh
```

## Integration Configuration

You can create a sample configuration from the app's `Settings > Integrations` tab.

Configuration file location:

```text
~/Library/Application Support/Suri/integrations.json
```

Example:

```json
{
  "slack": {
    "enabled": true,
    "mode": "agentSlack",
    "query": "",
    "workspace": "",
    "count": 20,
    "importantOnly": false,
    "includeLater": true,
    "lookbackHours": 72,
    "codexImportanceEnabled": true,
    "codexTimeoutSeconds": 30
  },
  "gitLab": {
    "enabled": true,
    "baseURL": "https://gitlab.com",
    "privateToken": "glpat-your-token",
    "scope": "reviews_for_me",
    "projectIDs": ["owner/project"]
  },
  "github": {
    "enabled": true,
    "mode": "ghCLI",
    "token": "",
    "owner": "",
    "repos": ["koong17/suri"],
    "count": 30,
    "includePullRequests": true,
    "includeIssues": true
  },
  "jira": {
    "enabled": false,
    "baseURL": "https://your-domain.atlassian.net",
    "email": "you@example.com",
    "apiToken": "your-api-token",
    "jql": "assignee = currentUser() AND statusCategory != Done ORDER BY duedate ASC"
  },
  "email": {
    "enabled": false,
    "directory": "~/Documents/SuriEmail"
  },
  "notes": {
    "enabled": false,
    "directory": "~/Documents/SuriNotes"
  }
}
```

Do not commit your real `integrations.json`. It may contain tokens and account-specific paths.

## Slack

The default Slack mode is `agentSlack`, which uses local `agent-slack` authentication instead of requiring a Slack bot token.

By default, Suri searches recent Slack activity within `lookbackHours` for:

- messages that mention you
- `@here`
- `@channel`
- `@everyone`
- DMs
- Slack Later items

When `importantOnly` is `false`, Suri shows all review-worthy Slack items in the main review list and shows the highest-priority subset in `Important Slack`.

When `codexImportanceEnabled` is `true`, Suri optionally calls local `codex exec` to refine Slack importance classification. If Codex fails or times out, Suri falls back to the built-in rule-based classifier.

## GitLab

GitLab projects can be configured as numeric project IDs, URL-encoded project paths, or regular project paths.

Example:

```json
"projectIDs": ["tms/appius"]
```

To track only merge requests that need your review:

```json
"scope": "reviews_for_me"
```

## GitHub

The default GitHub mode is `ghCLI`, which uses the account already authenticated by GitHub CLI:

```bash
gh auth login
gh auth status
```

Suri checks:

- open pull requests where review is requested from `@me`
- open issues assigned to `@me`

Set `repos` to narrow the search:

```json
"repos": ["koong17/suri"]
```

If `token` is present, Suri passes it only to the `gh` subprocess as `GH_TOKEN` and `GITHUB_TOKEN`. Leaving it empty keeps authentication in GitHub CLI.

## Cache And Sync

The last successful sync result is cached at:

```text
~/Library/Application Support/Suri/sync-cache.json
```

Operational pipeline files:

```text
~/Library/Application Support/Suri/dedup-cache.json
~/Library/Application Support/Suri/ai-queue.json
```

On launch, Suri loads the cached snapshot first so the app can show useful data immediately. It then syncs again when conditions allow.

Default sync behavior:

- sync when the app becomes active
- sync periodically while the app remains active
- default automatic sync interval is 5 minutes
- manual refresh ignores the interval and forces a sync
- successful syncs update the cache

Automatic sync and sync interval can be changed in Settings.

## Project Structure

```text
Sources/Suri/App              App entry point and scene structure
Sources/Suri/Models           Task, source, and sidebar models
Sources/Suri/Services         Slack, GitLab, GitHub, Jira, cache, notification, and sync services
Sources/Suri/Stores           App state and sync state
Sources/Suri/Support          Commands, preferences, and formatting helpers
Sources/Suri/Views            Sidebar, detail, inspector, and settings views
script/build_and_run.sh       SwiftPM macOS build/run script
```

## Repository

Remote:

```text
git@github.com:koong17/suri.git
```

Default branch:

```text
main
```

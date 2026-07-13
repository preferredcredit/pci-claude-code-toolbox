---
name: workspace-init
description: Bootstrap a workspace for the engineer-toolkit plugin's Jira-driven dev workflow — checks plugin prereqs, CLI binaries (git, dotnet), prompts for user-specific config, scaffolds a small user-owned CLAUDE.md plus the plugin-managed workflow doctrine, and migrates pre-split workspaces.
disable-model-invocation: true
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, AskUserQuestion, mcp__plugin_atlassian_atlassian__atlassianUserInfo
---

# workspace-init

Set up (or refresh) a workspace for the `engineer-toolkit` plugin's Jira-driven dev workflow. Interactive — runs in the current chat session.

## Invocation

`/workspace-init` — no arguments.

## Phase 0 — Prerequisite check

Verify each required plugin is **both installed AND enabled**. These are two separate things:

- **Installed** — present in `~/.claude/plugins/installed_plugins.json` under the `plugins` key.
- **Enabled** — set to `true` in `enabledPlugins` in `~/.claude/settings.json` (user-level) or in `<cwd>/.claude/settings.json` (project-level). Either one is sufficient.

A plugin can be installed but disabled (the user installed it once, then disabled it via `/plugin`). MCP calls to a disabled plugin fail at runtime with a confusing error, so we gate up front.

**Required plugins:**
- `superpowers@claude-plugins-official`
- `atlassian@claude-plugins-official`
- `playwright@claude-plugins-official`

**Optional plugins (warn only, do not gate):**
- `csharp-lsp@claude-plugins-official`
- `claude-md-management@claude-plugins-official`

### Check algorithm

For each required plugin `<name>@<marketplace>`:

1. Read `~/.claude/plugins/installed_plugins.json`. If `plugins["<name>@<marketplace>"]` is missing or its array is empty → status is **not-installed**.
2. Else read `~/.claude/settings.json` and (if it exists) `<cwd>/.claude/settings.json`. If `enabledPlugins["<name>@<marketplace>"] === true` in either → status is **enabled**. Otherwise → status is **installed-but-disabled**.

Apply the same algorithm to optional plugins; warn only, do not gate.

For each required plugin not in **enabled** state, print the matching remediation block:

```
[!] Required plugin <status>: <plugin-name>
    <fix>
    <secondary-line>
```

Status / fix / secondary-line by case:

| Case | `<status>` | `<fix>` | `<secondary-line>` |
|---|---|---|---|
| not-installed | `not installed` | `Install: in Claude Code, run /plugin → Discover → install "<short-name>"` | `Marketplace: <marketplace-name>` |
| installed-but-disabled | `installed but disabled` | `Enable: in Claude Code, run /plugin → enable "<short-name>"` | `Or edit ~/.claude/settings.json: set enabledPlugins["<plugin>@<marketplace>"] to true` |

For each missing optional plugin, print a warning but continue.

If any required plugin is missing/disabled, prompt:

```
Continue with workspace setup anyway? (yes / no)  [default: no]
```

If the user picks `no`, exit without scaffolding.

## Phase 0.5 — CLI binary check

Warn-only: these tools aren't validated by the plugin system but are required by individual skills later in the workflow. The checks don't gate initialization — they tell the user what'll break and where.

Run the checks in parallel via Bash. Treat a non-zero exit as "not configured."

| Tool | Why it matters | Check |
|---|---|---|
| `git` | All repo cloning + branch ops in `/work` and `/local-test` | `git --version` |
| `dotnet` | `dotnet build`/`dotnet test` in `/author-review` and `/local-test` | `dotnet --version` |

> The GitHub CLI (`gh`) is intentionally not checked. PCI hosts code on Azure DevOps on-prem, where `gh` doesn't work — the review skills fall back to user-supplied diffs / local `git diff`. See workflow doctrine "No GitHub CLI".

For each failed check, print:

```
[!] CLI tool not configured: <tool>
    Needed by: <skill list>
    Install: <one-line pointer>
    Continuing — will fail later when that skill runs.
```

Suggested install pointers:

- `git` → `winget install Git.Git` (or https://git-scm.com/)
- `dotnet` → `winget install Microsoft.DotNet.SDK.9`

Then always print one info note (regardless of outcomes above):

```
[i] Dashboard links use vscode://file/<path>. If you use a different editor:
      Cursor              → works automatically (cursor://file/<path>)
      VS Code Insiders    → works automatically (vscode-insiders://file/<path>)
      Visual Studio, JetBrains, Sublime → no native URL handler; links open the OS picker
    Override in <workspace>\CLAUDE.md under "Open-in-editor links".
```

No prompt. Proceed to Phase 1 regardless.

## Phase 1 — Detect existing workspace

Default workspace path: `C:\ClaudeWorkspace`.

If the default path doesn't exist → skip directly to Phase 2 with the default path.

If the default path exists, classify it by checking for files in this order:

| Detected | Classification | Refresh behavior |
|---|---|---|
| `<workspace>\.engineer-toolkit\VERSION` exists and matches plugin version | **Up to date** | `refresh` is a no-op — offer to skip |
| `<workspace>\.engineer-toolkit\VERSION` exists but older than plugin version | **Doctrine out of date** | `refresh` overwrites `workflow.md`, `VERSION`, and `PlanningWorkspace\CLAUDE.md`; root `CLAUDE.md` and `PlanningWorkspace\repos.md` untouched |
| `<workspace>\.engineer-toolkit\` missing AND `<workspace>\CLAUDE.md` exists | **Pre-split workspace** | Migration path (see below) |
| None of `<workspace>\CLAUDE.md`, `Active\`, `Complete\` present | **Empty-ish** | Treat as new — skip to Phase 2 |

The plugin version comes from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` → `version`.

### Prompt (Up to date / Doctrine out of date)

```
Workspace at <path>: <classification tag>
  refresh        — overwrite <workspace>\.engineer-toolkit\workflow.md, VERSION, and
                   <workspace>\PlanningWorkspace\CLAUDE.md with the latest plugin doctrine.
                   Your CLAUDE.md, PlanningWorkspace\repos.md, Active\, Complete\, Archive\
                   are never touched. (First refresh after upgrading may extract an old repo
                   table into PlanningWorkspace\repos.md and leave a
                   PlanningWorkspace\CLAUDE.md.bak-<timestamp> backup.)
  pick-different — choose a different workspace path.
  cancel         — exit without changes.
```

### Pre-split migration (one-time)

When `.engineer-toolkit\` is missing but `CLAUDE.md` exists, the workspace was created by an older version of the plugin. Migrate before scaffolding:

1. Read `<workspace>\CLAUDE.md`. Parse the `## Configuration` section's table rows. Extract:
   - `Workspace path` → use as the workspace path (sanity-check matches the path we're inspecting)
   - `User Account ID`
   - `User Name`
   Tolerate either the old single-table layout or the User-specific/Org-wide split layout — both have the same row labels.
2. Prompt:

   ```
   Pre-split workspace detected at <path>. Migration will:
     - Extract your Configuration values from the existing CLAUDE.md (User Account ID, User Name).
     - Back up the existing CLAUDE.md to CLAUDE.md.bak-<YYYYMMDDHHMMSS>.
     - Write a new minimal CLAUDE.md (Configuration table + one @import line).
     - Write <workspace>\.engineer-toolkit\workflow.md (plugin doctrine, managed file).
     - Write <workspace>\PlanningWorkspace\CLAUDE.md (plugin doctrine) and, if your old PlanningWorkspace\CLAUDE.md had a repo table, extract it to PlanningWorkspace\repos.md first (old file backed up).
     - Write <workspace>\.engineer-toolkit\VERSION.
   Active\, Complete\, Archive\ are untouched.
   Type `migrate` to proceed, anything else to cancel.
   ```

3. If the user types `migrate`, store the extracted values for Phase 3 (skipping Phase 2's collection) and continue. Otherwise, exit.

If extraction fails (e.g., CLAUDE.md is mangled and the Configuration rows can't be found), fall through to Phase 2 — collect values fresh, but still back up the existing file before write.

## Phase 2 — Collect user-specific config

Skip this phase entirely if Phase 1 returned `migrate` (the values were extracted from the existing CLAUDE.md). Skip if Phase 1 returned `refresh` (we're only rewriting doctrine, not CLAUDE.md). Run only for new workspaces.

Prompt for two values (one at a time, via AskUserQuestion or chat):

1. **Workspace path** — default `C:\ClaudeWorkspace`. Accept any absolute path. Create it if it doesn't exist.

2. **Jira account ID** — first try the `atlassianUserInfo` MCP tool. If it returns a valid account ID, use it without prompting. Otherwise prompt:

   ```
   Couldn't auto-detect your Jira account ID. Enter it (looks like 712020:abc-123-...):
   ```

3. **Display name** — first try `atlassianUserInfo` for the user's display name. If it returns a name, use it without prompting. Otherwise prompt for it.

## Phase 3 — Scaffold the workspace

The plugin's templates live at `${CLAUDE_PLUGIN_ROOT}/templates/` (`CLAUDE_PLUGIN_ROOT` is set by Claude Code when a plugin's skill runs). The plugin version comes from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` → `version`.

Ownership layers in this scaffold:

| File | Owner | Refresh behavior |
|---|---|---|
| `<workspace>\CLAUDE.md` | User | Never overwritten on `refresh`. Only written when missing or during one-time migration (with backup). |
| `<workspace>\.engineer-toolkit\workflow.md` | Plugin | Always overwritten on `refresh`. No diff. No backup. |
| `<workspace>\.engineer-toolkit\VERSION` | Plugin | Always overwritten on `refresh`. Single-line plain text matching the plugin version. |
| `<workspace>\PlanningWorkspace\CLAUDE.md` | Plugin | Always overwritten on `refresh` (doctrine only — no user data lives here). |
| `<workspace>\PlanningWorkspace\repos.md` | User | Written from template only when missing. Never overwritten. |

### Steps

1. **Create folders** (no error if they already exist):
   - `<workspace>\Active\`
   - `<workspace>\Complete\`
   - `<workspace>\Archive\`
   - `<workspace>\PlanningWorkspace\`
   - `<workspace>\.engineer-toolkit\`

2. **Write `<workspace>\CLAUDE.md`** (conditional):
   - **Skip entirely** if Phase 1 chose `refresh` (CLAUDE.md is user-owned).
   - **Otherwise** (new workspace or `migrate`), read `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md.template` and substitute:
     - `{{WORKSPACE_PATH}}` → workspace path (collected in Phase 2 or extracted by migration)
     - `{{USER_ACCOUNT_ID}}` → Jira account ID
     - `{{USER_DISPLAY_NAME}}` → display name
   - For migration: back up the existing `<workspace>\CLAUDE.md` to `<workspace>\CLAUDE.md.bak-<YYYYMMDDHHMMSS>` before writing.
   - For new workspace: just write.

3. **Write `<workspace>\.engineer-toolkit\workflow.md`** (always):
   - Read `${CLAUDE_PLUGIN_ROOT}/templates/workflow.md.template`.
   - Substitute `{{TEMPLATE_VERSION}}` → the plugin version.
   - Overwrite unconditionally. No backup.

4. **Write `<workspace>\.engineer-toolkit\VERSION`** (always):
   - Plain text, single line: the plugin version (e.g. `2.0.0`). No trailing newline issues — the file is one logical line.
   - Overwrite unconditionally.

5. **Write `<workspace>\PlanningWorkspace\CLAUDE.md`** (plugin-managed):
   - **Backup + extraction check first:**
     - If no existing file: just write from the template (next bullet).
     - If an existing file's content differs from what will be written: ALWAYS back it up to `<workspace>\PlanningWorkspace\CLAUDE.md.bak-<YYYYMMDDHHMMSS>` before overwriting — regardless of whether the extraction below applies.
     - **One-time extraction:** if the existing file contains a `## Repositories` section AND `<workspace>\PlanningWorkspace\repos.md` does not exist, this is a pre-registry file — extract the `## Repositories` table (and the `## Quick Reference: Which Repo?` table if present) into `<workspace>\PlanningWorkspace\repos.md` (template shape from `${CLAUDE_PLUGIN_ROOT}/templates/PlanningWorkspace.repos.md.template`, with the extracted rows replacing the commented examples). If the old file held extra user content beyond doctrine + those tables (e.g. coding patterns), tell the user in the Phase 4 summary that it survives only in the backup and recommend moving it to `<workspace>\.claude\rules\`.
   - Then read `${CLAUDE_PLUGIN_ROOT}/templates/PlanningWorkspace.CLAUDE.md.template` and write it as-is — do NOT substitute `<workspace>`; the token is defined symbolically inside the file. Overwrite on `refresh` like `workflow.md`.

6. **Write `<workspace>\PlanningWorkspace\repos.md`** (user-owned, conditional):
   - Only if the file does not exist (and step 5's extraction didn't just create it): read `${CLAUDE_PLUGIN_ROOT}/templates/PlanningWorkspace.repos.md.template` and write it as-is.
   - Never overwritten on `refresh`.

Path-scoped rules under `<workspace>\.claude\rules\` are NOT scaffolded by this skill. Engineers typically have team- or repo-specific coding rules they want to manage themselves; this plugin doesn't ship opinionated defaults. If you want rules, drop your own files into `.claude\rules\` (see https://code.claude.com/docs/en/memory#path-specific-rules for format).

## Phase 4 — Summary

Print a one-line headline followed by labeled file lists. Only print the sections that apply to the flow that actually ran.

| Flow | Headline | Sections to include |
|---|---|---|
| New workspace | `Workspace ready at <workspace>.` | `Created:` (all 10 scaffolded paths), then `Next steps:` (the 4 entry-point commands below) |
| Refresh | `Workspace at <workspace> refreshed (v<old> → v<new>).` | `Updated:` (workflow.md, VERSION, PlanningWorkspace\CLAUDE.md), `Created:` (`PlanningWorkspace\repos.md`, when the step-5 extraction ran), `Backed up:` (`PlanningWorkspace\CLAUDE.md.bak-<timestamp>`, when the step-5 backup ran), `Untouched (user-owned):` (CLAUDE.md, PlanningWorkspace\repos.md) |
| Pre-split migration | `Workspace at <workspace> migrated to plugin v<plugin-version>.` | `Backed up:` (CLAUDE.md.bak-<timestamp>), `Created:` (.engineer-toolkit/ + contents, plus PlanningWorkspace\repos.md when the step-5 extraction ran), `Rewrote:` (CLAUDE.md) |

`Created:` and `Updated:` list paths with a brief parenthetical for plugin-managed files (e.g. `.engineer-toolkit\workflow.md   (plugin-managed doctrine)`).

**Next steps** block (new-workspace flow only):

```
Next steps:
  /work <KEY>              Import a Jira ticket and start ticketed work (pull + triage in one)
  /adhoc <slug> "<title>"  Start an unticketed work item
  /work                    Dispatch go-flagged items (queue runner)
  /status                  Refresh Jira, sweep, dashboard, suggest next work
```

## Safety rules

- **Never touch contents of `Active\`, `Complete\`, or `Archive\`** under any circumstance.
- Workspace path collected in Phase 2 is only honored after explicit user confirmation.
- If `atlassianUserInfo` is unavailable (atlassian plugin not enabled despite passing Phase 0), proceed with manual prompts but note in summary: `Could not auto-detect Jira identity — values entered manually.`

## Out of scope

This skill does NOT:
- Install or enable other plugins (it can only point at `/plugin`)
- Set up MCP servers
- Create, transition, or modify Jira tickets
- Clone code repos into `PlanningWorkspace\`
- Create starter items in `Active\`

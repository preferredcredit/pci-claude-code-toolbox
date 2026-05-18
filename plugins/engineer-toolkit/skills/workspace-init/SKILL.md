---
name: workspace-init
description: Bootstrap a workspace for the engineer-toolkit plugin's Jira-driven dev workflow — checks plugin prereqs, CLI binaries (git, gh, dotnet), prompts for user-specific config, and scaffolds the workspace with templated CLAUDE.md.
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

For each required plugin not in **enabled** state, print one of these remediation blocks:

```
[!] Required plugin not installed: <plugin-name>
    Install: in Claude Code, run /plugin → Discover → install "<short-name>"
    Marketplace: <marketplace-name>
```

```
[!] Required plugin installed but disabled: <plugin-name>
    Enable: in Claude Code, run /plugin → enable "<short-name>"
    Or edit ~/.claude/settings.json: set enabledPlugins["<plugin>@<marketplace>"] to true
```

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
| `git` | All repo cloning + branch ops in `/work`, `/direct`, `/smoke` | `git --version` |
| `gh` | `gh pr create` in `/work` Phase 6 Wrap; also verifies the user is logged in | `gh --version && gh auth status` |
| `dotnet` | `dotnet build`/`dotnet test` in `/author-review` and `/smoke` | `dotnet --version` |

For each failed check, print:

```
[!] CLI tool not configured: <tool>
    Needed by: <skill list>
    Install: <one-line pointer>
    Continuing — will fail later when that skill runs.
```

Suggested install pointers:

- `git` → `winget install Git.Git` (or https://git-scm.com/)
- `gh` not installed → `winget install GitHub.cli`
- `gh` installed but not logged in → `gh auth login`
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

If the default path exists AND contains any of: `CLAUDE.md`, `Active\`, `Complete\` — treat it as an existing workspace.

### Classify the existing CLAUDE.md (refresh safety)

Inspect `<workspace>\CLAUDE.md` before offering choices, so the prompt can show what `refresh` would actually do:

1. **Parse the version stamp.** Look at the first non-blank line for `<!-- engineer-toolkit template v<X.Y.Z> ... -->`. Extract `<X.Y.Z>` as `STAMPED_VERSION` (or `none` if absent).
2. **Read the plugin version** from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` → `version` (call it `CURRENT_VERSION`).
3. **Detect local edits.** Read the shipped template, substitute these into a temporary in-memory copy:
   - `{{WORKSPACE_PATH}}` → the path being inspected
   - `{{USER_ACCOUNT_ID}}` and `{{USER_DISPLAY_NAME}}` → values from `atlassianUserInfo` if available, otherwise the corresponding lines in the existing file
   - `{{TEMPLATE_VERSION}}` → `STAMPED_VERSION` (so the version-stamp line doesn't itself read as a diff)
   Diff that substituted template against the on-disk file, ignoring trailing whitespace and blank-line-only changes. Count the changed lines.
4. **Pick a classification tag** for the prompt:
   - `(up to date)` — `STAMPED_VERSION == CURRENT_VERSION` AND 0 local-edit lines
   - `(version <STAMPED> → <CURRENT>, no local edits)` — version bump, clean
   - `(local edits: N lines)` — non-zero local-edit lines, version stamp matches
   - `(version <STAMPED> → <CURRENT>, local edits: N lines)` — both
   - `(unstamped, possible local edits: N lines)` — `STAMPED_VERSION` is `none`

### Prompt

```
Workspace at <path> already has files. <classification tag>
  refresh        — overwrite CLAUDE.md and PlanningWorkspace\CLAUDE.md with the latest templates;
                   Active\, Complete\, Archive\ are never touched.
  pick-different — choose a different workspace path.
  cancel         — exit without changes.
```

### Behavior when the user picks `refresh`

- **0 local-edit lines:** proceed silently to Phase 2.
- **Any local-edit lines:** show a unified-diff summary capped at 30 lines (truncate with `... (N more)`), then require a second explicit confirmation:

  ```
  Refresh will overwrite the local edits shown above. Type `overwrite` to proceed, anything else to cancel.
  ```

  Before writing, back up the existing file to `<workspace>\CLAUDE.md.bak-<YYYYMMDDHHMMSS>`. Note the backup path in Phase 4's summary.

If the default path does NOT exist, skip directly to Phase 2 with the default path.

## Phase 2 — Collect user-specific config

Prompt for two values (one at a time, via AskUserQuestion or chat):

1. **Workspace path** — default `C:\ClaudeWorkspace`. Accept any absolute path. Create it if it doesn't exist.

2. **Jira account ID** — first try the `atlassianUserInfo` MCP tool. If it returns a valid account ID, use it without prompting. Otherwise prompt:

   ```
   Couldn't auto-detect your Jira account ID. Enter it (looks like 712020:abc-123-...):
   ```

3. **Display name** — first try `atlassianUserInfo` for the user's display name. If it returns a name, use it without prompting. Otherwise prompt for it.

## Phase 3 — Scaffold the workspace

Substitute the collected values into the templates and write the resulting files. The plugin's templates live at `${CLAUDE_PLUGIN_ROOT}/templates/` (the env var `CLAUDE_PLUGIN_ROOT` is set by Claude Code when a plugin's skill runs; if it isn't available in your version, resolve the plugin path relative to this SKILL.md's location).

1. Create folders (no error if they already exist):
   - `<workspace>\Active\`
   - `<workspace>\Complete\`
   - `<workspace>\Archive\`
   - `<workspace>\PlanningWorkspace\`

2. Write `<workspace>\CLAUDE.md`:
   - Read `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md.template`
   - Read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` → `version` (for the version-stamp substitution)
   - Substitute placeholders:
     - `{{TEMPLATE_VERSION}}` → the plugin version (so the first-line stamp reads `<!-- engineer-toolkit template vX.Y.Z ... -->`)
     - `{{WORKSPACE_PATH}}` → the collected workspace path
     - `{{USER_ACCOUNT_ID}}` → the collected Jira account ID
     - `{{USER_DISPLAY_NAME}}` → the collected display name
   - Write the resulting file. **Overwrite without prompting only if Phase 1 returned `refresh` AND the local-edits count was 0**. If Phase 1 detected local edits, the explicit `overwrite` confirmation from Phase 1 is required first; otherwise leave the file alone and log a warning in Phase 4.

3. Write `<workspace>\PlanningWorkspace\CLAUDE.md`:
   - Read `${CLAUDE_PLUGIN_ROOT}/templates/PlanningWorkspace.CLAUDE.md.template`
   - Substitute `<workspace>` references where the template uses them
   - Write the resulting file (same overwrite rules as above)

Path-scoped rules under `<workspace>\.claude\rules\` are NOT scaffolded by this skill. Engineers typically have team- or repo-specific coding rules they want to manage themselves; this plugin doesn't ship opinionated defaults. If you want rules, drop your own files into `.claude\rules\` (see https://code.claude.com/docs/en/memory#path-specific-rules for format).

## Phase 4 — Summary

Print a summary like:

```
Workspace ready at <workspace>.

Created:
  Active\
  Complete\
  Archive\
  PlanningWorkspace\
  CLAUDE.md
  PlanningWorkspace\CLAUDE.md

Next steps:
  /jira-import <KEY>       Import a Jira ticket to start ticketed work
  /adhoc <slug> "<title>"  Start an unticketed work item
  /work                    Run a work-loop pass once you have items
```

If Phase 1 returned `refresh`, the "Created:" list becomes "Updated:" and lists only files that were overwritten. If a backup was created during Phase 1, add a line:

```
Backed up:
  CLAUDE.md.bak-<YYYYMMDDHHMMSS>   (previous CLAUDE.md before refresh)
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

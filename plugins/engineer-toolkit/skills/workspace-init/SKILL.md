---
name: workspace-init
description: Bootstrap a workspace for the engineer-toolkit plugin's Jira-driven dev workflow — checks prerequisites, prompts for user-specific config, and scaffolds the workspace folder structure with templated CLAUDE.md and rules.
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

## Phase 1 — Detect existing workspace

Default workspace path: `C:\ClaudeWorkspace`.

If the default path exists AND contains any of: `CLAUDE.md`, `Active\`, `Complete\` — treat it as an existing workspace and prompt:

```
Workspace at <path> already has files.
  refresh        — overwrite CLAUDE.md and .claude/rules/* with the latest templates;
                   Active\, Complete\, Archive\ are never touched.
  pick-different — choose a different workspace path.
  cancel         — exit without changes.
```

If the existing workspace's `CLAUDE.md` differs from the shipped template (run a quick diff against the plugin's `templates/CLAUDE.md.template`), include an inline note: `CLAUDE.md has local edits.`

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
   - Substitute placeholders:
     - `{{WORKSPACE_PATH}}` → the collected workspace path
     - `{{USER_ACCOUNT_ID}}` → the collected Jira account ID
     - `{{USER_DISPLAY_NAME}}` → the collected display name
   - Write the resulting file. **Overwrite without prompting only if Phase 1 returned `refresh`** OR the file didn't exist before this run.

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

If Phase 1 returned `refresh`, the "Created:" list becomes "Updated:" and lists only files that were overwritten.

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

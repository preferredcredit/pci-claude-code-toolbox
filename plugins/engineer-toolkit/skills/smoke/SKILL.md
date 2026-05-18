---
name: smoke
description: Run an autonomous local smoke walk over a Jira ticket or adhoc investigation. Starts the local app(s), composes a walk plan from the acceptance criteria, dispatches the qa-runner subagent to drive the browser via Playwright while tailing app logs for exceptions. Local environment only — for deployed-env QA use /qa instead.
argument-hint: <key-or-hint> [--vs] [--no-cross-write]
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task, mcp__plugin_atlassian_atlassian__atlassianUserInfo, mcp__plugin_atlassian_atlassian__getJiraIssue
---

In this skill, `<workspace>` refers to the Workspace path defined in the workspace `CLAUDE.md` `## Configuration` block. `<CloudId>` refers to the Jira CloudId from the same Configuration block.

# Smoke

Run an autonomous local smoke walk: start the app(s), walk the acceptance criteria via Playwright, watch the app log for exceptions, write a verdict. Local environment only.

The orchestrator (this skill) runs in the main conversation. The walk itself is dispatched to the `qa-runner` subagent which owns the entire Playwright run end-to-end.

For deployed-env QA verification use `/qa <key> <env>` (env = `dev` | `qa` | `staging`). For pre-PR review use `engineer-toolkit:author-review`.

## Configuration

Read from the workspace `CLAUDE.md` `## Configuration` table:
- `Jira CloudId` (referred to as `<CloudId>` below)

Hardcoded in this skill:
- Active issues folder: `<workspace>\Active\`
- PlanningWorkspace fallback: `<workspace>\PlanningWorkspace\`
- Smoke profile cache: `<workspace>\.smoke\profile\<host>\`
- Jira key pattern (regex): `^[A-Z]+-\d+$`
- Playwright auth flags (Windows Integrated Authentication):
  - `--auth-server-allowlist=localhost,*.preferredcredit.net`
  - `--auth-negotiate-delegate-allowlist=localhost,*.preferredcredit.net`
- App startup timeout: 60 seconds (per app)

## Invocation

`/smoke <key-or-hint> [--vs] [--no-cross-write]`

- `<key-or-hint>` (required): Jira key (e.g. `CO-166`), adhoc slug, or substring hint.
- `--vs` (optional): the user starts the app(s) in Visual Studio and supplies log paths. Default = Claude starts via `dotnet run`.
- `--no-cross-write` (optional): suppress the `[smoke]` line written to the issue file's Discussion at end-of-run.

If `<key-or-hint>` is missing, print exactly:

```
Usage: /smoke <key-or-hint> [--vs] [--no-cross-write]
```

and stop.

## Argument Resolution

Resolve to a single `<TARGET>` BEFORE running Phase 0:

1. Exact directory match in `Active\<arg>\` (case-insensitive).
2. Upper-cased Jira-key match against `Active\` if `<arg>` matches `^[a-zA-Z]+-\d+$`.
3. Substring match (case-insensitive) across `Active\` directory names.

Outcomes:
- Zero matches → `No item matches '<arg>'.` and stop.
- Multiple matches → `Multiple matches for '<arg>': <list>. Be more specific.` and stop.
- One match → store as `<TARGET>`, proceed.

## Phases

Run in order. Do NOT skip ahead.

### Phase 0: Setup

1. Ensure run folder exists:
   ```powershell
   New-Item -ItemType Directory -Path "<workspace>\Active\<TARGET>\Screenshots" -Force | Out-Null
   ```
2. Check for an existing `Active\<TARGET>\smoke.md`:
   - **`status: in-progress`** → print `Resuming /smoke for <TARGET>.` Skip Phase 3 (plan exists). Resume Phase 4 (driver re-dispatch).
   - **`status: passed | failed | aborted`** → prompt `R | F | C` (re-run / fork / close):
     - R → rename existing `smoke.md` to `smoke-<YYYYMMDDHHMMSS>.md`, continue as fresh.
     - F → same as R, but Phase 3 prompts the user for a new scope description before composing plan.
     - C → print `Closed.` and stop.
   - **Absent** → continue to Phase 1.

### Phase 1: Read per-repo `## Environments`

For each subdirectory `<repo>` in `Active\<TARGET>\AgentWorkspace\`:

1. Try in order:
   1. `Active\<TARGET>\AgentWorkspace\<repo>\CLAUDE.md` — the working clone on the feature branch.
   2. `PlanningWorkspace\<repo>\CLAUDE.md` — fallback for newer main not yet in feature branch.
2. Locate the `## Environments` section. Parse the fenced ```yaml``` block.
3. Required keys: `solution`, `startup_project`, `launch_profile`, `ready_signal`, `urls.local`.
4. If absent or incomplete, derive a candidate from `launchSettings.json`:
   - Find `<repo>\<startup_csproj>\Properties\launchSettings.json` (scan repo for a `Properties\launchSettings.json` whose parent project name matches the repo name pattern).
   - Pick the `https` profile if present, else the first profile.
   - `urls.local` = the `applicationUrl` value (take the first https:// entry if multiple semicolon-separated).
   - `ready_signal` = `"Now listening on: <url>"`.
   - `solution` = scan repo root for `*.sln` or `*.slnx`.
   - `startup_project` = relative path to the chosen `.csproj`.
   - `depends_on` = `[]`.
   - `urls.dev | qa | staging` = leave unset for now (only `urls.local` is required for /smoke).
5. Print the derived YAML block, ask `Save this to <repo>/CLAUDE.md (commit on current branch)? (Y / edit / N)`:
   - **Y** → write the file with a `# <repo>` heading and the `## Environments` section. Stage and commit:
     ```bash
     cd "<repo path>"
     git add CLAUDE.md
     git commit -m "[Claude] Add CLAUDE.md with ## Environments section"
     ```
   - **edit** → prompt for inline corrections, apply, re-confirm.
   - **N** → keep values in memory for this run only; do not write or commit.

Store the parsed values in memory keyed by repo name for use in subsequent phases.

### Phase 2: Start app(s)

**`--vs` mode:**

1. Print, for each app:
   ```
   Start <repo> in Visual Studio (launch profile: <profile>, expected URL: <url>).
   Redirect stdout/stderr to a log file I can read. Reply with the absolute log path.
   ```
2. Wait for the user's response per app. Validate:
   ```powershell
   $exists = Test-Path "<path>"
   $age = if ($exists) { (Get-Date) - (Get-Item "<path>").LastWriteTime } else { $null }
   ```
   If `-not $exists` or `$age.TotalMinutes -gt 5` → re-prompt.
3. Store log paths in memory. Set `apps_started_by: vs` in smoke.md frontmatter.

**Default mode (Claude starts):**

1. For each app, probe its port:
   ```powershell
   $listening = Get-NetTCPConnection -LocalPort <port> -State Listen -ErrorAction SilentlyContinue
   ```
   If listening → prompt `R | K | A`:
   - R → ask user for the log path of the already-running app, validate as in `--vs` mode.
   - K → identify owning PID, run `Stop-Process -Id <pid> -Force`, then proceed to fresh start.
   - A → exit.
2. Build each repo once:
   ```bash
   cd "<workspace>/Active/<TARGET>/AgentWorkspace/<repo>"
   dotnet build "<solution>"
   ```
   Non-zero exit → halt, surface the error, abort.
3. Determine start order from `depends_on`. Topological sort. If no dependencies declared, use AgentWorkspace listing order.
4. For each app in order, spawn via Bash with `run_in_background: true`:
   ```bash
   cd "<workspace>/Active/<TARGET>/AgentWorkspace/<repo>"
   dotnet run --project "<startup_project>" --launch-profile <launch_profile> > "<workspace>/Active/<TARGET>/<repo>.log" 2>&1
   ```
   Capture the returned shell ID. Track for cleanup.
5. Poll each log for `ready_signal` with a 60s timeout:
   ```powershell
   $deadline = (Get-Date).AddSeconds(60)
   while ((Get-Date) -lt $deadline) {
     if (Select-String -Path "<log path>" -Pattern "<ready_signal>" -SimpleMatch -Quiet) { break }
     Start-Sleep -Milliseconds 500
   }
   if ((Get-Date) -ge $deadline) { abort "Ready-signal timeout for <repo>." }
   ```
6. Set `apps_started_by: claude` in smoke.md frontmatter; record PID + shell ID per app.

### Phase 3: Compose walk plan

1. Read `Active\<TARGET>\<TARGET>.md` for the Jira description (or adhoc Scope).
2. If `<TARGET>` matches a Jira key and the description looks truncated, fetch fresh via `getJiraIssue` for the `description` field.
3. Parse AC bullets and validation rules.
4. Compose a numbered plan:
   ```
   1. action: navigate to <primary_url>
      expect: page header reads "<title>", core elements render
   2. action: <playwright-executable instruction>
      expect: <observable from AC>
   ...
   N. action: free-roam — click 3-5 visible interactive elements, scroll, screenshot before/after
      expect: no new exceptions in app log(s); no obvious render failures
   ```
   - Skip the free-roam step for adhoc runs with no AC.
   - Validation rules become individual steps (one per case — "type 5, tab out, expect range error" is its own step).
5. Write `Active\<TARGET>\smoke.md` using this template:

```markdown
---
target: <TARGET>
started: <ISO 8601 timestamp>
status: in-progress
driver: playwright
apps_started_by: claude | vs
apps:
  - name: <repo>
    url: <url>
    log: <relative path>
    pid: <pid or null>
---

# Smoke Walk: <TARGET>

## Scope
<Jira summary>

<Jira description, verbatim>

## Plan
1. action: ...
   expect: ...
...

## Execution Log
_(Newest entries appended below.)_

## Verdict
_(Pending.)_
```

6. Print the plan to chat. Ask `R | E | A`:
   - R → continue to Phase 4.
   - E → ask `What would you like to change?`, apply edits to the file's `## Plan`, re-print, re-ask.
   - A → set `status: aborted` in frontmatter, write `## Verdict` noting `**ABORTED before execution.** User declined plan.`, skip to Phase 5.

### Phase 4: Dispatch driver subagent

Construct the dispatch prompt with values resolved in earlier phases, then invoke the `qa-runner` agent via the Task tool.

Prompt template:

```
Smoke walk for <TARGET>.

State file: <workspace>\Active\<TARGET>\smoke.md
Apps:
  - name: <repo>
    url: <url>
    log: <log path>
  ...

Playwright launch configuration:
  args: [
    "--auth-server-allowlist=localhost,*.preferredcredit.net",
    "--auth-negotiate-delegate-allowlist=localhost,*.preferredcredit.net"
  ]
  context.ignoreHTTPSErrors: true
  userDataDir: <workspace>\.smoke\profile\<primary-host>\
  Default to headless. Switch to headed only if an auth wall is detected (see your agent docs).

Primary URL: <primary_url>

Execute the plan in the ## Plan section of the state file. Follow your agent definition for per-step behavior, failure handling, free-roam, frontmatter updates, and Verdict.

Return: one line — passed | failed | aborted | auth-fallback — optionally with up to 3 short findings.
```

Handle the agent's return value:
- **`auth-fallback`** → print to the user:
  ```
  Auth wall detected. A headed browser is open at <primary_url>. Sign in to the app, then reply 'ok' to continue.
  ```
  Wait for `ok`. Re-dispatch the agent with the same prompt plus the suffix `Resume execution — auth state is now established.`
- **`passed | failed | aborted`** → continue to Phase 5.

### Phase 5: Verdict, cleanup, cross-write

1. Read `Active\<TARGET>\smoke.md` `## Verdict`.
2. Print summary:
   ```
   /smoke <TARGET>:
     Verdict: <PASSED | FAILED | ABORTED>
     Steps executed: <N>
     Failures: <comma-separated step numbers, or "none">
     Tooling fallbacks: <count of [tooling-fallback] entries in Execution Log>
     Run folder: <workspace>\Active\<TARGET>\
     Screenshots: <workspace>\Active\<TARGET>\Screenshots\
   ```
3. **App cleanup:**
   - `apps_started_by: claude` → for each tracked PID:
     ```powershell
     Stop-Process -Id <pid> -ErrorAction SilentlyContinue
     ```
     Append `[/smoke] shutdown <ISO timestamp>` to each app's log.
   - `apps_started_by: vs` → print `Apps were started in VS; leaving them running.`
4. **Cross-write to Discussion** (unless `--no-cross-write` was passed):
   - Only if `<TARGET>` matches `^[A-Z]+-\d+$` AND `Active\<TARGET>\<TARGET>.md` exists.
   - Insert one line at the top of `## Discussion` (above the first existing entry):
     ```
     [smoke] PASS — all <N> steps. See smoke.md.
     ```
     or
     ```
     [smoke] FAIL — <one-line>. See smoke.md.
     ```
     or
     ```
     [smoke] ABORTED at step <N> — <reason>. See smoke.md.
     ```
   - Adhoc targets: skip cross-write.

## Notes

- The driver subagent never prompts the user. The orchestrator owns user interaction; the only mid-run prompt is the auth-fallback handshake.
- `smoke.md` is updated incrementally during the walk. Re-running `/smoke <TARGET>` while a run is in-progress resumes at the next un-logged step.
- The persistent Playwright profile per host caches the app session cookie post-Windows-Auth handshake, keeping subsequent runs headless. If the profile gets stale (cookies expired), the driver detects the auth wall on the next run and triggers the auth-fallback flow.
- Cleanup is best-effort. Failure to `Stop-Process` is logged but non-fatal.
- This skill is local-only by design. For QA against `dev`, `qa`, or `staging`, use `/qa <key> <env>`.

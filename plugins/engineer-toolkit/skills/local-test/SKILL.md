---
name: local-test
description: Run an autonomous local test walk over a Jira ticket or adhoc investigation (formerly /smoke — renamed 2026-07-13). Starts the local app(s), composes a walk plan from the acceptance criteria, dispatches the playwright-driver subagent to drive the browser while tailing app logs for exceptions. Local environment only — for deployed-env QA use /qa instead.
argument-hint: <key-or-hint> [--vs] [--no-cross-write]
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task, mcp__plugin_atlassian_atlassian__atlassianUserInfo, mcp__plugin_atlassian_atlassian__getJiraIssue
---

<!-- Distribution copy. Canonical source: the ClaudeWorkspace project skill of the same name; sync deliberately. Last sync: 2026-07-13. -->

In this skill, `<workspace>` refers to the Workspace path defined in the workspace `CLAUDE.md` `## Configuration` block. `<CloudId>` refers to the Jira CloudId from the same Configuration block.

# Local Test

Run an autonomous local test walk: start the app(s), walk the acceptance criteria via Playwright, watch the app log for exceptions, write a verdict. Local environment only. (Formerly `/smoke` — renamed 2026-07-13.)

The orchestrator (this skill) runs in the main conversation. The walk itself is dispatched to the `playwright-driver` subagent — a pure function (dispatch prompt in, structured return out). The driver does not read or write `local-test.md`; this skill owns the file end-to-end.

For deployed-env QA verification use `/qa <key> <env>` (env = `dev` | `qa` | `staging`). For pre-PR review use `engineer-toolkit:author-review`.

## Configuration

Read from the workspace `CLAUDE.md` `## Configuration` table:
- `Jira CloudId` (referred to as `<CloudId>` below)

Hardcoded in this skill:
- Active issues folder: `<workspace>\Active\`
- PlanningWorkspace fallback: `<workspace>\PlanningWorkspace\`
- Browser profile cache: `<workspace>\.local-test\profile\<host>\`
- Jira key pattern (regex): `^[A-Z]+-\d+$`
- Playwright auth flags (Windows Integrated Authentication):
  - `--auth-server-allowlist=localhost,*.preferredcredit.net`
  - `--auth-negotiate-delegate-allowlist=localhost,*.preferredcredit.net`
- App startup timeout: 60 seconds (per app)

## Invocation

`/local-test <key-or-hint> [--vs] [--no-cross-write]`

- `<key-or-hint>` (required): Jira key (e.g. `CO-166`), adhoc slug, or substring hint.
- `--vs` (optional): the user starts the app(s) in Visual Studio and supplies log paths. Default = Claude starts via `dotnet run`.
- `--no-cross-write` (optional): suppress the `[local-test]` line written to the issue file's Discussion at end-of-run.

If `<key-or-hint>` is missing, print exactly:

```
Usage: /local-test <key-or-hint> [--vs] [--no-cross-write]
```

and stop.

## Argument Resolution

See [references/argument-resolution.md](../../references/argument-resolution.md). Apply the standard algorithm against `<workspace>\Active\` and store the resolved name as `<TARGET>`. No variant applies. Resolution runs BEFORE Phase 0.

## Phases

Run in order. Do NOT skip ahead.

### Phase 0: Setup

1. Ensure run folder exists:
   ```powershell
   New-Item -ItemType Directory -Path "<workspace>\Active\<TARGET>\Screenshots" -Force | Out-Null
   ```
2. Check for an existing `Active\<TARGET>\local-test.md` (or a legacy `smoke.md` from before the rename — treat it identically, but write all new output to `local-test.md`):
   - **`status: in-progress`** → print `Resuming /local-test for <TARGET>.` Skip Phase 3 (plan exists). Resume Phase 4 (driver re-dispatch).
   - **`status: passed | failed | aborted`** → prompt `R | F | C` (re-run / fork / close):
     - R → rename existing `local-test.md` to `local-test-<YYYYMMDDHHMMSS>.md`, continue as fresh.
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
   - `urls.dev | qa | staging` = leave unset for now (only `urls.local` is required for /local-test).
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

The literal start commands (PowerShell port probe, bash build + spawn, PowerShell ready-signal poll, log-path freshness check) live in [references/start-apps.md](../../references/start-apps.md). The flow:

**`--vs` mode:** for each app, print `Start <repo> in Visual Studio (launch profile: <profile>, expected URL: <url>). Redirect stdout/stderr to a log file I can read. Reply with the absolute log path.` Wait for the user's response, validate the path (exists + modified within 5 min), re-prompt on failure. Set `apps_started_by: vs` in local-test.md.

**Default mode (Claude starts):** for each app, port-probe to detect already-running instances (prompt `R | K | A` if listening). Build each repo once (abort on non-zero exit). Determine start order via `depends_on` topo sort. Spawn each app in background via `dotnet run`. Poll each log for the `ready_signal` with a 60s timeout. Set `apps_started_by: claude` and record PID + shell ID per app for cleanup.

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
5. Write `Active\<TARGET>\local-test.md` using this template:

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

# Local Test Walk: <TARGET>

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

The agent is a pure function: dispatch prompt in, return message out. It does not read or write local-test.md. This skill owns the file format end-to-end — this phase composes the dispatch prompt from the plan, invokes the agent, then splices the agent's return back into local-test.md.

#### Step 1: Compose the dispatch prompt

Read the `## Plan` section of `Active\<TARGET>\local-test.md` and substitute it into the dispatch prompt template at [references/playwright-dispatch-prompt.md](../../references/playwright-dispatch-prompt.md). Also substitute the Apps tuples, the primary URL, the Screenshots dir, and the per-host profile dir from the values resolved in Phases 0–2. Include the optional `Starting step: <N>` line on re-dispatch (after auth-fallback, or when resuming an interrupted run — `N` = highest step number already in `## Execution Log` + 1); omit it on a fresh first dispatch.

#### Step 2: Invoke the agent

Dispatch `playwright-driver` via the Task tool with the composed prompt.

#### Step 3: Splice the return into local-test.md

When the agent returns, parse the message:

- **First line** — `Verdict: <token>` where `<token>` is `passed`, `failed`, `aborted at step <N>`, or `auth-fallback at step <N>`.
- **Second line** — the human-readable verdict (`**PASSED** — ...` / `**FAILED** — ...` / etc.).
- **Optional lines 3-5** — short findings.
- **`## Step Results` block** — one `### Step N: ...` entry per executed step.

Then:

1. **If `Verdict: auth-fallback at step <N>`** → print to the user:
   ```
   Auth wall detected at step <N>. A headed browser is open at <primary_url>. Sign in to the app, then reply 'ok' to continue.
   ```
   Wait for `ok`. Append whatever `## Step Results` entries the agent returned (steps 1..N-1) to local-test.md's `## Execution Log`. Re-dispatch the agent with the same prompt plus `Starting step: <N>`. Loop back to Step 3 to parse the new return.
2. **Otherwise** (`passed | failed | aborted`):
   a. Append the agent's `## Step Results` entries to local-test.md's `## Execution Log`. Preserve any entries appended from prior auth-fallback rounds.
   b. Write the human-readable verdict line (and any findings) into local-test.md's `## Verdict` section, replacing the `_(Pending.)_` placeholder.
   c. Update local-test.md frontmatter `status:` to match the token (`passed | failed | aborted`).
   d. Continue to Phase 5.

### Phase 5: Verdict, cleanup, cross-write

1. Read `Active\<TARGET>\local-test.md` `## Verdict`.
2. Print summary:
   ```
   /local-test <TARGET>:
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
     Append `[/local-test] shutdown <ISO timestamp>` to each app's log.
   - `apps_started_by: vs` → print `Apps were started in VS; leaving them running.`
4. **Cross-write to Discussion** (unless `--no-cross-write` was passed):
   - Only if `<TARGET>` matches `^[A-Z]+-\d+$` AND `Active\<TARGET>\<TARGET>.md` exists.
   - Insert one line at the top of `## Discussion` (above the first existing entry):
     ```
     [local-test] PASS — all <N> steps. See local-test.md.
     ```
     or
     ```
     [local-test] FAIL — <one-line>. See local-test.md.
     ```
     or
     ```
     [local-test] ABORTED at step <N> — <reason>. See local-test.md.
     ```
   - Adhoc targets: skip cross-write.

## Notes

- The driver subagent never prompts the user. The orchestrator owns user interaction; the only mid-run prompt is the auth-fallback handshake.
- `local-test.md` is updated by the orchestrator after each dispatch round (the driver itself never touches it). Re-running `/local-test <TARGET>` while a run is in-progress resumes at the next un-logged step via `Starting step:`.
- The persistent Playwright profile per host caches the app session cookie post-Windows-Auth handshake, keeping subsequent runs headless. If the profile gets stale (cookies expired), the driver detects the auth wall on the next run and triggers the auth-fallback flow.
- Cleanup is best-effort. Failure to `Stop-Process` is logged but non-fatal.
- This skill is local-only by design. For QA against `dev`, `qa`, or `staging`, use `/qa <key> <env>`.
- Runs are **serial-only**: never run two local-test walks in parallel — local apps bind fixed ports and collide. Finish one walk (apps shut down) before starting the next.

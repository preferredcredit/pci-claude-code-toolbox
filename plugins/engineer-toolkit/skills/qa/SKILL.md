---
name: qa
description: Run a QA verification pass for a Jira ticket or adhoc investigation against a deployed environment (dev, qa, or staging). Composes a scenario from how-tos and test data, drives automated steps via Chrome MCP, prompts the user for manual steps, captures evidence, and reports the verdict. No local code clones — for local-branch verification use /smoke instead. Argument is `<key-or-hint> <env>`.
argument-hint: <key-or-hint> <env>
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task, mcp__plugin_atlassian_atlassian__atlassianUserInfo, mcp__plugin_atlassian_atlassian__getJiraIssue, mcp__Claude_in_Chrome__navigate, mcp__Claude_in_Chrome__find, mcp__Claude_in_Chrome__form_input, mcp__Claude_in_Chrome__computer, mcp__Claude_in_Chrome__get_page_text, mcp__Claude_in_Chrome__read_page, mcp__Claude_in_Chrome__read_console_messages, mcp__Claude_in_Chrome__list_connected_browsers, mcp__Claude_in_Chrome__select_browser, mcp__Claude_in_Chrome__switch_browser
---

In this skill, `<workspace>` refers to the Workspace path defined in the workspace `CLAUDE.md` `## Configuration` block. `<CloudId>` refers to the Jira CloudId from the same Configuration block. `<vpn-host>` refers to the On-prem VPN host from the same block.

# QA

Run a QA verification pass over a Jira ticket or adhoc investigation. Drives the multi-app data setup and verification across dev, qa, or staging environments. For local-branch verification, use `/smoke` instead. Uses a hybrid execution model: Claude drives `[automated]` steps via Chrome MCP, prompts the user for `[manual]` steps, validates `[assertion]` steps against a source of truth.

This skill runs the orchestrator pipeline (phases 1–4) directly in the main conversation. Subagents are NOT dispatched for v1 — manual-step interaction requires real-time user response, which only the main conversation can provide. The `playwright-driver` agent (at `agents/playwright-driver.md`) is a pure-function Playwright walker that any future fully-automated regression flow can dispatch — it has no /qa or /smoke specifics; the caller supplies the plan, app config, and screenshots dir, and gets back a structured verdict + step results.

## Configuration

Read from the workspace `CLAUDE.md` `## Configuration` table:
- `Jira CloudId` (referred to as `<CloudId>` below)

Hardcoded in this skill:
- QA root: `<workspace>\QA\`
- Active issues folder: `<workspace>\Active\`
- Jira key pattern (regex): `^[A-Z]+-\d+$`
- Envs accepted: `dev`, `qa`, `staging`
- Per-app URLs (dev / qa / staging): read from `<workspace>\PlanningWorkspace\<repo>\CLAUDE.md` `## Environments` section. `QA\Environments.md` is the workspace-level fallback when a repo's CLAUDE.md doesn't declare URLs for the target env.

## Invocation

`/qa <key-or-hint> <env>` — both arguments required.

- `<key-or-hint>`: Jira key (e.g., `CRD-123`), adhoc slug (kebab-case, e.g., `flaky-payment-bug`), or a substring hint.
- `<env>`: `dev`, `qa`, or `staging`. For local-branch verification, use `/smoke` instead.

If either argument is missing or `<env>` is not one of the three valid values, print exactly:

```
Usage: /qa <key-or-hint> <env>
  env must be dev, qa, or staging.
```

and stop.

## Argument Resolution

See [references/argument-resolution.md](../../references/argument-resolution.md). Apply the **multi-root** variant — `/qa` searches both `<workspace>\QA\Active\` and `<workspace>\Active\` because the QA run folder can exist independently of the issue folder. Store the resolved name as `<TARGET>`. Resolution runs BEFORE Phase 1.

## Phases

Run these phases in order. Do NOT skip ahead.

### Phase 1: VPN check

Two probes — Atlassian Cloud is public-internet, so it succeeds with or without VPN. The on-prem host (`<vpn-host>`) is the actual VPN signal. Both must succeed.

**Probe 1 — Atlassian reachability:** call `mcp__plugin_atlassian_atlassian__atlassianUserInfo` with no parameters. On failure (network error, auth error, timeout, any non-200 response), print:
```
VPN check failed — Atlassian API unreachable. Connect to VPN and re-run /qa.
```
and stop.

**Probe 2 — On-prem reachability:** run `nslookup <vpn-host> 2>&1 | head -5`. If output contains `can't find`, `NXDOMAIN`, `server can't find`, or the command exits non-zero, print:
```
VPN check failed — <vpn-host> not resolving. Connect to VPN and re-run /qa.
```
(substituting the actual host) and stop.

Only proceed to Phase 2 when both probes pass.

### Phase 2: Resolve target and set up run folder

Branch by whether the QA run folder already exists.

**If `<workspace>\QA\Active\<TARGET>\` exists — resume case.** Read `run.md`, extract `status` from frontmatter, then:

- `status: in-progress` — find the highest step in `## Execution Log`, print `Resuming <TARGET> from step <N>: <description>.`, continue to Phase 3.
- `status: passed | failed | blocked` — print `## Verdict`, then prompt:
  ```
  Run is currently <status>. Options:
    R — re-run from scratch (archives current run.md to run-<timestamp>.md)
    F — fork to a new scenario (archives, then prompts Phase 3 Step 3 for new scope)
    C — close (no action, /qa exits)
  ```
  On `R` or `F`: rename existing `run.md` to `run-<YYYYMMDDHHMMSS>.md`, then proceed as fresh case below (F sets a flag for Phase 3 Step 3 to ask new scope). On `C`: print `Closed.` and stop.

**If `<workspace>\QA\Active\<TARGET>\` does not exist — fresh case.**

1. Create folders: `<workspace>\QA\Active\<TARGET>\Screenshots` and `Notes`.
2. **Ticketed target** (matches `^[A-Z]+-\d+$`): call `getJiraIssue` (`cloudId: <CloudId>`, `issueIdOrKey: <TARGET>`, `fields: ["summary", "description", "status"]`). On failure, print `Failed to fetch Jira ticket <TARGET>: <error>. Continuing without Jira-pre-fill.` and treat as adhoc below.
3. Write `run.md` using the canonical template (next subsection); only the `## Scope` section differs:
   - Ticketed: Jira summary as a bold line, then Jira description verbatim.
   - Adhoc (or ticketed-with-failed-fetch): the placeholder `_(Adhoc — to be authored at start of execution.)_`. Phase 3 Step 2 will prompt the user to author Scope.

#### Canonical `run.md` template

Used for both fresh ticketed and fresh adhoc runs. Substitute `<TARGET>`, `<ENV>`, the ISO 8601 timestamp, and the Scope content.

```markdown
---
target: <TARGET>
env: <ENV>
scenario: (to be determined)
started: <ISO 8601 timestamp>
status: in-progress
---

# QA Run: <TARGET>

## Scope

<Scope content — see Phase 2 rules above for ticketed vs adhoc>

## Plan

_(To be composed in Phase 3.)_

## Execution Log

_(Newest entries appended below.)_

## Verdict

_(Pending.)_
```

### Phase 3: Execute QA (in-conversation execution loop)

This phase runs in the main conversation. Claude IS the QA runner.

#### Step 1: Read run state

Read `QA\Active\<TARGET>\run.md`. Note:
- The `env` from frontmatter.
- The contents of `## Scope`.
- Whether `## Plan` already has content (resume case) or is `_(To be composed in Phase 3.)_` (fresh case).
- The highest step number in `## Execution Log` (for resume).

#### Step 2: Author Scope (adhoc, fresh runs only)

If `## Scope` contains the placeholder text `_(Adhoc — to be authored at start of execution.)_`, prompt user:

```
What are we testing in this adhoc QA run? Describe the scope (one or more sentences):
```

Wait for response. Replace the placeholder with the user's response in `run.md`.

#### Step 3: Compose the plan

If `## Plan` already has content (resume case), skip to Step 5.

Otherwise:

1. List the contents of `QA\Scenarios\` via `Glob` for `*.md`.
2. For each scenario file, read its frontmatter `description` field. Identify any scenario whose description matches the Scope semantically.
3. **If a matching scenario exists:**
   - Read the scenario file.
   - Write the scenario's `## Steps` (with parameter bindings filled in from Scope context) into `run.md`'s `## Plan` section.
   - Set the frontmatter field: `scenario: <scenario-name>`.
4. **If no scenario matches:**
   - List `QA\HowTos\` for available how-tos. Read each one's frontmatter `description` to understand what they do.
   - List `QA\TestData\` for available data templates.
   - Compose a bespoke plan as a numbered list of how-to invocations, manual steps, and assertions, using this format:
     ```markdown
     ## Plan

     1. how-to `create-borrower` with `borrower_template=happy-path-borrower` → `borrower_id`
     2. **[manual]** Verify in Gateway.Web that the borrower appears in the customer list.
     3. **[assertion]** NextGenOrig DB: `SELECT Status FROM Borrowers WHERE Id={{borrower_id}}` → expected `Active`.
     ```
   - For parts where no how-to exists yet, inline `[manual]` steps with explicit instructions.
   - Set frontmatter: `scenario: bespoke`.
5. Write the plan into `run.md`, replacing the placeholder.

#### Step 4: Confirm plan with user (hard gate)

Print the plan you just wrote, followed by:

```
Plan composed (above). Choose:
  R — run as-is
  E — edit the plan (you'll describe edits, I'll update run.md and re-confirm)
  A — abort
```

Wait for response.

- **R**: proceed to Step 5.
- **E**: ask `What would you like to change?`, apply the edits to `run.md`'s `## Plan`, re-print, and ask again.
- **A**: set `status: blocked` in frontmatter, append to `## Verdict`:
  ```markdown
  ## Verdict

  **ABORTED before execution.** User declined to run the composed plan.
  ```
  Skip to Phase 4.

#### Step 5: Execute step-by-step

For each step `N` in the plan, in order (skipping any already in the Execution Log on resume):

##### Automated steps

If the step is tagged `[automated]` (or references a how-to whose step is `[automated]`):

1. Resolve URLs and template values:
   - For each app referenced by the step, look up `urls.<env>` in `<workspace>\PlanningWorkspace\<repo>\CLAUDE.md` `## Environments` section.
   - If the per-repo CLAUDE.md doesn't declare a URL for `<env>`, fall back to `QA\Environments.md`'s entry for that app.
   - For template substitution (`{{var}}`), look up the value in either:
     - Test data referenced in the plan (read from `QA\TestData\<file>.md`).
     - Earlier step outputs in the Execution Log.
2. Drive the action via Chrome MCP. At the start of the very first `[automated]` step in the run, call `mcp__Claude_in_Chrome__list_connected_browsers`. If no browser is connected, prompt the user:
   ```
   No Chrome browser connected via MCP. Open Chrome with the MCP extension active, then reply `ok` to retry.
   ```
   Wait for response and retry.
3. After each meaningful action (navigation, form submission), capture a screenshot:
   ```
   mcp__Claude_in_Chrome__computer with action: screenshot
   ```
   Save the screenshot to `QA\Active\<TARGET>\Screenshots\step-<N>.png` (use Write tool with binary content from the MCP response).
4. Append the outcome to `## Execution Log`:
   ```markdown
   ### Step <N>: <step description> [automated]
   - <HH:MM:SS> — <one-line observation>
   - Screenshot: Screenshots/step-<N>.png
   - Output: <var>=<value>   (if the step produces an output, capture it)
   - Result: passed
   ```

##### Manual steps

If the step is tagged `[manual]`:

1. Print to user:
   ```
   Step <N> [manual]: <step description>

   Please perform this step. Reply with one of:
     ok — step passed, continue
     fail: <reason> — step failed (mismatch); I'll ask what to do next
     abort: <reason> — hard stop, end the run now
   ```
2. Wait for response.
3. Append to Execution Log:
   ```markdown
   ### Step <N>: <step description> [manual]
   - <HH:MM:SS> — prompted user
   - <HH:MM:SS> — user replied: <response, verbatim>
   - Result: <passed if `ok` | failed if `fail:` | aborted if `abort:`>
   ```
4. If user replied `abort: ...`: handle as **Hard abort** (Step 6 below).
5. If user replied `fail: ...`: handle as **Step-level failure** (Step 6 below).
6. Otherwise: continue to next step.

##### Assertion steps

If the step is tagged `[assertion]`:

1. Execute the assertion:
   - **DB query**: run via `Bash` using `sqlcmd` if available, or via a small PowerShell SqlClient script. Connection details should come from a how-to or from user input if not yet documented.
   - **API call**: `curl` against the appropriate endpoint, parse the response.
   - **UI check**: navigate via Chrome MCP, read the relevant element.
2. Compare observed vs. expected (as stated in the step).
3. Append to Execution Log:
   ```markdown
   ### Step <N>: <step description> [assertion]
   - <HH:MM:SS> — observed: <value>
   - Expected: <value>
   - Result: <passed | failed>
   ```
4. If `failed`: handle as **Step-level failure** (Step 6 below).

#### Step 6: Failure handling

Three failure modes:

| Mode | Trigger | Resolution |
|---|---|---|
| **Hard abort** | App crashed / unrecoverable state during an automated step, OR user typed `abort: <reason>` at a manual prompt | Set `status: failed`; write `## Verdict` as `**ABORTED at step <N>.** Reason: <reason>. See Execution Log for details.`; skip to Phase 4. |
| **Step-level failure** | Assertion mismatch, OR user replied `fail: <reason>` at a manual prompt | Halt; prompt user with the `C / A / B` menu below. `C` → log decision, continue. `A` → handle as Hard abort. `B` → set `status: blocked`, write Verdict with block reason, skip to Phase 4. |
| **Tooling failure** | Chrome MCP timeout, selector not found, element not interactable — the app itself is healthy | Retry once. If still failing, append `[tooling-fallback] Chrome MCP failed: <error>. Degrading to manual.` to the Execution Log, then treat the step as `[manual]` and continue. |

Step-level failure prompt:

```
Step <N> failed: <observed> vs <expected, or user-stated reason>.

Options:
  C — continue to next step (mark this step failed but keep going)
  A — abort (end run as failed)
  B — mark blocked (end run as blocked, e.g., waiting on a code fix)
```

#### Step 7: Final verdict (full pass)

If all plan steps logged `Result: passed` (and no aborts occurred):

1. Set `status: passed` in frontmatter.
2. Write `## Verdict`:
   ```markdown
   ## Verdict

   **PASSED** — all <N> steps completed successfully.
   ```

#### Step 8: Offer library promotion (passed runs only)

If `status` is `passed`, run the library-promotion routine: scan the Execution Log for reusable patterns, prompt the user per candidate, and write accepted how-tos to `<workspace>\QA\HowTos\`. See [references/library-promotion.md](../../references/library-promotion.md) for the detection rules, the user prompt format, and the how-to template.

Skip this step entirely if `status` is `failed` or `blocked` — partial or incorrect sequences should not become reusable how-tos. After all candidates handled (or none found), continue to Phase 4.

### Phase 4: Report and cross-write

#### Print summary

Print to the user:

```
QA Run <TARGET> on <env>:
  Verdict: <PASSED | FAILED | BLOCKED>
  Steps executed: <N>
  Failures: <comma-separated step numbers, or "none">
  Tooling fallbacks: <count of [tooling-fallback] entries in Execution Log, or "none">
  Run folder: <workspace>\QA\Active\<TARGET>\
```

If the Verdict is not PASSED, append:
```
  See Verdict and Execution Log in run.md for details.
```

#### Cross-write to issue Discussion (ticketed runs only)

If `<TARGET>` matches `^[A-Z]+-\d+$` AND `<workspace>\Active\<TARGET>\<TARGET>.md` exists:

1. Read `Active\<TARGET>\<TARGET>.md`.
2. Find the `## Discussion` section. Below the header line `_(Newest first - format: [agent] message)_`, find the first existing entry (or the location right after that header line if no entries).
3. Insert one line directly above the first existing entry (or right after the format-hint line):
   ```
   [qa] <env> run: <verdict>. <one-line summary>. See QA\Active\<TARGET>\run.md.
   ```
   Where `<one-line summary>` is generated based on results:
   - PASSED: `All <N> steps passed`
   - FAILED with hard abort: `Aborted at step <N>: <reason>`
   - FAILED with step-level failure: `Step <N> failed: <one-line observation>`
   - BLOCKED: `Blocked at step <N>: <reason>`

Adhoc runs (target doesn't match Jira key regex): skip cross-write.

## Notes

- All Atlassian MCP failures inside Phase 2 are non-fatal except `getJiraIssue` in Case B (no Jira lookup = no Scope pre-fill). If that fails, fall through to Case C (treat as adhoc) and the user will author Scope at Phase 3 Step 2.
- Chrome MCP browser connection is checked lazily at the first `[automated]` step, not at Phase 1. This lets you start runs without a browser connected when the first steps are manual.
- `[tooling-fallback]` entries are surfaced in the Phase 4 summary so a "PASSED" verdict that relied heavily on manual fallback is visible at a glance.
- The user can interrupt at any manual prompt with `abort: <reason>` to trigger a hard abort.
- Run.md is updated incrementally during execution — if the conversation is interrupted, re-running `/qa <TARGET> <env>` enters Case A (resume) and picks up at the next un-executed step.

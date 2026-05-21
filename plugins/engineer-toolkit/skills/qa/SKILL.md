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

Three cases — pick the one that matches `<TARGET>`:

#### Case A: `QA\Active\<TARGET>\` exists

Resume an existing run.

1. Read `QA\Active\<TARGET>\run.md`.
2. Extract the `status` field from the YAML frontmatter.
3. **If `status: in-progress`:**
   - Look at the `## Execution Log` section to find the highest step number already logged.
   - The next step to execute is the step after it in the `## Plan` section.
   - Print: `Resuming <TARGET> from step <N>: <step description>.`
   - Continue to Phase 3.
4. **If `status: passed`, `status: failed`, or `status: blocked`:**
   - Print the contents of the `## Verdict` section.
   - Ask user (this is a literal prompt — wait for response):
     ```
     Run is currently <status>. Options:
       R — re-run from scratch (archives current run.md to run-<timestamp>.md)
       F — fork to a new scenario (archives, starts fresh with new scope)
       C — close (no action, /qa exits)
     ```
   - On `R`: rename existing `run.md` to `run-<YYYYMMDDHHMMSS>.md`, then proceed as if Case B/C (depending on target type).
   - On `F`: same as `R`, but during Phase 3 Step 3 prompt the user for new scenario context.
   - On `C`: print `Closed.` and stop.

#### Case B: Target is a Jira key without a QA run

(Target matches `^[A-Z]+-\d+$` AND `QA\Active\<TARGET>\` does NOT exist.)

1. Create folders:
   ```bash
   mkdir -p "<workspace>/QA/Active/<TARGET>/Screenshots"
   mkdir -p "<workspace>/QA/Active/<TARGET>/Notes"
   ```
2. Call `mcp__plugin_atlassian_atlassian__getJiraIssue` with:
   ```
   cloudId: <CloudId>
   issueIdOrKey: <TARGET>
   fields: ["summary", "description", "status"]
   ```
3. If the call fails: print `Failed to fetch Jira ticket <TARGET>: <error>. Continuing without Jira-pre-fill.` and treat as Case C (adhoc).
4. Write `QA\Active\<TARGET>\run.md` using this template (substitute placeholders):
   ```markdown
   ---
   target: <TARGET>
   env: <ENV>
   scenario: (to be determined)
   started: <ISO 8601 timestamp, e.g., 2026-05-11T14:00:00Z>
   status: in-progress
   ---

   # QA Run: <TARGET>

   ## Scope

   **<Jira summary>**

   <Jira description, verbatim — already markdown>

   ## Plan

   _(To be composed in Phase 3.)_

   ## Execution Log

   _(Newest entries appended below.)_

   ## Verdict

   _(Pending.)_
   ```

#### Case C: Target is an adhoc slug without a QA run

(Target does NOT match `^[A-Z]+-\d+$` AND `QA\Active\<TARGET>\` does NOT exist.)

1. Create folders:
   ```bash
   mkdir -p "<workspace>/QA/Active/<TARGET>/Screenshots"
   mkdir -p "<workspace>/QA/Active/<TARGET>/Notes"
   ```
2. Write `QA\Active\<TARGET>\run.md`:
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

   _(Adhoc — to be authored at start of execution.)_

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

**Hard abort** — triggered by:
- App crashed, blocking error, or unrecoverable data state observed during an automated step.
- User typed `abort: <reason>` at a manual prompt.

Actions:
1. Set `status: failed` in `run.md` frontmatter.
2. Replace `## Verdict` content with:
   ```markdown
   ## Verdict

   **ABORTED at step <N>.** Reason: <reason>.

   See Execution Log for details.
   ```
3. Skip to Phase 4.

**Step-level failure** — assertion mismatch or user replied `fail: <reason>` at a manual prompt.

Actions:
1. Halt execution and prompt user:
   ```
   Step <N> failed: <observed> vs <expected, or user-stated reason>.

   Options:
     C — continue to next step (mark this step failed but keep going)
     A — abort (end run as failed)
     B — mark blocked (end run as blocked, e.g., waiting on a code fix)
   ```
2. On `C`: log the user's decision in Execution Log, continue to next step.
3. On `A`: same as Hard abort.
4. On `B`: set `status: blocked`, write Verdict noting the block reason, skip to Phase 4.

**Tooling failure** — Chrome MCP timeout, selector not found, element not interactable; the application itself is healthy.

Actions:
1. Retry the action once.
2. If still failing, append to Execution Log:
   ```
   - <HH:MM:SS> — [tooling-fallback] Chrome MCP failed: <error>. Degrading to manual.
   ```
3. Treat the step as `[manual]` from this point — print the manual prompt and wait for user response. Continue.

#### Step 7: Final verdict (full pass)

If all plan steps logged `Result: passed` (and no aborts occurred):

1. Set `status: passed` in frontmatter.
2. Write `## Verdict`:
   ```markdown
   ## Verdict

   **PASSED** — all <N> steps completed successfully.
   ```

#### Step 8: Offer library promotion (passed runs only)

Skip this step if `status` is `failed` or `blocked`. Partial or incorrect sequences should not become reusable how-tos.

For `status: passed` runs:

1. Scan the `## Execution Log` for inlined step sequences that could become reusable how-tos. Look for:
   - 2+ consecutive steps that together form a single domain operation (e.g., "navigate → fill borrower form → submit → capture id" = `create-borrower`).
   - Manual-step prompts describing a discrete user action with clear inputs and outputs.
   - Sequences that referenced no existing how-to (you authored them inline during plan composition).
2. For each candidate sequence, propose a how-to name (kebab-case, derived from the operation, e.g., `create-borrower`, `originate-deal`). Check `QA\HowTos\` for name collisions; if a collision exists, append a numeric suffix or pick a more specific name.
3. Prompt the user once per candidate (in order; do not batch):
   ```
   Detected a reusable pattern in steps <N>-<M>:
     <one-line summary of the sequence>
     Inputs:  <comma-separated input names>
     Outputs: <comma-separated output names>

   Save as `QA\HowTos\<proposed-name>.md`?
     Y — yes, save as proposed
     R — rename, then save (I'll ask for the new name)
     N — no, skip this one
   ```
4. Wait for response.
   - **Y**: write the how-to file using the template below. Append a line to the Execution Log: `[promoted] Steps <N>-<M> → QA\HowTos\<proposed-name>.md`.
   - **R**: ask `What name? (kebab-case, no path or .md extension)`, validate (kebab-case format, no collision); on valid input, write file and log `[promoted]` entry. On invalid input, ask again or fall back to `N` after two tries.
   - **N**: skip silently. Move to next candidate.
5. After all candidates handled (or if no candidates found): continue to Phase 4.

If the user replies with anything other than `Y | R | N` at the prompt, re-ask once; on second invalid response, default to `N` for that candidate.

**How-to template** (use when promoting):

```markdown
---
name: <kebab-case-name>
description: <one-line description derived from the sequence>
inputs: [<list of input names extracted from the sequence>]
outputs: [<list of output names captured in the sequence>]
---

# How-To: <Title Case Name>

## Steps

<numbered list of steps copied from the inlined sequence, preserving [automated]/[manual]/[assertion] tags. Replace concrete values from the source run with `{{var}}` placeholders where they correspond to inputs.>

## Notes

- Promoted from run `<TARGET>` on <YYYY-MM-DD>.
```

Library promotion applies only to how-tos in v1. Test data templates and named scenarios are not auto-promoted; the user can request those explicitly after the run.

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

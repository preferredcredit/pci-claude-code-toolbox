---
name: work
description: Run the work pass — VPN check, refresh Jira Status field on local files, sweep completed items, print dashboard, process `go`-flagged work. Accepts an optional issue key or hint to scope to a single item.
argument-hint: [key-or-hint]
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Task, mcp__plugin_atlassian_atlassian__atlassianUserInfo, mcp__plugin_atlassian_atlassian__getJiraIssue, mcp__plugin_atlassian_atlassian__getTransitionsForJiraIssue, mcp__plugin_atlassian_atlassian__transitionJiraIssue, mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql
---

In this skill, `<workspace>` refers to the Workspace path defined in the workspace `CLAUDE.md` `## Configuration` block.

# Work

Run a work pass over `<workspace>\Active\`. Idempotent — re-runs cheaply when nothing has the `go` flag.

## Two-field status model

Each ticketed issue file carries two distinct fields:

- **`Status:`** — the local workflow state (Planning / Development / Code Review / Development Complete / Complete). Owned by Claude and the user. `/work` reads it to decide what to dispatch in Phase 5; `/work` never overwrites it.
- **`Jira Status:`** — the verbatim Jira ticket status, refreshed in Phase 2. Read-only mirror; only Phase 2 writes it. Used by Phase 3 to decide whether the ticket is "done in Jira" and should be swept, and by Phase 5 to decide whether to issue a Jira transition.

Adhoc items (kebab-case directories, no `Jira:` line) only have `Status:`. They never get a `Jira Status:` line.

## Configuration

Read from the workspace `CLAUDE.md` `## Configuration` table:
- `Workspace path` (referred to as `<workspace>` below)
- `Jira CloudId`
- `User Account ID`

Hardcoded in this skill (PCI-wide):
- PlanningWorkspace: `<workspace>\PlanningWorkspace\`
- Active folder: `<workspace>\Active\`
- Complete folder: `<workspace>\Complete\`
- Jira key pattern (regex): `^[A-Z]+-\d+$` — matches directory names to determine ticketed vs adhoc.

## Modes

- **Full pass** (`/work`, no argument): every phase considers every Active item. Phase 5 processes only `go`-flagged items.
- **Targeted** (`/work <hint>`): phases 2, 3, 4, 5, 6 are scoped to a single resolved target. Phase 5 processes the target regardless of `go` flag — naming the item is consent. Phases 0 and 1 always run identically.

## Argument Resolution (targeted mode only)

When an argument is provided, resolve it to a single `Active\<DIR>\` BEFORE running Phase 0. Resolution order (first match wins):

1. **Exact directory match** (case-insensitive): use Glob on `<workspace>\Active\<arg>\` (case-insensitive comparison if needed).
2. **Upper-cased Jira-key match**: if the argument matches `^[a-zA-Z]+-\d+$`, upper-case it and try as an exact match (`co-322` → `CO-322`).
3. **Substring match**: case-insensitive substring against all `Active\` directory names.

Outcomes:

- **Zero matches** — print `No active item matches '<arg>'.` and stop.
- **Multiple matches** — print `Multiple matches for '<arg>': <comma-separated list>. Be more specific.` and stop.
- **One match** — store the resolved directory name as `<TARGET>` and proceed to Phase 0.

## Phases

Run these phases in order. Do NOT skip ahead. Each phase's output feeds the next.

### Phase 0: VPN check

Call `mcp__plugin_atlassian_atlassian__atlassianUserInfo` with no parameters.

- On success: proceed silently to Phase 1.
- On failure (network error, auth error, timeout, any non-200 response): print exactly:
  ```
  VPN check failed — Atlassian API unreachable. Connect to VPN and re-run /work.
  ```
  and stop. Do NOT proceed to subsequent phases.

### Phase 1: Refresh PlanningWorkspace

For each subdirectory in `<workspace>\PlanningWorkspace\`:

```bash
cd "<workspace>/PlanningWorkspace/<repo>" && git fetch origin && git reset --hard origin/main
```

If a repo fails (network, conflict, missing remote), capture the error and continue with the next repo. Track failed repos for the Phase 6 summary.

Use this single bash command to do all repos at once and capture errors:

```bash
cd <workspace>/PlanningWorkspace && for dir in */; do
  echo "=== $dir ==="
  (cd "$dir" && git fetch origin 2>&1 && git reset --hard origin/main 2>&1) || echo "FAILED: $dir"
done
```

### Phase 2: Refresh `Jira Status:` on ticketed items

Phase 2 refreshes the **`Jira Status:`** field only. It NEVER touches the local **`Status:`** field. The two are decoupled — see "Two-field status model" above.

1. Build the working set:
   - **Full pass**: use Glob to enumerate all `<workspace>\Active\*\` directories.
   - **Targeted**: working set is just `<TARGET>`.
2. For each directory `<DIR>` in the working set:
   - If `<DIR>` matches the Jira-key regex (`^[A-Z]+-\d+$`), it is a **ticketed item**.
   - Otherwise, it is an **adhoc item** — skip in this phase.
3. For each ticketed item:
   - Read the issue file at `<workspace>\Active\<DIR>\<DIR>.md`.
   - Extract the current `Jira Status:` field value, if present. If the field is missing entirely, treat the previous value as empty (the line will be inserted, not updated).
   - Call `mcp__plugin_atlassian_atlassian__getJiraIssue` with `cloudId: 19ff5866-fc24-4369-81c2-4b8de43058a3`, `issueIdOrKey: <DIR>`, `fields: ["status"]`.
   - Compare the new Jira status name to the local `Jira Status:` field (case-insensitive after trimming).
   - **If they match:** do nothing.
   - **If they differ (or the field is missing):**
     - **Add or update the `Jira Status:` line** with the new value (preserve Jira's casing).
       - If the field already exists, edit the line in place.
       - If the field is missing, insert it directly below the `Jira:` URL line.
     - Insert a new line at the top of the Discussion section (right after the `_(Newest first - format: [agent] message)_` line, before any existing entries):
       ```
       [sync] Jira status changed from <old-value> to <new-value>.
       ```
       Use `(none)` for `<old-value>` if the field was missing.

**Important:** Do NOT touch the local `Status:` field — it represents the local workflow state and is owned by Claude/the user.

To insert at the top of Discussion safely with the Edit tool, find the existing first non-blank line under the Discussion header and insert the new line above it.

### Phase 3: Sweep completed work

1. Build the working set:
   - **Full pass**: re-enumerate all `Active\*\` directories (some may have been touched by Phase 2).
   - **Targeted**: working set is just `<TARGET>` (verify it still exists; Phase 2 should not have moved it).
2. For each directory `<DIR>` in the working set:
   - Read `Active\<DIR>\<DIR>.md`.
   - Extract local `Status:` field. For ticketed items, also extract `Jira Status:` field.
   - Determine if it should be swept:
     - **Ticketed** (`<DIR>` matches Jira-key regex): sweep if **either** of the following (case-insensitive, trimmed):
       - local `Status:` is `Complete`
       - `Jira Status:` is `Complete` OR `Development Complete`

       Once `Jira Status:` reaches `Development Complete`, dev work is done and `/work` stops tracking it locally; QA is handled outside this workflow. Local `Status: Complete` is the user/agent's manual override.
     - **Adhoc**: sweep if local `Status:` is `Complete` (case-insensitive).
3. For each item to sweep, run:
   ```bash
   mv "<workspace>/Active/<DIR>" "<workspace>/Complete/<DIR>"
   rm -rf "<workspace>/Complete/<DIR>/AgentWorkspace"
   ```
4. Track swept items for the Phase 6 summary.

### Phase 4: Dashboard

**Full pass:**

1. Re-enumerate `Active\*\` directories (after sweep).
2. For each directory, read its `<DIR>.md` file and extract:
   - Title — first `# ...` line, stripped.
   - Status — local `Status:` field value.
   - Tier — `Tier:` field value (empty → `-`).
   - Mode — `Mode:` field value (empty → `-`).
   - Jira — `Jira Status:` field value if present, else `-` (adhoc items).
   - Branch — `Branch:` field value (empty → `-`).
   - Blocked — `Blocked:` field value (empty → `-`).
   - Next — `agent` if file's first non-empty line starts with `go` (case-insensitive), else `user`.
3. Print:

```
Active Work (<N> items)

| Key      | Title                          | Status               | Tier     | Mode    | Jira                 | Next  | Branch       | Blocked |
|----------|--------------------------------|----------------------|----------|---------|----------------------|-------|--------------|---------|
| <key>    | <title>                        | <status>             | <tier>   | <mode>  | <jira>               | <next>| <branch>     | <blocked> |
...

Ready for agent: <K> items have `go` flag (<comma-separated keys>)
Locked to chat: <L> items have Mode: direct (<comma-separated keys>)
```

- Truncate Title to 30 characters with `…` if longer.
- If `<N>` is 0, print `Active Work (0 items)` and skip the table.
- If `<K>` is 0, print `Ready for agent: 0 items.`

**Also write the HTML dashboard** (full pass only, when `<N>` ≥ 1):

Write a single-file dark-themed HTML report to `<workspace>\dashboard.html` containing the same per-item data, rendered as a card/table action board. Color-code rows by `Status:`, show `Jira Status:` and `Branch` as clickable links where applicable, mark `Mode: direct` items with a distinct badge. The Launch preview panel auto-renders the file. The chat output remains the markdown table above — the HTML is the readable surface, the chat block is the at-a-glance.

Skip the HTML write if `<N>` is 0 — leave any prior `dashboard.html` in place.

**Targeted:**

If `<TARGET>` was swept in Phase 3 (its directory no longer exists in `Active\`), print `Target <TARGET> was swept to Complete\.` Phase 5's guard clause will skip processing; proceed to Phase 6.

Otherwise, read `<TARGET>`'s file and print a single-line header:

```
Target: <TARGET> — <status> (tier: <tier-or-->, mode: <mode-or-->), jira: <jira-or-->, next: <agent|user>, branch: <branch-or-->, blocked: <blocked-or-->
```

### Phase 5: Process items

**Guard clauses:**

1. **Targeted mode + swept:** if targeted mode and `<TARGET>` no longer exists in `Active\` (because Phase 3 swept it), skip directly to Phase 6.
2. **Targeted mode + Mode: direct:** if `<TARGET>` has `Mode: direct` in its file, abort with:
   ```
   <TARGET> is Mode: direct. Use /direct <TARGET> or remove the lock first.
   ```
   Do not dispatch.

**Build the queue:**

- **Full pass**: items where (the file's first non-empty line starts with `go`, case-insensitive) AND (the file does NOT contain a `Mode: direct` line).
- **Targeted**: a single-item queue containing `<TARGET>` (already verified not Mode: direct).

**Log skips:**

In full pass mode, list any items skipped because of `Mode: direct` in the Phase 6 summary as:
```
Skipped (Mode: direct): <KEY>, <KEY>, ...
```

**Sort the queue** by Priority field (`High` > `Medium` > `Low`; missing or unrecognized → treat as `Medium`), then by directory name ascending. (Targeted mode has only one item, so sorting is trivial.)

**For each queued item, in order:**

1. If the user added comments after the `go` line (text between `go` and `# <title>`), copy them to Discussion as `[user]` entry, then remove that text from the file. (In targeted mode without a `go` line, this step is a no-op.)
2. Determine action by `Status:` and `Tier:` fields:

   | Local `Status:` | `Tier:` set? | Dispatch |
   |---|---|---|
   | `Planning` | no | Run **Triage**: dispatch a subagent that reads the issue file plus 1-2 relevant code files referenced in the description, proposes Trivial / Standard / Full with one-sentence rationale, writes `Tier:` field, logs `[Triage] Tier=<tier>: <rationale>` in Discussion, removes `go` line, and exits. User reviews and re-adds `go`. |
   | `Planning` | `Trivial` | Skip Spec and Plan phases. Set `Status: Development`, clone AgentWorkspace, create branch, transition Jira to In Development. Dispatch a subagent running `superpowers:executing-plans` with the issue description as the implicit plan (no plan.md). |
   | `Planning` | `Standard` | Dispatch a subagent running `superpowers:writing-plans` to produce `Active\<DIR>\plan.md`. On return, subagent sets `Status: Code Review`, removes `go`. User reviews plan.md and re-adds `go` to proceed to Development. |
   | `Planning` | `Full` | Dispatch a subagent running `superpowers:brainstorming` to produce `Active\<DIR>\spec.md`, then `superpowers:writing-plans` to produce `Active\<DIR>\plan.md`. On return, subagent sets `Status: Code Review`, removes `go`. |
   | `Development` (or `In Development`) | — | Clone AgentWorkspace if missing, create branch if missing, transition Jira to In Development if not already (see step 3 below), dispatch a subagent running `superpowers:executing-plans` with `plan.md` as input. |
   | `Code Review` / `Development Complete` / `QA` / `QA Complete` / `Complete` / `Deployed` | — | Skip with warning logged for the Phase 6 summary in the format `[<KEY>] Skipped — Status=<status> is not actionable by /work.` |

3. **Outbound Jira transition (ticketed items only, when dispatching a development subagent):**
   - Check the local `Jira Status:` field (refreshed in Phase 2). If already `In Development` (case-insensitive), skip the transition silently.
   - Otherwise, call `mcp__plugin_atlassian_atlassian__getTransitionsForJiraIssue` with `cloudId: 19ff5866-fc24-4369-81c2-4b8de43058a3`, `issueIdOrKey: <KEY>`.
   - Find a transition whose target name is `In Development` (case-insensitive).
   - If found, call `mcp__plugin_atlassian_atlassian__transitionJiraIssue` with the transition ID.
   - If not found, log to summary: `[<KEY>] Could not find "In Development" transition; skipped.`
   - On any error, log to summary and continue — do NOT block dev work.
   - On success, optimistically update the local `Jira Status:` line to `In Development`.

4. After dispatch, the subagent runs `engineer-toolkit:author-review` as the final pre-PR step (per CLAUDE.md > Agent Workflow > Review phase) and opens the PR with the author-review summary as the description.

Subagents launch concurrently.

### Phase 6: Summary

After all subagents return, print:

```
Done. Processed <N> items:
- <key>: <action taken, new local status>
...

Swept <M> items to Complete:
- <key>
...

Sync updated <K> local files from Jira.

PlanningWorkspace refresh failures: <list, or "none">

Warnings:
- <any warning text>
```

Omit a section if it has zero entries.

In targeted mode, the summary covers only `<TARGET>`. Sections that don't apply (e.g., `Sync updated K local files from Jira` when sync touched zero items) are omitted as in full pass.

### Phase 7: Suggest next work (full pass, idle only)

Run only if **all** of these are true:

- Mode is full pass (no argument).
- Phase 5 dispatched zero subagents (no items had the `go` flag).
- Active folder has at least one item.

Otherwise skip silently.

Goal: surface what the user can do next, grouped by the action required. Bucket every Active item into exactly one of these groups based on the issue file's local `Status:`:

| Bucket | Inclusion rule | Hint to print |
|--------|----------------|---------------|
| **Merge & transition Jira** | `Status: Development Complete` | merge PR, then move Jira |
| **Review PR** | `Status: Code Review` AND `Branch:` is non-empty | PR awaiting your review |
| **Review plan** | `Status: Code Review` AND `Branch:` is empty | plan.md awaiting your review |
| **Resume dev** | `Status: Development` (or `In Development`) AND file has no `go` line | add `go` to resume |
| **Kick off planning** | `Status: Planning` AND file has no `go` line AND no `plan.md` exists | add `go` to start planning |
| **Plan delivered, awaiting approval** | `Status: Planning` AND file has no `go` line AND `plan.md` exists | review plan.md, then add `go` with approval |
| **Tracking / parent** | anything else (rare) | no immediate action |

Within each bucket, sort by Priority (`High` > `Medium` > `Low`), then by directory name.

Print:

```
What to do next

<Bucket name> (N):
- <KEY> — <title> — <hint>
- ...

<Next bucket> (N):
...
```

Truncate title to 50 chars with `…` if longer. Omit empty buckets entirely. If every Active item lands in **Tracking / parent** (i.e., nothing actionable), print:

```
What to do next

Nothing in Active is waiting on you. Pull a new ticket with /jira-import.
```

Keep the section terse — this is a nudge, not a report.

**Plus: surface assigned Jira issues not yet imported**

After the in-chat "What to do next" output, also check Jira for assigned work the local workflow hasn't seen:

1. Call `mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql` with:
   - `cloudId: 19ff5866-fc24-4369-81c2-4b8de43058a3`
   - `jql: project in (CRD, CO) AND status != Complete AND assignee = currentUser()`
   - `fields: ["summary", "status", "priority"]`
2. Build a "known keys" set from directory names in `<workspace>\Active\*\`, `<workspace>\Complete\*\`, and `<workspace>\Archive\*\` (case-insensitive comparison).
3. Filter the JQL result to keys NOT in the known set.
4. If any remain, print as a new bucket appended to the "What to do next" chat output:
   ```
   Pull from Jira (N):
   - <KEY> — <title> — <status> — /jira-import <KEY>
   - ...
   ```
   Sort by Priority (`Critical - Immediate` > `Highest` > `High` > `Medium` > `Low` > `Lowest`; missing → `Medium`), then by key ascending. Cap the list at 10; if more, append `… (<M> more in Jira)`.
5. **Include this bucket in the HTML "What to do next" board** as a new section with a distinct accent color (suggest indigo/violet) and the same card structure. Each card's action is `/jira-import <KEY>` rendered as a copyable code badge.
6. On any JQL failure (network, auth, timeout, non-200): skip silently — log nothing, don't break the rest of Phase 7.

The bucket name is **Pull from Jira** — Jira says you own it, `/work` has never seen it locally.

**HTML dashboard (overwrites Phase 4's write):** when Phase 7 runs, overwrite `<workspace>\dashboard.html` with a richer "action board" — bucket sections as colored cards (one per non-empty bucket), items grouped by action required, Jira / branch / PR links per item, summary stats up top (counts per bucket). Use the same dark, card-based styling as Phase 4. The in-chat output stays the terse markdown above; the HTML is the surface the user actually scans and clicks through.

## Notes

- Phases 1–4 plus Phase 6 always run, even when no `go` items exist. The dashboard is the primary value of an idle `/work` invocation.
- Phase 5 is the only phase that dispatches subagents.
- Phase 7 only runs on idle full passes — targeted mode and active dispatches skip it.
- All Atlassian MCP failures inside Phases 2, 5, and 7 are recoverable: log to summary (Phase 2/5) or skip silently (Phase 7's JQL discovery). Only Phase 0 hard-aborts on Atlassian failure.
- In targeted mode, argument resolution runs BEFORE Phase 0 — argument errors don't waste a VPN check.

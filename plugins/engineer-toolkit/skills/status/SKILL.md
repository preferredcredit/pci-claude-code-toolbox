---
name: status
description: Discovery + housekeeping pass over <workspace>\Active\. Refresh PlanningWorkspace, sync Jira Status field on local files, sweep completed items, print dashboard (markdown + HTML), suggest next work, surface unimported Jira tickets. No dispatch.
argument-hint: ""
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Task, mcp__plugin_atlassian_atlassian__atlassianUserInfo, mcp__plugin_atlassian_atlassian__getJiraIssue, mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql
---

In this skill, `<workspace>` refers to the Workspace path defined in the workspace `CLAUDE.md` `## Configuration` block. `<CloudId>` refers to the Jira CloudId from the same Configuration block.

# Status

Run a discovery + housekeeping pass over `<workspace>\Active\`. Idempotent — re-runs cheaply. Owns all writes to the `Jira Status:` field on local issue files. Does NOT dispatch any work (`/work` does that).

## Two-field status model

Each ticketed issue file carries two distinct fields:

- **`Status:`** — local workflow state. Owned by Claude and the user. `/status` never touches it.
- **`Jira Status:`** — verbatim Jira ticket status. Owned by `/status` (this skill is the only writer). Refreshed in Phase 2.

Adhoc items only have `Status:`. No `Jira Status:` line.

## Configuration

Read from the workspace `CLAUDE.md` `## Configuration` block:
- `Workspace path` (referred to as `<workspace>`)
- `Jira CloudId` (referred to as `<CloudId>`)
- `Discovery JQL` (used in Phase 5 — the JQL string that surfaces assigned-but-unimported tickets)

Hardcoded in this skill:
- PlanningWorkspace: `<workspace>\PlanningWorkspace\`
- Active folder: `<workspace>\Active\`
- Complete folder: `<workspace>\Complete\`
- Jira key pattern (regex): `^[A-Z]+-\d+$`

## Mode

Full pass only. `/status` does not accept arguments. (For targeted-item behavior, use `/work <hint>`.)

## Phases

Run these phases in order.

### Phase 0: Atlassian probe

Call `mcp__plugin_atlassian_atlassian__atlassianUserInfo` with no parameters. On failure (network error, auth error, timeout, any non-200 response), print exactly:

```
VPN check failed — Atlassian API unreachable. Connect to VPN and re-run /status.
```

and stop.

Note: `/status` does NOT probe the on-prem VPN host. PlanningWorkspace refresh (Phase 1) talks to GitHub / Azure DevOps for those repos, not the on-prem server. If you also need to dispatch work, `/work` will do its own on-prem VPN probe.

### Phase 1: Refresh PlanningWorkspace

For each subdirectory in `<workspace>\PlanningWorkspace\`, fetch + reset to `origin/main`. If a repo fails (network, conflict, missing remote), capture the error and continue with the next repo. Track failed repos for Phase 6.

Use this single bash command (substitute the actual workspace path):

```bash
cd <workspace>/PlanningWorkspace && for dir in */; do
  echo "=== $dir ==="
  (cd "$dir" && git fetch origin 2>&1 && git reset --hard origin/main 2>&1) || echo "FAILED: $dir"
done
```

### Phase 2: Refresh `Jira Status:` on ticketed items

Phase 2 refreshes the **`Jira Status:`** field only. It NEVER touches the local **`Status:`** field.

1. Enumerate all `<workspace>\Active\*\` directories via Glob.
2. For each directory `<DIR>`:
   - If `<DIR>` matches the Jira-key regex (`^[A-Z]+-\d+$`), it is a **ticketed item**.
   - Otherwise, it is an **adhoc item** — skip.
3. For each ticketed item:
   - Read the issue file at `<workspace>\Active\<DIR>\<DIR>.md`.
   - Extract the current `Jira Status:` field, if present. If missing, treat the previous value as empty.
   - Call `mcp__plugin_atlassian_atlassian__getJiraIssue` with `cloudId: <CloudId>`, `issueIdOrKey: <DIR>`, `fields: ["status"]`.
   - Compare the new Jira status name to the local field (case-insensitive after trimming).
   - **If they match:** do nothing.
   - **If they differ (or the field is missing):**
     - Update or insert the `Jira Status:` line with the new value (preserve Jira's casing). If missing, insert directly below the `Jira:` URL line.
     - Insert at the top of Discussion (right after the `_(Newest first - format: [agent] message)_` line, before existing entries): `[sync] Jira status changed from <old-value> to <new-value>.` Use `(none)` for `<old-value>` if the field was missing.

To insert at the top of Discussion safely with the Edit tool, find the existing first non-blank line under the Discussion header and insert the new line above it.

### Phase 3: Sweep completed work

1. Re-enumerate all `Active\*\` directories (Phase 2 may have updated `Jira Status:` to a sweep-triggering value).
2. For each directory `<DIR>`:
   - Read `Active\<DIR>\<DIR>.md`.
   - Extract local `Status:` field. For ticketed items, also extract `Jira Status:` field.
   - Determine if it should be swept:
     - **Ticketed** (`<DIR>` matches Jira-key regex): sweep if **either** of the following (case-insensitive, trimmed):
       - local `Status:` is `Complete`
       - `Jira Status:` is `Complete` OR `Development Complete`
     - **Adhoc**: sweep if local `Status:` is `Complete` (case-insensitive).
3. For each item to sweep:
   ```bash
   mv "<workspace>/Active/<DIR>" "<workspace>/Complete/<DIR>"
   rm -rf "<workspace>/Complete/<DIR>/AgentWorkspace"
   ```
4. Track swept items for Phase 6.

### Phase 4: Dashboard

1. Re-enumerate `Active\*\` directories (after sweep).
2. For each directory, read its `<DIR>.md` file and extract: Title, Status, Tier, Mode, Jira (`Jira Status:` or `-`), Branch, Blocked, Next (`agent` if `go` line present, else `user`).
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

**Also write `<workspace>\dashboard.html`** (when `<N>` ≥ 1):

Single-file dark-themed HTML report with the same per-item data, rendered as a card/table action board. Color-code rows by `Status:`, show `Jira Status:` and `Branch` as clickable links where applicable, mark `Mode: direct` items with a distinct badge. Skip the HTML write if `<N>` is 0 — leave any prior `dashboard.html` in place.

### Phase 5: Suggest next work + Pull from Jira

Bucket every Active item into exactly one of these groups based on the issue file's local `Status:`:

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
```

Truncate title to 50 chars with `…` if longer. Omit empty buckets. If every Active item lands in **Tracking / parent**, print:

```
What to do next

Nothing in Active is waiting on you. Pull a new ticket with /jira-import.
```

**Pull from Jira (JQL):**

After the in-chat "What to do next" output:

1. Call `mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql` with:
   - `cloudId: <CloudId>`
   - `jql: <Discovery JQL>` (from `## Configuration` — typically `project in (CRD, CO) AND status != Complete AND assignee = currentUser()`)
   - `fields: ["summary", "status", "priority"]`
2. Build a "known keys" set from directory names in `Active\*\`, `Complete\*\`, and `Archive\*\` (case-insensitive comparison).
3. Filter the JQL result to keys NOT in the known set.
4. If any remain, print as a new bucket appended to the chat output:
   ```
   Pull from Jira (N):
   - <KEY> — <title> — <status> — /jira-import <KEY>
   - ...
   ```
   Sort by Priority (`Critical - Immediate` > `Highest` > `High` > `Medium` > `Low` > `Lowest`; missing → `Medium`), then by key ascending. Cap at 10; if more, append `… (<M> more in Jira)`.
5. **Include this bucket in the HTML dashboard** as a new section with a distinct accent color (suggest indigo/violet) and the same card structure. Each card's action is `/jira-import <KEY>` rendered as a copyable code badge.
6. On any JQL failure: skip silently — log nothing, don't break the rest of Phase 5.

**HTML dashboard (overwrites Phase 4's write):** the richer "action board" — bucket sections as colored cards (one per non-empty bucket), items grouped by action required, Jira / branch / PR links per item, summary stats up top. Same dark, card-based styling as Phase 4.

### Phase 6: Summary

Print:

```
Refreshed PlanningWorkspace (failures: <list, or "none">).
Sync updated <K> local files from Jira.
Swept <M> items to Complete:
- <key>
...
```

Omit a section if it has zero entries. The "What to do next" + "Pull from Jira" buckets from Phase 5 stand on their own.

## What `/status` does NOT do (use `/work` for these)

- Process `go`-flagged items.
- Dispatch dev subagents.
- Make outbound Jira transitions (e.g., to "In Development").
- Force-dispatch a named item.

## Notes

- `/status` is the network-aware command. Jira API failures in Phase 2 are recoverable: log to summary and continue. Phase 5's JQL failure is silently skipped.
- Only Phase 0's Atlassian probe hard-aborts on failure.
- The "Pull from Jira" surface lets you know about assignment changes outside the local workflow.

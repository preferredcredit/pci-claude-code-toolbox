---
name: work
description: Process go-flagged items in <workspace>\Active\, or work a single named item as a focused session. Local-first queue runner. For dashboard / sync / sweep / discovery, use /status.
argument-hint: "[key-or-hint]"
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Task, Skill, mcp__plugin_atlassian_atlassian__atlassianUserInfo, mcp__plugin_atlassian_atlassian__getJiraIssue, mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql, mcp__plugin_atlassian_atlassian__getTransitionsForJiraIssue, mcp__plugin_atlassian_atlassian__transitionJiraIssue
---

<!-- Distribution copy. Canonical source: the ClaudeWorkspace project skill of the same name; sync deliberately. Last sync: 2026-07-08. -->

In this skill, `<workspace>` refers to the Workspace path defined in the workspace `CLAUDE.md` `## Configuration` block. `<CloudId>` refers to the Jira CloudId from the same block. `<vpn-host>` refers to the On-prem VPN host from the same block.

# Work

Process `go`-flagged items in `<workspace>\Active\`. Lightweight, local-first — no Jira sync, no dashboard, no sweep. For the full discovery + housekeeping pass, use `/status`.

## Status fields

See the workflow doctrine's "Two-Field Status Model" for canonical definitions. Short version: `Status:` is the local workflow state — `/work` reads it but never writes it from Jira. `Jira Status:` is the verbatim Jira mirror, last written by `/status`; `/work` trusts it without re-pulling. Adhoc items only carry `Status:`.

## Configuration

Read from the workspace `CLAUDE.md` `## Configuration` block:
- `Workspace path` (referred to as `<workspace>`)
- `Jira CloudId` (referred to as `<CloudId>`)
- `On-prem VPN host` (referred to as `<vpn-host>`)

Hardcoded in this skill:
- Active folder: `<workspace>\Active\`
- Complete folder: `<workspace>\Complete\` (sweep happens in `/status`, not here)
- Jira key pattern (regex): `^[A-Z]+-\d+$`

## Modes

- **Full pass** (`/work`, no argument): autonomously process every `go`-flagged item — dispatch a subagent per item and report back. The `go` flag is the queue signal.
- **Targeted** (`/work <hint>`): work that one item as a focused session in the current chat. Naming the item is consent — it runs regardless of the `go` flag. On claim, **clear the `go` flag** so a concurrent full pass won't also pick it up; progression is then conversational (you steer between phases), not gated on `go`. Re-add `go` later to hand the item back to the autonomous queue.

There is no separate interactive command and no lock field — `go`-absence is the only coordination signal. A targeted session clears `go` to claim the item; full pass only ever touches `go`-flagged items.

## Argument resolution (targeted mode only)

Resolution is performed by `scan-queue.ps1 -Target <arg>` (Phase 0 + 1 below) — it matches the argument against the **top-level** `Active\` directory names using `Get-ChildItem -Directory` only, so it never recurses into `AgentWorkspace\` build output. Do **not** Glob for directories yourself; read the script's `resolution` block instead.

Resolution order (first match wins): exact directory match → upper-cased Jira-key match (`co-322` → `CO-322`) → case-insensitive substring. The outcome is reported as `resolution.status`:

- **`one`** — `resolution.resolvedTarget` is the directory; the script has already scanned it into `items` (a single entry). Set `<TARGET> = resolvedTarget` and proceed.
- **`multiple`** — print `Multiple matches for '<arg>': <resolution.candidates joined by ", ">. Be more specific.` and stop.
- **`zero`** — the argument has no folder and is not a Jira key (adhoc miss). Print `No active item matches '<arg>'. If it's a Jira key, check the key; for adhoc work create it first with /adhoc <slug> "<title>".` and stop.
- **`jirakey-miss`** — no local folder, but the argument is a Jira key (`resolution.importKey`). **Import it inline** (below), then process the freshly imported item. `/work <KEY>` is pull + triage in one command.

### Inline import (jirakey-miss)

Follow the import procedure in [references/issue-file-format.md](../../references/issue-file-format.md): fetch the issue with `mcp__plugin_atlassian_atlassian__getJiraIssue` and write `Active\<importKey>\<importKey>.md` per the template — local `Status: Planning`, empty `Tier:`, `Priority:` from the mapping, `Jira Status:` verbatim, `## Description` from the issue body. **Omit the `go` line** (a targeted claim leaves it off). Import needs Atlassian, not the VPN; it scaffolds the folder even when the VPN is down. If the fetch fails (issue not found, API error), print the failure and stop.

After writing the file, **re-run `scan-queue.ps1 -Target <importKey>`** — it now resolves to `one` with the item scanned — and continue from the VPN gate. The item is `Planning` with no `Tier:`, so Phase 3 runs triage immediately.

## Phase 0 + 1: Scan (run the script)

The VPN probe and the Active-queue scan are mechanical and deterministic, so they live in a re-runnable script that ships with this skill. Run it instead of doing these steps by hand.

**Run it with the Bash tool** — the command relies on the `${CLAUDE_PLUGIN_ROOT}` shell variable, which only expands in Bash (PowerShell would pass it literally and the path would break). The script path is already quoted and forward-slashed, so Bash handles it safely; quote the `-Workspace` value so its backslashes survive. Invoke:

```
powershell -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/skills/work/scan-queue.ps1" -Workspace "<workspace>" -VpnHost "<vpn-host>"
```

Targeted mode: pass the raw argument straight through — the script resolves it (see Argument resolution above):

```
powershell -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/skills/work/scan-queue.ps1" -Workspace "<workspace>" -VpnHost "<vpn-host>" -Target <arg>
```

The script emits one JSON object:

```json
{ "vpn": { "host": "...", "ok": true, "detail": "..." },
  "workspace": "...", "target": "...",
  "resolution": { "arg", "status", "resolvedTarget", "candidates", "importKey" },
  "items": [ { "dir", "goFlagged", "queued", "status", "priority", "tier", "ticketed" } ] }
```

`resolution` is `null` for a full pass (no `-Target`); in targeted mode `status` is `one` / `multiple` / `zero` / `jirakey-miss` (see Argument resolution). `items` is pre-sorted by Priority (`High` > `Medium` > `Low`; missing/unrecognized → `Medium`) then directory name; it holds the single resolved item on `one`, and is empty on `multiple` / `zero` / `jirakey-miss`. Each item's `queued` is `true` when it is `go`-flagged.

**Re-runnable:** the script never modifies files and never dispatches. Run it again any time to re-check VPN + queue state (e.g. after connecting to VPN, or after editing a `go` flag).

### Act on the JSON

0. **Resolution (targeted mode only).** Act on `resolution.status` **before** the VPN gate (full pass: `resolution` is `null` — skip this step):
   - **`multiple`** / **`zero`** — print the message from Argument resolution and stop.
   - **`jirakey-miss`** — import the ticket inline (see Argument resolution → Inline import). This scaffolds `Active\<importKey>\` even when the VPN is down. Then re-run `scan-queue.ps1 -Target <importKey>` and continue from step 1 with the now-`one` result.
   - **`one`** — set `<TARGET> = resolution.resolvedTarget` and continue.

1. **VPN gate.** If `vpn.ok` is `false`, print exactly and stop:
   ```
   VPN check failed — <vpn-host> not resolving. Connect to VPN and re-run /work.
   ```
   (Triage, planning, and all git work need the VPN. A `jirakey-miss` import in step 0 already scaffolded the folder, so re-run `/work <KEY>` once the VPN is up to triage it. If you also need a dashboard / Jira sync / sweep, run `/status` after VPN is restored.)

2. **Build the queue.**
   - **Full pass:** the queue is every item with `queued == true`, in the order returned (already sorted).
   - **Targeted:** the queue is `[<TARGET>]` regardless of its `go` state. **Claim it:** if the item still has a `go` line, remove it now so a concurrent full pass won't also grab it. This is a focused session — you'll work this one item through its phases in the current chat.

3. **Empty queue (full pass only).** If no item has `queued == true`, print exactly and exit without further output:
   ```
   Nothing queued. Run /status to check state.
   ```

The queue is already sorted by the script (Priority then directory name), so there is no separate sort step. Targeted mode has only one item.

## Phase 3: Process each item

**Always pull latest before planning or working — no exceptions.** Before dispatching ANY subagent (planning OR development) for a queued item, refresh the repo it will touch to `origin/main`:

- **Planning dispatch** (Triage / Standard / Full): the planning subagent reads from `PlanningWorkspace`, which `/work` does not sweep wholesale. Refresh just the repo(s) relevant to this item before designing:
  ```
  git -C <workspace>\PlanningWorkspace\<repo> fetch origin
  git -C <workspace>\PlanningWorkspace\<repo> reset --hard origin/main
  ```
  Designing against a stale tree has already caused wasted work on already-merged fixes.
- **Development dispatch:** if `AgentWorkspace\` already exists, pull `fb/<KEY>` and merge `origin/main` before resuming (`git fetch origin` then `git merge origin/main`). A freshly created shallow clone is already current.

This rule is not satisfied by "the clone looks recent" — resumed branches and shared planning trees drift. Refresh, then dispatch.

**Execution mode (full pass vs targeted).** The dispatch table below decides *what phase* to run by `Status:`/`Tier:`. *How* it runs depends on the mode:

- **Full pass** — autonomous. Execute via `superpowers:executing-plans`. Human review happens between runs through the `go` flag: a subagent that finishes planning sets the next `Status:` and removes `go`; you re-add `go` to continue. The triage `< 80` gate removes `go` and stops.
- **Targeted** — focused session in this chat. Execute via `superpowers:subagent-driven-development` (review between tasks, in-chat). Spec review, plan review, and the triage `< 80` confirm are **chat turns**, not `go` edits — you already cleared `go` on claim and you never re-add it to progress; you just continue the conversation. See [references/triage.md](../../references/triage.md) for the per-mode confidence behavior.

For each queued item in order:

1. **Pre-dispatch: copy go-line comments.** If the user added comments after the `go` line (text between `go` and `# <title>`), copy them to Discussion as `[user]` entry, then remove that text from the file. (Targeted mode without a `go` line: no-op.)

2. **Determine action by `Status:` and `Tier:`:**

   | Local `Status:` | `Tier:` set? | Dispatch |
   |---|---|---|
   | `Planning` | no | Run **Triage** per [references/triage.md](../../references/triage.md): dispatch the `architect` agent (Task tool, `subagent_type: architect`) with the documented triage prompt, parse its `TIER` / `CONFIDENCE` / `RATIONALE` / `OPEN_QUESTIONS`, write `Tier:`, and log `[Triage] Tier=<tier> (confidence <n>): <rationale>`. **Confidence ≥ 80** → auto-advance through the tier's phases this same run (see *Auto-advance* note below). **Confidence < 80** → *full pass:* remove `go` and stop (user reviews open questions, re-adds `go`); *targeted:* show the confirm prompt as a chat turn and continue on the reply. Per `triage.md`. |
   | `Planning` | `Trivial` | Skip Spec and Plan phases. Set `Status: Development`, clone AgentWorkspace, create branch, attempt Jira transition (best-effort). Dispatch a subagent running `superpowers:executing-plans` with the issue description as the implicit plan (no plan.md). |
   | `Planning` | `Standard` | Dispatch a subagent running `superpowers:writing-plans` to produce `Active\<DIR>\plan.md`. On return, subagent sets `Status: Plan Review`, removes `go`. User reviews plan.md and re-adds `go` to approve. |
   | `Planning` | `Full` | Dispatch a subagent running `superpowers:brainstorming` to produce `Active\<DIR>\spec.md` **only** — no plan yet. On return, subagent sets `Status: Spec Review`, removes `go`. User reviews (and optionally edits) spec.md and re-adds `go` to approve. **The spec gate is never skipped**, regardless of triage confidence — Full tier exists because requirements are ambiguous, so the spec always gets human eyes before design proceeds. |
   | `Spec Review` | — | Spec was written and is now approved (the user re-added `go`; targeted mode: approval was a chat turn). Dispatch a subagent running `superpowers:writing-plans` with `spec.md` as input to produce `Active\<DIR>\plan.md`. Then check the `[Triage]` Discussion entry: if it records confidence ≥ 80, continue straight through Development → Review → Wrap in the same run (spec approval + high-confidence triage stand in for plan review); otherwise set `Status: Plan Review`, remove `go`. |
   | `Plan Review` | — | Plan was written and is now approved (the user re-added `go`). Set `Status: Development`, then dispatch exactly as the `Development` row below (clone AgentWorkspace, create branch, attempt Jira transition, run `superpowers:executing-plans` with `plan.md`). This is the routing that turns plan approval into execution — do **not** treat `Plan Review` as non-actionable. |
   | `Development` (or `In Development`) | — | Clone AgentWorkspace if missing, create branch if missing, attempt Jira transition (best-effort), dispatch a subagent running `superpowers:executing-plans` with `plan.md` as input. |
   | `Code Review` | — | **A `go` flag means "work this" — never skip a `go`-flagged item on account of its status.** Read the issue file (Discussion, `PR:`, `Branch:`). If Discussion or the PR records reviewer feedback / requested changes, dispatch a development subagent to address them (resume the branch via the `Development` row). If the PR is merely awaiting human review with nothing outstanding, report that in the summary and ask what's needed. |
   | `Development Complete` / `QA` / `QA Complete` / `Deployed` | — | **Don't skip — read and decide.** Read the issue file and do whatever follow-up work it describes (dispatch as `Development` if there's code to write); if nothing is outstanding, report the current state in the summary. |
   | `Complete` | — | **Read the file.** If the work is genuinely done, don't dispatch — report `[<KEY>] Already Complete — run /status to sweep.` (Sweeping `Active\`→`Complete\` stays a `/status` job.) If the file describes new work, treat it as `Development`. |

   **Auto-advance (high-confidence triage).** When triage returns confidence ≥ 80, the same `/work` run continues without stopping — but how far depends on tier. **Trivial:** straight to Execute → Review → Wrap. **Standard:** the plan-review pause is skipped (the high-confidence triage stands in for it); Plan → Execute → Review → Wrap, ending at `Status: Code Review`. **Full:** auto-advance carries the run only as far as the spec — write `spec.md`, set `Status: Spec Review`, remove `go`, stop. **The spec gate is a hard stop on Full tier; no confidence score crosses it.** After the user approves the spec, the `Spec Review` row resumes and the recorded confidence decides whether plan review is also skipped. The per-tier rows above (`Planning` + `Trivial`/`Standard`/`Full`) also describe the **resumed** path used when a `Tier:` is already set with no fresh triage — e.g. the user set it manually, or a low-confidence (< 80) triage wrote it then stopped and was re-queued. In **full pass** that resumed path keeps the `go`-gated reviews; in a **targeted** session spec/plan review are chat turns instead. Full semantics in [references/triage.md](../../references/triage.md).

3. **Outbound Jira transition (ticketed items only, when dispatching a development subagent — best-effort):**
   - Check the local `Jira Status:` field (last written by `/status`). If already `In Development` (case-insensitive), skip the transition silently.
   - Otherwise, call `mcp__plugin_atlassian_atlassian__getTransitionsForJiraIssue` with `cloudId: <CloudId>`, `issueIdOrKey: <KEY>`.
   - Find a transition whose target name is `In Development` (case-insensitive).
   - If found, call `mcp__plugin_atlassian_atlassian__transitionJiraIssue` with the transition ID.
   - On any error (network, auth, transition not found): log to summary as `[<KEY>] Jira transition skipped: <reason>.` Continue with dispatch — Atlassian failures do NOT block dev work.
   - On success, optimistically update the local `Jira Status:` line to `In Development`.

4. After dispatch, the subagent is responsible for running `engineer-toolkit:author-review` as the final pre-PR step and then completing the Wrap contract in [references/workflow-phases.md](../../references/workflow-phases.md) (Phase 6): write the PR body to `Active\<DIR>\pr-description.md` (**under 4000 characters** — ADO on-prem limit; never call `gh pr create`), set `Status: Code Review` + `PR:` on the issue file, and log the Discussion entry. **Include that reference path in every development dispatch prompt** so the subagent reads it.

Subagents launch concurrently.

## Phase 4: Summary

After all subagents return, print:

```
Done. Processed <N> items:
- <key>: <action taken, new local status>
...
```

Followed by this optional section, omitted if empty:

```
Warnings:
- <any warning text>
```

In targeted mode, the summary covers only `<TARGET>`.

## What `/work` does NOT do (use `/status` for these)

- Refresh **all** of `PlanningWorkspace` (the workspace-wide `git reset --hard` sweep). `/work` does a *targeted* single-repo refresh per queued item before planning (see Phase 3), but the full sweep stays in `/status`.
- Sync `Jira Status:` field on local files.
- Sweep `Active\` items to `Complete\`.
- Print the dashboard or write `dashboard.html`.
- Suggest next work or pull unimported Jira tickets via JQL.

If you've been working for a while and want to see the bigger picture, run `/status` first, then come back to `/work`.

## Notes

- Phase 0 + 1 run via `scan-queue.ps1` (VPN probe + queue scan). Re-run it any time to re-check state without dispatching.
- The VPN probe is the only hard prerequisite. Atlassian failures during dispatch are tolerated and logged.
- `/work` is offline-tolerant when only Atlassian is unreachable (the on-prem git server is still required for repo operations). Exception: targeted `/work <KEY>` on a not-yet-local key imports the ticket inline (per `references/issue-file-format.md`) — pull + triage in one command — and that single path needs Atlassian.
- All Atlassian MCP tools remain available in `allowed-tools` for ad-hoc lookups or one-off debugging; `getJiraIssue` is the one the inline-import path depends on.
- In targeted mode, the scan script (`scan-queue.ps1 -Target <arg>`) resolves the argument and scans in one pass; act on its `resolution` block (Argument resolution above).

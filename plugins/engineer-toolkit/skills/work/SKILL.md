---
name: work
description: Process go-flagged items in <workspace>\Active\, or force-dispatch a single named item. Local-first queue runner. For dashboard / sync / sweep / discovery, use /status.
argument-hint: "[key-or-hint]"
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Task, Skill, mcp__plugin_atlassian_atlassian__atlassianUserInfo, mcp__plugin_atlassian_atlassian__getJiraIssue, mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql, mcp__plugin_atlassian_atlassian__getTransitionsForJiraIssue, mcp__plugin_atlassian_atlassian__transitionJiraIssue
---

In this skill, `<workspace>` refers to the Workspace path defined in the workspace `CLAUDE.md` `## Configuration` block. `<CloudId>` refers to the Jira CloudId from the same Configuration block. `<vpn-host>` refers to the On-prem VPN host from the same block.

# Work

Process `go`-flagged items in `<workspace>\Active\`. Lightweight, local-first — no Jira sync, no dashboard, no sweep. For the full discovery + housekeeping pass, use `/status`.

## Status fields

See workflow.md > "Two-Field Status Model" for canonical definitions. Short version: `Status:` is the local workflow state — `/work` reads it but never writes it. `Jira Status:` is the verbatim Jira mirror, last written by `/status`; `/work` trusts it without re-pulling. Adhoc items only carry `Status:`.

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

See [references/argument-resolution.md](../../references/argument-resolution.md). Apply the algorithm against `<workspace>\Active\` with the **auto-scaffold fallback** variant and store the resolved name as `<TARGET>`. A Jira-key argument not yet in `Active\` is imported on the fly (via `/jira-import` through the Skill tool), then targeted — so `/work <KEY>` pulls a ticket and runs triage on it in one command. Resolution runs BEFORE the scan so argument errors don't waste a probe; the on-the-fly import needs Atlassian (Jira Cloud), not the VPN.

## Phase 0 + 1: Scan (run the script)

`/work` does NOT call Atlassian as a gate. Jira transitions during dispatch are best-effort. The only network dep that gates dispatch is the on-prem git server (needed for `git clone` / `git push`). Atlassian Cloud is public-internet and answers regardless of VPN state, so it's not a reliable VPN signal — `<vpn-host>` is.

The VPN probe and the Active-queue scan are mechanical and deterministic, so they live in a re-runnable script. Run it instead of doing these steps by hand, substituting `<workspace>` and `<vpn-host>` from `## Configuration`.

**Run it with the Bash tool** — the command relies on the `${CLAUDE_PLUGIN_ROOT}` shell variable, which only expands in Bash (PowerShell would pass it literally and the path would break). The path is already quoted and forward-slashed, so Bash handles it safely:

```
powershell -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/skills/work/scan-queue.ps1" -Workspace "<workspace>" -VpnHost "<vpn-host>"
```

Targeted mode: after resolving `<arg>` to a single `<TARGET>` (see Argument resolution above), add `-Target <TARGET>`.

The script emits one JSON object:

```json
{ "vpn": { "host": "...", "ok": true, "detail": "..." },
  "workspace": "...", "target": "...",
  "items": [ { "dir", "goFlagged", "queued", "status", "priority", "tier", "ticketed" } ] }
```

`items` is pre-sorted by Priority (`High` > `Medium` > `Low`; missing/unrecognized → `Medium`) then directory name. Each item's `queued` is `true` when it is `go`-flagged.

**Re-runnable:** the script never modifies files and never dispatches. Run it again any time to re-check VPN + queue state (e.g. after connecting to VPN, or after editing a `go` flag).

### Act on the JSON

1. **VPN gate.** If `vpn.ok` is `false`, print exactly (substituting the actual host) and stop:
   ```
   VPN check failed — <vpn-host> not resolving. Connect to VPN and re-run /work.
   ```
   (If you also need a dashboard / Jira sync / sweep, run `/status` after VPN is restored.)

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

- **Planning dispatch** (Triage / Standard / Full): the planning subagent reads from `<workspace>\PlanningWorkspace`, which `/work` does not sweep wholesale. Refresh just the repo(s) relevant to this item before designing:
  ```
  git -C "<workspace>\PlanningWorkspace\<repo>" fetch origin
  git -C "<workspace>\PlanningWorkspace\<repo>" reset --hard origin/main
  ```
  Designing against a stale tree has already caused wasted work on already-merged fixes.
- **Development dispatch:** if `AgentWorkspace\` already exists, pull `fb/<KEY>` and merge `origin/main` before resuming (`git fetch origin` then `git merge origin/main`). A freshly created shallow clone is already current.

This rule is not satisfied by "the clone looks recent" — resumed branches and shared planning trees drift. Refresh, then dispatch.

**Execution mode (full pass vs targeted).** The dispatch table below decides *what phase* to run by `Status:`/`Tier:`. *How* it runs depends on the mode:

- **Full pass** — autonomous. Execute via `superpowers:executing-plans`. Human review happens between runs through the `go` flag: a subagent that finishes planning sets the next `Status:` and removes `go`; the user re-adds `go` to continue. The triage `< 80` gate removes `go` and stops.
- **Targeted** — focused session in this chat. Execute via `superpowers:subagent-driven-development` (review between tasks, in-chat). Plan review and the triage `< 80` confirm are **chat turns**, not `go` edits — `go` was already cleared on claim and is never re-added to progress; just continue the conversation. See [references/triage.md](../../references/triage.md) for the per-mode confidence behavior.

For each queued item in order:

1. **Pre-dispatch: copy go-line comments.** If the user added comments after the `go` line (text between `go` and `# <title>`), copy them to Discussion as `[user]` entry, then remove that text from the file. (Targeted mode without a `go` line: no-op.)

2. **Determine action by `Status:` and `Tier:`:**

   | Local `Status:` | `Tier:` set? | Dispatch |
   |---|---|---|
   | `Planning` | no | Run **Triage** per [references/triage.md](../../references/triage.md): dispatch the `architect` agent (Task tool, `subagent_type: architect`) with the documented triage prompt, parse its `TIER` / `CONFIDENCE` / `RATIONALE` / `OPEN_QUESTIONS`, write `Tier:`, and log `[Triage] Tier=<tier> (confidence <n>): <rationale>`. **Confidence ≥ 80** → auto-advance through the tier's phases this same run (see *Auto-advance* note below). **Confidence < 80** → *full pass:* remove `go` and stop (user reviews open questions, re-adds `go`); *targeted:* show the confirm prompt as a chat turn and continue on the reply. Per [references/triage.md](../../references/triage.md). |
   | `Planning` | `Trivial` | Skip Spec and Plan phases. Set `Status: Development`, clone AgentWorkspace, create branch, attempt Jira transition (best-effort). Dispatch a subagent running `superpowers:executing-plans` with the issue description as the implicit plan (no plan.md). |
   | `Planning` | `Standard` | Dispatch a subagent running `superpowers:writing-plans` to produce `Active\<DIR>\plan.md`. On return, subagent sets `Status: Plan Review`, removes `go`. User reviews plan.md and re-adds `go` to approve. |
   | `Planning` | `Full` | Dispatch a subagent running `superpowers:brainstorming` to produce `Active\<DIR>\spec.md`, then `superpowers:writing-plans` to produce `Active\<DIR>\plan.md`. On return, subagent sets `Status: Plan Review`, removes `go`. |
   | `Plan Review` | — | Plan was written and is now approved (the user re-added `go`). Set `Status: Development`, then dispatch exactly as the `Development` row below (clone AgentWorkspace, create branch, attempt Jira transition, run `superpowers:executing-plans` with `plan.md`). This is the routing that turns plan approval into execution — do **not** treat `Plan Review` as non-actionable. |
   | `Development` (or `In Development`) | — | Clone AgentWorkspace if missing, create branch if missing, attempt Jira transition (best-effort), dispatch a subagent running `superpowers:executing-plans` with `plan.md` as input. |
   | `Code Review` / `Development Complete` / `QA` / `QA Complete` / `Deployed` | — | **A `go` flag is always the work signal — never skip a `go`-flagged item on account of its status** (see the *Local `Status:` values* table in workflow.md). Read the issue file (Discussion, `PR:`, `Branch:`): if it records reviewer feedback / requested changes, dispatch a development subagent to address them (resume the branch via the `Development` row); if nothing is outstanding, report the current state in the summary and ask what's needed. |
   | `Complete` | — | Read the file. If the work is genuinely done, don't dispatch — report `[<KEY>] Already Complete — run /status to sweep.` (Sweeping `Active\`→`Complete\` stays a `/status` job.) If the file describes new work, treat it as `Development`. |

   **Auto-advance (high-confidence triage).** When triage returns confidence ≥ 80, the same `/work` run continues straight through the tier's phases without stopping — for Standard/Full the plan-review pause is skipped (the high-confidence triage stands in for it), and the run proceeds Spec (Full only) → Plan → Execute → Review → Wrap, ending at `Status: Code Review`. The per-tier rows above (`Planning` + `Trivial`/`Standard`/`Full`) describe the **resumed** path used when a `Tier:` is already set with no fresh triage — e.g. the user set it manually, or a low-confidence (< 80) triage wrote it then stopped and was re-queued. In **full pass** that resumed path keeps the `go`-gated plan review (Standard/Full produce `plan.md`, set `Status: Plan Review`, remove `go`); in a **targeted** session plan review is a chat turn instead. Full semantics in [references/triage.md](../../references/triage.md).

3. **Outbound Jira transition (ticketed items only, when dispatching a development subagent — best-effort):**
   - Check the local `Jira Status:` field (last written by `/status`). If already `In Development` (case-insensitive), skip the transition silently.
   - Otherwise, call `mcp__plugin_atlassian_atlassian__getTransitionsForJiraIssue` with `cloudId: <CloudId>`, `issueIdOrKey: <KEY>`.
   - Find a transition whose target name is `In Development` (case-insensitive).
   - If found, call `mcp__plugin_atlassian_atlassian__transitionJiraIssue` with the transition ID.
   - On any error (network, auth, transition not found): log to summary as `[<KEY>] Jira transition skipped: <reason>.` Continue with dispatch — Atlassian failures do NOT block dev work.
   - On success, optimistically update the local `Jira Status:` line to `In Development`.

4. After dispatch, the subagent is responsible for running `engineer-toolkit:author-review` as the final pre-PR step and producing the PR description. **PR body must be under 4000 characters** (Azure DevOps on-prem limit). If the author-review summary is longer, trim before paste: preserve commit list, build line, and architectural decisions; drop verbose explanations and review logs.

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
- The on-prem VPN probe is the only hard prerequisite. Atlassian failures during dispatch are tolerated and logged.
- `/work` is offline-tolerant when only Atlassian is unreachable (on-prem git still required for repo operations). Exception: targeted `/work <KEY>` on a not-yet-local key auto-imports the ticket (via `/jira-import`) — pull + triage in one command — and that single path needs Atlassian.
- All Atlassian MCP tools remain available in `allowed-tools` for ad-hoc lookups or one-off debugging, even though the default flow doesn't use the read tools.
- In targeted mode, argument resolution runs BEFORE the scan — argument errors don't waste a probe.

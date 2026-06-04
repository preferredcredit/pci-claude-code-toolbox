---
name: work
description: Process go-flagged items in <workspace>\Active\, or force-dispatch a single named item. Local-first queue runner. For dashboard / sync / sweep / discovery, use /status.
argument-hint: "[key-or-hint]"
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Task, mcp__plugin_atlassian_atlassian__atlassianUserInfo, mcp__plugin_atlassian_atlassian__getJiraIssue, mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql, mcp__plugin_atlassian_atlassian__getTransitionsForJiraIssue, mcp__plugin_atlassian_atlassian__transitionJiraIssue
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

- **Full pass** (`/work`, no argument): process every `go`-flagged item.
- **Targeted** (`/work <hint>`): resolve hint to a single item and force-dispatch regardless of `go` flag (naming the item is consent).

## Argument resolution (targeted mode only)

See [references/argument-resolution.md](../../references/argument-resolution.md). Apply the standard algorithm against `<workspace>\Active\` and store the resolved name as `<TARGET>`. No variant applies — `/work` uses the standard 3-step search and standard outcomes. Resolution runs BEFORE the scan so argument errors don't waste a probe.

## Phase 0 + 1: Scan (run the script)

`/work` does NOT call Atlassian as a gate. Jira transitions during dispatch are best-effort. The only network dep that gates dispatch is the on-prem git server (needed for `git clone` / `git push`). Atlassian Cloud is public-internet and answers regardless of VPN state, so it's not a reliable VPN signal — `<vpn-host>` is.

The VPN probe and the Active-queue scan are mechanical and deterministic, so they live in a re-runnable script. Run it instead of doing these steps by hand, substituting `<workspace>` and `<vpn-host>` from `## Configuration`:

```
powershell -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/skills/work/scan-queue.ps1" -Workspace "<workspace>" -VpnHost "<vpn-host>"
```

Targeted mode: after resolving `<arg>` to a single `<TARGET>` (see Argument resolution above), add `-Target <TARGET>`.

The script emits one JSON object:

```json
{ "vpn": { "host": "...", "ok": true, "detail": "..." },
  "workspace": "...", "target": "...",
  "items": [ { "dir", "goFlagged", "modeDirect", "queued", "status", "priority", "tier", "ticketed" } ] }
```

`items` is pre-sorted by Priority (`High` > `Medium` > `Low`; missing/unrecognized → `Medium`) then directory name. Each item's `queued` is `true` when it is `go`-flagged AND not `Mode: direct`.

**Re-runnable:** the script never modifies files and never dispatches. Run it again any time to re-check VPN + queue state (e.g. after connecting to VPN, or after editing a `go` flag).

### Act on the JSON

1. **VPN gate.** If `vpn.ok` is `false`, print exactly (substituting the actual host) and stop:
   ```
   VPN check failed — <vpn-host> not resolving. Connect to VPN and re-run /work.
   ```
   (If you also need a dashboard / Jira sync / sweep, run `/status` after VPN is restored.)

2. **Build the queue.**
   - **Full pass:** the queue is every item with `queued == true`, in the order returned (already sorted). Items that are `goFlagged == true` AND `modeDirect == true` are skipped — collect their `dir`s for the `Skipped (Mode: direct): ...` summary line.
   - **Targeted:** the queue is `[<TARGET>]`. If that item has `modeDirect == true`, abort with:
     ```
     <TARGET> is Mode: direct. Use /direct <TARGET> or remove the lock first.
     ```
     Do not dispatch.

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

For each queued item in order:

1. **Pre-dispatch: copy go-line comments.** If the user added comments after the `go` line (text between `go` and `# <title>`), copy them to Discussion as `[user]` entry, then remove that text from the file. (Targeted mode without a `go` line: no-op.)

2. **Determine action by `Status:` and `Tier:`:**

   | Local `Status:` | `Tier:` set? | Dispatch |
   |---|---|---|
   | `Planning` | no | Run **Triage**: dispatch a subagent that reads the issue file plus 1-2 relevant code files referenced in the description, proposes Trivial / Standard / Full with one-sentence rationale, writes `Tier:` field, logs `[Triage] Tier=<tier>: <rationale>` in Discussion, removes `go` line, and exits. User reviews and re-adds `go`. |
   | `Planning` | `Trivial` | Skip Spec and Plan phases. Set `Status: Development`, clone AgentWorkspace, create branch, attempt Jira transition (best-effort). Dispatch a subagent running `superpowers:executing-plans` with the issue description as the implicit plan (no plan.md). |
   | `Planning` | `Standard` | Dispatch a subagent running `superpowers:writing-plans` to produce `Active\<DIR>\plan.md`. On return, subagent sets `Status: Code Review`, removes `go`. User reviews plan.md and re-adds `go` to proceed to Development. |
   | `Planning` | `Full` | Dispatch a subagent running `superpowers:brainstorming` to produce `Active\<DIR>\spec.md`, then `superpowers:writing-plans` to produce `Active\<DIR>\plan.md`. On return, subagent sets `Status: Code Review`, removes `go`. |
   | `Development` (or `In Development`) | — | Clone AgentWorkspace if missing, create branch if missing, attempt Jira transition (best-effort), dispatch a subagent running `superpowers:executing-plans` with `plan.md` as input. |
   | `Code Review` / `Development Complete` / `QA` / `QA Complete` / `Complete` / `Deployed` | — | Skip with warning logged for the summary: `[<KEY>] Skipped — Status=<status> is not actionable by /work.` |

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

Followed by these optional sections, each omitted if empty:

```
Skipped (Mode: direct): <key>, <key>

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
- `/work` is offline-tolerant when only Atlassian is unreachable (on-prem git still required for repo operations).
- All Atlassian MCP tools remain available in `allowed-tools` for ad-hoc lookups or one-off debugging, even though the default flow doesn't use the read tools.
- In targeted mode, argument resolution runs BEFORE the scan — argument errors don't waste a probe.

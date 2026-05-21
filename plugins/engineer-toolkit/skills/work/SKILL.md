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

## Two-field status model

Issue files carry two distinct fields:

- **`Status:`** — local workflow state. `/work` reads it to decide what to dispatch; `/work` never overwrites it.
- **`Jira Status:`** — verbatim Jira ticket status, last written by `/status`. `/work` treats this as read-only and trusts it (does not re-pull during a run). Used to decide whether to issue an "In Development" transition during dispatch.

Adhoc items (kebab-case directories, no `Jira:` line) only have `Status:`.

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

When an argument is provided, resolve it to a single `Active\<DIR>\` BEFORE running the VPN probe. Resolution order (first match wins):

1. **Exact directory match** (case-insensitive): use Glob on `<workspace>\Active\<arg>\`.
2. **Upper-cased Jira-key match**: if the argument matches `^[a-zA-Z]+-\d+$`, upper-case it and try as an exact match (`co-322` → `CO-322`).
3. **Substring match**: case-insensitive substring against all `Active\` directory names.

Outcomes:

- **Zero matches** — print `No active item matches '<arg>'.` and stop.
- **Multiple matches** — print `Multiple matches for '<arg>': <comma-separated list>. Be more specific.` and stop.
- **One match** — store the resolved directory name as `<TARGET>` and proceed.

## Phase 0: On-prem VPN probe

`/work` does NOT call Atlassian as a gate. Jira transitions during dispatch are best-effort. The only network dep that gates dispatch is the on-prem git server (needed for `git clone` / `git push`). Atlassian Cloud is public-internet and answers regardless of VPN state, so it's not a reliable VPN signal — `<vpn-host>` is.

Run via Bash:
```bash
nslookup <vpn-host> 2>&1 | head -5
```
(substituting the actual value from `## Configuration`).

If the output contains `can't find`, `NXDOMAIN`, `server can't find`, or the command exits non-zero, the on-prem DNS isn't resolving. Print exactly:

```
VPN check failed — <vpn-host> not resolving. Connect to VPN and re-run /work.
```

(substituting the actual host) and stop.

If you also need a dashboard / Jira sync / sweep, run `/status` after VPN is restored.

## Phase 1: Build queue

**Full pass:**
- Enumerate all `<workspace>\Active\*\` directories via Glob.
- For each, read the issue file. Include in queue if:
  - The file's first non-empty line starts with `go` (case-insensitive), AND
  - The file does NOT contain a `Mode: direct` line.
- Items with `Mode: direct` and a `go` line are skipped (log to summary as `Skipped (Mode: direct): ...`).

**Targeted:**
- Queue is `[<TARGET>]`.
- If `<TARGET>` has `Mode: direct`, abort with:
  ```
  <TARGET> is Mode: direct. Use /direct <TARGET> or remove the lock first.
  ```
  Do not dispatch.

**Empty queue (full pass only):**
- If the queue is empty, print exactly:
  ```
  Nothing queued. Run /status to check state.
  ```
  and exit without further output.

## Phase 2: Sort

Sort the queue by Priority field (`High` > `Medium` > `Low`; missing or unrecognized → treat as `Medium`), then by directory name ascending. Targeted mode has only one item, so sorting is trivial.

## Phase 3: Process each item

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

- Refresh `PlanningWorkspace`.
- Sync `Jira Status:` field on local files.
- Sweep `Active\` items to `Complete\`.
- Print the dashboard or write `dashboard.html`.
- Suggest next work or pull unimported Jira tickets via JQL.

If you've been working for a while and want to see the bigger picture, run `/status` first, then come back to `/work`.

## Notes

- The on-prem VPN probe is the only hard prerequisite. Atlassian failures during dispatch are tolerated and logged.
- `/work` is offline-tolerant when only Atlassian is unreachable (on-prem git still required for repo operations).
- All Atlassian MCP tools remain available in `allowed-tools` for ad-hoc lookups or one-off debugging, even though the default flow doesn't use the read tools.
- In targeted mode, argument resolution runs BEFORE Phase 0 — argument errors don't waste a VPN probe.

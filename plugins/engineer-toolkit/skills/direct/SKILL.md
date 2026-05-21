---
name: direct
description: Open a direct-mode session on a single issue in the current chat. Workflow runs end-to-end interactively instead of via dispatched subagents.
argument-hint: <KEY-or-slug>
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task, Skill, mcp__plugin_atlassian_atlassian__atlassianUserInfo, mcp__plugin_atlassian_atlassian__getJiraIssue, mcp__plugin_atlassian_atlassian__getTransitionsForJiraIssue, mcp__plugin_atlassian_atlassian__transitionJiraIssue
---

In this skill, `<workspace>` refers to the Workspace path defined in the workspace `CLAUDE.md` `## Configuration` block. `<CloudId>` refers to the Jira CloudId from the same Configuration block. `<vpn-host>` refers to the On-prem VPN host from the same block.

# Direct

Open a direct-mode session for a single ticketed or adhoc issue inside the current chat. The workflow runs through every phase (Setup → Triage → Spec → Plan → Execute → Review → Wrap) interactively. No subagent dispatch; the chat is the runtime.

## Configuration

Read from the workspace `CLAUDE.md` `## Configuration` table:
- `Jira CloudId` (referred to as `<CloudId>` below)

Hardcoded in this skill:
- Active folder: `<workspace>\Active\`
- Jira key pattern (regex): `^[A-Z]+-\d+$`

## Argument

`/direct <KEY-or-slug>`

If the argument is missing, respond: `Usage: /direct <KEY-or-slug>` and stop.

## Resolution

Resolve `<arg>` to a target directory:

1. **Exact match:** if `Active\<arg>\` exists, use it as the target.
2. **Upper-cased Jira-key match:** if `<arg>` matches `^[a-zA-Z]+-\d+$` and the upper-cased form exists in `Active\`, use it.
3. **Substring match:** case-insensitive substring against `Active\` directory names.
   - Zero matches: see step 4.
   - One match: use it.
   - Multiple matches: print `Multiple matches for '<arg>': <comma-separated list>. Be more specific.` and stop.

4. **Auto-scaffold path (zero matches above):**
   - If `<arg>` upper-cased matches `^[A-Z]+-\d+$` (looks like a Jira key): run `/jira-import <UPPER-ARG>`. After import succeeds, set the target to the newly created `Active\<UPPER-ARG>\` directory. If import fails (Jira API error, issue not found), print the failure and stop.
   - Otherwise (looks like an adhoc slug): print `Adhoc slug '<arg>' doesn't exist. Create it first with /adhoc <slug> "<title>".` and stop.

Store the resolved directory name as `<TARGET>`.

## Phase 0: VPN check (ticketed items only)

Atlassian Cloud is public-internet — it answers with or without VPN. The on-prem host (`<vpn-host>`) is the actual VPN signal. Both probes must pass.

**Probe 1 — Atlassian reachability:** call `mcp__plugin_atlassian_atlassian__atlassianUserInfo`. On failure, print:
```
VPN check failed — Atlassian API unreachable. Connect to VPN and re-run /direct.
```
and stop.

**Probe 2 — On-prem reachability:** run `nslookup <vpn-host> 2>&1 | head -5`. If output contains `can't find`, `NXDOMAIN`, `server can't find`, or the command exits non-zero, print:
```
VPN check failed — <vpn-host> not resolving. Connect to VPN and re-run /direct.
```
(substituting the actual host) and stop.

Only proceed when both probes pass.

For adhoc items, skip VPN check entirely (no Jira / on-prem calls needed at this stage).

## Phase 0b: Acquire mode lock

Read `Active\<TARGET>\<TARGET>.md`. Then:

1. **Check for conflicting lock:** if the file already has `Mode: direct`, this might be a resumed session in the same chat. Allow re-entry silently. (We don't try to detect "different chat" — there's no reliable session marker.)
2. **Insert `Mode: direct` line** after the `Status:` line if not present, or update the existing `Mode:` line. Use the Edit tool.
3. **Remove `go` line** if the file's first non-empty line starts with `go` (case-insensitive).
4. **Add Discussion entry:** insert `[orchestrator] Direct session started.` as the newest line in the Discussion section (right after `_(Newest first - format: [agent] message)_`).

## Phase 0c: Refresh Jira (ticketed only)

`<CloudId>` below is the Jira CloudId from `## Configuration` in CLAUDE.md.

For ticketed items:
- Call `mcp__plugin_atlassian_atlassian__getJiraIssue` with `cloudId: <CloudId>`, `issueIdOrKey: <TARGET>`, `fields: ["status"]`.
- Compare the returned status name (case-insensitive after trimming) to the local `Jira Status:` line. If they match, do nothing.
- If they differ (or the local line is missing):
  - Update or insert the `Jira Status:` line in the file (use Jira's casing). Insert directly below the `Jira:` URL line if missing.
  - Insert at the top of Discussion (right after the `_(Newest first - format: [agent] message)_` line, before existing entries): `[sync] Jira status changed from <old-value> to <new-value>.` Use `(none)` for `<old-value>` if the field was missing.

## Phase 1: Triage

Read the issue file plus any obviously-relevant code referenced in the description (e.g., file paths, class names). Use Read/Grep for this.

Propose a tier to the user:

```
Proposed tier: <Trivial|Standard|Full>
Reasoning: <one sentence>

Confirm? (yes / no / different tier)
```

Wait for user response. On confirmation, write `Tier: <tier>` to the issue file (insert after the `Status:` line or update existing `Tier:` line).

If the file already has `Tier:` set (resumed session), skip Triage and use the existing value.

## Phase 2: Spec (Full tier only)

Invoke `superpowers:brainstorming` via the Skill tool.

**Important override:** the brainstorming skill defaults to saving spec at `docs/superpowers/specs/...`. When invoking, tell the user up front that the spec should be saved to `Active\<TARGET>\spec.md` instead. The skill's flow expects the agent to write the spec — direct it to the correct path when the time comes.

After the brainstorming skill completes and the user approves the spec:
- Verify `Active\<TARGET>\spec.md` exists.
- Add Discussion entry: `[orchestrator] Spec written. See spec.md.`

## Phase 3: Plan (Standard + Full)

Invoke `superpowers:writing-plans` via the Skill tool.

Same override applies: plan should be saved to `Active\<TARGET>\plan.md`, not the default `docs/superpowers/plans/...`. Pass the spec.md path (if Full tier) as the source.

After the skill completes:
- Verify `Active\<TARGET>\plan.md` exists.
- Add Discussion entry: `[orchestrator] Plan written. See plan.md.`

## Phase 4: Execute

**Setup (run on every entry to Execute — steps are idempotent):**

1. Identify required repos:
   - **Standard / Full tiers:** read `plan.md` to identify which repos the tasks touch.
   - **Trivial tier:** use the issue description plus any file paths referenced in it. If unclear, ask the user before cloning.
2. Create `Active\<TARGET>\AgentWorkspace\` folder if missing.
3. For each required repo, shallow clone if the per-repo folder is missing (see `PlanningWorkspace\CLAUDE.md` for repo URLs):
   ```bash
   git clone --depth 1 <repo-url> "<workspace>\Active\<TARGET>\AgentWorkspace\<RepoName>"
   ```
4. In each clone, create branch `fb/<TARGET>` if not already on it. Push it if not already pushed:
   ```bash
   git checkout -b fb/<TARGET> 2>/dev/null || git checkout fb/<TARGET>
   git push -u origin fb/<TARGET> 2>/dev/null || true
   ```
5. Update issue file: set `Status: Development` if not already. Set `Branch: <link-to-azure-devops-branch>` (construct link from origin URL) if not already.
6. **Ticketed items only:** check `Jira Status:` — if already `In Development` (case-insensitive), skip. Otherwise transition Jira to "In Development" using `getTransitionsForJiraIssue` then `transitionJiraIssue`, and update the local `Jira Status:` line on success.

Note: `Status:` stays `Planning` through Phases 2 (Spec) and 3 (Plan); it only flips to `Development` here when Setup runs.

**Execute the plan:**

- **Standard / Full tiers:** invoke `superpowers:subagent-driven-development` via the Skill tool. It will dispatch one sub-subagent per task in `plan.md`, with chat review between tasks.
- **Trivial tier:** no plan.md exists. Execute the change inline using Read / Edit / Write / Bash directly in this chat — there's not enough work to justify spawning sub-subagents. After making the change, verify it (build/test or smoke check as appropriate) before moving to Phase 5.

## Phase 5: Review

Invoke `engineer-toolkit:author-review` via the Skill tool. Provide it with:
- Branch name: `fb/<TARGET>`
- Jira key + title: from the issue file
- Story description: from the `## Description` section
- Anything to scrutinize: ask the user, otherwise pass "no specific concerns"

The skill runs build/tests, delegates to code-reviewer + architect-review (per its internal logic), and produces a structured review summary. Surface the summary to the user in chat.

## Phase 6: Wrap

1. Commit any uncommitted local changes (each clone in AgentWorkspace) with `[Claude]` prefix. Push.
2. Do NOT open a PR. The user opens the PR manually after reviewing the pushed branch.
3. Update issue file:
   - `Status: Code Review`
   - Remove `Mode: direct` line
4. Discussion entry: `[agent] Implementation complete. Branch pushed: fb/<TARGET>. Author-review: <risk-score>/10, cost: <reversibility>.`
5. Report to user:
   ```
   Done with <TARGET>. Branch pushed: fb/<TARGET>
   Risk: <score>/10. Cost of change: <reversibility>.
   Status set to Code Review. Open the PR when ready; transition Jira after merge.
   ```

## Exit handling (mid-session)

Match user intent, not exact phrasing. The strings below are illustrative — classify any deferral intent as "park," any completion intent as "complete," and ask if ambiguous.

| User intent | Example phrases | Action |
|---|---|---|
| **Park for async** | "park it", "hand off", "let /work pick it up", "save for later", "come back to this tomorrow", "punt" | Remove `Mode: direct` line. Re-add `go` line at top. Discussion entry: `[orchestrator] Direct session paused. Re-flagged for /work.` Status unchanged. |
| **Mark complete** | "we're done", "mark complete", "ship it", "all set" | Set `Status: Complete`. Remove `Mode: direct` line. Discussion entry: `[orchestrator] Marked complete. Sweep on next /status.` |
| **Chat ends, no exit signal** | (silent) | Do nothing. File stays `Mode: direct`. Next `/direct <TARGET>` resumes; `/work` skips. |

## Notes

- This skill orchestrates other skills (`brainstorming`, `writing-plans`, `subagent-driven-development`, `author-review`). When invoking via the Skill tool, follow each invoked skill's flow as it instructs — don't second-guess it.
- `Mode: direct` is the only lock. There is no separate "in-progress" state.
- If something fails mid-phase (build error, test failure, blocked on user input), stop and report. Don't auto-retry. The user is right here.

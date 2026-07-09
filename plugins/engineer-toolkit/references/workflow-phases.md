# Workflow Phases

Canonical definition of the per-item workflow phases. `/work` (both modes) and
dispatched subagents defer to this file — do not duplicate the phase mechanics
elsewhere. Sibling references: `issue-file-format.md` (file template + import),
`triage.md` (tier criteria + confidence gate).

`<workspace>` refers to the Workspace path in the workspace `CLAUDE.md`
`## Configuration` block.

Both `/work` modes (full-pass async, and targeted `/work <item>` focused-session) drive
the same phase sequence. Phase 0 setup always runs first; Phase 1 Triage determines
tier; remaining phases run conditionally per tier.

## Phase 0: Setup

1. Folder created at `Active\<KEY>\` (or `Active\<slug>\`) if missing.
2. Jira Status refreshed (ticketed items only — via `/status`).
3. Shallow clone of required repos into `AgentWorkspace\` (only when Execute phase begins).
4. Branch `fb/<KEY>` created and pushed (only when Execute phase begins).

For ticketed items, a targeted `/work <KEY>` imports the ticket inline (per
`issue-file-format.md`) if the folder doesn't exist (Jira keys only — adhoc slugs are
never auto-scaffolded).

## Phase 1: Triage

Performed by the `architect` agent per `triage.md`: it returns a tier plus a 0–100
confidence.

| Tier | Spec | Plan | Examples |
|------|------|------|----------|
| **Trivial** | skip | skip | Version bump, rename, one-line fix, doc typo |
| **Standard** | skip | write `plan.md` | Few files, no architectural decisions, follows existing patterns |
| **Full** | write `spec.md` | write `plan.md` | New surface area, cross-repo, ambiguous requirements, design decisions |

In a **targeted** session the user confirms when confidence < 80 (≥ 80 proceeds with a
heads-up); in a **full pass**, ≥ 80 auto-advances through the tier's phases and < 80
writes the tier, removes `go`, and stops for the user. Exception: on **Full tier the
spec gate is never auto-advanced past** — the run always stops at `Status: Spec Review`
after writing spec.md (see Phase 2). Tier is locked once written; user can retriage by
editing the file and re-flagging `go`.

## Phase 2: Spec (Full tier only)

Invokes `superpowers:brainstorming`. Output saved to `Active\<KEY>\spec.md`. (The
skill's default location is `docs/superpowers/specs/...`; override to the issue folder.)

Targeted: spec is built interactively in the session; spec approval is a chat turn.
Full pass: dispatched subagent builds spec autonomously, Discussion captures the
summary, then the run **always stops at the spec gate** — set `Status: Spec Review`,
remove `go`. The user reviews (and optionally edits) spec.md and re-adds `go` to
approve; the next `/work` cycle picks up at Phase 3. No triage confidence score skips
this gate: Full tier exists because requirements are ambiguous, and tier confidence
measures "is Full the right tier?", not "is the solution understood?".

## Phase 3: Plan (Standard + Full tiers)

Invokes `superpowers:writing-plans`. Output saved to `Active\<KEY>\plan.md`.

Targeted: plan is reviewed conversationally in the session. Full pass: subagent
finishes plan, sets `Status: Plan Review`, removes `go` — user reviews plan.md and
re-adds `go` to approve, which advances the item to Development on the next `/work`
cycle. The plan-review pause is skipped when: **Standard tier** — triage confidence
≥ 80 auto-advanced; **Full tier** — the `[Triage]` Discussion entry records confidence
≥ 80 and the user just approved the spec (spec approval + high-confidence triage stand
in for plan review). Unlike the spec gate, plan review is confidence-skippable.

## Phase 4: Execute (all tiers)

Targeted: invokes `superpowers:subagent-driven-development`. Sub-subagents implement
tasks; the chat session reviews between them.
Full pass: invokes `superpowers:executing-plans`. Dispatched subagent runs the plan
with internal review checkpoints.

When Execute begins:
- AgentWorkspace clones happen if not already (Phase 0 deferred to first need).
- Branch `fb/<KEY>` created.
- Ticketed items get an auto Jira transition to "In Development" (best-effort;
  discover the transition via `getTransitionsForJiraIssue` — IDs vary per project
  and are never cached).

`superpowers:verification-before-completion` is the discipline applied throughout
Execute — never claim a task complete without running the verification command from
the plan and confirming the expected output. For .NET work specifically: always run
`dotnet build <solution>` after edits, before claiming the task done.

## Phase 5: Review (all tiers)

Invokes `engineer-toolkit:author-review`. The skill internally:

1. Runs `dotnet build` and `dotnet test` against the affected solution.
2. Delegates to `engineer-toolkit:code-reviewer` agent (always).
3. Delegates to `engineer-toolkit:architect-review` agent (Complex changes only).
4. Produces a structured review summary with risk score, cost-of-change, and findings —
   designed for direct paste into PR description.

Build/test failures here are blocking. Critical findings should be addressed before
opening PR.

Tier → author-review complexity mapping:

| Workflow Tier | author-review Complexity |
|---------------|--------------------------|
| Trivial | Simple |
| Standard | Simple |
| Full | Complex |

Optional, on demand only (not auto-run): `engineer-toolkit:reviewer-check` — post-PR
independent reviewer pass that validates author-review output and adds its own
findings as a PR comment.

## Phase 6: Wrap

1. Commit and push the branch. **Do not call `gh pr create`** — PCI is on Azure DevOps
   on-prem and the GitHub CLI is not used (see the workflow doctrine's "No GitHub
   CLI"). Instead, write the PR body to `Active\<TARGET>\pr-description.md` (sourced
   from the author-review summary) so the user can paste it when opening the PR in the
   ADO web UI. **Keep PR body under 4000 characters** (ADO on-prem limit). If the
   author-review summary is longer, trim before write: preserve the commit list, build
   line, and architectural decisions worth surfacing; drop verbose explanations, full
   review logs, and per-task breakdowns.
2. Update issue file: `Status: Code Review`, `PR: <link>`. (A targeted session already
   cleared `go` on claim; leave it off.)
3. Discussion entry: `[agent] Implementation complete. PR: <link>. Author-review:
   <risk-score>/10, cost: <reversible/moderate/irreversible>.`

User reviews PR in Azure DevOps; after merge, user transitions Jira (typically to
"Development Complete"). On the next `/status` run, the Jira change is mirrored and the
folder is swept to `Complete\`.

## Archive

After 30 days in `Complete\`: move to `Archive\`.

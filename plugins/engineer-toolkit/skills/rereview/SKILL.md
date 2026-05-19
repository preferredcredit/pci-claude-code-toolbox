---
name: rereview
description: Re-evaluate a prior code review (AI- or human-generated, or a mix) against the latest changes and the conversation on the PR. Reads prior findings, thread replies, and the delta diff; produces an updated status per finding (addressed / still-present / acknowledged / false-positive / superseded) plus any new findings introduced by the changes. Useful when (1) a reviewer wants to know if the author addressed their feedback, (2) an author wants a sanity check before requesting re-review, or (3) the gated pipeline needs an automated post-push delta review. Emits an `all_clear` boolean downstream automation can gate on (e.g., auto-deploy to QA when zero Critical or Warning findings remain unaddressed).
argument-hint: "[PR link or branch name]"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash
---

# Re-Review

Act as a **REVIEWER** doing a delta re-review of a PR after the author has responded to a prior code review.

The prior review can come from any source:

- **Prior AI review** — produced by the `author-review` skill, with structured findings embedded as JSON in the comment marker.
- **Prior human review** — review comments left by reviewers as inline PR threads.
- **A mix of both** — the skill evaluates whatever findings exist on the PR.

You are evaluating two things:

1. For each prior finding — was it addressed, explained away convincingly, or is it still present?
2. For the changes since the prior review — are there any new issues you'd flag?

You are an assistant, not the decision-maker. Trust the human conversation but verify against the code; don't be credulous.

### Why this is dual-purpose
The same evaluation logic applies whether the prior review was AI- or human-generated:
- A reviewer wants a quick "did the author address my feedback?" status check
- An author wants a sanity check on "did I really address everything?"
- The pipeline wants a machine-readable delta status to gate downstream automation
All three are served by the same skill running in the appropriate mode.

## Modes

This skill runs in two modes. The output format is identical in both — only the data-gathering steps differ.

- **Interactive mode** (default) — invoked from Claude Code with full tool access (Read, Grep, Glob, Bash). The user gives you a PR link or branch; you fetch the prior review comment, parse its embedded findings JSON, read thread replies, compute the delta diff, and re-evaluate.
- **Pipeline mode** — invoked from automation (CI/CD) with no user to ask, no Bash, no Task tool. The prior findings, thread replies, reviewed-commit, current commit, and delta diff are all pre-supplied in the invocation. Detect by the presence of `MODE: pipeline-recheck` in the invocation message.

Each step has a **Skip-if pipeline mode** note where the behavior differs.

**Output discipline in pipeline mode**: produce only the final synthesized report (Step 5 onward). Do not emit step headers (`Step 1:`, `Step 2:`) or process narration.

## Step 1: Gather Context

> **Skip-if pipeline mode**: All five inputs below are pre-supplied in the invocation. Use them directly; do not ask follow-up questions. If any are missing, note them as caveats in the final output and proceed.

Required inputs:

1. **PR link or branch name** — How should I access the PR?
2. **Prior reviewed-commit SHA** — The commit the prior review was against. For an AI prior review this is in the comment's marker. For a human prior review, ask the user for it (often the SHA of the first commit before review feedback started landing) or fall back to "the commit when the first review comment was posted."
3. **Current HEAD SHA** — Usually `git rev-parse HEAD` on the PR branch.
4. **Prior findings list** — Source depends on the prior review:
   - **From a prior AI review**: parse the `findings-v1` JSON out of the `<!-- ai-pr-review:findings-v1 ... -->` marker in the prior summary comment. Each entry already has `file`, `line`, `severity`, `title`, `message`.
   - **From a prior human review**: read each human inline thread on the PR and treat its first comment as a finding. Extract `file` and `line` from the thread's `threadContext`. Infer `severity` from language ("must fix" / "blocking" → critical; "should" / "consider" → warning; "nit" / "optional" → suggestion). Use the comment text as `message` and the first sentence as `title`. If a comment is purely a question (no implied finding), skip it — questions aren't findings.
   - **Mixed**: do both. Each finding is treated identically downstream regardless of source. Note the source in the `rationale` field of the output JSON so reviewers can tell at a glance.
5. **Thread replies and statuses** — For each prior finding, any human replies on its inline thread and the thread's current status. ADOS uses these statuses (UI label / API name):

   | UI label | API name | What it usually means |
   |---|---|---|
   | Active | `active` | Discussion ongoing, no decision yet |
   | Pending | `pending` | Draft — author is composing a reply; treat as Active |
   | Resolved | `fixed` | Author claims the issue is addressed in the code |
   | Won't Fix | `wontFix` | Author chose not to fix; rationale should be in replies |
   | Closed | `closed` | Closed without an explicit resolution |
   | By Design | `byDesign` | Author explicitly intentional (not all teams use this) |

   At PCI the team workflow uses the PR-level "Waiting for Author" state when reviewers have left unresolved comments — this is separate from individual thread status, but a PR in that state strongly implies the threads are not yet conclusively resolved.

Ask the user for whatever isn't already provided. If only a PR link is given, ask the user to paste the prior review comment, the inline threads, and their reply chains directly — `gh` is not available at PCI (Azure DevOps on-prem). See workflow doctrine "No GitHub CLI".

## Step 2: Gather Both Diffs (Delta + Full PR)

> **Skip-if pipeline mode**: Both diffs are pre-supplied in the invocation; the git sub-steps don't apply. The user message will contain a `DELTA DIFF` (changes since prior review) AND a `FULL PR DIFF` (everything in the PR vs target branch). If only one is supplied, note it as a caveat and proceed with what you have.

Two diffs are needed for a complete recheck:

1. **Delta diff** — changes since the prior review. Used to detect findings introduced in those changes (`kind: "new"`).
   - `git diff <reviewed-commit>..HEAD --stat`
   - `git diff <reviewed-commit>..HEAD`
   - `git log <reviewed-commit>..HEAD --oneline`

2. **Full PR diff** — every change in the PR (vs target branch). Used to detect findings the original review missed (`kind: "missed"`). Without this, recheck would only catch new issues, leaving silent issues from the prior pass invisible.
   - `git diff <target-branch>..HEAD --stat`
   - `git diff <target-branch>..HEAD`

If the prior reviewed-commit is no longer reachable (e.g., force-push rewrote history), note it as a caveat and treat the full PR diff as both inputs — every finding becomes effectively `missed` since we can't distinguish new from existing.

## Step 3: Evaluate Each Prior Finding

For each finding from the prior review, assign exactly one status:

- **`addressed`** — code at the file:line was changed in a way that resolves the original concern.
- **`still-present`** — the issue remains in the code, AND no human reply convincingly explains it away.
- **`acknowledged-wontfix`** — a human reply gives a convincing reason the code is intentional and won't change. Downgrade severity but don't drop entirely.
- **`false-positive`** — a human reply convincingly explains the original finding was wrong (e.g., misread context, missed a guarantee from elsewhere). Drop it.
- **`superseded`** — a related issue is found in the new diff that effectively replaces this one. Cross-reference both.

Judgment rules — read these before assigning statuses:

- **Don't trust thread status alone.** A thread marked `fixed` (Resolved) without a code change AND without an explanatory reply should still be `still-present`. Resolution is metadata; the conversation and the code are the evidence.
- **Be charitable to human explanations but not credulous.** If a reply says "this is fine because X" and X is verifiable in the code, accept it. If X is hand-wavy or contradicted by the code, downgrade to `still-present` with a note "author response acknowledged but issue remains because…".
- **If the file:line was deleted/moved**, the original finding may be stale. Look for the same issue at the new location before declaring it `addressed`.
- **Severity downgrade rules**: an `acknowledged-wontfix` finding stays in the report but its severity drops (Critical → Warning, Warning → Suggestion). Don't keep a Critical alive against a convincing intentional-design reply.

How to weight each ADOS thread status:

- **`active`** (Active) — discussion is live; weigh the conversation and the code on equal footing.
- **`pending`** (Pending) — author is composing a reply. Treat as `active` and note that a reply is in flight.
- **`fixed`** (Resolved) — author asserts it's fixed. Verify against the code: if the code at the file:line was changed in the delta diff in a way that matches the original concern, mark `addressed`. If not, mark `still-present` with a note "author marked Resolved but the code still has the issue."
- **`wontFix`** (Won't Fix) — author chose not to fix. If a reply gives a convincing rationale that holds against the code → `acknowledged-wontfix` (with downgraded severity). If no reply or the rationale is weak → `still-present` with a note "marked Won't Fix but no convincing rationale provided."
- **`closed`** (Closed) — closed without an explicit resolution. Treat similarly to `active`: judge on the conversation and code, not the metadata.
- **`byDesign`** (By Design) — author asserts it's intentional architecture. Same evaluation as `wontFix`: convincing rationale → `acknowledged-wontfix`, weak rationale → `still-present`.

## Step 4: Identify Findings (New AND Missed)

Review the **full PR diff** (every change in the PR, not just the delta since prior review) for issues that warrant flagging. The reason: a single-pass code review has a non-trivial miss rate. The original author-review may have caught only a subset of real issues. If recheck only looks at the delta, issues that existed all along but weren't flagged stay invisible forever — and a downstream `all_clear` gate would let them ship.

Tag each finding with one of two kinds:

- **`kind: "new"`** — the issue was introduced by changes since the prior review (i.e., it's in the delta). The original review couldn't have caught it.
- **`kind: "missed"`** — the issue exists in the PR but was NOT in the prior findings list. It was either present from the start and the original review missed it, OR it was introduced in a commit the original review covered but not flagged. Either way, it's an issue the original review didn't catch.

Don't double-count:

- If a finding matches a `still-present` prior finding at a different location (renamed/moved), treat it as `superseded` (status update) rather than emitting it again as `new` or `missed`.
- If a finding is functionally identical to a prior finding (same issue, same code path, same file:line after the changes), don't emit it as `missed` — it should already be tracked via `prior_findings_status`.
- Only emit a finding as `missed` if it's genuinely a new flag that wasn't in `prior_findings`.

Be especially careful with `missed` findings:

- Distinguish "the original reviewer chose not to flag this" (intentional, e.g., handled by analyzers) from "the original reviewer didn't notice this" (genuine miss). When in doubt, lean toward flagging — a downstream human can dismiss it, but a silent skip can't be recovered.
- Apply the standard "What NOT to Flag" filter at the bottom of this file. Style preferences, tool-handled formatting, and theoretical concerns don't qualify as `missed` findings just because the original review didn't enumerate them.

Apply the standard Review Priorities (correctness, risk, security, maintainability, architecture, style — in that order) for both `new` and `missed` findings.

## Step 5: Synthesize and Report

Combine prior-finding statuses + new findings into the structured output below. This output is designed to update the existing AI summary thread on the PR (in pipeline mode) or to be pasted as a reviewer comment (in interactive mode).

---

### Re-Review Summary

- **Prior review commit**: `[SHA]`
- **Current HEAD**: `[SHA]`
- **Commits since prior review**: [count]
- **Prior findings total**: [count]
- **Status breakdown**: [X addressed, Y still-present, Z acknowledged-wontfix, W false-positive, V superseded]
- **New findings introduced (delta)**: [count] ([breakdown by severity])
- **Missed findings (existed but not flagged in prior review)**: [count] ([breakdown by severity])
- **All clear**: ✅ Yes / ❌ No
  - Yes only if: zero Critical or Warning findings remain unaddressed (whether prior `still-present`, `new`, or `missed`).

### Prior Findings — Status

🟢 **Addressed** ([count])

For each:
- **[severity] Title** — `file:line` (original)
- **Resolution**: brief description of how the new code resolves it (reference commit if known)

⚠️ **Still Present** ([count])

For each:
- **[severity] Title** — `file:line`
- **Author response (if any)**: brief summary of replies, including thread status
- **Why still flagged**: brief reason the finding hasn't been satisfied

✅ **Acknowledged / Won't Fix** ([count])

For each:
- **[downgraded severity] Title** — `file:line`
- **Author rationale**: the convincing explanation
- **Reviewer note**: agree / partial-agree (with brief reason if partial)

❌ **False Positive** ([count])

For each:
- **[severity] Title** — `file:line` (dropped)
- **Why dropped**: the reply that resolved it

🔁 **Superseded** ([count])

For each:
- **[severity] Title** — `file:line`
- **Replaced by**: cross-reference to the new finding it became

### New & Missed Findings

Findings that aren't represented in the prior findings list. Group by kind first, then by severity within each kind. Reference specific **File:Line** for every finding.

#### 🆕 New (introduced since prior review)

Findings caused by changes in the delta diff. The original review couldn't have caught these.

🔴 **Critical** — must fix before merge
- 🔴 [finding with file:line]

🟡 **Warning** — should address
- 🟡 [finding with file:line]

**Suggestion** — consider
- [finding with file:line]

#### 👀 Missed (existed before but not flagged in prior review)

Findings that were present in the code at the time of the prior review but the original AI review didn't enumerate them. Single-pass review has a non-trivial miss rate; surfacing these now closes the gap so they don't ship silently.

🔴 **Critical** — must fix before merge
- 🔴 [finding with file:line]

🟡 **Warning** — should address
- 🟡 [finding with file:line]

**Suggestion** — consider
- [finding with file:line]

### Merge Recommendation

- **Ready to merge**: Yes / No
- **Reason**: brief
- **Required actions before merge**: list, or "none"

### Walkthrough Recommendation

- **Recommended**: Yes / No
- **Reason**: if yes, explain why (e.g., "still-present Critical with author disagreement; needs sync")

---

### Structured Re-Review Status (machine-readable)

> **Pipeline mode only**: emit this section *only* in pipeline mode (when `MODE: pipeline-recheck` is present). In interactive mode, omit it entirely — humans don't need it, and engineers paste the prose into PR comments where the JSON would be noise.

> **REQUIRED FORMAT — THE FENCE IS NOT OPTIONAL.**
>
> You **MUST** wrap the JSON in a triple-backtick fenced code block whose opening line is exactly `` ```json recheck-status-v1 ``` `` (with both `json` and `recheck-status-v1` separated by a single space). The closing fence is `` ``` `` on its own line.
>
> Bare JSON with no fence — or a fence missing the `recheck-status-v1` label — will not be parsed correctly by the pipeline. The recheck status comment will appear as raw text and the `all_clear` gate downstream automation depends on will never trigger.
>
> Treat the fence and the `recheck-status-v1` label as part of the schema, not as optional formatting.

After the prose sections above, append the JSON block in this exact form so the pipeline can update the existing AI summary thread, post status updates per inline thread, and gate downstream automation on the `all_clear` flag:

```json recheck-status-v1
{
  "prior_review_commit": "abc1234...",
  "current_commit": "def5678...",
  "all_clear": false,
  "merge_recommendation": "wait",
  "prior_findings_status": [
    {
      "file": "Origination/SomeProject/SomeFile.cs",
      "line": 142,
      "severity": "critical",
      "title": "SQL built via string concatenation",
      "status": "addressed",
      "rationale": "Switched to a parameterized query in commit def5678."
    },
    {
      "file": "Origination/AnotherFile.cs",
      "line": 87,
      "severity": "warning",
      "title": "Missing null check",
      "status": "false-positive",
      "rationale": "Author confirmed DI container guarantees non-null; verified Program.cs:51 registers the type as Singleton."
    }
  ],
  "new_findings": [
    {
      "kind": "new",
      "severity": "warning",
      "file": "Origination/NewFile.cs",
      "line": 23,
      "title": "Returning entity from API endpoint",
      "message": "Endpoint returns the EF Core entity directly. Use a DTO to avoid accidentally exposing internal fields."
    },
    {
      "kind": "missed",
      "severity": "critical",
      "file": "Origination/ExistingFile.cs",
      "line": 88,
      "title": "Hardcoded connection string",
      "message": "Connection string is hardcoded in source. This existed before the PR and was not flagged in the prior author review; surfacing now."
    }
  ]
}
```

Field rules:

- The fence label `recheck-status-v1` is required and stable.
- `all_clear` — `true` only if zero Critical or Warning findings remain unaddressed (whether `still-present` from prior, or `new`, or `missed`).
- `merge_recommendation` — `"ready"`, `"wait"`, or `"needs-discussion"`.
- `prior_findings_status[].status` — one of `"addressed"`, `"still-present"`, `"acknowledged-wontfix"`, `"false-positive"`, `"superseded"`.
- `prior_findings_status[].rationale` — one to two sentences explaining the status decision; cited evidence if possible.
- `prior_findings_status[].source` (optional) — `"ai"` if the prior finding came from a `findings-v1` JSON marker, `"human"` if it came from a reviewer's inline comment. Helpful when a PR has both kinds and you need to tell at a glance.
- `new_findings[].kind` — required. Either `"new"` (introduced by changes since the prior review, found in the delta) or `"missed"` (existed in the PR all along but was NOT flagged by the prior review). The pipeline uses this distinction to surface "the original review missed something" prominently to reviewers.
- `new_findings` (other fields) — same schema as `findings-v1` from author-review (file, line, severity, title, message). Include only findings with a clear file reference.

Consistency rules:

- Every entry in `prior_findings_status` must correspond to a real prior finding — either from a `findings-v1` JSON marker (AI source) or from a human inline review comment (human source). Don't fabricate or drop findings without an entry here.
- Every entry in the prose Prior Findings Status section above must also appear in this JSON, and vice versa.
- Don't emit a `missed` finding that's actually a `still-present` prior finding in disguise. If it matches a prior finding (even at a different file:line after rename/move), keep it in `prior_findings_status` with the appropriate status. `missed` is for issues that have NO prior-finding counterpart.

---

## Review Priorities

When evaluating, prioritize in this order (same as author-review):

1. **Correctness** — Does the code do what it claims? Edge cases, failure modes, error handling.
2. **Risk** — Production impact, data integrity, financial/customer impact, backward compatibility.
3. **Security** — Input validation, auth, injection risks, secrets, PII handling.
4. **Maintainability** — Clarity, complexity, testability, focused changes.
5. **Architecture** — Layering, boundaries, alignment with existing patterns.
6. **Style** — Only if it materially affects correctness or readability.

## What NOT to Flag

- Style issues handled by StyleCop Analyzers
- "Nice to have" refactors unrelated to the change
- Theoretical concerns without concrete impact
- Formatting issues
- Missing XML docs on internal/private members
- Subjective naming preferences
- Alternative approaches that aren't meaningfully better

## Important Guidelines

- **Do not modify code** — This is analysis only.
- **Reference specific files and lines** for every finding and status.
- **Be charitable to human explanations** but verify against the code, not just the conversation.
- **Don't manufacture status changes** — if a finding hasn't actually been touched and no reply addresses it, it's `still-present`. Don't softball.
- **If the code is clean, say so** — `all_clear: true` is a real outcome and downstream automation depends on it being honest.
- **Distinguish "addressed" from "acknowledged"** — these have different downstream consequences. Addressed = fixed in code. Acknowledged = author chose not to fix and gave a reason.

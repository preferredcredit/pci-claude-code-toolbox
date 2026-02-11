---
name: reviewer-check
description: Run a reviewer validation check on a PR at PCI. Validates the author's AI review, runs an independent code quality pass, and identifies missed issues.
argument-hint: "[PR link or branch name]"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash
---

# Reviewer Validation Check

Act as a **REVIEWER** validating someone else's PR at Preferred Credit Inc. (PCI).

You are an assistant, not the decision-maker. Optimize for risk reduction and team flow, not perfection.

## Step 1: Gather Context

Ask the user for the following information. Wait for answers before proceeding.

1. **PR link or branch name** — How should I access the changes?
2. **Author's AI Review Summary** — Paste the author's review output (from `/author-review`), or indicate if there isn't one
3. **Jira story key and acceptance criteria** — For validating correctness
4. **Anything specific you want checked** — Areas of concern as a reviewer

## Step 2: Gather the Diff

Once context is provided:

1. If a PR link was given, use `gh pr diff <number>` and `gh pr view <number>` to get the diff and PR description
2. If a branch was given, run:
   - `git diff main...HEAD --stat` to see changed files
   - `git diff main...HEAD` to get the full diff
   - `git log main..HEAD --oneline` to understand the commits
3. Read all changed files in full to understand context around the changes

## Step 3: Independent Code Quality Pass

Regardless of what the author's review found, use the Task tool to delegate to the `code-reviewer` agent:

> Review the following code changes at PCI. The changes are for: [story context].
> Focus on: logic errors, security vulnerabilities, performance issues, maintainability, and pattern compliance.
> Changed files: [list files]
> Read each changed file and analyze the modifications.

This ensures nothing was missed in the author's self-review.

## Step 4: Validate Author's Review (if provided)

If the author included an AI Review Summary, validate each section:

- **Summary accuracy** — Does the summary accurately describe what changed?
- **Risk score** — Do you agree with the score? Would you adjust up or down?
- **Cost of change** — Is the reversibility assessment correct?
- **Missed findings** — Did the author's review miss any significant issues?
- **Missed files** — Are there changed files not covered in the review?

## Step 5: Verify Against Acceptance Criteria

- Do the changes satisfy the stated acceptance criteria?
- Are there acceptance criteria that appear unaddressed?
- Are there changes that go beyond the stated scope?

## Step 6: Synthesize and Report

Produce the following structured output. This output is designed to be added as a PR comment.

---

### Reviewer AI Check

#### Risk Score Validation
- **Author's score**: [X] / **Reviewer's score**: [Y]
- **Agreement**: Agree / Disagree
- **Rationale**: [why you agree or would adjust]

Risk score reference:

| Score | Level | Examples |
|------:|-------|---------|
| 1-3 | Simple / low risk | Bug fix, UI tweak, log message change, documentation |
| 4-6 | Moderate complexity | New feature in existing pattern, internal API change, NuGet update |
| 7-8 | Complex or multi-system | Cross-project changes, new integrations, saga modifications |
| 9-10 | High financial / customer risk | Payment processing, credit bureau integration, data migration, schema change affecting live data |

#### Cost of Change Validation
- **Author's assessment**: [Reversible/Moderate/Irreversible]
- **Reviewer's assessment**: [Reversible/Moderate/Irreversible]
- **Agreement**: Agree / Disagree
- **Rationale**: [why you agree or would adjust]

Cost of change definitions:
- **Reversible** — Easy to change or roll back (UI tweaks, log messages, internal method refactors)
- **Moderate** — Requires coordination to undo (internal API changes, configuration changes, new NuGet package versions)
- **Irreversible** — Costly, risky, or disruptive to undo (public APIs, database schemas, message contracts, core domain rules, data migrations)

#### Acceptance Criteria Check
- [ ] [AC item 1] — Met / Not Met / Unclear
- [ ] [AC item 2] — Met / Not Met / Unclear

#### Missed Issues
Issues not identified in the author's review:

**Blockers** (must fix before merge):
- [finding with **File:Line** reference, severity, and why it's a blocker]

**Non-Blockers** (should address, but not merge-blocking):
- [finding with **File:Line** reference and recommendation]

#### Confirmed Findings
Findings from the author's review that the reviewer confirms:
- [list confirmed issues that should be addressed]

#### Good Patterns Observed
- [positive observations about the code quality]

#### Questions
- [questions for the author about intent, behavior, or decisions]

#### Walkthrough Recommendation
- **Recommended**: Yes / No
- **Reason**: [if yes, explain triggers]

Recommend a walkthrough if:
- Risk score >= 7
- Cost of change is Irreversible
- Changes span multiple systems or layers
- Business logic is complex or subtle
- Disagreement on approach between author and reviewer

---

## Review Priorities

When reviewing, prioritize in this order:
1. **Correctness** — Does the code do what it claims? Edge cases, failure modes, error handling
2. **Risk** — Production impact, data integrity, financial/customer impact, backward compatibility
3. **Security** — Input validation, auth, injection risks, secrets, PII handling
4. **Maintainability** — Clarity, complexity, testability, focused changes
5. **Architecture** — Layering, boundaries, alignment with existing patterns
6. **Style** — Only if it materially affects correctness or readability (StyleCop handles the rest)

## What NOT to Flag

- Style issues handled by StyleCop Analyzers
- "Nice to have" refactors unrelated to the change
- Theoretical concerns without concrete impact
- Formatting issues
- Missing XML docs on internal/private members
- Subjective naming preferences
- Alternative approaches that aren't meaningfully better

## Important Guidelines

- **Do not modify code** — This is analysis only
- **Run your own code-reviewer pass** — Don't rely solely on the author's review
- **Reference specific files and lines** for all findings
- **Clearly distinguish blockers from non-blockers** — This is the most important signal for the author
- **Be constructive** — You're helping improve the code, not gatekeeping
- **If the code is clean, say so** — Don't manufacture findings to justify the review
- **Praise good patterns** — Acknowledge quality work
- If no author review was provided, produce a full review using the `/author-review` output format instead

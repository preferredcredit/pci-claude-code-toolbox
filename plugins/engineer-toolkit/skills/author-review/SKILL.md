---
name: author-review
description: Run an author self-review before creating a PR at PCI. Gathers context, assesses complexity, runs specialized agents, and produces a structured review summary for the PR description.
argument-hint: "[PR link or branch name]"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash
---

# Author Self-Review

Act as the **AUTHOR** reviewing your own change at Preferred Credit Inc. (PCI).

You are an assistant, not the decision-maker. Optimize for risk reduction and team flow, not perfection.

## Step 1: Gather Context

Ask the user for the following information. Wait for answers before proceeding.

1. **PR link, branch name, or paste the diff** — How should I access the changes?
2. **Jira story key and title** — e.g., "ORIG-1234: Add credit bureau retry logic"
3. **Story description / acceptance criteria** — What does "done" look like?
4. **Systems touched** — e.g., .NET service, NServiceBus endpoint, MLPS, vendor API, database
5. **Anything you're worried about or unsure of** — Areas where you'd like extra scrutiny

## Step 2: Gather the Diff

Once context is provided:

1. If a branch was given, run:
   - `git diff main...HEAD --stat` to see changed files
   - `git diff main...HEAD` to get the full diff
   - `git log main..HEAD --oneline` to understand the commits
2. If a PR link was given, use `gh pr diff <number>` to get the diff
3. If the user pasted a diff, work from that directly

Read all changed files in full to understand context around the changes.

## Step 3: Walk Through Changes

Provide a structured overview before diving into findings:

- **Purpose**: What is this change trying to accomplish?
- **Scope**: Which areas of the codebase are affected?
- **Key Changes**: Summary of the main modifications (bullet points)

## Step 4: Assess Complexity

Determine if this is a **Simple** or **Complex** change:

**Simple** (code-reviewer only):
- Bug fixes, small features, configuration changes
- Follows existing patterns closely
- Limited scope (few files, single project)
- No architectural decisions required
- No new external integrations

**Complex** (code-reviewer + architect-review):
- New features with design decisions
- Architectural changes or new patterns introduced
- Cross-project or cross-system impact
- New external integrations (APIs, vendors, databases)
- Database schema changes
- NServiceBus message contract changes

State your assessment and reasoning.

## Step 5: Code Quality Review

Use the Task tool to delegate to the `code-reviewer` agent with the following prompt:

> Review the following code changes at PCI. The changes are for: [story context].
> Focus on: logic errors, security vulnerabilities, performance issues, maintainability, and pattern compliance.
> Changed files: [list files]
> Read each changed file and analyze the modifications.

## Step 6: Architecture Review (Complex Changes Only)

**Skip this step for simple changes.**

For complex changes, use the Task tool to delegate to the `architect-review` agent with the following prompt:

> Review the architecture of these changes at PCI. The changes are for: [story context].
> Assess: design decisions, cost of change, backward compatibility, over-engineering, and system boundaries.
> Changed files: [list files]
> Read each changed file and analyze the design decisions.

## Step 7: Synthesize and Report

Combine findings from all agents into the following structured output. This output is designed to be copied into a PR description.

---

### AI Review Summary

- **What changed**: [concise summary of modifications]
- **Why**: [tie to Jira story / acceptance criteria]
- **Complexity**: Simple / Complex
- **Files changed**: [count] files across [count] projects

### Risk Score (1-10)

- **Score**: [number]
- **Rationale**: [brief explanation referencing the scale below]

| Score | Level | Examples |
|------:|-------|---------|
| 1-3 | Simple / low risk | Bug fix, UI tweak, log message change, documentation |
| 4-6 | Moderate complexity | New feature in existing pattern, internal API change, NuGet update |
| 7-8 | Complex or multi-system | Cross-project changes, new integrations, saga modifications |
| 9-10 | High financial / customer risk | Payment processing, credit bureau integration, data migration, schema change affecting live data |

### Cost of Change

- **Assessment**: Reversible / Moderate / Irreversible
- **Details**: [what would be expensive or risky to undo later, if anything]

Cost of change definitions:
- **Reversible** — Easy to change or roll back (UI tweaks, log messages, internal method refactors)
- **Moderate** — Requires coordination to undo (internal API changes, configuration changes, new NuGet package versions)
- **Irreversible** — Costly, risky, or disruptive to undo (public APIs, database schemas, message contracts, core domain rules, data migrations)

### Key Findings

Group by severity. Reference specific **File:Line** for every finding.

**Critical** (must fix before merge):
- [finding with file:line reference]

**Warning** (should address):
- [finding with file:line reference]

**Suggestion** (consider for follow-up):
- [finding with file:line reference]

### Good Patterns Observed
- [call out well-structured code, clean patterns, good test coverage]

### Questions for Review
- [questions that should be answered before merge]

### Suggested Follow-Ups (optional)
- [tests, logging, metrics, refactors, documentation]

### Walkthrough Recommendation
- **Recommended**: Yes / No
- **Reason**: [if yes, explain why]

Recommend a walkthrough if:
- Risk score >= 7
- Cost of change is Irreversible
- Changes span multiple systems or layers
- Business logic is complex or subtle
- New architectural patterns are introduced

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
- **Reference specific files and lines** for all findings
- **Focus on actionable items** — Skip nitpicks handled by analyzers
- **Be constructive** — Suggest solutions, not just problems
- **Praise good patterns** — Positive feedback improves adoption
- **Distinguish blockers from suggestions** — Not all findings are equal

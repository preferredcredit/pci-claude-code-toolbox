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

## Modes

This skill runs in two modes. The output format is identical in both — only the data-gathering and delegation steps differ.

- **Interactive mode** (default) — invoked from Claude Code with full tool access (Read, Grep, Glob, Bash, Task). Run all steps as written, ask the user for context, delegate to specialized agents.
- **Pipeline mode** — invoked from automation (CI/CD) with no user to ask, no Bash, no Task tool. Context (the diff at minimum) is pre-supplied in the invocation. Detect by the presence of `MODE: pipeline` in the invocation message.

Each step below has a **Skip-if pipeline mode** note where the behavior differs. Follow it in pipeline mode; ignore it in interactive mode.

**Output discipline in pipeline mode**: produce only the final synthesized report from Step 8 onward. Do not emit step headers (`Step 1:`, `Step 4 & 5:`, etc.) or process narration (`I'll work through this systematically…`). The receiver wants the result, not the journey through the steps.

## Step 1: Gather Context

> **Skip-if pipeline mode**: Use whatever context is provided in the invocation (typically the diff). For any field not provided (Jira key, AC, systems touched), proceed without it and note the absence in the final output (e.g., `Jira context: not provided`). Do not ask follow-up questions.

Ask the user for the following information. Wait for answers before proceeding.

1. **PR link, branch name, or paste the diff** — How should I access the changes?
2. **Jira story key and title** — e.g., "ORIG-1234: Add credit bureau retry logic"
3. **Story description / acceptance criteria** — What does "done" look like?
4. **Systems touched** — e.g., .NET service, NServiceBus endpoint, MLPS, vendor API, database
5. **Anything you're worried about or unsure of** — Areas where you'd like extra scrutiny

## Step 2: Gather the Diff

> **Skip-if pipeline mode**: The diff is already supplied in the invocation. The git/`gh` sub-steps and the "Read all changed files" sub-step do not apply — analyze the diff content as-is.

Once context is provided:

1. If a branch was given, run:
   - `git diff main...HEAD --stat` to see changed files
   - `git diff main...HEAD` to get the full diff
   - `git log main..HEAD --oneline` to understand the commits
2. If a PR link was given, use `gh pr diff <number>` to get the diff
3. If the user pasted a diff, work from that directly

Read all changed files in full to understand context around the changes.

## Step 3: Build and Test

> **Skip-if pipeline mode**: Bash is unavailable. Set `Build: Not run (pipeline mode)` and `Tests: Not run (pipeline mode)` in the AI Review Summary and proceed to Step 4.

Before analyzing the code, verify the solution builds and tests pass:

1. Identify the solution file (`.sln` or `.slnx`) in the repository root or nearest parent directory
2. Run `dotnet build <solution>` and report the result
3. Run `dotnet test <solution>` and report the result
4. Record both outcomes — they feed into the risk score and key findings

If the build fails, report it as a **Critical** finding. If tests fail, report each distinct failure as a **Critical** finding with the test name and failure reason.

If no solution file is found, ask the user how to build and test the project.

## Step 4: Walk Through Changes

Provide a structured overview before diving into findings:

- **Purpose**: What is this change trying to accomplish?
- **Scope**: Which areas of the codebase are affected?
- **Key Changes**: Summary of the main modifications (bullet points)

## Step 5: Assess Complexity

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

## Step 6: Code Quality Review

> **Skip-if pipeline mode**: The Task tool is unavailable. Perform the equivalent code review yourself, inline. Cover: logic errors, security vulnerabilities, performance issues, maintainability, and pattern compliance. Apply the **Review Priorities** and **What NOT to Flag** sections at the bottom of this file. Reference specific file:line for every finding.

Use the Task tool to delegate to the `code-reviewer` agent with the following prompt:

> Review the following code changes at PCI. The changes are for: [story context].
> Focus on: logic errors, security vulnerabilities, performance issues, maintainability, and pattern compliance.
> Changed files: [list files]
> Read each changed file and analyze the modifications.

## Step 7: Architecture Review (Complex Changes Only)

**Skip this step for simple changes.**

> **Skip-if pipeline mode**: The Task tool is unavailable. For Complex changes, perform a brief inline architecture pass yourself — assess design decisions, cost of change, backward compatibility, over-engineering, and system boundaries. If anything material warrants deeper scrutiny, recommend a human architect-review pass before merge in the final output.

For complex changes, use the Task tool to delegate to the `architect-review` agent with the following prompt:

> Review the architecture of these changes at PCI. The changes are for: [story context].
> Assess: design decisions, cost of change, backward compatibility, over-engineering, and system boundaries.
> Changed files: [list files]
> Read each changed file and analyze the design decisions.

## Step 8: Synthesize and Report

Combine findings from all agents into the following structured output. This output is designed to be copied into a PR description.

---

### AI Review Summary

- **What changed**: [concise summary of modifications]
- **Why**: [tie to Jira story / acceptance criteria]
- **Complexity**: Simple / Complex
- **Files changed**: [count] files across [count] projects
- **Build**: Pass / Fail
- **Tests**: [passed] passed, [failed] failed, [skipped] skipped

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

🔴 **Critical** (must fix before merge):
- 🔴 [finding with file:line reference]

🟡 **Warning** (should address):
- 🟡 [finding with file:line reference]

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

### Structured Findings (machine-readable)

> **Pipeline mode only**: emit this section *only* in pipeline mode (when `MODE: pipeline` is present in the invocation). In interactive mode, omit it entirely — humans reading the prose report don't need it, and engineers paste the report into PR descriptions where the JSON would be noise.

> **REQUIRED FORMAT — THE FENCE IS NOT OPTIONAL.**
>
> You **MUST** wrap the JSON in a triple-backtick fenced code block whose opening line is exactly `` ```json findings-v1 ``` `` (with both `json` and `findings-v1` separated by a single space). The closing fence is `` ``` `` on its own line.
>
> Bare JSON with no fence — or a fence missing the `findings-v1` label — will not be parsed correctly by the pipeline. Inline comments will not be posted. The JSON will appear as raw text in the PR comment, defeating the purpose of having structure at all.
>
> Treat the fence and the `findings-v1` label as part of the schema, not as optional formatting.

After all the prose sections above, append the JSON block in this exact form:

```json findings-v1
{
  "findings": [
    {
      "severity": "critical",
      "file": "Origination/SomeProject/SomeFile.cs",
      "line": 142,
      "title": "SQL built via string concatenation",
      "message": "User input is concatenated into the SQL on line 142, opening an injection path. Switch to a parameterized query."
    }
  ]
}
```

Field rules:

- The fence label `findings-v1` is required and stable — automation grep relies on it.
- `severity` — exactly one of `"critical"`, `"warning"`, `"suggestion"` (lowercase).
- `file` — repository-relative path with forward slashes, no leading slash. Required for any finding intended to surface as an inline PR comment.
- `line` — integer line number in the new (post-change) file, 1-based. If the finding is file-level rather than line-specific, use `null`.
- `title` — under 80 chars, suitable as a single-line comment header.
- `message` — full detail. Markdown is fine (will render in PR comments). Mirrors the prose finding but standalone-readable.
- If there are no findings, emit `{"findings": []}` so automation can detect "all clear" reliably.

What to include in the JSON:

- Every Critical, Warning, and Suggestion that has a clear file reference (with or without a line number).
- Skip pure architecture/global concerns that have no file anchor — those stay in the prose only. The JSON is for things automation can place on the diff.

Consistency with the prose:

- Every JSON finding should also appear in the prose Key Findings section. The prose is for humans skimming the PR; the JSON is for tools.
- Don't add "phantom" findings to the JSON that aren't in the prose, or vice versa.

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

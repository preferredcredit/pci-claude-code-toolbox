---
name: create-crd-story
description: Creates a Story in PCI's Jira CRD project (Credit Risk & Decisioning) using the stream team's standard format — user story/goal, details, and testable acceptance criteria. Use ONLY when the user explicitly invokes /create-crd-story. Never auto-trigger on natural language.
disable-model-invocation: true
allowed-tools: AskUserQuestion, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getAccessibleAtlassianResources, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__searchJiraIssuesUsingJql, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createJiraIssue
---

# Create CRD Story

Creates a **Story** in the `CRD` project at `preferredcredit.atlassian.net` in the team's standard format. The user is the subject-matter expert; this skill is the ghostwriter — it asks for the key points, drafts a clean ticket, and confirms before writing to Jira.

Stories are for concrete code/system changes. Decisions, analysis, data pulls, and config coordination belong in `/create-crd-task`; defects belong in `/create-crd-bug`.

## Input

The user has provided: `$ARGUMENTS`

Recognized flags:
- `--title "..."` — story summary. Drafted from context if omitted.
- `--parent CRD-###` — parent epic key.
- `--priority <name>` — Critical - Immediate, Highest, High, Medium, Low, Lowest. Default: leave unset (Jira defaults to Medium).

Any other text is freeform context describing the work — use it before asking questions.

## Step 1: Intake

From `$ARGUMENTS`, work out what is already known. Then ask conversationally for whatever is still missing (skip anything already covered):

1. **Component/area** — which system does this touch? (Established title prefixes: `NextGen BC`, `NextGen`, `Gateway`, `Core`, `Decisioning`, `Client Portal`, `Origination BC`, `PCSM`.)
2. **What & why** — what's changing, and who benefits / what outcome it enables.
3. **Done-when** — rough acceptance criteria, in their words. Push for at least one.

Don't interrogate — at most three rounds of questions, then draft; use follow-up rounds only when an answer genuinely needs clarifying. Gaps the user can't fill become omitted sections, not boilerplate. The parent epic is handled in Step 2 — don't ask for it here.

## Step 2: Resolve parent epic

Every CRD story belongs under an epic — this is the team's one universally honored field.

- If `--parent` was provided, validate with `getJiraIssue` (fields: `summary`, `issuetype`, `status`). It must exist and be an Epic — if not, tell the user what it actually is and ask again. Never guess corrections.
- If not, run `searchJiraIssuesUsingJql` with `project = CRD AND issuetype = Epic AND statusCategory != Done ORDER BY updated DESC`, fields `["summary", "status"]`, maxResults 50, and show the **10 most recently updated**. Ask the user to pick one or name another.
- If the user explicitly says no epic fits, proceed without a parent but note it in the preview.

For all Jira calls, pass `preferredcredit.atlassian.net` as `cloudId`. If that's rejected, call `getAccessibleAtlassianResources` and use the `id` of the resource whose `url` contains `preferredcredit.atlassian.net`.

## Step 3: Draft

**Title:** `<Component> - <imperative action>` using the prefixes from Step 1, e.g. `Gateway - Refactor Applicants Credit Reports card`. Name concrete artifacts (class names, question numbers, strategy codes) when known. 6–12 words. Plain verb-first with no prefix is fine for business/config asks.

**Description** (markdown), from this template — include a section only when there's real content for it:

```
## User Story
As a <persona>, I want <capability>, so that <outcome>.
```
*(For purely technical stories, use `## Goal` with a one-paragraph statement of what changes and why instead.)*

```
## Details
What is changing and where. Name the exact projects, classes, tables, question
numbers, or message contracts in scope. Link related Jira tickets and Confluence
pages instead of restating them. Put load-bearing values (codes, rates, field
definitions) in markdown tables — never screenshot-only.

## Technical Notes        ← optional; for engineering-authored stories
Bulleted, organized by code area, with file paths and method-level guidance.

## Assumptions / Open Questions        ← optional
State assumptions explicitly. When an open question is answered, record the
answer inline — don't leave questions dangling.

## Acceptance Criteria        ← required, every story
- Bulleted, independently testable.
- Cover happy path, empty/null, error, and exclusion cases as applicable.
- Group by scenario/state for UI work; use Given/When/Then for complex backend behavior.

## Dependencies        ← optional
Release-blocking external work and its ticket key.
```

Quality bar: CRD-434 (rich backend story), CRD-202 (UI story with grouped AC), CRD-232 (functional details + answered open questions). These are reference keys for maintainers — don't fetch them during a run. Minimum bar even for small config asks: 2–3 sentences of context plus one acceptance criterion — never an empty description.

## Step 4: Preview, refine, confirm

Show **one** preview — metadata plus the full draft:

```
About to create CRD Story:

  Project:   CRD
  Type:      Story
  Summary:   <title>
  Parent:    <CRD-### — epic summary | (none — user opted out)>
  Priority:  <name | (default)>

--- Description ---
<full markdown>
```

Then ask: **"Create this Story, or what would you refine?"**
- `yes`/`y` → create.
- `no`/`cancel` → abort with no Jira writes.
- Anything else → treat it as refinement direction: re-draft, re-show the preview, ask again.

Confirmation is mandatory — there is no `--yes` flag.

## Step 5: Create and report

Call `createJiraIssue`:

```json
{
  "cloudId": "preferredcredit.atlassian.net",
  "projectKey": "CRD",
  "issueTypeName": "Story",
  "summary": "<title>",
  "description": "<markdown>",
  "contentFormat": "markdown",
  "parent": "<CRD-### — omit if none>",
  "additional_fields": { "priority": { "name": "<name>" } }
}
```

Omit `additional_fields` unless a non-default priority was requested. If the API rejects the top-level `parent`, retry once with `additional_fields: { "parent": { "key": "CRD-###" } }`.

On success report: `Story created: https://preferredcredit.atlassian.net/browse/<KEY>`. On failure, surface the API error verbatim and stop.

## Important Guidelines

- **Strict trigger.** Only respond to explicit `/create-crd-story` invocation.
- **Confirmation is mandatory.** No Jira writes without an explicit `yes` at the preview.
- **Never fabricate Jira keys** — validate the parent epic; never guess corrections.
- **Omit, don't pad.** A missing section beats canned filler. But Acceptance Criteria are non-negotiable — push the user for at least one testable criterion.
- **Don't set unused fields.** Labels, components, fix versions, story points, sprint, assignee — none are set at create time on this board (sprint and assignee are handled on the board after creation). Reporter defaults to the authenticated user; don't set it.
- **One story = one change.** If intake reveals multiple unrelated changes, suggest splitting and create them one at a time.
- **No Atlassian tools?** If the Atlassian MCP server isn't connected, stop and tell the user to connect it — don't attempt workarounds.

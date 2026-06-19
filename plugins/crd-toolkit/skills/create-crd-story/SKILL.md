---
name: create-crd-story
description: Creates a Story in PCI's Jira CRD project (Credit Risk & Decisioning) for a concrete code/system change — user story/goal, details, testable acceptance criteria. Invoke when the user wants to create/file a CRD story or track an implementation change. Non-code work → create-crd-task; defects → create-crd-bug; multi-story workstreams → create-crd-epic. Also runnable via /create-crd-story. Always previews and requires explicit confirmation before writing to Jira.
allowed-tools: AskUserQuestion, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getAccessibleAtlassianResources, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__searchJiraIssuesUsingJql, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getIssueLinkTypes, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createIssueLink
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
- `--relates KEY` — create a `Relates` link to KEY. Repeatable.
- `--blocked-by KEY` — this story **is blocked by** KEY. Repeatable.
- `--blocks KEY` — this story **blocks** KEY. Repeatable.

Any other text is freeform context describing the work — use it before asking questions.

## Step 1: Intake

From `$ARGUMENTS`, work out what is already known. Then ask conversationally for whatever is still missing (skip anything already covered):

1. **Component/area** — which system does this touch? (Established title prefixes: `NextGen BC`, `NextGen`, `Gateway`, `Core`, `Decisioning`, `Client Portal`, `Origination BC`, `PCSM`.)
2. **What & why** — what's changing, and who benefits / what outcome it enables.
3. **Done-when** — rough acceptance criteria, in their words. Push for at least one.
4. **Related/blocking tickets** *(optional)* — any tickets this relates to, is blocked by, or blocks? (Or pass `--relates` / `--blocked-by` / `--blocks`.) Skip if none.

Don't interrogate — at most three rounds of questions, then draft; use follow-up rounds only when an answer genuinely needs clarifying. Gaps the user can't fill become omitted sections, not boilerplate. The parent epic is handled in Step 2 — don't ask for it here.

## Step 2: Resolve parent epic

Every CRD story belongs under an epic — this is the team's one universally honored field.

- If `--parent` was provided, validate with `getJiraIssue` (fields: `summary`, `issuetype`, `status`). It must exist and be an Epic — if not, tell the user what it actually is and ask again. Never guess corrections.
- If not, run `searchJiraIssuesUsingJql` with `project = CRD AND issuetype = Epic AND statusCategory != Done ORDER BY updated DESC`, fields `["summary", "status"]`, maxResults 50, and show the **10 most recently updated**. Ask the user to pick one or name another.
- If the user explicitly says no epic fits, proceed without a parent but note it in the preview.

For all Jira calls, pass `preferredcredit.atlassian.net` as `cloudId`. If that's rejected, call `getAccessibleAtlassianResources` and use the `id` of the resource whose `url` contains `preferredcredit.atlassian.net`.

## Step 3: Resolve link types & validate targets

Skip this step entirely if no related/blocking tickets were provided.

1. **Resolve link type names.** Call `getIssueLinkTypes`. Capture the canonical `name` of the `Relates` type (also accept the sort-prefixed `1Relates`) and — if any `--blocked-by`/`--blocks` targets exist — the `Blocks` type (accept sort-prefixed variants) plus its `inward`/`outward` labels for direction. If a *requested* type isn't found, report it and drop those targets; don't abort the skill.
2. **Validate each target.** Call `getJiraIssue` (fields `summary`, `issuetype`, `status`) for every link key. Keys that don't resolve go to a `missing[]` list shown in the preview — never link them, never guess corrections.

Carry the resolved links (type, direction, key, summary) into the preview and Step 6.

## Step 4: Draft

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
Release-blocking external work and its ticket key. Keys passed via `--blocked-by`/`--blocks` (or named in intake) are listed here **and** created as native Jira links.
```

**Reflect gathered links in the body too.** Per team preference, every related/blocking ticket also appears in the description, not only as a native link: list `--blocked-by`/`--blocks` keys under `## Dependencies` and weave `--relates` keys into `## Details`. Keep existing inline citations and Confluence / non-Jira links as markdown.

Quality bar: CRD-434 (rich backend story), CRD-202 (UI story with grouped AC), CRD-232 (functional details + answered open questions). These are reference keys for maintainers — don't fetch them during a run. Minimum bar even for small config asks: 2–3 sentences of context plus one acceptance criterion — never an empty description.

## Step 5: Preview, refine, confirm

Show **one** preview — metadata plus the full draft:

```
About to create CRD Story:

  Project:   CRD
  Type:      Story
  Summary:   <title>
  Parent:    <CRD-### — epic summary | (none — user opted out)>
  Priority:  <name | (default)>

Links to create:        ← omit this block if no links
  • relates       → CRD-123 — <summary>
  • is blocked by  → CRD-456 — <summary>
Skipped (not found in Jira):
  • <BAD-KEY>

--- Description ---
<full markdown>
```

Then ask: **"Create this Story, or what would you refine?"**
- `yes`/`y` → create.
- `no`/`cancel` → abort with no Jira writes.
- Anything else → treat it as refinement direction: re-draft, re-show the preview, ask again.

Confirmation is mandatory — there is no `--yes` flag.

## Step 6: Create, link, and report

1. **Create.** Call `createJiraIssue`:

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

Omit `additional_fields` unless a non-default priority was requested. If the API rejects the top-level `parent`, retry once with `additional_fields: { "parent": { "key": "CRD-###" } }`. On `createJiraIssue` failure, surface the API error verbatim and stop — don't attempt linking.

2. **Link each target** from Step 3, using the new story key as `NEW`:
   - relates → `{ "type": { "name": "<Relates name>" }, "inwardIssue": { "key": "<target>" }, "outwardIssue": { "key": "<NEW>" } }`
   - `--blocks` (story blocks target) → `{ "type": { "name": "<Blocks name>" }, "inwardIssue": { "key": "<target>" }, "outwardIssue": { "key": "<NEW>" } }`
   - `--blocked-by` (target blocks story) → `{ "type": { "name": "<Blocks name>" }, "inwardIssue": { "key": "<NEW>" }, "outwardIssue": { "key": "<target>" } }`

   Continue past per-link failures — collect them for the report.

3. **Report:**

```
Story created: https://preferredcredit.atlassian.net/browse/<KEY>

Linked <S>/<T> related items.        ← omit if no links
Failed links (if any):
  • <KEY>: <reason>
```

## Important Guidelines

- **Trigger.** Model-invocable: fire when the user wants to create/file a CRD story or track an implementation change (or runs `/create-crd-story`). Don't fire on mere discussion or while implementing — only when a ticket is actually wanted. Non-code work → `/create-crd-task`; a defect → `/create-crd-bug`. Confirmation before any Jira write remains mandatory.
- **Confirmation is mandatory.** No Jira writes without an explicit `yes` at the preview.
- **Never fabricate Jira keys** — validate the parent epic and every link target; unresolved keys are reported in the preview, never guessed.
- **Omit, don't pad.** A missing section beats canned filler. But Acceptance Criteria are non-negotiable — push the user for at least one testable criterion.
- **Don't set unused fields.** Labels, components, fix versions, story points, sprint, assignee — none are set at create time on this board (sprint and assignee are handled on the board after creation). Reporter defaults to the authenticated user; don't set it.
- **One story = one change.** If intake reveals multiple unrelated changes, suggest splitting and create them one at a time.
- **No Atlassian tools?** If the Atlassian MCP server isn't connected, stop and tell the user to connect it — don't attempt workarounds.

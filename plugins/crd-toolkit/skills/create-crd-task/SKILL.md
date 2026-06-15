---
name: create-crd-task
description: Creates a Task in PCI's Jira CRD project (Credit Risk & Decisioning) using the stream team's standard format — context, concrete ask, inputs, and deliverable. For non-code work like decisions, analysis, data pulls, and configuration. Use ONLY when the user explicitly invokes /create-crd-task. Never auto-trigger on natural language.
disable-model-invocation: true
allowed-tools: AskUserQuestion, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getAccessibleAtlassianResources, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__searchJiraIssuesUsingJql, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createJiraIssue
---

# Create CRD Task

Creates a **Task** in the `CRD` project at `preferredcredit.atlassian.net` in the team's standard format. The user is the subject-matter expert; this skill is the ghostwriter — it asks for the key points, drafts a clean ticket, and confirms before writing to Jira.

On this board, Tasks are **non-code work**: decisions to make, tradeoff analysis, spikes/data gathering, training, AccountMate/client configuration, documentation, and coordination. Implementation work belongs in `/create-crd-story`; defects belong in `/create-crd-bug`.

## Input

The user has provided: `$ARGUMENTS`

Recognized flags:
- `--title "..."` — task summary. Drafted from context if omitted.
- `--parent CRD-###` — parent epic key.
- `--priority <name>` — Critical - Immediate, Highest, High, Medium, Low, Lowest. Default: leave unset (Jira defaults to Medium).

Any other text is freeform context — use it before asking questions.

## Step 1: Intake

From `$ARGUMENTS`, work out what is already known. Then ask conversationally for whatever is still missing — the core is:

1. **The ask** — what exactly needs to be done, decided, analyzed, or configured? For spikes: is there a timebox?
2. **Deliverable** — where does the output land? A recorded decision, an updated Confluence doc, follow-up stories created, settings applied?

Ask about context (why now, related links) and exact inputs (client numbers, AM question/setting values, date ranges) only when the draft would be empty without them — otherwise those sections are simply omitted.

Don't interrogate — at most three rounds of questions, then draft; use follow-up rounds only when an answer genuinely needs clarifying. The parent epic is handled in Step 2 — don't ask for it here.

## Step 2: Resolve parent epic

Parent epics are encouraged for Tasks but not mandatory.

- If `--parent` was provided, validate with `getJiraIssue` (fields: `summary`, `issuetype`, `status`). It must exist and be an Epic — if not, tell the user what it actually is and ask again. Never guess corrections.
- If not, run `searchJiraIssuesUsingJql` with `project = CRD AND issuetype = Epic AND statusCategory != Done ORDER BY updated DESC`, fields `["summary", "status"]`, maxResults 50, and show the **10 most recently updated**. The user picks one, names another, or says none.

For all Jira calls, pass `preferredcredit.atlassian.net` as `cloudId`. If that's rejected, call `getAccessibleAtlassianResources` and use the `id` of the resource whose `url` contains `preferredcredit.atlassian.net`.

## Step 3: Draft

**Title:** verb-first, 4–10 words, no component prefix (that's a Story convention). Lead with the action verb the team already uses — `Define`, `Decide`, `Determine`, `Analyze`, `Confirm`, `Gather`, `Set up`, `Update` — plus the object and milestone qualifier, e.g. `Determine pilot client strategies for CRS24 CFS MVP`. Avoid bare question titles like "Is this needed?" — name the thing.

**Description** (markdown), from this template — include a section only when there's real content for it:

```
## Context
1–3 sentences of background. Link the Confluence requirements page and related
tickets. State any scope boundary explicitly ("This task does not touch X").

## Task
What exactly to do, decide, analyze, or configure — numbered steps if multi-part.
For spikes, state the timebox ("Limit to ~2 hours; if it will take longer, raise it").
Name collaborators with @mentions, but the @mention is never the whole description.

## Details / Inputs        ← optional
Exact values needed to execute: client numbers, AM question numbers,
setting names/values, date ranges, attached reference data.

## Deliverable
Where the output lands: decision recorded, Confluence doc updated,
follow-up Stories created, or settings applied.
```

Quality bar: CRD-424 (phased analysis with deliverable), CRD-233 (exact question details), CRD-7 (timeboxed spike with precise data request). These are reference keys for maintainers — don't fetch them during a run. Anti-pattern to avoid: descriptions that only say who will figure out the work later.

For decision-type Tasks, add a closing-convention note at the end of the description:

```
_When resolved, append: DECISION: <outcome> — per <person>, <date>._
```

## Step 4: Preview, refine, confirm

Show **one** preview — metadata plus the full draft:

```
About to create CRD Task:

  Project:   CRD
  Type:      Task
  Summary:   <title>
  Parent:    <CRD-### — epic summary | (none)>
  Priority:  <name | (default)>

--- Description ---
<full markdown>
```

Then ask: **"Create this Task, or what would you refine?"**
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
  "issueTypeName": "Task",
  "summary": "<title>",
  "description": "<markdown>",
  "contentFormat": "markdown",
  "parent": "<CRD-### — omit if none>",
  "additional_fields": { "priority": { "name": "<name>" } }
}
```

Omit `additional_fields` unless a non-default priority was requested. If the API rejects the top-level `parent`, retry once with `additional_fields: { "parent": { "key": "CRD-###" } }`.

On success report: `Task created: https://preferredcredit.atlassian.net/browse/<KEY>`. On failure, surface the API error verbatim and stop.

## Important Guidelines

- **Strict trigger.** Only respond to explicit `/create-crd-task` invocation.
- **Confirmation is mandatory.** No Jira writes without an explicit `yes` at the preview.
- **Never fabricate Jira keys** — validate the parent epic; never guess corrections.
- **Omit, don't pad.** A missing section beats canned filler. But Task and Deliverable are the minimum — a one-line question is not a description.
- **Right type for the work.** If intake reveals this is actually a code/system change, steer to `/create-crd-story`; a defect, `/create-crd-bug`.
- **Don't set unused fields.** Labels, components, fix versions, story points, sprint, assignee — none are set at create time on this board (sprint and assignee are handled on the board after creation). Reporter defaults to the authenticated user; don't set it.
- **No Atlassian tools?** If the Atlassian MCP server isn't connected, stop and tell the user to connect it — don't attempt workarounds.

---
name: create-crd-task
description: Creates a Task in PCI's Jira CRD project (Credit Risk & Decisioning) for non-code work — decisions, tradeoff analysis, spikes/data pulls, AccountMate/client configuration, documentation, coordination. Invoke when the user wants to create/file a CRD task for non-implementation work. Code/system changes → create-crd-story; defects → create-crd-bug. Also runnable via /create-crd-task. Always previews and requires explicit confirmation before writing to Jira.
allowed-tools: AskUserQuestion, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getAccessibleAtlassianResources, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__searchJiraIssuesUsingJql, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getIssueLinkTypes, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createIssueLink
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
- `--link "<relationship> KEY"` — link this task to KEY using any relationship the Jira instance offers (e.g. `relates to`, `blocks`, `is blocked by`, `duplicates`, `is caused by`, `clones`). The last token is the key; the rest is the relationship phrase. Repeatable.

Any other text is freeform context — use it before asking questions.

## Step 1: Intake

From `$ARGUMENTS`, work out what is already known. Then ask conversationally for whatever is still missing — the core is:

1. **The ask** — what exactly needs to be done, decided, analyzed, or configured? For spikes: is there a timebox?
2. **Deliverable** — where does the output land? A recorded decision, an updated Confluence doc, follow-up stories created, settings applied?
3. **Related issues** *(optional)* — any other issues to link, and how they relate (e.g. "blocked by CRD-123", "duplicates CRD-456", "relates to CRD-789")? (Or pass `--link`.) Skip if none.

Ask about context (why now, related links) and exact inputs (client numbers, AM question/setting values, date ranges) only when the draft would be empty without them — otherwise those sections are simply omitted.

Don't interrogate — at most three rounds of questions, then draft; use follow-up rounds only when an answer genuinely needs clarifying. The parent epic is handled in Step 2 — don't ask for it here.

## Step 2: Resolve parent epic

Parent epics are encouraged for Tasks but not mandatory.

- If `--parent` was provided, validate with `getJiraIssue` (fields: `summary`, `issuetype`, `status`). It must exist and be an Epic — if not, tell the user what it actually is and ask again. Never guess corrections.
- If not, run `searchJiraIssuesUsingJql` with `project = CRD AND issuetype = Epic AND statusCategory != Done ORDER BY updated DESC`, fields `["summary", "status"]`, maxResults 50, and show the **10 most recently updated**. The user picks one, names another, or says none.

For all Jira calls, pass `preferredcredit.atlassian.net` as `cloudId`. If that's rejected, call `getAccessibleAtlassianResources` and use the `id` of the resource whose `url` contains `preferredcredit.atlassian.net`.

## Step 3: Resolve links

Skip this step entirely if no related issues were named.

1. **Discover the link catalog.** Call `getIssueLinkTypes` and read each type's `name`, `inward`, and `outward` phrasings. Use whatever the instance offers — don't assume a fixed set. (PCI's instance currently includes `1Relates` [relates to], `Blocks` [blocks / is blocked by], `Duplicate` [duplicates / is duplicated by], `Cloners` [clones / is cloned by], `Problem/Incident` [causes / is caused by], and `Predecessor` [precedes / is preceded by]; the `Polaris…`, `Translation`, and `Action item` types are system-managed — ignore them unless the user explicitly asks.)
2. **Pick the type that fits.** For each requested link, choose the type whose `inward`/`outward` phrasing best matches the relationship the user described. If nothing fits, fall back to `Relates` (`1Relates`) and say so; if the phrase is ambiguous, ask.
3. **Validate each target.** Call `getJiraIssue` (fields `summary`, `issuetype`, `status`) for every key. Keys that don't resolve go to a `missing[]` list shown in the preview — never link them, never guess corrections.
4. **Fix the direction from the type's own labels.** Follow the `createIssueLink` contract exactly: `inwardIssue` is the issue that *performs* the type's **outward** verb; `outwardIssue` is the issue on the **inward** (receiving) side. (Tool's own example: *"A is blocked by B"* → `inwardIssue: B, outwardIssue: A` — B blocks, so B is inward.) From the new task's side:
   - the task **performs** the outward verb — it *blocks / duplicates / causes / clones* the target → `inwardIssue: <NEW>, outwardIssue: <target>`
   - the task is on the **inward** side — it *is blocked by / is caused by* the target → `inwardIssue: <target>, outwardIssue: <NEW>`
   - symmetric types (`Relates`) → direction doesn't matter.
   If unsure how a link will read, create one and confirm its direction in Jira before adding the rest.

Carry each resolved link (`type name`, `inward key`, `outward key`, display phrase) into the preview and Step 6.

## Step 4: Draft

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

**Reflect gathered links in the body too.** Per team preference, every linked issue also appears in the description, not only as a native link — list them in `## Context` with their relationship. Keep existing inline citations and Confluence / non-Jira links as markdown.

Quality bar: CRD-424 (phased analysis with deliverable), CRD-233 (exact question details), CRD-7 (timeboxed spike with precise data request). These are reference keys for maintainers — don't fetch them during a run. Anti-pattern to avoid: descriptions that only say who will figure out the work later.

For decision-type Tasks, add a closing-convention note at the end of the description:

```
_When resolved, append: DECISION: <outcome> — per <person>, <date>._
```

## Step 5: Preview, refine, confirm

Show **one** preview — metadata plus the full draft:

```
About to create CRD Task:

  Project:   CRD
  Type:      Task
  Summary:   <title>
  Parent:    <CRD-### — epic summary | (none)>
  Priority:  <name | (default)>

Links to create:        ← omit this block if no links
  • is blocked by → CRD-456 — <summary>
  • duplicates    → CRD-123 — <summary>
Skipped (not found in Jira):
  • <BAD-KEY>

--- Description ---
<full markdown>
```

Then ask: **"Create this Task, or what would you refine?"**
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
  "issueTypeName": "Task",
  "summary": "<title>",
  "description": "<markdown>",
  "contentFormat": "markdown",
  "parent": "<CRD-### — omit if none>",
  "additional_fields": { "priority": { "name": "<name>" } }
}
```

Omit `additional_fields` unless a non-default priority was requested. If the API rejects the top-level `parent`, retry once with `additional_fields: { "parent": { "key": "CRD-###" } }`. On `createJiraIssue` failure, surface the API error verbatim and stop — don't attempt linking.

2. **Link each resolved target** from Step 3 by calling `createIssueLink` with the new task key, the chosen type `name`, and the inward/outward keys fixed in Step 3:

```json
{
  "cloudId": "preferredcredit.atlassian.net",
  "type": { "name": "<resolved link type, e.g. Blocks>" },
  "inwardIssue": { "key": "<inward key from Step 3>" },
  "outwardIssue": { "key": "<outward key from Step 3>" }
}
```

   Continue past per-link failures — collect them for the report.

3. **Report:**

```
Task created: https://preferredcredit.atlassian.net/browse/<KEY>

Linked <S>/<T> related items.        ← omit if no links
Failed links (if any):
  • <KEY>: <reason>
```

## Important Guidelines

- **Trigger.** Model-invocable: fire when the user wants to create/file a CRD task for non-code work (or runs `/create-crd-task`). Don't fire on mere discussion — only when a ticket is actually wanted. Code/system changes → `/create-crd-story`; a defect → `/create-crd-bug`. Confirmation before any Jira write remains mandatory.
- **Confirmation is mandatory.** No Jira writes without an explicit `yes` at the preview.
- **Never fabricate Jira keys** — validate the parent epic and every link target; unresolved keys are reported in the preview, never guessed.
- **Omit, don't pad.** A missing section beats canned filler. But Task and Deliverable are the minimum — a one-line question is not a description.
- **Right type for the work.** If intake reveals this is actually a code/system change, steer to `/create-crd-story`; a defect, `/create-crd-bug`.
- **Don't set unused fields.** Labels, components, fix versions, story points, sprint, assignee — none are set at create time on this board (sprint and assignee are handled on the board after creation). Reporter defaults to the authenticated user; don't set it.
- **No Atlassian tools?** If the Atlassian MCP server isn't connected, stop and tell the user to connect it — don't attempt workarounds.

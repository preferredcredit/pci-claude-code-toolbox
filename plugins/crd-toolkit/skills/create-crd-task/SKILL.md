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
- `--relates KEY` — create a `Relates` link to KEY. Repeatable.
- `--blocked-by KEY` — this task **is blocked by** KEY. Repeatable.
- `--blocks KEY` — this task **blocks** KEY. Repeatable.

Any other text is freeform context — use it before asking questions.

## Step 1: Intake

From `$ARGUMENTS`, work out what is already known. Then ask conversationally for whatever is still missing — the core is:

1. **The ask** — what exactly needs to be done, decided, analyzed, or configured? For spikes: is there a timebox?
2. **Deliverable** — where does the output land? A recorded decision, an updated Confluence doc, follow-up stories created, settings applied?
3. **Related/blocking tickets** *(optional)* — any tickets this relates to, is blocked by, or blocks? (Or pass `--relates` / `--blocked-by` / `--blocks`.) Skip if none.

Ask about context (why now, related links) and exact inputs (client numbers, AM question/setting values, date ranges) only when the draft would be empty without them — otherwise those sections are simply omitted.

Don't interrogate — at most three rounds of questions, then draft; use follow-up rounds only when an answer genuinely needs clarifying. The parent epic is handled in Step 2 — don't ask for it here.

## Step 2: Resolve parent epic

Parent epics are encouraged for Tasks but not mandatory.

- If `--parent` was provided, validate with `getJiraIssue` (fields: `summary`, `issuetype`, `status`). It must exist and be an Epic — if not, tell the user what it actually is and ask again. Never guess corrections.
- If not, run `searchJiraIssuesUsingJql` with `project = CRD AND issuetype = Epic AND statusCategory != Done ORDER BY updated DESC`, fields `["summary", "status"]`, maxResults 50, and show the **10 most recently updated**. The user picks one, names another, or says none.

For all Jira calls, pass `preferredcredit.atlassian.net` as `cloudId`. If that's rejected, call `getAccessibleAtlassianResources` and use the `id` of the resource whose `url` contains `preferredcredit.atlassian.net`.

## Step 3: Resolve link types & validate targets

Skip this step entirely if no related/blocking tickets were provided.

1. **Resolve link type names.** Call `getIssueLinkTypes`. Capture the canonical `name` of the `Relates` type (also accept the sort-prefixed `1Relates`) and — if any `--blocked-by`/`--blocks` targets exist — the `Blocks` type (accept sort-prefixed variants) plus its `inward`/`outward` labels for direction. If a *requested* type isn't found, report it and drop those targets; don't abort the skill.
2. **Validate each target.** Call `getJiraIssue` (fields `summary`, `issuetype`, `status`) for every link key. Keys that don't resolve go to a `missing[]` list shown in the preview — never link them, never guess corrections.

Carry the resolved links (type, direction, key, summary) into the preview and Step 6.

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

**Reflect gathered links in the body too.** Per team preference, every related/blocking ticket also appears in the description, not only as a native link — list them in `## Context`. Keep existing inline citations and Confluence / non-Jira links as markdown.

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
  • relates       → CRD-123 — <summary>
  • is blocked by  → CRD-456 — <summary>
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

2. **Link each target** from Step 3, using the new task key as `NEW`:
   - relates → `{ "type": { "name": "<Relates name>" }, "inwardIssue": { "key": "<target>" }, "outwardIssue": { "key": "<NEW>" } }`
   - `--blocks` (task blocks target) → `{ "type": { "name": "<Blocks name>" }, "inwardIssue": { "key": "<target>" }, "outwardIssue": { "key": "<NEW>" } }`
   - `--blocked-by` (target blocks task) → `{ "type": { "name": "<Blocks name>" }, "inwardIssue": { "key": "<NEW>" }, "outwardIssue": { "key": "<target>" } }`

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

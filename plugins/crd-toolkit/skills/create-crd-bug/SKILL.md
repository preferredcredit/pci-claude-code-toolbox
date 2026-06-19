---
name: create-crd-bug
description: Creates a Bug in PCI's Jira CRD project (Credit Risk & Decisioning) for a defect — environment, test data, repro steps, expected vs actual, impact. Invoke when the user wants to file/report a CRD bug or something working incorrectly. Enhancement ideas → create-crd-story. Also runnable via /create-crd-bug. Always previews and requires explicit confirmation before writing to Jira.
allowed-tools: AskUserQuestion, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getAccessibleAtlassianResources, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__searchJiraIssuesUsingJql, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getIssueLinkTypes, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createIssueLink
---

# Create CRD Bug

Creates a **Bug** in the `CRD` project at `preferredcredit.atlassian.net` in the team's standard format. The user is the subject-matter expert; this skill is the ghostwriter — it asks for the key points, drafts a clean ticket, and confirms before writing to Jira.

Bugs are defects: something that worked or was required works incorrectly. Enhancement ideas and cosmetic suggestions belong in `/create-crd-story`.

## Input

The user has provided: `$ARGUMENTS`

Recognized flags:
- `--title "..."` — bug summary. Drafted from context if omitted.
- `--parent CRD-###` — parent epic key.
- `--priority <name>` — Critical - Immediate, Highest, High, Medium, Low, Lowest. Default: leave unset (Jira defaults to Medium).
- `--relates KEY` — create a `Relates` link to KEY. Repeatable.
- `--blocked-by KEY` — this bug **is blocked by** KEY. Repeatable.
- `--blocks KEY` — this bug **blocks** KEY. Repeatable.

Any other text is freeform context — use it before asking questions.

## Step 1: Intake

From `$ARGUMENTS`, work out what is already known. Then ask conversationally for whatever is still missing (skip anything already covered):

1. **Where seen** — environment (Stage / QA / Prod) and channel if relevant (client portal, mobile, Gateway, NextGen)?
2. **How to reproduce** — the actions taken, in order, plus the test data used (account number, prequal reference, client ID, test SSN/DOB)?
3. **Expected vs actual** — what should have happened (cite the requirement ticket if one exists), and what happened instead? Any error message or API response — paste the text, not just a screenshot.
4. **Impact** — one line: who/what is affected? (This drives priority.)
5. **Related/blocking tickets** *(optional)* — any tickets this relates to (e.g. the requirement it violates), is blocked by, or blocks? (Or pass `--relates` / `--blocked-by` / `--blocks`.) Skip if none.

Don't interrogate — at most three rounds of questions, then draft; use follow-up rounds only when an answer genuinely needs clarifying. Gaps the user can't fill become omitted sections, not boilerplate. The parent epic is handled in Step 2 — don't ask for it here.

## Step 2: Resolve parent epic

Every recent CRD bug has a parent epic — treat it as expected.

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

**Title:** `<Area> - <specific symptom>`, e.g. `Client Portal - Prequalification reference number max length not enforced`. The area prefix (`Gateway`, `NextGen BC`, `Client Portal`, `Core`, `PCSM`, ...) stands in for the unused Components field. Use concrete symptom phrasing — "not showing", "not calculating", "erroring out", "incorrect" — never vague titles like "Error during prequal".

**Description** (markdown), from this template — include a section only when there's real content for it:

```
## Environment
Stage / QA / Prod, plus channel if relevant (client portal, mobile, ...).

## Test Data
Account number, prequal reference, client ID, test SSN/DOB used.

## Steps to Reproduce
1. Numbered actions, one user action per step.

## Expected Behavior
Explicit statement of the correct result. Cite the requirement ticket if one exists.

## Actual Behavior
What happened instead. Paste error messages and API responses as verbatim text —
searchable, not screenshot-only. Screenshots supplement, never replace, the text.

## Impact
One line: who/what is affected and how badly. This is the priority rationale.

## Root Cause / Dev Notes        ← optional, when known
Mechanism, class/method names, repo or Confluence links.
```

**Reflect gathered links in the body too.** Per team preference, every related/blocking ticket also appears in the description, not only as a native link — cite a related requirement ticket in `## Expected Behavior` and note blocking tickets in `## Root Cause / Dev Notes`. Keep existing inline citations and Confluence / non-Jira links as markdown.

Quality bar: CRD-193 (step-by-step repro with test account), CRD-172 (verbatim API error payload + researched constraint), CRD-184 (developer-written root cause). These are reference keys for maintainers — don't fetch them during a run. Anti-pattern to avoid: a screenshot with no text.

**Priority:** from the Impact line, pick a suggested priority when it's clearly not Medium (Prod-blocking → High or above; cosmetic → Low). Surface it on the preview's Priority line — don't run a separate confirmation round for it.

## Step 5: Preview, refine, confirm

Show **one** preview — metadata plus the full draft:

```
About to create CRD Bug:

  Project:   CRD
  Type:      Bug
  Summary:   <title>
  Parent:    <CRD-### — epic summary | (none — user opted out)>
  Priority:  <name | (default) | <name> — suggested from Impact; change it in your reply if wrong>

Links to create:        ← omit this block if no links
  • relates       → CRD-123 — <summary>
  • is blocked by  → CRD-456 — <summary>
Skipped (not found in Jira):
  • <BAD-KEY>

--- Description ---
<full markdown>
```

Then ask: **"Create this Bug, or what would you refine?"**
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
  "issueTypeName": "Bug",
  "summary": "<title>",
  "description": "<markdown>",
  "contentFormat": "markdown",
  "parent": "<CRD-### — omit if none>",
  "additional_fields": { "priority": { "name": "<name>" } }
}
```

Omit `additional_fields` unless a non-default priority was confirmed. If the API rejects the top-level `parent`, retry once with `additional_fields: { "parent": { "key": "CRD-###" } }`. On `createJiraIssue` failure, surface the API error verbatim and stop — don't attempt linking.

2. **Link each target** from Step 3, using the new bug key as `NEW`:
   - relates → `{ "type": { "name": "<Relates name>" }, "inwardIssue": { "key": "<target>" }, "outwardIssue": { "key": "<NEW>" } }`
   - `--blocks` (bug blocks target) → `{ "type": { "name": "<Blocks name>" }, "inwardIssue": { "key": "<target>" }, "outwardIssue": { "key": "<NEW>" } }`
   - `--blocked-by` (target blocks bug) → `{ "type": { "name": "<Blocks name>" }, "inwardIssue": { "key": "<NEW>" }, "outwardIssue": { "key": "<target>" } }`

   Continue past per-link failures — collect them for the report.

3. **Report:**

```
Bug created: https://preferredcredit.atlassian.net/browse/<KEY>

Linked <S>/<T> related items.        ← omit if no links
Failed links (if any):
  • <KEY>: <reason>
```

Remind the user to attach screenshots in the Jira UI if any were mentioned — this skill can't upload them.

## Important Guidelines

- **Trigger.** Model-invocable: fire when the user wants to file/report a CRD defect (or runs `/create-crd-bug`). Don't fire on mere discussion — only when a ticket is actually wanted. An enhancement request → `/create-crd-story`. Confirmation before any Jira write remains mandatory.
- **Confirmation is mandatory.** No Jira writes without an explicit `yes` at the preview.
- **Never fabricate Jira keys** — validate the parent epic and every link target; unresolved keys are reported in the preview, never guessed.
- **Repro or it didn't happen.** Steps to Reproduce, Expected, and Actual are the minimum bar. If the user genuinely can't reproduce it, record exactly what was observed and when.
- **Text over screenshots.** Always capture error text verbatim in the description; images rot and aren't searchable.
- **Right type for the work.** If intake reveals an enhancement request rather than a defect, steer to `/create-crd-story`.
- **Don't set unused fields.** Labels, components, fix versions, story points, sprint, assignee — none are set at create time on this board (sprint and assignee are handled on the board after creation). Reporter defaults to the authenticated user; don't set it.
- **No Atlassian tools?** If the Atlassian MCP server isn't connected, stop and tell the user to connect it — don't attempt workarounds.

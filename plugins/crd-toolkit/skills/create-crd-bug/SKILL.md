---
name: create-crd-bug
description: Creates a Bug in PCI's Jira CRD project (Credit Risk & Decisioning) using the stream team's standard format — environment, test data, repro steps, expected vs actual, and impact. Use ONLY when the user explicitly invokes /create-crd-bug. Never auto-trigger on natural language.
disable-model-invocation: true
allowed-tools: AskUserQuestion, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getAccessibleAtlassianResources, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__searchJiraIssuesUsingJql, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createJiraIssue
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

Any other text is freeform context — use it before asking questions.

## Step 1: Intake

From `$ARGUMENTS`, work out what is already known. Then ask conversationally for whatever is still missing (skip anything already covered):

1. **Where seen** — environment (Stage / QA / Prod) and channel if relevant (client portal, mobile, Gateway, NextGen)?
2. **How to reproduce** — the actions taken, in order, plus the test data used (account number, prequal reference, client ID, test SSN/DOB)?
3. **Expected vs actual** — what should have happened (cite the requirement ticket if one exists), and what happened instead? Any error message or API response — paste the text, not just a screenshot.
4. **Impact** — one line: who/what is affected? (This drives priority.)

Don't interrogate — at most three rounds of questions, then draft; use follow-up rounds only when an answer genuinely needs clarifying. Gaps the user can't fill become omitted sections, not boilerplate. The parent epic is handled in Step 2 — don't ask for it here.

## Step 2: Resolve parent epic

Every recent CRD bug has a parent epic — treat it as expected.

- If `--parent` was provided, validate with `getJiraIssue` (fields: `summary`, `issuetype`, `status`). It must exist and be an Epic — if not, tell the user what it actually is and ask again. Never guess corrections.
- If not, run `searchJiraIssuesUsingJql` with `project = CRD AND issuetype = Epic AND statusCategory != Done ORDER BY updated DESC`, fields `["summary", "status"]`, maxResults 50, and show the **10 most recently updated**. Ask the user to pick one or name another.
- If the user explicitly says no epic fits, proceed without a parent but note it in the preview.

For all Jira calls, pass `preferredcredit.atlassian.net` as `cloudId`. If that's rejected, call `getAccessibleAtlassianResources` and use the `id` of the resource whose `url` contains `preferredcredit.atlassian.net`.

## Step 3: Draft

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

Quality bar: CRD-193 (step-by-step repro with test account), CRD-172 (verbatim API error payload + researched constraint), CRD-184 (developer-written root cause). These are reference keys for maintainers — don't fetch them during a run. Anti-pattern to avoid: a screenshot with no text.

**Priority:** from the Impact line, pick a suggested priority when it's clearly not Medium (Prod-blocking → High or above; cosmetic → Low). Surface it on the preview's Priority line — don't run a separate confirmation round for it.

## Step 4: Preview, refine, confirm

Show **one** preview — metadata plus the full draft:

```
About to create CRD Bug:

  Project:   CRD
  Type:      Bug
  Summary:   <title>
  Parent:    <CRD-### — epic summary | (none — user opted out)>
  Priority:  <name | (default) | <name> — suggested from Impact; change it in your reply if wrong>

--- Description ---
<full markdown>
```

Then ask: **"Create this Bug, or what would you refine?"**
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
  "issueTypeName": "Bug",
  "summary": "<title>",
  "description": "<markdown>",
  "contentFormat": "markdown",
  "parent": "<CRD-### — omit if none>",
  "additional_fields": { "priority": { "name": "<name>" } }
}
```

Omit `additional_fields` unless a non-default priority was confirmed. If the API rejects the top-level `parent`, retry once with `additional_fields: { "parent": { "key": "CRD-###" } }`.

On success report: `Bug created: https://preferredcredit.atlassian.net/browse/<KEY>`. Remind the user to attach screenshots in the Jira UI if any were mentioned — this skill can't upload them. On failure, surface the API error verbatim and stop.

## Important Guidelines

- **Strict trigger.** Only respond to explicit `/create-crd-bug` invocation.
- **Confirmation is mandatory.** No Jira writes without an explicit `yes` at the preview.
- **Never fabricate Jira keys** — validate the parent epic; never guess corrections.
- **Repro or it didn't happen.** Steps to Reproduce, Expected, and Actual are the minimum bar. If the user genuinely can't reproduce it, record exactly what was observed and when.
- **Text over screenshots.** Always capture error text verbatim in the description; images rot and aren't searchable.
- **Right type for the work.** If intake reveals an enhancement request rather than a defect, steer to `/create-crd-story`.
- **Don't set unused fields.** Labels, components, fix versions, story points, sprint, assignee — none are set at create time on this board (sprint and assignee are handled on the board after creation). Reporter defaults to the authenticated user; don't set it.
- **No Atlassian tools?** If the Atlassian MCP server isn't connected, stop and tell the user to connect it — don't attempt workarounds.

---
name: create-crd-epic
description: Creates an Epic in PCI's Jira CRD project (Credit Risk & Decisioning) — a long-lived workstream bucket (goal, scope checklist, decision log) that Stories/Tasks/Bugs parent to. Invoke when the user wants to create/open a CRD epic or workstream grouping for a program/product phase. A single code change → create-crd-story; non-code work → create-crd-task; a defect → create-crd-bug. Also runnable via /create-crd-epic. Always previews and requires explicit confirmation before writing to Jira.
allowed-tools: AskUserQuestion, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getAccessibleAtlassianResources, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__searchJiraIssuesUsingJql, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getIssueLinkTypes, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createIssueLink
---

# Create CRD Epic

Creates an **Epic** in the `CRD` project at `preferredcredit.atlassian.net` in the team's standard format. The user is the subject-matter expert; this skill is the ghostwriter — it asks for the key points, drafts a clean ticket, and confirms before writing to Jira.

Epics are workstream buckets that Stories, Tasks, and Bugs parent to. They live a long time — the description doubles as a scope ledger and decision log, so it has to stand on its own. (Most past CRD epics have empty descriptions; this skill exists to end that.)

## Input

The user has provided: `$ARGUMENTS`

Recognized flags:
- `--title "..."` — epic summary. Drafted from context if omitted.
- `--parent CRD-###` — parent Initiative key.
- `--relates KEY` — create a `Relates` link to KEY (e.g. the driving idea or a related epic). Repeatable.
- `--blocked-by KEY` — this epic **is blocked by** KEY. Repeatable.
- `--blocks KEY` — this epic **blocks** KEY. Repeatable.

Any other text is freeform context — use it before asking questions.

## Step 1: Intake

From `$ARGUMENTS`, work out what is already known. Then ask conversationally for whatever is still missing — the core is:

1. **Goal** — who wants this and what outcome does it deliver? One or two sentences. Also: which program, product line, and phase does it belong to (e.g. CRS24, CFS / Water, MVP / Post MVP)? That feeds the title.
2. **Scope** — the concrete workstreams or deliverables, as a rough list. Known owners?
3. **Related/blocking tickets** *(optional)* — a driving idea/ticket or related epic this relates to, is blocked by, or blocks? (Or pass `--relates` / `--blocked-by` / `--blocks`.) These become native links. Skip if none. *(Child stories are not linked here — they attach via their own `--parent`.)*

Ask about out-of-scope items ("not for MVP", deferred work) and links (driving idea/ticket, Confluence requirements page) only if the user hasn't volunteered them — and if there are none, those sections are simply omitted.

Don't interrogate — at most three rounds of questions, then draft; use follow-up rounds only when an answer genuinely needs clarifying. The Goal is mandatory; everything else can be thin in v1 of a ticket. The parent Initiative is handled in Step 2 — don't ask for it here.

## Step 2: Resolve parent Initiative

CRD uses an **Initiative** issue type above Epic as the board's real grouping mechanism (labels and components are unused).

- If `--parent` was provided, validate with `getJiraIssue` (fields: `summary`, `issuetype`, `status`). It must exist and be an Initiative — if not, tell the user what it actually is and ask again. Never guess corrections.
- If not, run `searchJiraIssuesUsingJql` with `project = CRD AND issuetype = Initiative AND statusCategory != Done ORDER BY updated DESC`, fields `["summary", "status"]`, maxResults 50, and show the **10 most recently updated**. The user picks one, names another, or says none.

For all Jira calls, pass `preferredcredit.atlassian.net` as `cloudId`. If that's rejected, call `getAccessibleAtlassianResources` and use the `id` of the resource whose `url` contains `preferredcredit.atlassian.net`.

## Step 3: Resolve link types & validate targets

Skip this step entirely if no related/blocking tickets were provided. This covers **peer** relationships only (driving idea, related/blocking epics or initiatives) — child Stories/Tasks/Bugs attach via their own `--parent`, not here.

1. **Resolve link type names.** Call `getIssueLinkTypes`. Capture the canonical `name` of the `Relates` type (also accept the sort-prefixed `1Relates`) and — if any `--blocked-by`/`--blocks` targets exist — the `Blocks` type (accept sort-prefixed variants) plus its `inward`/`outward` labels for direction. If a *requested* type isn't found, report it and drop those targets; don't abort the skill.
2. **Validate each target.** Call `getJiraIssue` (fields `summary`, `issuetype`, `status`) for every link key. Keys that don't resolve go to a `missing[]` list shown in the preview — never link them, never guess corrections.

Carry the resolved links (type, direction, key, summary) into the preview and Step 6.

## Step 4: Draft

**Title:** `<Workstream> - <change> for <phase> <program/product>`, e.g. `Core - Client Setting updates for MVP CFS CRS24 go live`. Keep the MVP / Post MVP qualifier and product line (CFS / Water) in the title. Avoid bare bucket titles like "Core" or "Application Maint" that mean nothing without tribal knowledge. Question-form titles only for genuine discovery epics.

**Description** (markdown), from this template — include a section only when there's real content for it (exceptions: Goal is required, and the Decisions scaffold is always included):

```
## Goal        ← required, always
1–2 sentences naming the stakeholder and the outcome:
"<Team> wants <capability> so that <outcome>." or
"This Epic represents the work to <outcome>."

## Context & Links        ← optional
Links to the driving idea/ticket and the Confluence requirements page.

## Scope
1. Numbered checklist of concrete, verifiable workstreams.
2. Name an owner inline where known.
3. As child stories are created, link them on their line; mark items
   ✅ when done and ⚖️ when a decision is pending.

## Out of Scope / Deferred        ← optional but encouraged
- Explicit "not for MVP" / "create future work item" lines.

## Decisions
_Append as they happen:_ DECISION: <outcome> — per <person>, <date>.
```

Always include the `## Decisions` section with its append-convention line, even though it's empty at creation — it's the one deliberate scaffold this skill emits, so decisions land in the ticket instead of being buried in comments.

**Reflect gathered peer links in the body too.** Per team preference, any `--relates`/`--blocked-by`/`--blocks` target also appears in `## Context & Links`, not only as a native link. **Do not** convert the `## Scope` child-story checklist into native links — child items attach via their own `--parent`, and the checklist's ✅/⚖️ markers are a deliberate scope ledger. Keep Confluence / non-Jira links as markdown.

Quality bar: CRD-261 (scope ledger with owners and explicit exclusions), CRD-262 (checklist with status markers and story links), CRD-237 (goal statement that needs no tribal knowledge), CRD-124 (decision record). These are reference keys for maintainers — don't fetch them during a run. Anti-patterns to avoid: empty descriptions, one-line tautologies restating the title, and "requirements coming" placeholders.

## Step 5: Preview, refine, confirm

Show **one** preview — metadata plus the full draft:

```
About to create CRD Epic:

  Project:   CRD
  Type:      Epic
  Summary:   <title>
  Parent:    <CRD-### — initiative summary | (none)>

Links to create:        ← omit this block if no links
  • relates       → CRD-123 — <summary>
  • is blocked by  → CRD-456 — <summary>
Skipped (not found in Jira):
  • <BAD-KEY>

--- Description ---
<full markdown>
```

Then ask: **"Create this Epic, or what would you refine?"**
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
  "issueTypeName": "Epic",
  "summary": "<title>",
  "description": "<markdown>",
  "contentFormat": "markdown",
  "parent": "<CRD-### — omit if none>"
}
```

If the API rejects the top-level `parent`, retry once with `additional_fields: { "parent": { "key": "CRD-###" } }`. On `createJiraIssue` failure, surface the API error verbatim and stop — don't attempt linking.

2. **Link each target** from Step 3, using the new epic key as `NEW`:
   - relates → `{ "type": { "name": "<Relates name>" }, "inwardIssue": { "key": "<target>" }, "outwardIssue": { "key": "<NEW>" } }`
   - `--blocks` (epic blocks target) → `{ "type": { "name": "<Blocks name>" }, "inwardIssue": { "key": "<target>" }, "outwardIssue": { "key": "<NEW>" } }`
   - `--blocked-by` (target blocks epic) → `{ "type": { "name": "<Blocks name>" }, "inwardIssue": { "key": "<NEW>" }, "outwardIssue": { "key": "<target>" } }`

   Continue past per-link failures — collect them for the report.

3. **Report:**

```
Epic created: https://preferredcredit.atlassian.net/browse/<KEY>

Linked <S>/<T> related items.        ← omit if no links
Failed links (if any):
  • <KEY>: <reason>
```

## Important Guidelines

- **Trigger.** Model-invocable: fire when the user wants to create/open a CRD epic or workstream grouping (or runs `/create-crd-epic`). Don't fire on mere discussion — only when an epic is actually wanted. A single change → `/create-crd-story`; non-code work → `/create-crd-task`; a defect → `/create-crd-bug`. Confirmation before any Jira write remains mandatory.
- **Confirmation is mandatory.** No Jira writes without an explicit `yes` at the preview.
- **Never fabricate Jira keys** — validate the parent Initiative and every link target; unresolved keys are reported in the preview, never guessed.
- **No empty epics.** The Goal section is mandatory — if the user can't articulate the goal in two sentences, the epic isn't ready to create.
- **No placeholders.** Never write "requirements coming" — omit the section instead. (The `## Decisions` scaffold is the one deliberate exception.)
- **Don't set unused fields.** Labels, priority, components, fix versions, sprint, assignee — none are set at create time on this board. Reporter defaults to the authenticated user; don't set it.
- **Don't create child items.** Stories/Tasks/Bugs under this epic are created with their own skills, passing `--parent <new epic key>`.
- **No Atlassian tools?** If the Atlassian MCP server isn't connected, stop and tell the user to connect it — don't attempt workarounds.

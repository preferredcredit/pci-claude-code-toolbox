---
name: create-crd-initiative
description: Creates an Initiative in PCI's Jira CRD project (Credit Risk & Decisioning) — the top-level theme that groups Epics, in the team's standard format (goal, epic-scope checklist, out-of-scope lines, decision log). Invoke when the user wants to create/open a CRD initiative or a multi-epic theme/program. A single workstream → create-crd-epic; a concrete code/system change → create-crd-story. Also runnable via /create-crd-initiative. Always previews and requires explicit confirmation before writing to Jira.
allowed-tools: AskUserQuestion, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getAccessibleAtlassianResources, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getIssueLinkTypes, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createIssueLink
---

# Create CRD Initiative

Creates an **Initiative** in the `CRD` project at `preferredcredit.atlassian.net` in the team's standard format. The user is the subject-matter expert; this skill is the ghostwriter — it asks for the key points, drafts a clean ticket, and confirms before writing to Jira.

Initiatives sit at the **top of the CRD hierarchy** (above Epic): a long-lived theme or program that several Epics roll up to. They live a long time — the description doubles as a scope ledger and decision log, so it has to stand on its own. Quality reference: CRD-515.

A single workstream is an Epic (`/create-crd-epic`); a concrete code/system change is a Story (`/create-crd-story`).

## Input

The user has provided: `$ARGUMENTS`

Recognized flags:
- `--title "..."` — initiative summary. Drafted from context if omitted.
- `--relates KEY` — create a `Relates` link to KEY (e.g. a related initiative). Repeatable.
- `--blocked-by KEY` — this initiative **is blocked by** KEY. Repeatable.
- `--blocks KEY` — this initiative **blocks** KEY. Repeatable.

Any other text is freeform context — use it before asking questions.

## Step 1: Intake

From `$ARGUMENTS`, work out what is already known. Then ask conversationally for whatever is still missing — the core is:

1. **Goal** — who wants this and what outcome does it deliver? One to three sentences, plus the sub-goals it unlocks. Note any phasing (what phase one establishes; what's downstream).
2. **Scope (epics)** — the major workstreams this breaks into, as a rough list. Which already exist as epics (CRD keys), and which are still to create?
3. **Related/blocking tickets** *(optional)* — a related initiative this relates to, is blocked by, or blocks? (Or pass `--relates` / `--blocked-by` / `--blocks`.) These become native links. Skip if none. *(Child epics are not linked here — they attach via their own `--parent`.)*

Ask about out-of-scope items ("not now", deferred work) only if the user hasn't volunteered them — and if there are none, that section is simply omitted.

Don't interrogate — at most three rounds of questions, then draft; use follow-up rounds only when an answer genuinely needs clarifying. The Goal is mandatory; everything else can be thin in v1 of a ticket.

## Step 2: Resolve link types & validate targets

Skip this step entirely if no related/blocking tickets were provided. This covers **peer** relationships only (related/blocking initiatives) — child Epics attach via their own `--parent`, not here.

For all Jira calls, pass `preferredcredit.atlassian.net` as `cloudId`. If that's rejected, call `getAccessibleAtlassianResources` and use the `id` of the resource whose `url` contains `preferredcredit.atlassian.net`.

1. **Resolve link type names.** Call `getIssueLinkTypes`. Capture the canonical `name` of the `Relates` type (also accept the sort-prefixed `1Relates`) and — if any `--blocked-by`/`--blocks` targets exist — the `Blocks` type (accept sort-prefixed variants) plus its `inward`/`outward` labels for direction. If a *requested* type isn't found, report it and drop those targets; don't abort the skill.
2. **Validate each target.** Call `getJiraIssue` (fields `summary`, `issuetype`, `status`) for every link key. Keys that don't resolve go to a `missing[]` list shown in the preview — never link them, never guess corrections.

Carry the resolved links (type, direction, key, summary) into the preview and Step 5.

## Step 3: Draft

**Title:** a plain capability/theme phrase naming the business outcome — e.g. `Re-Pull Credit on Existing Accounts`. No component prefix and no phase/program qualifier (those are Epic conventions); an Initiative title is the thing a stakeholder recognizes at a glance. 4–10 words.

**Description** (markdown), from this template — include a section only when there's real content for it (exceptions: Goal is required, and the Decisions scaffold is always included):

```
## Goal        ← required, always
1–3 sentences naming the stakeholder and the outcome, then the sub-goals it
unlocks (bullets). Add a phasing note when the work is staged:
"Phase one establishes <X>; acting on it operationally is downstream."

## Scope (Epics)
1. Numbered list of the epics this initiative breaks into — a short description
   per line, with the epic's CRD key once it exists.
2. Mark items ✅ when done and ⚖️ when a decision is pending.
3. Add an "items to slot in as we go" sub-list for work not yet assigned to an epic.

## Out of Scope / Deferred        ← optional but encouraged
- Explicit "not now" / "future epic" lines, with the reason and likely owner.

## Decisions
_Append as they happen:_ DECISION: <outcome> — per <person>, <date>.
```

Always include the `## Decisions` section with its append-convention line, even though it's empty at creation — it's the one deliberate scaffold this skill emits, so decisions land in the ticket instead of being buried in comments.

**Reflect gathered peer links in the body too.** Per team preference, any `--relates`/`--blocked-by`/`--blocks` target also appears in the body (a short `Related work:` line under the Goal), not only as a native link. **Do not** turn the `## Scope (Epics)` checklist into native links — child epics attach via their own `--parent` (created with `/create-crd-epic`), and the checklist's ✅/⚖️ markers are a deliberate scope ledger.

Quality bar: CRD-515 (goal with phasing, epic-scope checklist with keys, decision log). Reference key for maintainers — don't fetch it during a run. Anti-patterns to avoid: empty descriptions, one-line tautologies restating the title, and "epics coming" placeholders.

## Step 4: Preview, refine, confirm

Show **one** preview — metadata plus the full draft:

```
About to create CRD Initiative:

  Project:   CRD
  Type:      Initiative
  Summary:   <title>

Links to create:        ← omit this block if no links
  • relates       → CRD-123 — <summary>
  • is blocked by  → CRD-456 — <summary>
Skipped (not found in Jira):
  • <BAD-KEY>

--- Description ---
<full markdown>
```

Then ask: **"Create this Initiative, or what would you refine?"**
- `yes`/`y` → create.
- `no`/`cancel` → abort with no Jira writes.
- Anything else → treat it as refinement direction: re-draft, re-show the preview, ask again.

Confirmation is mandatory — there is no `--yes` flag.

## Step 5: Create, link, and report

1. **Create.** Call `createJiraIssue`:

```json
{
  "cloudId": "preferredcredit.atlassian.net",
  "projectKey": "CRD",
  "issueTypeName": "Initiative",
  "summary": "<title>",
  "description": "<markdown>",
  "contentFormat": "markdown"
}
```

On `createJiraIssue` failure, surface the API error verbatim and stop — don't attempt linking.

2. **Link each target** from Step 2, using the new initiative key as `NEW`:
   - relates → `{ "type": { "name": "<Relates name>" }, "inwardIssue": { "key": "<target>" }, "outwardIssue": { "key": "<NEW>" } }`
   - `--blocks` (initiative blocks target) → `{ "type": { "name": "<Blocks name>" }, "inwardIssue": { "key": "<target>" }, "outwardIssue": { "key": "<NEW>" } }`
   - `--blocked-by` (target blocks initiative) → `{ "type": { "name": "<Blocks name>" }, "inwardIssue": { "key": "<NEW>" }, "outwardIssue": { "key": "<target>" } }`

   Continue past per-link failures — collect them for the report.

3. **Report:**

```
Initiative created: https://preferredcredit.atlassian.net/browse/<KEY>

Linked <S>/<T> related items.        ← omit if no links
Failed links (if any):
  • <KEY>: <reason>

Next: create child epics with /create-crd-epic --parent <KEY>, then list them in the Scope (Epics) section.
```

## Payload shape

```json
{
  "cloudId": "preferredcredit.atlassian.net",
  "projectKey": "CRD",
  "issueTypeName": "Initiative",
  "summary": "<title>",
  "description": "<markdown>",
  "contentFormat": "markdown"
}
```

Initiative is the top of the CRD hierarchy — there is **no parent**. Don't set `parent`, `priority` (defaults to Medium), `labels`, `components`, `fixVersions`, `assignee`, or `reporter` (Jira fills it from the authenticated user).

## Important Guidelines

- **Trigger.** Model-invocable: fire when the user wants to create/open a CRD initiative or a multi-epic theme/program (or runs `/create-crd-initiative`). Don't fire on mere discussion — only when an initiative is actually wanted. A single workstream → `/create-crd-epic`; a concrete change → `/create-crd-story`. Confirmation before any Jira write remains mandatory.
- **Confirmation is mandatory.** No Jira writes without an explicit `yes` at the preview.
- **Never fabricate Jira keys** — validate every link target; unresolved keys are reported in the preview, never guessed.
- **No empty initiatives.** The Goal section is mandatory — if the user can't state the goal in a few sentences, the initiative isn't ready to create.
- **No placeholders.** Never write "epics coming" — omit the section instead. (The `## Decisions` scaffold is the one deliberate exception.)
- **Don't set unused fields.** Labels, priority, components, fix versions, sprint, assignee, start/due dates — none are set at create time on this board. Reporter defaults to the authenticated user; don't set it.
- **Don't create child items.** Epics under this initiative are created with `/create-crd-epic`, passing `--parent <new initiative key>`; Stories/Tasks/Bugs hang off those epics.
- **No Atlassian tools?** If the Atlassian MCP server isn't connected, stop and tell the user to connect it — don't attempt workarounds.

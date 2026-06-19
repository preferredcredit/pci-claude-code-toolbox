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
- `--link "<relationship> KEY"` — link this initiative to a peer issue (e.g. a related/blocking initiative) using any relationship the Jira instance offers (`relates to`, `blocks`, `is blocked by`, `duplicates`, …). The last token is the key; the rest is the relationship phrase. Repeatable.

Any other text is freeform context — use it before asking questions.

## Step 1: Intake

From `$ARGUMENTS`, work out what is already known. Then ask conversationally for whatever is still missing — the core is:

1. **Goal** — who wants this and what outcome does it deliver? One to three sentences, plus the sub-goals it unlocks. Note any phasing (what phase one establishes; what's downstream).
2. **Scope (epics)** — the major workstreams this breaks into, as a rough list. Which already exist as epics (CRD keys), and which are still to create?
3. **Related issues** *(optional)* — a related/blocking initiative, and how it relates (e.g. "blocked by CRD-123", "relates to CRD-456")? (Or pass `--link`.) These become native links. Skip if none. *(Child epics are not linked here — they attach via their own `--parent`.)*

Ask about out-of-scope items ("not now", deferred work) only if the user hasn't volunteered them — and if there are none, that section is simply omitted.

Don't interrogate — at most three rounds of questions, then draft; use follow-up rounds only when an answer genuinely needs clarifying. The Goal is mandatory; everything else can be thin in v1 of a ticket.

## Step 2: Resolve links

Skip this step entirely if no related issues were named. This covers **peer** relationships only (related/blocking initiatives) — child Epics attach via their own `--parent`, not here.

For all Jira calls, pass `preferredcredit.atlassian.net` as `cloudId`. If that's rejected, call `getAccessibleAtlassianResources` and use the `id` of the resource whose `url` contains `preferredcredit.atlassian.net`.

1. **Discover the link catalog.** Call `getIssueLinkTypes` and read each type's `name`, `inward`, and `outward` phrasings. Use whatever the instance offers — don't assume a fixed set. (PCI's instance currently includes `1Relates` [relates to], `Blocks` [blocks / is blocked by], `Duplicate` [duplicates / is duplicated by], `Cloners` [clones / is cloned by], `Problem/Incident` [causes / is caused by], and `Predecessor` [precedes / is preceded by]; the `Polaris…`, `Translation`, and `Action item` types are system-managed — ignore them unless the user explicitly asks.)
2. **Pick the type that fits.** For each requested link, choose the type whose `inward`/`outward` phrasing best matches the relationship the user described. If nothing fits, fall back to `Relates` (`1Relates`) and say so; if the phrase is ambiguous, ask.
3. **Validate each target.** Call `getJiraIssue` (fields `summary`, `issuetype`, `status`) for every key. Keys that don't resolve go to a `missing[]` list shown in the preview — never link them, never guess corrections.
4. **Fix the direction from the type's own labels.** Follow the `createIssueLink` contract exactly: `inwardIssue` is the issue that *performs* the type's **outward** verb; `outwardIssue` is the issue on the **inward** (receiving) side. (Tool's own example: *"A is blocked by B"* → `inwardIssue: B, outwardIssue: A` — B blocks, so B is inward.) From the new initiative's side:
   - the initiative **performs** the outward verb — it *blocks / duplicates* the target → `inwardIssue: <NEW>, outwardIssue: <target>`
   - the initiative is on the **inward** side — it *is blocked by* the target → `inwardIssue: <target>, outwardIssue: <NEW>`
   - symmetric types (`Relates`) → direction doesn't matter.
   If unsure how a link will read, create one and confirm its direction in Jira before adding the rest.

Carry each resolved link (`type name`, `inward key`, `outward key`, display phrase) into the preview and Step 5.

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

**Reflect gathered peer links in the body too.** Per team preference, any linked issue also appears in the body (a short `Related work:` line under the Goal, with its relationship), not only as a native link. **Do not** turn the `## Scope (Epics)` checklist into native links — child epics attach via their own `--parent` (created with `/create-crd-epic`), and the checklist's ✅/⚖️ markers are a deliberate scope ledger.

Quality bar: CRD-515 (goal with phasing, epic-scope checklist with keys, decision log). Reference key for maintainers — don't fetch it during a run. Anti-patterns to avoid: empty descriptions, one-line tautologies restating the title, and "epics coming" placeholders.

## Step 4: Preview, refine, confirm

Show **one** preview — metadata plus the full draft:

```
About to create CRD Initiative:

  Project:   CRD
  Type:      Initiative
  Summary:   <title>

Links to create:        ← omit this block if no links
  • is blocked by → CRD-456 — <summary>
  • relates to    → CRD-123 — <summary>
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

Initiative is the top of the CRD hierarchy — there is **no parent**, and priority defaults to Medium, so neither is set. On `createJiraIssue` failure, surface the API error verbatim and stop — don't attempt linking.

2. **Link each resolved target** from Step 2 by calling `createIssueLink` with the new initiative key, the chosen type `name`, and the inward/outward keys fixed in Step 2:

```json
{
  "cloudId": "preferredcredit.atlassian.net",
  "type": { "name": "<resolved link type, e.g. Blocks>" },
  "inwardIssue": { "key": "<inward key from Step 2>" },
  "outwardIssue": { "key": "<outward key from Step 2>" }
}
```

   Continue past per-link failures — collect them for the report.

3. **Report:**

```
Initiative created: https://preferredcredit.atlassian.net/browse/<KEY>

Linked <S>/<T> related items.        ← omit if no links
Failed links (if any):
  • <KEY>: <reason>

Next: create child epics with /create-crd-epic --parent <KEY>, then list them in the Scope (Epics) section.
```

## Important Guidelines

- **Trigger.** Model-invocable: fire when the user wants to create/open a CRD initiative or a multi-epic theme/program (or runs `/create-crd-initiative`). Don't fire on mere discussion — only when an initiative is actually wanted. A single workstream → `/create-crd-epic`; a concrete change → `/create-crd-story`. Confirmation before any Jira write remains mandatory.
- **Confirmation is mandatory.** No Jira writes without an explicit `yes` at the preview.
- **Never fabricate Jira keys** — validate every link target; unresolved keys are reported in the preview, never guessed.
- **No empty initiatives.** The Goal section is mandatory — if the user can't state the goal in a few sentences, the initiative isn't ready to create.
- **No placeholders.** Never write "epics coming" — omit the section instead. (The `## Decisions` scaffold is the one deliberate exception.)
- **Don't set unused fields.** Labels, priority, components, fix versions, sprint, assignee, start/due dates — none are set at create time on this board. Reporter defaults to the authenticated user; don't set it.
- **Don't create child items.** Epics under this initiative are created with `/create-crd-epic`, passing `--parent <new initiative key>`; Stories/Tasks/Bugs hang off those epics.
- **No Atlassian tools?** If the Atlassian MCP server isn't connected, stop and tell the user to connect it — don't attempt workarounds.

---
name: create-pf-issue
description: >-
  Creates a Story (or Task) in PCI's Jira PF project (Public Facing) with the team's full field set —
  Description, Technical Details, QA Details, System Component, Product Manager, QA Person. Invoke when
  the user wants to create, file, or write up a PF ticket for public-facing work: the client portal,
  the iOS/Android apps, the mobile API, the origination endpoints, or RAPS. Use create-crd-story for
  the CRD project, create-issue for other projects, and create-change-from-release for a release CHANGE
  record. Always previews and requires explicit confirmation before writing to Jira.
allowed-tools: AskUserQuestion, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getAccessibleAtlassianResources, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__atlassianUserInfo, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__searchJiraIssuesUsingJql, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getJiraIssueTypeMetaWithFields, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__lookupJiraAccountId
---

# Create PF Issue

Creates a **Story** (or Task) in the `PF` project at `preferredcredit.atlassian.net` in the Public
Facing team's format. The user is the subject-matter expert; this skill is the ghostwriter — it asks
for the key points, drafts the ticket across PF's three body fields, and confirms before writing.

Read **`references/pf-fields.md`** before creating anything. It holds every field id, the System
Component list, the ADF templates, and the gotchas. The value of this skill is that PF's format is
convention rather than validation — Jira will happily accept a story with nothing but a summary, so
nothing except this workflow stops an under-filled ticket.

## When to use

- Public-facing work: client portal, `pci-mobile-ios` / `pci-mobile-android`, `Mobile.Api`,
  the origination endpoints, RAPS.
- The user has described a change and wants it turned into a ticket.

Not this skill: the CRD project → `/create-crd-story`. Other projects → `/create-issue`. A release
CHANGE record → `/create-change-from-release`. Mere discussion of work, or work already underway, is
not a request for a ticket — only fire when a ticket is actually wanted.

## Prerequisites

The **Atlassian MCP must be connected** (`getJiraIssue`, `createJiraIssue`, `lookupJiraAccountId`,
`searchJiraIssuesUsingJql`, `getJiraIssueTypeMetaWithFields`). If it isn't, stop and tell the user to
connect it — don't attempt workarounds. Pass `preferredcredit.atlassian.net` as `cloudId`; if that's
rejected, resolve the real id with `getAccessibleAtlassianResources`.

## Input

The user has provided: `$ARGUMENTS`

Recognized flags:

- `--title "..."` — summary. Drafted from context if omitted.
- `--parent PF-###` — parent epic key.
- `--type story|task` — issue type. Default `story`.
- `--component "..."` — System Component. Repeatable; inferred from the repo if omitted.

Any other text is freeform context describing the work — use it before asking questions.

## Step 1: Intake

From `$ARGUMENTS`, work out what's already known, then ask for what's missing. Skip anything covered:

1. **System Component** — which repos/systems does this touch? Infer a default from the working
   directory using the repo→component map in `references/pf-fields.md`, then confirm rather than asking
   cold. Multiple components are fine.
2. **What & why** — what's changing, what exists today, and who benefits.
3. **Technical notes** — files, config, versions, dependencies, known traps. Ask once; if the user
   doesn't have them, draft what's known and omit the rest.
4. **QA angle** — what QA should exercise to verify it.
5. **Done-when** — acceptance criteria in their words. Push for at least one.

At most three rounds of questions, then draft. Use follow-up rounds only when an answer genuinely needs
clarifying. Gaps the user can't fill become omitted content, not boilerplate.

## Step 2: Resolve people, component, and parent

- **People.** `lookupJiraAccountId` for the Product Manager (default **Carissa Schwinghammer**) and QA
  Person (default **Kelly Knier**). The accountIds in `references/pf-fields.md` are a fallback, not a
  substitute — they go stale.
- **Component.** Validate the chosen values against the twelve in `references/pf-fields.md`. If the
  user names something not on the list, ask rather than mapping it yourself.
- **Parent epic.** Opt-in — PF issues don't consistently live under epics, so **don't ask if the user
  didn't raise it**:

| Input | Action |
|---|---|
| Epic named (`--parent PF-412`, "story for epic PF-412", a pasted PF epic URL) | Validate with `getJiraIssue` (fields `summary`, `issuetype`, `status`). It must exist **and** be an Epic — if it's something else, say what it actually is and ask again. Never guess a correction. |
| Epic wanted but not named | `searchJiraIssuesUsingJql` with `project = PF AND issuetype = Epic AND statusCategory != Done ORDER BY updated DESC`, fields `["summary", "status"]`, maxResults 50. Show the 10 most recent; let the user pick. |
| Not mentioned | No parent. Don't ask. |

## Step 3: Draft

Three body fields, not one. Each has its own job — don't repeat content across them.

**Summary:** `<Component> - <imperative action>`, or `<Area>: <what changes>`. 6–12 words, naming
concrete artifacts. E.g. `Payables Report: Add Excel Export and Move Print View to Icon Buttons`.

**Description** (markdown) — the *what and why*, no implementation detail:

```
## Background
What exists today and why it's a problem. Name the navigation path and the current behavior.

---

## Requested changes
### 1. <Named change>
* Bullets that are decisions, each carrying its rationale.
* Bold the load-bearing constraints.
* Give exact strings/formats, then a worked example.
* Say what stays unchanged alongside what changes.

---

## Acceptance criteria
* [ ] Independently checkable, one behavior each. Cover the regression risks, not just the happy path.

---

## Out of scope        ← optional
* Named, with the reason and the follow-up implication.
```

**Technical Details** (ADF, `customfield_10059`) — the *where and how*. H2 `Technical notes`, then
bolded group labels with bullets. Exact paths in `code` marks, each with the reason it matters.
Concrete versions where they constrain the work. Net-new dependencies called out explicitly. Gotchas
stated *with their consequence* — not "give it its own config" but "give it its own config, or that
markup lands in the cells and stops the amounts being numeric." Surface decisions rather than making
them silently.

**QA Details** (ADF, `customfield_10066`) — what QA should exercise, and the cases that would otherwise
be missed. Concise: a testing note, not a test plan.

Depth scales with the work. A small config change gets a few bullets, not invented structure. Minimum
bar even for a one-line change: a couple of sentences of context and one acceptance criterion — never
an empty Description. `PF-431` is the quality bar; its characteristics are in
`references/pf-fields.md`.

## Step 4: Preview, refine, confirm

Show **one** preview — metadata plus every drafted field in full. `<TYPE>` below is the resolved issue
type from Step 1 — `Story` or `Task`. Carry it through every line; never print `Story` for a Task:

```
About to create PF <TYPE>:

  Project:    PF
  Type:       <TYPE>
  Summary:    <title>
  Parent:     <PF-### — epic summary | (none)>
  Component:  <System Component(s)>
  Product Mgr:<name>
  QA Person:  <name>

--- Description ---
<full markdown>

--- Technical Details ---
<rendered text>

--- QA Details ---
<rendered text>
```

Then ask: **"Create this `<TYPE>`, or what would you refine?"**

- `yes`/`y` → create.
- `no`/`cancel` → abort with no Jira writes.
- Anything else → treat as refinement direction: re-draft, re-show the preview, ask again.

Confirmation is mandatory — there is no `--yes` flag.

## Step 5: Create and report

Call `createJiraIssue`. ADF fields go in `additional_fields` as ADF JSON — `contentFormat` governs
`description` only (templates in `references/pf-fields.md`):

```json
{
  "cloudId": "preferredcredit.atlassian.net",
  "projectKey": "PF",
  "issueTypeName": "<TYPE — Story or Task, as resolved in Step 1>",
  "summary": "<title>",
  "description": "<markdown>",
  "contentFormat": "markdown",
  "parent": "<PF-### — omit if none>",
  "additional_fields": {
    "customfield_10059": { "type": "doc", "version": 1, "content": [ "<Technical Details ADF>" ] },
    "customfield_10066": { "type": "doc", "version": 1, "content": [ "<QA Details ADF>" ] },
    "customfield_11455": [ { "value": "ClientPortal.Web" } ],
    "customfield_10721": [ { "accountId": "<Product Manager>" } ],
    "customfield_10076": { "accountId": "<QA Person>" }
  }
}
```

If the API rejects the top-level `parent`, retry once with
`additional_fields: { "parent": { "key": "PF-###" } }`. If it rejects a System Component value, pull the
option ids from `getJiraIssueTypeMetaWithFields` (project `PF`, issueTypeId `10009` for a Story or
`10007` for a Task, `requiredFieldsOnly: false`) and retry with the ids **still wrapped in the array** —
`[ { "id": "<option id>" } ]`, never a bare object. On any other failure, surface the API error verbatim
and stop.

Report, using the same `<TYPE>`:

```
PF <TYPE> created: https://preferredcredit.atlassian.net/browse/<KEY>
```

## Common mistakes

| Mistake | Fix |
|---|---|
| Printing or sending `Story` when the user asked for a Task | The resolved type flows through the preview header, the confirm question, `issueTypeName`, the create-meta fallback id (`10009` / `10007`), and the report line. Substitute it in all five. |
| Product Manager passed as a bare object | It's a user **array** — `[{ "accountId": "..." }]`. QA Person is a single object. |
| Markdown string in Technical Details / QA Details | Those are ADF fields; `contentFormat` doesn't reach `additional_fields`. Build ADF JSON. |
| `Technical notes` written as bold text | It's an ADF `heading` at level 2. |
| Implementation detail in Description | Description is what/why; Technical Details is where/how. Don't duplicate. |
| Filling `Issue Description`, `Answer`, or `Requirements Question` | The team leaves those at their defaults. Leave them alone. |
| Prompting for a parent epic unprompted | Parent is opt-in. Silence means no parent. |
| Creating with no System Component | It's optional to Jira but load-bearing downstream — `create-change-from-release` reads it to build Release Steps. Always set it. |

## Important guidelines

- **Confirmation is mandatory.** No Jira writes without an explicit `yes` at the preview.
- **Never fabricate Jira keys.** Validate the parent epic; an unresolved key is reported, never guessed.
- **Omit, don't pad.** A missing section beats canned filler. Acceptance criteria are the exception —
  push for at least one testable criterion.
- **One story = one change.** If intake reveals several unrelated changes, suggest splitting and create
  them one at a time.
- **Don't set what the board handles** — priority, fixVersion, story points, labels, assignee, sprint.

## Scope

- **Issue linking is deliberately out of scope.** PF links get added in Jira by hand. If the team
  needs them, lift the link-resolution step wholesale from `crd-toolkit/create-crd-story` — it
  already handles `Relates` / `Blocks` / `Predecessor` / `Bundle Work` and the inward/outward
  direction problem.
- **This skill exists for PF specifically.** `engineer-toolkit/create-issue` already creates generic
  Stories in any project; the justification for a separate skill is PF's field set — the three body
  fields, System Component, and the two people defaults. Keep it earning that, or fold it back in.

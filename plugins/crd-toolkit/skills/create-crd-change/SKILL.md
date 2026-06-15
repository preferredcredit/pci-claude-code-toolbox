---
name: create-crd-change
description: Creates a "Change" issue in PCI's Jira CHANGE project that bundles implemented work items (provided explicitly and/or scraped from git commits on named branches) as Relates links. Use ONLY when the user explicitly invokes /create-crd-change. Never auto-trigger on natural language.
disable-model-invocation: true
allowed-tools: Read, Bash, AskUserQuestion, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getAccessibleAtlassianResources, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getJiraIssueTypeMetaWithFields, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getIssueLinkTypes, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__getJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createJiraIssue, mcp__818f7cdc-591c-45c2-94ed-e07f62819c00__createIssueLink
---

# Create Jira Change

Creates a release-record **Change** issue in the `CHANGE` project at `preferredcredit.atlassian.net` and links the work items it bundles via `Relates`. The skill:

1. Looks up the linked stories (with their descriptions).
2. **Drafts** the Change Description from those stories (and an optional `git diff`).
3. **Collaborates** with the user on Validation Plan, Release Steps, and Rollback Plan — asks for the key points, then writes the polished prose.
4. Confirms everything with the user before writing to Jira.

No subtasks — Jira workflow auto-spawns the Change Approval Sub-task.

## Input

The user has provided: `$ARGUMENTS`

Recognized flags:
- `--title "..."` — Change summary. Default: `Release YYYY-MM-DD`.
- `--key ABC-123` — Jira key to include. Repeatable.
- `--risk <1-9>` — Change Risk prefix (1 = highest, 9 = lowest).
- `--reason <name>` — Change Reason: Enhancement, Maintenance, Update, Upgrade, Repair, Refactor, New Product. Case-insensitive.
- `--classification <code>` — Change Classification override. Defaults to **SOFTDEV** without prompting; only pass this if the Change isn't a software release (ASM, BAR, DATA, FACILITIES, INF, SERVDESK). Case-insensitive.
- `--diff-base <ref>` — git ref (tag/SHA) for the prior release. When supplied, the skill runs `git diff <ref>..HEAD` to ground the Change Description draft. Optional.

Any other text in `$ARGUMENTS` is freeform context.

## Step 1: Collect missing inputs

Prompt for anything not supplied:

1. Title — blank uses auto-generated `Release {today}`.
2. Explicit Jira keys (space-separated, or blank).
3. Branches to scan for keys in commit messages (space-separated, or blank to skip).
4. Diff base — blank to skip. (PCI releases from `main`, so this is typically the prior release tag/SHA.)

Required-field values (Risk, Reason, Classification) are resolved in Step 3 once the live `allowedValues` arrive.

## Step 2: Resolve cloudId

Call `getAccessibleAtlassianResources`. Pick `name == "preferredcredit"` and capture its `id`. Abort if not found.

## Step 3: Confirm schema and resolve required custom fields

Call `getJiraIssueTypeMetaWithFields` with `projectIdOrKey: "CHANGE"`, `issueTypeId: "10026"`. Locate the issue type named `Change`; capture its id and the `allowedValues` for the three required custom fields.

Known fields handled by this skill: `summary`, `issuetype`, `project`, `priority`, `reporter` (Jira fills it from the authenticated user — do not set), `customfield_10086` (Change Risk), `customfield_10092` (Change Reason), `customfield_10100` (Change Classification). If any field outside this list is `required: true`, abort:

> The CHANGE / Change issue type now requires an unknown field `<fieldName>` (id `<fieldId>`). This skill needs to be updated to populate it before it can create Changes.

Resolve each required custom field against its `allowedValues` — never hardcode option ids. The option values in Jira are bare strings with no descriptions, so use the **Reference: Required-field values** section at the end of this file to explain the choices when prompting:

- **Change Risk (cf_10086).** From `--risk N`, match the option whose value starts with `"<N> -"` (e.g. `--risk 9` → `"9 - Issues are UNLIKELY..."`). Otherwise prompt via `AskUserQuestion` (header: "Change Risk") with all 9 options as labels, no pre-selected default. Before prompting, briefly explain the Probability × Impact matrix so the user can place their change; suggest the number that fits if the change's nature is already clear from the linked stories.
- **Change Reason (cf_10092).** From `--reason`, case-insensitive match against the 7 allowed values. Otherwise prompt (header: "Change Reason") with all 7 options, using the one-line glosses from the Reference section as option descriptions. No pre-selected default.
- **Change Classification (cf_10100).** Default to **SOFTDEV** — do not prompt. Resolve the SOFTDEV option id from the live `allowedValues`. Only deviate if `--classification` was explicitly supplied (case-insensitive match against the allowed values).

Reject any flag value that doesn't match a live `allowedValue`. Capture each resolved option `id` for the payload.

## Step 4: Confirm Relates link type

Call `getIssueLinkTypes`. Find the entry named `Relates` (also accept the sort-prefixed `1Relates`). Capture the canonical `name` for Step 10. Abort if not found and report the available link type names.

## Step 5: Gather work items

### 5a. Explicit `--key` values
For each key, call `getJiraIssue` with `fields: ["summary", "issuetype", "status", "description"]` and `responseContentFormat: "markdown"`. Capture summary, status, and description (drafting input). Keys that don't resolve go into a `missing[]` list for the preview — never guess corrections.

### 5b. Branch scans
For each named branch, run via Bash (shell-aware quoting — on PowerShell use `'%s%n%b'`, on bash `'%s%n%b'`):

```
git log <branch> --not main --pretty=format:%s%n%b
```

Extract keys with `\b[A-Z][A-Z0-9]+-\d+\b`. Validate each via `getJiraIssue` the same way as 5a (same fields, including `description`).

### Merge
Combine 5a + 5b; dedupe by key; drop `CHANGE-*` (self-referential); preserve order (explicit first, then commit order). It's valid to end with zero items — warn but proceed.

## Step 6: Gather diff context (if `--diff-base` supplied)

Run via Bash:

```
git diff --stat <base>..HEAD
git diff <base>..HEAD
```

Capture both into `diffContext`. If the diff exceeds ~600 lines, keep the full `--stat` plus only the first ~50 lines per top-changed file with a `[truncated]` marker — the intent is to give Step 7 enough to name components, not to read every line. If either git command errors, surface the error verbatim and set `diffContext = null` — do not abort the skill.

If no diff base was supplied, set `diffContext = null`.

## Step 7: Collaborative narrative drafting

Walk the four narrative fields **in order** (7a → 7d). For each, after producing the final text, ask via `AskUserQuestion` (header: the field name): **Accept (Recommended) / Edit / Skip**. *Edit* means: print the draft, accept revised text in-conversation, re-show until the user accepts. *Skip* omits the field from the payload (do not send blank or `null`).

If a field has nothing meaningful to say — the user has no input and the stories carry no signal — **prefer Skip over canned text**. Blank is better than boilerplate (see Important Guidelines).

Use the generic templates at the end of this file as drafting scaffolding. They're shape-only; the user's input and the linked stories fill the bracketed slots.

### 7a. Change Description (`customfield_10090`)

Draft a first cut from the linked tickets' summaries/descriptions plus `diffContext` if available. Match the Change Description template: always `## Release Summary` (one paragraph); optionally `## Component Changes` with `### <Component>` sub-headings, but **only** when 2+ logically distinct changes are bundled — otherwise narrate as one paragraph. Prefer concrete artifact names (tables, columns, services, commands) over abstract verbs. Include reassurances ("no change to existing X", "no impact on customer-facing flow") only when supported by the source material — do not invent.

Show the draft, then ask: **"Accept this, or what would you refine?"** Blank/`accept` accepts as-is; any other input is treated as refinement direction — re-draft and re-ask. To omit the field, the user types `skip`.

If zero work items were gathered, the draft is one sentence: `Empty Change (no work items linked at creation).` Still walk the Accept / Edit / Skip prompt.

### 7b. Validation Plan (`customfield_10091`)

**Ask first**: "What are the key things to verify after deploy? Tables, services, dashboards, sync results, anything specific (or `skip`)?"

The user provides 1–3 sentences of intent (or `skip`). Draft polished prose around their input using the Validation Plan template. Then show the draft → Accept / Edit / Skip.

### 7c. Release Steps (`customfield_10094`)

**Ask first**: "What's the deploy order? Database first? Any post-deploy commands like message-injector commands or manual seeds (or `skip`)?"

The user provides intent (or `skip`). Draft around their input using the Release Steps template. Show → Accept / Edit / Skip.

### 7d. Rollback Plan (`customfield_10101`)

**Ask first**: "What's the rollback story? Which services to redeploy, what to do about schema changes and data written by new code, pre-prod or prod context (or `skip`)?"

The user provides intent (or `skip`). Draft around their input using the Rollback Plan template. Show → Accept / Edit / Skip.

### ADF wrapping

All rich-text fields are sent as ADF (Atlassian Document Format) docs. Plain text only — no marks, links, or code blocks. Supported node types: `heading` (`attrs.level` 2 or 3), `paragraph`, `orderedList` → `listItem` → `paragraph` → `text`, `bulletList` → `listItem` → `paragraph` → `text`.

Canonical skeleton covering all node types this skill needs:

```json
{
  "type": "doc",
  "version": 1,
  "content": [
    { "type": "heading", "attrs": { "level": 2 }, "content": [{ "type": "text", "text": "Release Summary" }] },
    { "type": "paragraph", "content": [{ "type": "text", "text": "<paragraph text>" }] },
    { "type": "heading", "attrs": { "level": 3 }, "content": [{ "type": "text", "text": "<Component>" }] },
    { "type": "orderedList", "attrs": { "order": 1 }, "content": [
      { "type": "listItem", "content": [
        { "type": "paragraph", "content": [{ "type": "text", "text": "<step text>" }] }
      ]}
    ]}
  ]
}
```

## Step 8: Defaulted optional fields

Two short fields with serviceable defaults:

| Field | Field ID | Default |
|---|---|---|
| Dependencies | `customfield_10103` | "None." |
| Post-Change Monitoring | `customfield_10105` | "Developer will monitor App Insights for 24 hours post-deploy." |

Ask via `AskUserQuestion` (header: "Defaulted optional fields"):
- **Use both defaults (Recommended)** — populate both with the values above.
- **Customize one or more** — per field: keep default / replace text / leave blank.
- **Skip both** — omit both from the payload.

Wrap each populated field in a single-paragraph ADF doc. Blank fields are omitted entirely.

## Step 9: Preview and confirm

Print the summary block plus the full text of each accepted/edited narrative field, then require explicit confirmation:

```
About to create Jira Change:

  Project:        CHANGE
  Issue type:     Change (id <id>)
  Summary:        <title>
  Priority:       Medium
  Change Risk:    <full option value>
  Change Reason:  <option value>
  Classification: <option value>
  Diff base:      <ref or "(none)">

Narrative fields:
  Change Description (cf_10090):     <accepted | edited | skipped>
  Validation Plan    (cf_10091):     <accepted | edited | skipped>
  Release Steps      (cf_10094):     <accepted | edited | skipped>
  Rollback Plan      (cf_10101):     <accepted | edited | skipped>

Defaulted optional fields:
  Dependencies          (cf_10103):  <default | customized | blank>
  Post-Change Monitoring (cf_10105): <default | customized | blank>

Items to link (Relates):
  • <KEY-1> — <summary>
  • <KEY-2> — <summary>

Skipped (not found in Jira):
  • <BAD-KEY>

--- Field contents ---
[print the accepted text of each non-skipped narrative + defaulted field]
```

Then ask: `Create this Change and link the N items? (yes/no)`. Proceed only on explicit `yes` or `y`. Anything else aborts with no Jira writes.

There is no `--yes` flag. Confirmation is mandatory.

## Step 10: Create, link, and report

1. **Create.** Call `createJiraIssue` with the final payload. Capture the returned `key` (e.g. `CHANGE-10562`). On failure, surface the API error verbatim and stop — do not attempt linking.
2. **Link each item.** For each work-item key from Step 5, call `createIssueLink` with `{ "type": { "name": "<canonical Relates name from Step 4>" }, "inwardIssue": { "key": "<work item key>" }, "outwardIssue": { "key": "<new CHANGE-#### key>" } }`. Continue past per-link failures — collect them for the report.
3. **Report.**

```
Change created: https://preferredcredit.atlassian.net/browse/<CHANGE-####>

Linked <S>/<T> items as Relates.

Failed links (if any):
  • <KEY>: <reason>

Note: Jira workflow auto-creates the Change Approval Sub-task — no action needed.
```

## Payload shape (assembled across Steps 3, 7, 8)

```json
{
  "fields": {
    "project":           { "key": "CHANGE" },
    "issuetype":         { "id": "<id from Step 3>" },
    "summary":           "<title>",
    "priority":          { "id": "3" },
    "customfield_10086": { "id": "<Change Risk option id>" },
    "customfield_10092": { "id": "<Change Reason option id>" },
    "customfield_10100": { "id": "<Change Classification option id>" },
    "customfield_10090": <ADF doc — omit if Change Description was skipped>,
    "customfield_10091": <ADF doc — omit if Validation Plan was skipped>,
    "customfield_10094": <ADF doc — omit if Release Steps was skipped>,
    "customfield_10101": <ADF doc — omit if Rollback Plan was skipped>,
    "customfield_10103": <ADF doc — omit if blank>,
    "customfield_10105": <ADF doc — omit if blank>
  }
}
```

Use the issue type id from Step 3 — don't trust the literal `10026`. Don't set `description`, `labels`, `components`, `fixVersions`, `assignee`, or `reporter`. Skipped/blank fields are **omitted entirely** — do not send `null`.

## Reference: Generic field templates

Shape-only scaffolding for the Step 7 drafts. Square-bracket placeholders are intent slots — the user's input and the linked stories fill them in.

### Change Description

```
## Release Summary
[2–4 sentence narrative: what this release enables, who is affected,
 downstream impact, and any "no change to existing X" reassurances.]

## Component Changes      ← optional; include only when 2+ distinct components
### <Component>
[1–3 sentences on what changed and the user/operator-observable impact.]
```

### Validation Plan

```
After deploy:
1. Verify [schema/config change] is present — [specific objects or queries].
2. Confirm [process/sync/job] completes successfully — [evidence to check].
3. Spot-check [data] against [source of truth].
```

### Release Steps

```
1. Deploy [database/migrations].
2. Deploy [service(s)] in [order].
3. [Post-deploy command — e.g., "Submit X via message injector to seed Y"].
```

### Rollback Plan

```
Roll back by redeploying the previous [service name] release.
[Schema-change disposition: leave in place / revert, with reason —
 e.g., "the prior code does not reference the new columns, so leaving
 them is non-destructive"].
[Data-state disposition: inert under old code / needs cleanup, with reason].
[Pre-prod vs prod context].
```

## Reference: Required-field values

The Jira option values carry no descriptions — this section is the context the skill gives the user when prompting in Step 3.

### Change Risk (cf_10086) — a Probability × Impact matrix

Each option encodes how *likely* issues are and how *big* the blast radius would be. 9 is the safest, 1 the riskiest:

| | **Low impact**(little/no effect) | **Medium impact**(moderate / dept-level) | **High impact**(major / company-wide) |
|---|---|---|---|
| **Unlikely** | 9 | 6 | 5 |
| **Possible** | 8 | 4 | 2 |
| **Very likely** | 7 | 3 | 1 |

Rules of thumb for developer-driven Changes:
- **9** — additive or telemetry-only changes; nothing existing is altered.
- **6** — alters active business logic or introduces schema changes, but failure would be contained to one department/system.
- **5 or lower** — touches company-wide flows (origination decisioning, payments, customer-facing paths); rare for routine releases and will draw approver scrutiny.

### Change Reason (cf_10092)

| Value | Use when |
|---|---|
| Enhancement | Net-new behavior or capability added to an existing system |
| Maintenance | Routine upkeep or small corrective updates |
| Update | Modifying existing functionality, configuration, or data |
| Upgrade | Version bump of a platform, framework, or third-party dependency |
| Repair | Fixing something broken in production |
| Refactor | Restructuring code with no intended behavior change |
| New Product | First release of a brand-new system or product |

Most developer releases are **Enhancement** (net-new) or **Maintenance** (corrective).

### Change Classification (cf_10100)

Department/area codes. This skill always uses **SOFTDEV** (software development) — it covers every developer-driven release this skill exists for, so it is applied silently without prompting. The other codes (ASM, BAR, DATA, FACILITIES, INF, SERVDESK) belong to other teams' change processes and are reachable only via the `--classification` flag.

## Important Guidelines

- **Strict trigger.** Only respond when the user explicitly invokes `/create-crd-change`. Never auto-fire on natural language mentioning Jira, change, or release.
- **Never create subtasks.** The Jira workflow auto-spawns a `Change Approval Sub-task`. The skill must not create subtasks of any kind.
- **Never fabricate Jira keys.** If `--key` references something that doesn't exist, exclude it from the link list and call it out in the preview. Do not guess corrections.
- **Confirmation is mandatory.** Always show the preview and require an explicit `yes`/`y` before any write to Jira.
- **Standard `description` stays blank.** The narrative goes into `customfield_10090` ("Change Description"), which is what humans actually use. Do not populate the built-in `description` field.
- **Re-discover schema each run.** Do not hardcode the `Change` issue type id, the option ids for Change Risk / Reason / Classification, the `Relates` link type name, or the cloudId. Always look them up via MCP so the skill stays correct if Jira admins rename or reconfigure.
- **Never invent option ids.** Resolve `--risk`, `--reason`, `--classification` against the live `allowedValues` returned by `getJiraIssueTypeMetaWithFields` in Step 3.
- **No `Bundle Work` or `Resolve` link types.** Only `Relates` in this version. If the user needs those, they can edit the link in the Jira UI after creation.
- **Never emit canned generic text.** If a narrative field has nothing meaningful to say from the user's input or the linked stories, skip the field instead. Generic boilerplate ("validate functionality of linked work items", "deploy via standard release pipeline", "redeploy the previous release tag") is worse than blank.

# CHANGE project — field & option reference

Everything here is for the **Change Management** project on `preferredcredit.atlassian.net`
(cloudId = `preferredcredit.atlassian.net`; if a tool rejects the site URL, resolve the real cloud id
with `getAccessibleAtlassianResources` and use that). These IDs were verified from the project's create-metadata
and from existing changes CHANGE-10473 (Mobile 6.26.0) and CHANGE-10807 (upload-docs hotfix). If a
`createJiraIssue` call ever rejects an option id, re-pull the metadata with
`getJiraIssueTypeMetaWithFields` (project `CHANGE`, issueTypeId `10026`, `requiredFieldsOnly: false`).

## Identifiers

- Project key: `CHANGE` (id `10419`)
- Issue type: **Change**, id `10026`
- Issue-link type for relating release issues: **`1Relates`** (inward/outward both `relates to`, id `10003`)

## Required fields (creation fails without these)

`summary`, Change Risk (`customfield_10086`), Change Reason (`customfield_10092`),
Change Classification (`customfield_10100`) — plus project/issuetype/reporter which are set implicitly.

## Field map

| Field | Field id | Type | Notes |
|---|---|---|---|
| Approver | `customfield_10107` | user | `{ "accountId": "..." }` — auto-creates the approval sub-task |
| Validator | `customfield_10084` | user | `{ "accountId": "..." }` |
| Change Start Date | `customfield_10099` | datetime | **optional**; release date/time, Central, e.g. `2026-06-19T09:00:00-05:00` |
| Change Completion Date (end date) | `customfield_10093` | datetime | **optional**; Central, e.g. `2026-07-30T07:00:00-05:00` |
| Change Reason | `customfield_10092` | option | see options below; **team default = Enhancement (10160)** |
| Change Classification | `customfield_10100` | option | see options below |
| Change Risk | `customfield_10086` | option | see options below |
| Environment | `customfield_10095` | option | see options below |
| Needs CRB | `customfield_10104` | option | Y `10468` / N `10469` |
| Application | `customfield_10108` | cascading | **usually left blank** |
| Release Steps | `customfield_10094` | ADF | bullet list of system components (see template) |
| Issue Description | `customfield_10072` | ADF | blank panel template (see template) |
| Request Type | `customfield_10010` | JSM request type | set to `"2505"` (the "Change" request type, service desk 119) — pass the id as a plain string |
| System Component (on PF issues, not CHANGE) | `customfield_11455` | multi-option | read from release issues to build Release Steps |

### Change Reason options (`customfield_10092`)
Enhancement `10160` · Maintenance `10161` · New Product `10162` · Refactor `10163` · Repair `10164` ·
Update `10165` · Upgrade `10166`

### Change Classification options (`customfield_10100`)
ASM `10461` · BAR `10462` · DATA `10463` · FACILITIES `10464` · INF `10465` · SERVDESK `10466` ·
**SOFTDEV `10467`** (software releases use SOFTDEV)

### Change Risk options (`customfield_10086`) — risk ladder 9 (lowest) → 1 (highest)
`10151` = "9 - Issues are UNLIKELY and would have LITTLE/NO EFFECT … (Low/Low)"  ← typical release default
`10152` 8 · `10153` 7 · `10154` 6 · `10155` 5 · `10156` 4 · `10157` 3 · `10158` 2 · `10159` 1 (High/High)

### Environment options (`customfield_10095`)
**Production `10470`** · Stage `10471` · QA `10472` · Dev `10473` · St. Cloud Data Center `18008` ·
Minneapolis/St. Paul Data Center `18009`

## Typical values for a mobile/API release change

```
Change Risk        = 10151 (9 - Low/Low)
Change Reason      = 10160 (Enhancement)  # team default; override only if asked
Change Classification = 10467 (SOFTDEV)
Environment        = 10470 (Production)
Needs CRB          = 10468 (Y)
Application         = <leave blank>
```

## People (accountId hints — re-verify with lookupJiraAccountId, IDs can be wrong/stale)

| Name | accountId |
|---|---|
| Carissa Schwinghammer (default Approver) | `5a25575d8c316e43f3b13876` |
| Kelly Knier (default Validator) | `5a27ce52ea677a37e8eb263b` |

Assignee = the dev running the skill; get their accountId from `atlassianUserInfo`.

## ADF templates

### Release Steps (`customfield_10094`) — one bullet per distinct System Component
Replace the list items with the actual distinct system components in the release
(e.g. `pci-mobile-ios`, `pci-mobile-android`, `Mobile.Api`). The user adds versions/links manually after.

```json
{ "type": "doc", "version": 1, "content": [
  { "type": "paragraph", "content": [ { "type": "text", "text": "Release the following:" } ] },
  { "type": "bulletList", "content": [
    { "type": "listItem", "content": [ { "type": "paragraph", "content": [ { "type": "text", "text": "Mobile.Api" } ] } ] }
  ] }
] }
```

### Issue Description (`customfield_10072`) — blank panel template (matches existing changes)

```json
{ "type": "doc", "version": 1, "content": [
  { "type": "panel", "attrs": { "panelType": "info" }, "content": [
    { "type": "paragraph", "content": [ { "type": "text", "text": "Currently", "marks": [ { "type": "strong" } ] } ] },
    { "type": "paragraph", "content": [ { "type": "text", "text": "[functionality already in place]" } ] } ] },
  { "type": "panel", "attrs": { "panelType": "info" }, "content": [
    { "type": "paragraph", "content": [ { "type": "text", "text": "As A", "marks": [ { "type": "strong" } ] } ] },
    { "type": "paragraph", "content": [ { "type": "text", "text": "[user role]" } ] } ] },
  { "type": "panel", "attrs": { "panelType": "info" }, "content": [
    { "type": "paragraph", "content": [ { "type": "text", "text": "I want/need", "marks": [ { "type": "strong" } ] } ] },
    { "type": "paragraph", "content": [ { "type": "text", "text": "[desired feature or change]" } ] } ] },
  { "type": "panel", "attrs": { "panelType": "info" }, "content": [
    { "type": "paragraph", "content": [ { "type": "text", "text": "Because", "marks": [ { "type": "strong" } ] } ] },
    { "type": "paragraph", "content": [ { "type": "text", "text": "[value/benefit]" } ] } ] },
  { "type": "panel", "attrs": { "panelType": "info" }, "content": [
    { "type": "paragraph", "content": [ { "type": "text", "text": "Notes", "marks": [ { "type": "strong" } ] } ] },
    { "type": "paragraph", "content": [ { "type": "text", "text": "[any additional notes]" } ] } ] }
] }
```

## Gotchas

- **Approval sub-task auto-generates.** Setting the Approver field creates a "Change Approval Needed
  <name>" sub-task (issue type `Change Approval Sub-task`, id `10021`). Do not create it by hand. If the
  approver is changed later, the sub-task follows the new approver.
- **Version "Related Work" is manual.** There is no MCP/REST endpoint exposed here to add a related-work
  entry to a release version. Always hand the user the click-path:
  Releases → the version → ⋯ menu → **Add related work** → paste the CHANGE url.
- **Large JQL results spill to a file.** `searchJiraIssuesUsingJql` for a release often exceeds the
  token cap and is saved to a `tool-results` file — parse it with PowerShell (`ConvertFrom-Json`),
  not by re-reading raw.

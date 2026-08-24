# PF project — field & format reference

Everything here is for the **Public Facing** project on `preferredcredit.atlassian.net`
(pass that string as `cloudId`; if a tool rejects it, resolve the real id with
`getAccessibleAtlassianResources` — it is `19ff5866-fc24-4369-81c2-4b8de43058a3`).

IDs verified 2026-08-20 from PF-431 (`getJiraIssue` with `expand: names`) and from
`getJiraIssueTypeMetaWithFields` on project `PF`.

## Project & issue types

| Thing | Value |
|---|---|
| Project key | `PF` — "Public Facing" (id `10472`) |
| Story | issue type id `10009` |
| Task | issue type id `10007` |
| Epic | issue type id `10000` |

**Only `summary` is actually required** to create a PF Story (plus project/issuetype/reporter, which
are implicit). Everything below is team convention, not Jira enforcement — which is the whole reason
this skill exists. Don't treat an optional field as skippable just because the API would accept it.

## Fields this skill writes

| Field | ID | Type | Payload shape |
|---|---|---|---|
| Summary | `summary` | string | plain string |
| Description | `description` | ADF | markdown string + `contentFormat: "markdown"` |
| Technical Details | `customfield_10059` | ADF | **ADF JSON** (see templates) |
| QA Details | `customfield_10066` | ADF | **ADF JSON** (see templates) |
| System Component | `customfield_11455` | multi-option | `[{ "value": "ClientPortal.Web" }]` |
| Product Manager | `customfield_10721` | **user array** | `[{ "accountId": "..." }]` |
| QA Person | `customfield_10076` | single user | `{ "accountId": "..." }` |
| Parent epic | `parent` | issue | `"PF-###"` top-level; fallback `additional_fields.parent.key` |

## Fields to leave alone

PF carries template fields the team does not fill — PF-431 leaves every one of them at its default.
Do not populate them:

| Field | ID | Default state |
|---|---|---|
| Issue Description | `customfield_10072` | Unfilled info panels (`Currently / As A / I want/need / Because / Notes`) |
| Answer | `customfield_10070` | `1.` |
| Requirements Question | `customfield_10079` | `1.` |
| Client Maintenance Description | `customfield_11201` | Unfilled panels (`Previous Setting / New Setting`) |

The user-story framing goes in `description`, not in Issue Description.

Also not set at create time: priority, fixVersion, story points, labels, components, assignee, sprint.
Reporter defaults to the authenticated user.

## System Component values (`customfield_11455`)

Components track the repos being changed. Multi-select — set every component the work touches.

```
ClientPortal.Web                ClientPortal.Sidecar.Web
ClientPortal.DynamicContent     Mobile.Api
pci-mobile-android              pci-mobile-ios
PublicFacing.Default.Endpoint   PublicFacingServices BC
Origination.Paperless.Endpoint  Origination.Default.Endpoint
Raps.Database                   Raps.Model
```

Only one option id is confirmed: `ClientPortal.Web` = `19836`. Pass values by `value`, not `id`. If
Jira rejects the value form, pull the option ids from
`getJiraIssueTypeMetaWithFields` (project `PF`, issueTypeId `10009`, `requiredFieldsOnly: false`).

**Repo → component mapping** for inferring the default from the working directory:

| Repo / path signal | Component |
|---|---|
| `pci-mobile-ios` | `pci-mobile-ios` |
| `pci-mobile-android` | `pci-mobile-android` |
| `PCI.ClientPortal.Web` | `ClientPortal.Web` |
| Mobile API repo | `Mobile.Api` |
| RAPS model / database work | `Raps.Model` / `Raps.Database` |

Infer, then confirm — never set it silently. If the repo doesn't map to a known component, ask.

## People (accountId hints — re-verify with `lookupJiraAccountId`, IDs go stale)

| Role | Name | accountId |
|---|---|---|
| Product Manager (default) | Carissa Schwinghammer | `5a25575d8c316e43f3b13876` |
| QA Person (default) | Kelly Knier | `5a27ce52ea677a37e8eb263b` |

Same two people as the CHANGE project's Approver/Validator, different roles here.

## ADF templates

`description` accepts markdown with `contentFormat: "markdown"`. The two custom rich-text fields do
**not** — they need ADF JSON in `additional_fields`, same convention as
`create-change-from-release`.

### Technical Details (`customfield_10059`)

H2 `Technical notes`, then bolded group labels with bullets under each. Structure from PF-431:

```json
{ "type": "doc", "version": 1, "content": [
  { "type": "heading", "attrs": { "level": 2 },
    "content": [ { "type": "text", "text": "Technical notes" } ] },
  { "type": "paragraph",
    "content": [ { "type": "text", "text": "Files", "marks": [ { "type": "strong" } ] } ] },
  { "type": "bulletList", "content": [
    { "type": "listItem", "content": [ { "type": "paragraph", "content": [
      { "type": "text", "text": "Table config: " },
      { "type": "text", "text": "path/to/File.js", "marks": [ { "type": "code" } ] },
      { "type": "text", "text": " — why this file matters" }
    ] } ] }
  ] }
] }
```

File paths, config keys, and code identifiers take `{ "type": "code" }` marks. Group labels are
paragraphs with a `strong` mark — not headings. Use as many groups as the work needs
(PF-431 uses `Files`, `New dependency`, `Export configuration gotchas`).

### QA Details (`customfield_10066`)

Plain prose or a short bullet list:

```json
{ "type": "doc", "version": 1, "content": [
  { "type": "paragraph", "content": [ { "type": "text", "text": "<what QA should exercise>" } ] }
] }
```

## Quality bar — PF-431

`PF-431` ("Payables Report: Add Excel Export and Move Print View to Icon Buttons") is the reference
ticket for Description and Technical Details. Read it if a run needs calibration.

**Description** — markdown, `---` rules between major sections:

```
## Background          what exists today and why it's a problem
## Requested changes   ### numbered sub-changes, bullets that are decisions
## Acceptance criteria * [ ] checkboxes, one behavior each
## Out of scope        named, with the reason
```

What makes it good:

- **Requirements carry their rationale** — "must land in Excel as numbers, not text, so clients can
  total them."
- **Contrast with existing behavior is explicit** — "differs from the print view, which does show the
  Total row and keeps doing so." Stops a developer 'fixing' the wrong thing.
- **Exact strings and formats, with a worked example** — `Payments-08192026-08202026.xlsx`.
- **Environment constraints named where they bind** — Font Awesome 4.7 not FA5; Bootstrap 3.3.7's
  `btn-sm`, not `btn-xs`.
- **Acceptance criteria encode the traps**, not just the happy path — "Re-running the report with a
  different date range produces a filename reflecting the new range."
- **Out of scope names the sibling that will look inconsistent** rather than going silent.

QA Details has no exemplar yet — PF-431 holds a placeholder. Keep that field concise until a real
example exists.

## Gotchas

- **Product Manager is a user ARRAY.** `customfield_10721` takes `[{ "accountId": "..." }]`. Passing a
  bare object fails. QA Person (`customfield_10076`) is a single object — the two differ.
- **`contentFormat` governs `description` only.** Custom ADF fields in `additional_fields` need real
  ADF JSON; a markdown string lands as literal text or is rejected.
- **`Technical notes` is a heading, not bold text.** ADF `heading` level 2 — matches existing tickets.
- **Nothing is required but the summary.** A half-filled PF story creates successfully. The preview
  gate is the only thing that catches an under-drafted ticket.
- **Two Atlassian MCP servers may be present.** The working one in this environment is the claude.ai
  Atlassian connector (the `getJiraIssue` / `createJiraIssue` tool family). `plugin:atlassian:atlassian`
  is separate and may be unauthorized.

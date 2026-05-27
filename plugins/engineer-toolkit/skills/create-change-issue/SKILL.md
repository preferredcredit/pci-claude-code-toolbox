---
name: create-change-issue
description: Use when creating a Jira CAB ticket in the CHANGE (Change Management) project — these tickets use a different field layout from CRD/CO. Triggers on phrases like "create a change ticket", "open a CAB", "deploy X", "Updated X", or any mention of CHANGE-#### tickets that need shaping.
---

# Create CHANGE Issue

Create a Jira ticket in the **CHANGE** (Change Management) project with the right fields populated. CHANGE is a Service Desk project with a different field layout from CRD/CO — the standard `description` field is unused; content lives in **Change Description** (`customfield_10090`), and three select fields are required at create time.

## Project Configuration

- **CloudId:** the Jira CloudId from `## Configuration` in CLAUDE.md (referred to as `<CloudId>` below)
- **Project key:** `CHANGE`
- **Issue type:** `Change` (id `10026`)
- **Default assignee:** the User Account ID from `## Configuration` in CLAUDE.md
- **Default reporter:** same as assignee unless specified

## The Two Gotchas

These are the things that will fail silently or noisily if you skip them:

1. **Content goes in `customfield_10090` (Change Description), NOT `description`.** The standard `description` field is unused on this project's UI; if you put content there, the ticket appears blank.
2. **Textarea custom fields require ADF format** despite the schema reporting `textarea`. Passing markdown errors with `Failed to convert markdown to adf`. You must pass an ADF doc object AND set `contentFormat: "adf"` on the edit/create call. To clear `description`, pass `{"type":"doc","version":1,"content":[]}` — passing `null` errors.

## Required Fields

| Field | Key | Type | Notes |
|---|---|---|---|
| Summary | `summary` | string | Concise: "Updated Socure Matching Logic", "Deploy Foo Service", etc. |
| Issue Type | `issuetype` | `{"id":"10026"}` | Always Change |
| Project | `project` | `{"key":"CHANGE"}` | |
| Reporter | `reporter` | `{"accountId":"..."}` | Auto-defaults; usually fine |
| **Change Risk** | `customfield_10086` | option | Pick from PCI risk matrix (see below) |
| **Change Reason** | `customfield_10092` | option | Enhancement / Maintenance / New Product / Refactor / Repair / Update / Upgrade |
| **Change Classification** | `customfield_10100` | option | ASM / BAR / DATA / FACILITIES / INF / SERVDESK / **SOFTDEV** (default for app-team work) |

### Change Risk options (`customfield_10086`)

Pass as `{"value": "..."}` or `{"id": "..."}`. Shorthand → full value:

| Probability \ Impact | Low Impact | Medium Impact | High Impact |
|---|---|---|---|
| **Low Probability** | `9 - ... Low/Low` | `6 - ... Low/Medium` | `5 - ... Low/High` |
| **Medium Probability** | `8 - ... Medium/Low` | `4 - ... Medium/Medium` | `2 - ... Medium/High` |
| **High Probability** | `7 - ... High/Low` | `3 - ... High/Medium` | `1 - ... High/High` |

Most app-team deploys land in **6** (Low Prob / Medium Impact) or **9** (Low Prob / Low Impact). The full text is verbose ("Issues are UNLIKELY and would have MODERATE/DEPT LEVEL EFFECT on PCI operations…") — fetch via `getJiraIssueTypeMetaWithFields` if you need the exact string, or pass `{"id":"10154"}` for option 6.

Option IDs: 9=10151, 8=10152, 7=10153, 6=10154, 5=10155, 4=10156, 3=10157, 2=10158, 1=10159.

### Change Reason values (`customfield_10092`)

Pass as `{"value":"Enhancement"}`. Allowed: Enhancement, Maintenance, New Product, Refactor, Repair, Update, Upgrade.

### Change Classification values (`customfield_10100`)

Pass as `{"value":"SOFTDEV"}`. Allowed: ASM, BAR, DATA, FACILITIES, INF, SERVDESK, **SOFTDEV** (typical for our work).

## Optional Fields (commonly populated)

| Field | Key | Type |
|---|---|---|
| Change Description | `customfield_10090` | ADF textarea — main narrative (Summary / Background / Risk) |
| Validation Plan | `customfield_10091` | ADF textarea |
| Release Steps | `customfield_10094` | ADF textarea — usually a link to the TFS/Azure release |
| Rollback Plan | `customfield_10101` | ADF textarea |
| Post-Change Monitoring | `customfield_10105` | ADF textarea |
| Dependencies | `customfield_10103` | ADF textarea |
| Environment | `customfield_10095` | option — Production / Stage / QA / Dev / data-center options |
| Change Start Date | `customfield_10099` | datetime ISO 8601 |
| Change Completion Date | `customfield_10093` | datetime ISO 8601 |
| Approver | `customfield_10107` | user picker |
| Approver 2 | `customfield_10096` | user picker |
| Validator | `customfield_10084` | user picker |
| Needs CRB | `customfield_10104` | option — `Y` / `N` |

Cascading selects (Infrastructure 10087, Interface/Service 10102, Application 10108, Website 10106, Desktop Software 10098) and multi-selects (Printers 10089, Transmissions 10088) exist but are usually skipped for app-team SOFTDEV tickets. Look up via the metadata file if needed.

## Workflow

Mirrors the conversational shape → confirm → create flow from the global Creating Issues docs.

1. **Shape.** From the user's request, draft:
   - Summary (under ~70 chars)
   - Change Description body (Summary / Background / Risk sections — skip Release Steps and Rollback if those custom fields will be populated separately)
   - Change Reason (default Enhancement unless they said otherwise)
   - Change Classification (default SOFTDEV)
   - Change Risk (default Low Prob / Medium Impact = option `6` / id `10154` for typical deploys; ask if uncertain)
   - Environment (default Production)

2. **Confirm.** Show the user the proposed values before calling the API. Especially confirm Change Risk and any user-pickers (Approver, etc.).

3. **Create.** Call `mcp__...__createJiraIssue` with `contentFormat: "adf"` and the field payload below. Then verify the response.

4. **Link the dev ticket.** If the CAB is deploying work from a CRD/CO/NGO/etc. ticket, add a "Relates" link from the new CHANGE issue to the dev ticket. See "Linking the dev ticket" below.

## Linking the dev ticket

When the CAB is deploying or implementing work from a dev ticket (CRD-###, CO-###, NGO-###, etc.), link them with a **Relates** issue link. This is the team-wide convention — confirmed across 26 of 26 dev-ticket references on recent CHANGE tickets. Parent/sub-issue relationships are **not** used for CHANGE → dev.

```
mcp__...__createIssueLink(
  cloudId: "<CloudId>",
  type: "1Relates",   # local instance's name for "Relates" (id 10003); leading "1" is a picker-sort hack
  inwardIssue:  "CO-424",         # the dev ticket
  outwardIssue: "CHANGE-10655"    # the new CHANGE ticket
)
```

Notes:
- "Relates" is symmetric, so the choice of inward vs outward is cosmetic.
- The link type's name in this instance is `1Relates`, not `Relates`. Either passes validation since the MCP wrapper matches case-insensitively, but `1Relates` matches what shows up in the UI.
- Mentioning the dev ticket only as a hyperlink inside the Change Description does **not** count — add the formal link.

## ADF examples

The literal JSON — working example payload, minimum-viable doc, and node-type cheat sheet (heading, paragraph, link, inline code, bullet list) — lives in [references/adf-examples.md](../../references/adf-examples.md). Pull that in when actually composing the request body. Same shape applies to `editJiraIssue` under `fields:` instead of `additional_fields:`.

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Content in `description` field | Ticket appears blank in CAB UI | Move to `customfield_10090` |
| Markdown passed to textarea field | Error: `Failed to convert markdown to adf` | Use ADF doc object, pass `contentFormat: "adf"` |
| Missing required field | 400 with field-name error | Always include `customfield_10086`, `_10092`, `_10100` at create |
| Passing `null` to clear `description` | Error: `Expected an ADF document` | Pass empty doc: `{"type":"doc","version":1,"content":[]}` |
| Passing markdown body via `description` field on edit | Same convert error if `contentFormat: "adf"` is set | Either send ADF doc OR drop `contentFormat` and send markdown — but not mixed |
| Forgetting Approver | Ticket sits without approval sub-task progressing | Set `customfield_10107` if known; otherwise note and continue |
| Skipping the Relates link to the dev ticket | CAB has no formal trace to the work it deploys | Add `createIssueLink` of type `1Relates` between CHANGE and the dev ticket — see "Linking the dev ticket" |

## When You Need a Field Not Listed Here

The full field metadata is large (~97k chars). Don't load it inline — fetch and grep:

```
getJiraIssueTypeMetaWithFields(cloudId, projectIdOrKey="CHANGE", issueTypeId="10026")
```

The MCP wrapper saves the response to a file when oversized. Then `Grep` the saved file for `"name": "<Field Name>"` with `-A 30` to see the schema and allowed values.

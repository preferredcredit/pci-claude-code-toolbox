---
name: create-issue
description: Use when creating a new Jira ticket in a regular project (CRD, CO, etc.) — the standard Story workflow with summary, markdown description, priority, and optional story points. Triggers on phrases like "create a story", "open an issue", "new CRD ticket", "new CO story", "file a ticket for X", "scaffold a new ticket", or any conversational request to shape a fresh Jira issue. Default issue type is Story (not Task — Task has an incomplete workflow). Do NOT use this for CHANGE-project CAB tickets — those have a different field layout and belong to the `/create-change-issue` skill.
---

# Create Issue

Create a new Jira ticket in a regular project (CRD, CO, or any other Story-workflow project) with the right fields populated. Mirrors the conversational shape → confirm → create flow used across the workflow.

## When to use

Use this skill for **regular project tickets** — Story-workflow projects like:

- **CRD** — Credit Risk & Decisioning (formerly NGU)
- **CO** — Core Origination
- Any other PCI project using the standard Story workflow

Use **`/create-change-issue`** instead when the user is creating a **CAB ticket in the CHANGE project** — those use a different field layout (Change Description as ADF, Change Risk / Reason / Classification required, etc.).

If the project isn't obvious from the user's request, ask before creating.

## Project Configuration

- **CloudId:** the Jira CloudId from `## Configuration` in CLAUDE.md (referred to as `<CloudId>` below)
- **Project key:** typically `CRD` or `CO` — ask the user if ambiguous
- **Issue type:** `Story` (always prefer Story over Task — Task has a different/incomplete workflow)
- **Default assignee:** the User Account ID from `## Configuration` in CLAUDE.md (always assign to the workflow user unless told otherwise)
- **Default priority:** `Medium` unless the user specifies

## The Procedure

Three steps. Don't skip the confirm.

### 1. Shape it

From the user's conversational input, draft:

- **Summary** — concise, action-oriented, under ~70 chars. Examples: "Add validation for SSN field on applicant form", "Refactor decision rules engine to use new schema".
- **Description** — markdown. Bullet points for lists of changes. Bold for section headers. Keep it concise. See **Description style** below for the convention.
- **Priority** — Medium by default; bump to High / Highest / Critical if the user signals urgency, drop to Low / Lowest if they signal it's a nice-to-have.
- **Project** — CRD vs CO vs other. Infer from context (the area of the system they're describing); ask if unclear.
- **Story points** — optional. Suggest only if the user gave enough scope signal; otherwise leave unset and let the team estimate.

### 2. Confirm

Show the user the proposed values **before** calling the API:

- Summary
- Description (rendered as markdown)
- Project key + issue type
- Priority
- Story points (if set)
- Any other custom fields (Technical Details, System Component)

Wait for confirmation or edits.

### 3. Create

Call `createJiraIssue` with these defaults:

- `cloudId`: the Jira CloudId from `## Configuration` in CLAUDE.md
- `projectKey`: confirmed in step 1 (`CRD`, `CO`, etc.)
- `issueTypeName`: `Story`
- `assignee_account_id`: the User Account ID from `## Configuration` in CLAUDE.md
- `summary`: shaped in step 1
- `description`: the markdown body
- `additional_fields`: priority + any optional custom fields, e.g.:
  ```json
  {
    "priority": {"name": "Medium"},
    "customfield_10057": 3
  }
  ```

After the response comes back, share the new issue key and URL with the user.

## Priority Values

Allowed values (pass as `{"name": "<value>"}` inside `additional_fields.priority`):

- `Critical - Immediate`
- `Highest`
- `High`
- `Medium` ← default
- `Low`
- `Lowest`

## Custom Fields (optional)

| Field | Key | Type | Notes |
|---|---|---|---|
| Story Points | `customfield_10057` | number | Fibonacci-ish: 0.5, 1, 2, 3, 5, 8, 13 |
| Technical Details | `customfield_10059` | text | Free-form technical notes — code paths, repos, integration points |
| System Component | `customfield_11455` | multi-select | Pass as `[{"value": "<component name>"}]`. Look up valid values via the project metadata if the user names a component you don't recognize. |

Example `additional_fields` payload combining the lot:

```json
{
  "priority": {"name": "High"},
  "customfield_10057": 5,
  "customfield_10059": "Touches Gateway.Web and NextGenOrig. New endpoint on DecisionController.",
  "customfield_11455": [{"value": "Decisioning"}]
}
```

## Description Style

The body of `description` is markdown — the Jira API converts it server-side for the regular project workflow. Style conventions:

- **Bullet points** for lists of changes / acceptance criteria / impacted files.
- **Bold** for section headers (`**Background**`, `**Changes**`, `**Acceptance**`).
- Keep it concise. The user is the audience — not a reviewer reading a spec.
- Inline code with backticks for class / method / field names: `DecisionEngine.Evaluate()`.
- Don't pad with filler ("This ticket is for the purpose of..."). Start with what's being done.

Minimum useful shape:

```markdown
**Background**
Brief context — what's broken / what's missing / why now.

**Changes**
- First change
- Second change

**Acceptance**
- Observable outcome 1
- Observable outcome 2
```

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Using `Task` instead of `Story` | Ticket lands in a workflow without standard transitions | Always use `Story` for app-team work |
| Forgetting `assignee_account_id` | Ticket lands unassigned, sits in the backlog | Always pass the workflow user's account ID |
| Putting priority at top level | API ignores it / errors | Priority must be nested in `additional_fields: {"priority": {"name": "..."}}` |
| Guessing a `System Component` value | 400 with `customfield_11455` error | Look up valid values via `getJiraIssueTypeMetaWithFields` if unsure |
| Wrong project for the work area | Ticket needs to be moved later | Confirm CRD vs CO with the user when not obvious |

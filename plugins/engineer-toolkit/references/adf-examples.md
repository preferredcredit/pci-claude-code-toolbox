# ADF Examples (`/create-change-issue`)

The CHANGE project's textarea fields (Change Description, Validation Plan, Release Steps, Rollback Plan, etc.) require **ADF** (Atlassian Document Format) — passing markdown errors with `Failed to convert markdown to adf`. This reference holds a working example payload and a node-type cheat sheet.

The skill body (`/create-change-issue`) owns the field map and the "two gotchas" (description-vs-customfield_10090, ADF requirement). This file owns the concrete JSON.

## Working Example Payload

A typical SOFTDEV deploy CAB:

```json
{
  "cloudId": "<CloudId>",
  "projectKey": "CHANGE",
  "issueTypeName": "Change",
  "summary": "Updated Socure Matching Logic",
  "assignee_account_id": "<User Account ID from CLAUDE.md ## Configuration>",
  "contentFormat": "adf",
  "additional_fields": {
    "customfield_10086": {"id": "10154"},
    "customfield_10092": {"value": "Enhancement"},
    "customfield_10100": {"value": "SOFTDEV"},
    "customfield_10095": {"value": "Production"},
    "customfield_10090": {
      "type": "doc",
      "version": 1,
      "content": [
        {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "Summary"}]},
        {"type": "paragraph", "content": [{"type": "text", "text": "Deploy ..."}]},
        {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "Background"}]},
        {"type": "paragraph", "content": [{"type": "text", "text": "..."}]},
        {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "Risk / impact"}]},
        {"type": "paragraph", "content": [{"type": "text", "text": "..."}]}
      ]
    }
  }
}
```

Editing an existing ticket via `editJiraIssue`: same shape works under `fields:` instead of `additional_fields:`. Always pass `contentFormat: "adf"`.

## ADF Quick Reference

Minimum viable ADF doc:

```json
{"type":"doc","version":1,"content":[
  {"type":"paragraph","content":[{"type":"text","text":"plain text"}]}
]}
```

To clear a textarea (e.g. setting `description` back to empty), pass `{"type":"doc","version":1,"content":[]}` — `null` errors with `Expected an ADF document`.

Useful node types for Change-ticket fields:

- **Heading:** `{"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"..."}]}`
- **Paragraph:** `{"type":"paragraph","content":[{"type":"text","text":"..."}]}`
- **Link inside text:** `{"type":"text","text":"...","marks":[{"type":"link","attrs":{"href":"https://..."}}]}`
- **Inline code:** `{"type":"text","text":"...","marks":[{"type":"code"}]}`
- **Bullet list:** `{"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"item"}]}]}]}`

Do NOT use markdown headings (`##`) inside text nodes — they render literally. Use heading nodes.

# Issue File Format & Jira Import

Canonical definition of the local issue file (`Active\<DIR>\<DIR>.md`) and the
procedure for importing a Jira ticket into one. `/work`, `/status`, and `/adhoc`
all defer to this file — do not duplicate the template elsewhere.

`<workspace>` and `<CloudId>` refer to the values in the workspace `CLAUDE.md`
`## Configuration` block.

## File template

**Agent's turn** (file starts with `go`):

```markdown
go
# [Issue Title]

Status: Planning | Spec Review | Plan Review | Development | Code Review | Development Complete | Complete
Tier: Trivial | Standard | Full
Priority: High | Medium | Low
Branch: [link]
PR: [link]
Blocked:
Jira: <Jira site>/browse/<KEY>
Jira Status: [verbatim Jira status name, refreshed by /status]

## Discussion
_(Newest first - format: [agent] message)_

[agent] message...

## Description
[From Jira]
```

**Not agent's turn** (file starts with `#`): identical, minus the leading `go`
line.

**Adhoc items** (kebab-case slug, created via `/adhoc`): omit the `Jira:` and
`Jira Status:` lines entirely. The absence of a `Jira:` line is the marker that
distinguishes adhoc from ticketed work.

## Field notes

- `Status:` — **local** workflow state. Owned by whoever is driving the work
  (planning agent, dev agent, user). `/work` reads it to decide what to dispatch
  but never overwrites it from Jira. See the workflow doctrine's "Two-Field
  Status Model".
- `Jira Status:` — verbatim mirror of the Jira ticket status. **Only `/status`
  writes this field.** Ticketed items only.
- `Tier:` — set once during Triage (`Trivial` / `Standard` / `Full`). Locked
  once written unless explicitly retriaged.
- `go` line — present = available for the autonomous full pass to pick up. A
  targeted `/work <item>` clears it on claim.
- `Blocked:` — empty when not blocked; contains the reason when blocked.

## Priority mapping (Jira → local)

| Jira priority | Local `Priority:` |
|---|---|
| Highest, High | High |
| Medium (or missing) | Medium |
| Low, Lowest | Low |

## Import procedure

Used by `/work` when a targeted Jira-key argument has no local folder yet
(pull + triage in one command). Requires Atlassian (not the VPN).

1. **Fetch** with `mcp__plugin_atlassian_atlassian__getJiraIssue`:
   - `cloudId: <CloudId>`
   - `issueIdOrKey: <KEY>` (upper-cased)
   - `responseContentFormat: markdown`
   - If the fetch fails (issue not found, API error), report it and stop — do
     not scaffold an empty folder.

2. **New vs. re-import** — check whether `<workspace>\Active\<KEY>\` exists:
   - **New:** create the folder and write `Active\<KEY>\<KEY>.md` using the
     template above. Set local `Status: Planning` (so the next step is Triage),
     `Tier:` empty, `Priority:` from the mapping, `Jira Status:` to the verbatim
     status name from the API, and the `## Description` from the issue body
     (already markdown). Include the leading `go` line only if scaffolding for
     the autonomous queue; a targeted `/work` claim leaves it off.
   - **Existing (re-import):** read the current file and refresh **only** the
     `## Description` section (everything after `## Description` to EOF) and the
     `Jira Status:` line. Preserve local `Status:`, `Tier:`, `Priority:`,
     `Branch:`, `PR:`, `Blocked:`, the `Jira:` URL, the `go` line, and the
     Discussion. If the file predates the `Tier:` field, insert an empty `Tier:`
     line directly after `Status:`.

3. Notes on field provenance:
   - `getJiraIssue` returns the description as markdown already — no conversion
     needed.
   - Priority is not always present in the `getJiraIssue` response; if absent,
     default local `Priority:` to `Medium`.

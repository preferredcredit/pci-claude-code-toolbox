---
name: create-change-from-release
description: >-
  Build the Jira Change Management (CHANGE) story for an ENTIRE Public Facing (PF) release or hotfix
  that is tracked as a Jira release version (a fix version). Use this when the user points at a whole
  release — a pasted PF release-report URL (`.../projects/PF/versions/<id>/...`), a fix-version name or
  id, or "the change for release X" — and wants the CHANGE ticket assembled from everything in that
  version: it queries the release's issues via `fixVersion`, derives the distinct System Components for
  the Release Steps, sets the CHANGE custom fields (approver, validator, reason, risk, dates, request
  type, etc.), links every release issue with a Relates link, and flags the manual Related-Work step.
  Trigger on "make/create the change (story/record/ticket) for the release", "release change for PF
  version …", "hotfix change for <version>", "CAB for the release", or a pasted PF release-report URL —
  even if they don't name the CHANGE project. This is the release-VERSION workflow; it is NOT for a
  single deploy or a one-dev-ticket CAB (use create-change-issue for that). Reach for this skill only
  when the change covers a whole release version made up of a set of issues.
---

# PCI Release Change (Mode A: create the Change story)

This skill creates the Change Management ("CHANGE") story that accompanies a Public Facing mobile/API
release, mirroring how the team has always done them (reference examples: CHANGE-10473 for the 6.26.0
release, CHANGE-10807 for the upload-docs hotfix). The value of the skill is that the CHANGE project has
~a dozen custom fields with non-obvious IDs and option IDs; getting them right by hand is slow and
error-prone. All of that lives in **`references/change-fields.md`** — read it before creating anything.

## Prerequisites

- The **Atlassian MCP must be connected** (the tools named `getJiraIssue`, `searchJiraIssuesUsingJql`,
  `createJiraIssue`, `editJiraIssue`, `createIssueLink`, `lookupJiraAccountId`,
  `getJiraIssueTypeMetaWithFields`, `atlassianUserInfo`). If they aren't available, tell the user to
  connect/authorize Atlassian first — you can't proceed without it.
- Site cloudId: `preferredcredit.atlassian.net`. If a tool rejects the site URL, resolve the real cloud
  id with `getAccessibleAtlassianResources` and use that instead.

## Inputs to collect

You need a **release version** to start. The user usually pastes a URL like
`https://preferredcredit.atlassian.net/projects/PF/versions/<id>/tab/release-report-all-issues` — the
`<id>` is the version id. A version name works too.

Everything else has a sensible default; confirm the rest with the user rather than assuming:

| Input | Default |
|---|---|
| Approver | **Carissa Schwinghammer** (override per release — it changes often) |
| Validator | **Kelly Knier** |
| Change Start Date (release date + time, Central) | **optional** — set only if given, else skip |
| Change End Date (Central) | **optional** — set only if given, else skip |
| Change Reason | **Enhancement** (`10160`) — team default; override only if asked |
| Change Risk | 9 - Low/Low (`10151`) unless the release is unusually risky |
| Summary | propose one from the release contents; let the user tweak |
| Link scope | all issues in the release (the team's convention) |

## Workflow

Read `references/change-fields.md` first — it has every field id, option id, the ADF templates, and the
gotchas. Then:

1. **Find the release issues.** Run `searchJiraIssuesUsingJql` with `fixVersion = <id>` (by id, exactly
   like the URL) requesting fields `summary, issuetype, status, parent, customfield_11455` with
   `maxResults: 100`. **If the response includes a `nextPageToken`, keep calling with that token and
   accumulate every page — a release can exceed 100 issues, and building the CHANGE from a partial set
   is a correctness bug.** These responses are big and usually spill to a `tool-results` file — parse it
   with PowerShell (`Get-Content -Raw | ConvertFrom-Json`), don't try to eyeball raw JSON.

2. **Derive the system components.** `customfield_11455` (System Component) on each issue gives the
   authoritative component list (e.g. `pci-mobile-ios`, `pci-mobile-android`, `Mobile.Api`). The
   distinct set becomes the **Release Steps** bullets. Sub-tasks (CR/Bug/QA) usually have no component of
   their own — treat them as their parent's. Usually the parent is also in the release, so its component
   is already counted; but if a sub-task's `parent` is **not** in the result set, fetch that parent with
   `getJiraIssue` and read its `customfield_11455` so you don't undercount components. **Call out
   explicitly** if a component beyond mobile/API appears (e.g. an Origination endpoint), since that means
   an extra release step the user may need to fill in.

3. **Confirm the inputs** in the table above with the user (summary, date/time, reason, approver,
   validator, link scope). Keep it to the few that actually vary.

4. **Resolve people to accountIds** with `lookupJiraAccountId` for whoever the approver/validator are —
   don't trust the cached IDs in the reference blindly; names occasionally resolve to the wrong person.
   Get the assignee (the current dev) from `atlassianUserInfo`.

5. **Create the Change.** `createJiraIssue`, project `CHANGE`, issueTypeName `Change`,
   `contentFormat: "adf"`, `assignee_account_id` = the current dev, and set the custom fields via
   `additional_fields` per the reference. Use the ADF templates for **Release Steps**
   (`customfield_10094`) and the blank **Issue Description** (`customfield_10072`). Set **Request Type**
   (`customfield_10010`) to `"2505"` (the "Change" request type) — `createJiraIssue` does NOT set this by
   default, so set it explicitly (in the create call or a follow-up `editJiraIssue`). **Leave Application
   (`customfield_10108`) blank.**

6. **Verify.** Re-read the new issue with `getJiraIssue` (fields `*all` or the specific custom fields)
   and confirm Approver, Validator, Change Start Date, Reason, Risk, Classification, Environment,
   Needs CRB, Request Type, and Release Steps all landed. Fix any that didn't with `editJiraIssue`.

7. **Link the release issues.** For each issue in scope, `createIssueLink` with type **`1Relates`**,
   `inwardIssue` = the PF key, `outwardIssue` = the new CHANGE key. (Default scope = every issue in the
   release; if the user prefers, link only the top-level stories and skip sub-tasks.)

8. **Confirm the approval sub-task.** Setting the Approver auto-creates a "Change Approval Needed
   <name>" sub-task — verify it exists; do **not** create one manually.

9. **Report + the one manual step.** Give the user the new CHANGE key/URL and a short checklist of what
   was set and linked. Then remind them of the only thing you can't do via API: add the CHANGE url to
   the release version's **Related Work** (Releases → the version → ⋯ → **Add related work**).

## Notes

- Creating a Change writes to **production Jira**. When trying the skill out, it's fine to stop after
  step 5's payload is assembled and show it for review before actually creating, or create one and
  delete it after verifying.
- If `createJiraIssue` rejects an option id, the project metadata may have changed — re-pull it with
  `getJiraIssueTypeMetaWithFields` (project `CHANGE`, issueTypeId `10026`) and update
  `references/change-fields.md`.

---
name: jira-import
description: Import a Jira issue (CRD, CO, or CHANGE project) into a local Active\<KEY>\ folder by key, or browse open issues assigned to you. Trigger phrases include "import <KEY>", "pull <KEY>", "scaffold ticket", or running /jira-import with no arguments to pick from a list. Re-imports refresh the Description from Jira without disturbing local Status, Branch, PR, or Discussion.
argument-hint: [issue-key]
disable-model-invocation: true
user-invocable: true
allowed-tools: Read, Write, Glob, mcp__plugin_atlassian_atlassian__getJiraIssue, mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql
---

In this skill, `<workspace>` refers to the Workspace path defined in the workspace `CLAUDE.md` `## Configuration` block. `<CloudId>` refers to the Jira CloudId from the same Configuration block.

# Jira Import

Import Jira issues to the local workspace workflow using the Atlassian MCP plugin. Supports the active projects listed in `## Configuration` (currently `CRD`, `CO`, `CHANGE`).

## Configuration

Read from the workspace `CLAUDE.md` `## Configuration` table:
- `Jira CloudId` (referred to as `<CloudId>` below)
- `Jira site` (e.g. `https://preferredcredit.atlassian.net`)
- `Primary projects` (the project keys to browse when no argument is given)

## With Argument: `/jira-import <KEY>`

`<KEY>` matches `^[A-Z]+-\d+$` — e.g. `CO-322`, `CRD-100`, `CHANGE-10561`. Legacy `NGU-###` keys still resolve to `CRD-###` server-side, so passing one works but the canonical project for new tickets is now `CRD`.

1. Fetch issue using `mcp__plugin_atlassian_atlassian__getJiraIssue`:
   - cloudId: `<CloudId>`
   - issueIdOrKey: `$ARGUMENTS`

2. Check if `<workspace>\Active\$ARGUMENTS\` exists:
   - **If exists:** Read current file. Refresh only the `## Description` section from Jira. Preserve everything else (Status, Priority, Branch, PR, Blocked, Discussion, `go` line).
   - **If new:** Create folder and issue file.

3. Map Jira priority:
   - Highest, High → High
   - Medium → Medium
   - Low, Lowest → Low

4. Create/update file at `<workspace>\Active\$ARGUMENTS\$ARGUMENTS.md`. Build the `Jira:` URL as `<Jira site>/browse/$ARGUMENTS` using the site from Configuration:

```markdown
go
# [Summary from Jira]

Status: Planning
Tier:
Priority: [mapped priority]
Branch:
PR:
Blocked:
Jira: <Jira site>/browse/$ARGUMENTS
Jira Status: [verbatim Jira status name from the API response]

## Discussion
_(Newest first - format: [agent] message)_

## Description
[Description from Jira - convert to markdown]
```

`Status:` is the **local** workflow state — initialized to `Planning` so the next `/work` dispatches the planning agent. `Jira Status:` is a verbatim mirror of the Jira ticket status (e.g. `Backlog`, `In Development`); only `/status` should ever rewrite it. See the workspace doctrine > "Two-Field Status Model" for details.

5. Confirm: `Imported $ARGUMENTS - [summary]. Ready for planning.`

## Without Argument: `/jira-import`

1. Fetch issues using `mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql`. Build the JQL `project in (...)` clause from the `Primary projects` list in Configuration (e.g. `project in (CRD, CO)` — exclude `CHANGE` from browse mode since CAB tickets aren't normally pulled into dev workflow):
   - cloudId: `<CloudId>`
   - jql: `project in (CRD, CO) AND statusCategory != Done AND assignee = currentUser() ORDER BY priority DESC, key ASC`
   - fields: `["summary", "status", "priority", "assignee"]`
   - maxResults: 20

2. Display results as a numbered list:
   ```
   Available issues:

   1. CO-322 - Gateway - Add Hit Code to Prequalification UI [Backlog] [Medium]
   2. CRD-216 - Implement Client Information... [In Development] [Medium] [Assigned: You]
   ...
   ```

   For each issue show: key, summary, Jira status in brackets, priority in brackets, and "[Assigned: Name]" if assigned.

3. Use the AskUserQuestion tool to let the user select which issue to import.

4. Import the selected issue using the "With Argument" flow above.

## Re-Import Behavior

When the issue folder already exists at `<workspace>\Active\$ARGUMENTS\`:

1. Read the existing file
2. Fetch latest from Jira
3. Replace ONLY the `## Description` section (everything after `## Description` until end of file)
4. Update the `Jira Status:` line in place to the latest verbatim Jira status (or insert it directly below the `Jira:` URL line if missing). Do NOT change local `Status:`, `Priority:`, `Branch:`, `PR:`, `Blocked:`, the `Jira:` URL, the `go` line, or the Discussion.
5. If the existing file has no `Tier:` line at all (legacy import before this field existed), insert an empty `Tier:` line directly after the `Status:` line.
6. Confirm: `Refreshed $ARGUMENTS description and Jira Status from Jira. Local state preserved.`

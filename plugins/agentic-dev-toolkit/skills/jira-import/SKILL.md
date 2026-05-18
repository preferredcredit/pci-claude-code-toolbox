---
name: jira-import
description: Import Jira issue by key or browse available NGU issues
argument-hint: [issue-key]
disable-model-invocation: true
allowed-tools: Read, Write, Glob
---

In this skill, `<workspace>` refers to the Workspace path defined in the workspace `CLAUDE.md` `## Configuration` block.

# Jira Import

Import Jira issues to the local workspace workflow using the Atlassian MCP plugin.

## Configuration

- CloudId: 19ff5866-fc24-4369-81c2-4b8de43058a3
- Project: NGU
- Site: https://preferredcredit.atlassian.net

## With Argument: `/jira-import NGU-###`

1. Fetch issue using `mcp__plugin_atlassian_atlassian__getJiraIssue`:
   - cloudId: `19ff5866-fc24-4369-81c2-4b8de43058a3`
   - issueIdOrKey: `$ARGUMENTS`

2. Check if `<workspace>\Active\$ARGUMENTS\` exists:
   - **If exists:** Read current file. Refresh only the `## Description` section from Jira. Preserve everything else (Status, Priority, Branch, PR, Blocked, Discussion, `go` line).
   - **If new:** Create folder and issue file.

3. Map Jira priority:
   - Highest, High → High
   - Medium → Medium
   - Low, Lowest → Low

4. Create/update file at `<workspace>\Active\$ARGUMENTS\$ARGUMENTS.md`:

```markdown
go
# [Summary from Jira]

Status: Planning
Tier:
Priority: [mapped priority]
Branch:
PR:
Blocked:
Jira: https://preferredcredit.atlassian.net/browse/$ARGUMENTS
Jira Status: [verbatim Jira status name from the API response]

## Discussion
_(Newest first - format: [agent] message)_

## Description
[Description from Jira - convert to markdown]
```

`Status:` is the **local** workflow state — initialized to `Planning` so the next `/work` dispatches the planning agent. `Jira Status:` is a verbatim mirror of the Jira ticket status (e.g. `Backlog`, `In Development`); only `/work` Phase 2 should ever rewrite it. See `CLAUDE.md` > "Two-Field Status Model" for details.

5. Confirm: `Imported $ARGUMENTS - [summary]. Ready for planning.`

## Without Argument: `/jira-import`

1. Fetch issues using `mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql`:
   - cloudId: `19ff5866-fc24-4369-81c2-4b8de43058a3`
   - jql: `project = NGU AND status IN ("Backlog", "Analysis", "Development") AND assignee = currentUser() ORDER BY priority DESC, key ASC`
   - fields: `["summary", "status", "priority", "assignee"]`
   - maxResults: 20

2. Display results as a numbered list:
   ```
   Available NGU issues:

   1. NGU-215 - Gateway - Add Hit Code to Prequalification UI [Backlog] [Medium]
   2. NGU-216 - Implement Client Information... [Analysis] [Medium] [Assigned: You]
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

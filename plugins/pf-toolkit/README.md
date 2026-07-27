# PF Toolkit

Claude Code plugin **specific to PCI's Public Facing (PF) team**. The skills here are tailored to the
PF team's release process and Jira setup (`preferredcredit.atlassian.net`) — not general-purpose Jira
skills. Each one gathers the needed context and writes to Jira only after an explicit confirmation step.

## Skills

Each skill is **model-invocable** (Claude can surface the right one from natural language) and also
runnable directly as a slash command.

| Command | Creates | Jira project | Notes |
|---|---|---|---|
| `/create-change-from-release` | Change | CHANGE | Builds the release **Change** record for a whole PF release/hotfix from a Jira release **version**: reads the `fixVersion`, gathers every issue, derives the distinct **System Components** for the Release Steps, sets the CHANGE custom fields (approver, validator, reason, risk, dates, request type), links every release issue via `Relates`, and flags the manual Related-Work step. |

> Not to be confused with `engineer-toolkit`'s `create-change-issue`, which builds a single-deploy CAB
> from one dev ticket. `create-change-from-release` is driven by a whole release **version** and links
> every issue in it.

## Requirements

- The **Atlassian MCP server** must be connected. If it isn't, the skill stops and asks you to connect
  it rather than attempting workarounds.

## Installation

```
/plugin marketplace add preferredcredit/pci-claude-code-toolbox
/plugin install pf-toolkit@pci-toolbox
```

## Usage

Point it at a PF release version — a pasted release-report URL, or a fix-version name/id:

```
/create-change-from-release https://preferredcredit.atlassian.net/projects/PF/versions/12076/tab/release-report-all-issues
```

It gathers the release's issues and system components, shows you the assembled CHANGE payload and the
link list, and writes to Jira only after you confirm.

## Development

Part of the PCI Claude Code Toolbox marketplace (`pci-toolbox`).

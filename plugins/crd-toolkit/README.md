# CRD Toolkit

Claude Code plugin **specific to PCI's Credit Risk & Decisioning (CRD) team**. The skills in this toolkit are tailored to the CRD team's Jira project, ticket types, and standard ticket formats — they are intended for the CRD team's workflows, not as general-purpose Jira skills. Each one drafts a ticket and creates it in PCI's Jira (`preferredcredit.atlassian.net`) after an explicit confirmation step.

## Skills

All skills are **explicitly invoked** (slash command only) and never auto-trigger on natural language. Each one interviews you for the key points, drafts the ticket, shows a preview, and writes to Jira only after you confirm.

| Command | Creates | Jira project | Notes |
|---|---|---|---|
| `/create-crd-epic` | Epic | CRD | Goal, scope checklist, decision log; resolves a parent Initiative |
| `/create-crd-story` | Story | CRD | User story/goal, details, testable acceptance criteria |
| `/create-crd-task` | Task | CRD | Non-code work — decisions, analysis, data pulls, configuration |
| `/create-crd-bug` | Bug | CRD | Environment, test data, repro, expected vs. actual, impact |
| `/create-crd-change` | Change | CHANGE | Release record bundling work items as `Relates` links |

## Requirements

- The **Atlassian MCP server** must be connected. If it isn't, the skills stop and ask you to connect it rather than attempting workarounds.

## Installation

```
/plugin marketplace add preferredcredit/pci-claude-code-toolbox
/plugin install crd-toolkit@pci-toolbox
```

## Usage

Invoke the matching command and answer the prompts, for example:

```
/create-crd-story Gateway - enforce max length on prequal reference number
/create-crd-bug --parent CRD-261
/create-crd-change --title "Release 2026-06-15" --diff-base v1.4.0
```

Each skill drafts the ticket from your input, shows a full preview, and requires an explicit `yes` before any write to Jira.

## Development

Part of the PCI Claude Code Toolbox marketplace.

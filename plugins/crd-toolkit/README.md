# CRD Toolkit

Claude Code plugin **specific to PCI's Credit Risk & Decisioning (CRD) team**. The skills in this toolkit are tailored to the CRD team's Jira project, ticket types, and standard ticket formats — they are intended for the CRD team's workflows, not as general-purpose Jira skills. Each one drafts a ticket and creates it in PCI's Jira (`preferredcredit.atlassian.net`) after an explicit confirmation step.

> These skills are ports of PCI's `jira-toolkit`, renamed under the `create-crd-*` command namespace for the CRD team. The ticket-authoring workflows are otherwise unchanged.

## Skills

Each skill is **model-invocable** (Claude can surface the right one from natural language) and also runnable directly as a slash command. Every skill interviews you for the key points, drafts the ticket, shows a preview, and writes to Jira only after you confirm.

| Command | Creates | Jira project | Notes |
|---|---|---|---|
| `/create-crd-initiative` | Initiative | CRD | Top-level theme grouping epics: goal, epic-scope checklist, decision log; peer links (Relates/Blocks/Predecessor/Bundle) |
| `/create-crd-epic` | Epic | CRD | Goal, scope checklist, decision log; resolves a parent Initiative; peer links (Relates/Blocks/Predecessor/Bundle) |
| `/create-crd-story` | Story | CRD | User story/goal, details, testable acceptance criteria; issue links (Relates/Blocks/Predecessor/Bundle) |
| `/create-crd-task` | Task | CRD | Non-code work — decisions, analysis, data pulls, configuration; issue links (Relates/Blocks/Predecessor/Bundle) |
| `/create-crd-bug` | Bug | CRD | Environment, test data, repro, expected vs. actual, impact; issue links (Relates/Blocks/Predecessor/Bundle) |
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

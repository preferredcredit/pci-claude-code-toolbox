# Agentic Dev Toolkit

A Jira-driven local dev workflow plugin for Claude Code. Triage, plan, execute, review, smoke-test, and QA-verify — all from your editor, all anchored to a single workspace folder.

## Quick start

1. **Install** — In Claude Code, run `/plugin` → Marketplaces → add `preferredcredit/pci-claude-code-toolbox` → Discover → install **Agentic Dev Toolkit**.
2. **Bootstrap your workspace** — Run `/adt-init`. The skill checks prerequisites, prompts for your workspace path and Jira account ID, and scaffolds the folder structure.
3. **Start working** — `/jira-import <KEY>` for ticketed work, or `/adhoc <slug> "<title>"` for an unticketed investigation. Then `/work` to run the work-loop pass.

## Skills

| Command | What it does |
|---|---|
| `/adt-init` | Bootstrap or refresh the workspace (folders, CLAUDE.md, rules). Run once after install; re-run to refresh templates. |
| `/work` | Main orchestrator pass — VPN check, sync Jira Status, sweep completed items, dashboard, dispatch ready items. Accepts optional `<key-or-hint>` to scope to one item. |
| `/direct <KEY>` | Open a direct/interactive session in the current chat for a single ticket. Locks the issue from `/work`. |
| `/adhoc <slug> "<title>"` | Create a new unticketed work item using a kebab-case slug. Also accepts free-form descriptions. |
| `/jira-import <KEY>` | Pull a Jira ticket into a local `Active\<KEY>\` folder. |
| `/smoke <KEY>` | Run a local Playwright walk-through of the ticket's acceptance criteria against your dev branch. |
| `/qa <KEY> <env>` | End-to-end QA verification across the multi-app ecosystem (dev / qa / staging). |
| `/create-change-issue` | Shape and create a CAB ticket in the CHANGE Jira project. |

## Agents

- **business-analyst** — Turns vague stakeholder asks into well-formed Jira issues. Invoked during planning phases.
- **qa-runner** — Headless Playwright driver for fully-automated regression / smoke passes (future use).

## Prerequisites

**Required (must be installed and enabled):**

| Plugin | Marketplace |
|---|---|
| `superpowers` | claude-plugins-official |
| `atlassian` | claude-plugins-official |
| `playwright` | claude-plugins-official |
| `engineer-toolkit` | pci-toolbox |

**Optional but recommended:**

| Plugin | Marketplace |
|---|---|
| `csharp-lsp` | claude-plugins-official |
| `claude-md-management` | claude-plugins-official |

`/adt-init` checks all of these at startup.

## Workspace layout

After `/adt-init`, your workspace looks like:

```
<workspace>\
├── CLAUDE.md                      ← workflow rules + your Configuration block
├── .claude\
│   └── rules\
│       ├── csharp.md
│       └── razor.md
├── Active\                        ← work items currently in flight
├── Complete\                      ← finished work (auto-swept here by /work)
├── Archive\                       ← long-term storage (>30 days complete)
└── PlanningWorkspace\             ← shared read-only clones of repos
    └── CLAUDE.md
```

## Configuration

User-specific values live in the workspace `CLAUDE.md` `## Configuration` block:

- **Workspace path** — set during `/adt-init`
- **User Account ID** — your Jira account ID (auto-detected when possible)
- **User Name** — your Jira display name

PCI-wide values (Jira CloudId, project keys) are also listed there for reference but should not need to change.

## Updating

After the plugin is updated (`/plugin` → Update), re-run `/adt-init` and pick `refresh` if you want the latest `CLAUDE.md` and rules templates. Your `Active\`, `Complete\`, and `Archive\` folders are never touched.

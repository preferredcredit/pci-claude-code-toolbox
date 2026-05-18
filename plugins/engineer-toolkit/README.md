# Engineer Toolkit

The PCI engineer's daily-driver Claude Code plugin. Two surfaces in one bag:

- **Workflow** — Jira-driven dev loop: triage, plan, execute, smoke, QA. Day-to-day driver.
- **Review** — Pre/post-PR code & architecture review agents. Run on demand.

## Quick start (workflow surface)

1. **Install** — `/plugin marketplace add preferredcredit/pci-claude-code-toolbox`, then install `engineer-toolkit@pci-toolbox`.
2. **Bootstrap your workspace** — Run `/workspace-init`. Checks prerequisites, prompts for your workspace path and Jira account ID, scaffolds the folder structure.
3. **Start working** — `/jira-import <KEY>` for ticketed work, or `/adhoc <slug> "<title>"` for unticketed investigations. Then `/work` to run the loop.

## Skills

### Workflow

| Command | What it does |
|---|---|
| `/workspace-init` | Bootstrap or refresh the workspace (folders, CLAUDE.md, rules). Run once after install; re-run to refresh templates. |
| `/work` | Main orchestrator pass — VPN check, sync Jira Status, sweep completed items, dashboard, dispatch ready items. Accepts optional `<key-or-hint>` to scope to one item. |
| `/direct <KEY>` | Open a direct/interactive session in the current chat for a single ticket. Locks the issue from `/work`. |
| `/adhoc <slug> "<title>"` | Create a new unticketed work item using a kebab-case slug. |
| `/jira-import <KEY>` | Pull a Jira ticket into a local `Active\<KEY>\` folder. |
| `/smoke <KEY>` | Run a local Playwright walk-through of the ticket's acceptance criteria against your dev branch. |
| `/qa <KEY> <env>` | End-to-end QA verification across the multi-app ecosystem (dev / qa / staging). |
| `/create-change-issue` | Shape and create a CAB ticket in the CHANGE Jira project. |

### Review

| Command | What it does |
|---|---|
| `/author-review` | Pre-PR self-review. Gathers context, assesses complexity, runs `code-reviewer` (always) and `architect-review` (complex only), produces a structured summary for the PR description. |
| `/reviewer-check` | Independent reviewer pass on someone else's PR. Validates the author's review and surfaces missed issues. Output goes in a PR comment. |

## Agents

- **code-reviewer** (Sonnet) — Bugs, security, performance, maintainability. Read-only.
- **architect-review** (Opus) — Design decisions, system boundaries, cost-of-change. Read-only with Mermaid diagrams.
- **qa-runner** (Sonnet) — Headless Playwright driver for fully-automated regression / smoke passes (future use).

## Prerequisites

**Required (must be installed and enabled):**

| Plugin | Marketplace |
|---|---|
| `superpowers` | claude-plugins-official |
| `atlassian` | claude-plugins-official |
| `playwright` | claude-plugins-official |

**Optional but recommended:**

| Plugin | Marketplace |
|---|---|
| `csharp-lsp` | claude-plugins-official |
| `claude-md-management` | claude-plugins-official |

`/workspace-init` checks all of these at startup.

## Workspace layout

After `/workspace-init`, your workspace looks like:

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

- **Workspace path** — set during `/workspace-init`
- **User Account ID** — your Jira account ID (auto-detected when possible)
- **User Name** — your Jira display name

PCI-wide values (Jira CloudId, project keys) are also listed there for reference but should not need to change.

## Updating

After the plugin is updated (`/plugin` → Update), re-run `/workspace-init` and pick `refresh` if you want the latest `CLAUDE.md` and rules templates. Your `Active\`, `Complete\`, and `Archive\` folders are never touched.

## Review flows

### Author review (before opening a PR)

```
/author-review
    |
    +-- Gather context (branch, story, AC)
    +-- Read diff and changed files
    +-- Assess complexity (Simple vs Complex)
    |
    +-- Launch code-reviewer (Sonnet) — always
    |   +-- Logic errors, security, performance, maintainability
    |
    +-- Launch architect-review (Opus) — complex only
    |   +-- Design decisions, cost of change, backward compatibility
    |
    +-- Synthesize into structured output
```

Output: AI Review Summary, Risk Score, Cost of Change, Key Findings — copy into the PR description.

### Reviewer check (validating someone else's PR)

```
/reviewer-check
    |
    +-- Gather context (PR, author's review)
    +-- Read diff and changed files
    |
    +-- Independent code-reviewer pass
    |   +-- Catches issues the author's review missed
    |
    +-- Validate author's review
    |   +-- Risk score, cost of change, coverage
    |
    +-- Produce Reviewer AI Check output
```

Output: Reviewer AI Check — add as a PR comment.

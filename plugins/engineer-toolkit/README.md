# Engineer Toolkit

The PCI engineer's daily-driver Claude Code plugin. Two surfaces in one bag:

- **Workflow** — Jira-driven dev loop: triage, plan, execute, smoke, QA. Day-to-day driver.
- **Review** — Pre/post-PR code & architecture review agents. Run on demand.

## Quick start (workflow surface)

1. **Install** — `/plugin marketplace add preferredcredit/pci-claude-code-toolbox`, then install `engineer-toolkit@pci-toolbox`.
2. **Bootstrap your workspace** — Run `/workspace-init`. Checks prerequisites, prompts for your workspace path and Jira account ID, scaffolds the folder structure.
3. **Start working** — `/work <KEY>` pulls a Jira ticket and triages it in one command (it auto-imports if not already local). Or `/jira-import <KEY>` to import without starting, and `/adhoc <slug> "<title>"` for unticketed investigations. Then `/status` to refresh the dashboard, or `/work` to dispatch anything ready.

## Skills

### Workflow

| Command | What it does |
|---|---|
| `/workspace-init` | Bootstrap or refresh the workspace (folders + CLAUDE.md). Checks plugin prereqs and CLI tools (git, dotnet). Re-run to refresh templates; existing local edits are detected and confirmed before overwrite. |
| `/work` | Queue runner — process `go`-flagged items (or one named item via `/work <key-or-hint>`). A not-yet-local Jira key is auto-imported then triaged (pull + triage in one command). Local-first, fast. Requires VPN to TFS for git ops; Jira transitions during dispatch are best-effort. |
| `/status` | Discovery + housekeeping — refresh PlanningWorkspace, sync Jira Status onto local files, sweep completed items, print the dashboard (chat + HTML), suggest next work, surface unimported Jira tickets. No dispatch. Requires VPN to Atlassian. |
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
- **playwright-driver** (Sonnet) — Headless Playwright driver. Walks a fixed plan against a running web app, tails logs, returns a verdict. Dispatched by /smoke today; designed to be reusable by any orchestrator that can supply the documented inputs.

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
├── CLAUDE.md                       ← your editable Configuration + one @import line
├── .engineer-toolkit\              ← plugin-managed (refresh overwrites)
│   ├── workflow.md                 ← workflow doctrine: critical rules, output format,
│   │                                 issue file format, two-field status, etc.
│   └── VERSION                     ← plugin version, plain text
├── Active\                         ← work items currently in flight
├── Complete\                       ← finished work (auto-swept here by /status)
├── Archive\                        ← long-term storage (>30 days complete)
└── PlanningWorkspace\              ← shared read-only clones of repos
    └── CLAUDE.md
```

`CLAUDE.md` imports the doctrine via Claude Code's `@filepath` syntax — at session start both files load into context as one merged document. You edit your `CLAUDE.md` freely; `refresh` only touches the `.engineer-toolkit\` folder.

Path-scoped coding rules (`<workspace>\.claude\rules\*.md`) are not shipped by the plugin — drop your own there if you want them. See https://code.claude.com/docs/en/memory#path-specific-rules.

## Configuration

User-specific values live in the workspace `CLAUDE.md` `## Configuration` block:

- **Workspace path** — set during `/workspace-init`
- **User Account ID** — your Jira account ID (auto-detected when possible)
- **User Name** — your Jira display name

PCI-wide values (Jira CloudId, project keys) are also listed there for reference but should not need to change.

## Updating

After the plugin is updated (`/plugin` → Update), re-run `/workspace-init` and pick `refresh` to pull the latest workflow doctrine into `.engineer-toolkit\workflow.md`. Your `CLAUDE.md`, `Active\`, `Complete\`, `Archive\`, and `.claude\rules\` are never touched. If you're upgrading from a pre-split workspace (single-file CLAUDE.md), `/workspace-init` detects this and offers a one-time migration that backs up your old file.

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

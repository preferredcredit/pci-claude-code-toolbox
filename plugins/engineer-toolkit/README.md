# Engineer Toolkit Plugin

Claude Code plugin providing engineering tools for code review, architecture analysis, and development workflows.

## Features

### Agents

This plugin includes 2 specialized agents for .NET development workflows:

#### code-reviewer
Code quality reviewer for bugs, security issues, and performance problems. Provides structured feedback without modifying code.

- **Model**: sonnet
- **Capabilities**: Read, Grep, Glob, Bash (read-only)
- **Use for**: Code review, security analysis, quality checks

#### architect-review
Architecture review specialist for design decisions, system boundaries, and technical strategy. Creates Mermaid diagrams and assesses cost of change.

- **Model**: opus
- **Capabilities**: Read, Grep, Glob, Write (no code editing)
- **Use for**: Architectural decisions, design reviews, cost-of-change assessment

### Skills

User-invoked workflows for code review:

#### /author-review
Run an author self-review before creating a PR. Gathers context, assesses complexity, runs specialized agents, and produces a structured review summary.

```
/author-review
```

- **Capabilities**: Read-only + Bash (Read, Grep, Glob, Bash)
- **Workflow**: Gather context -> Diff -> Assess complexity -> Code review -> Architecture review (if complex) -> Synthesize
- **Output**: AI Review Summary, Risk Score, Cost of Change, Key Findings — designed to copy into PR description

#### /reviewer-check
Validate someone else's PR against the author's AI review. Runs an independent code quality pass and identifies missed issues.

```
/reviewer-check
```

- **Capabilities**: Read-only + Bash (Read, Grep, Glob, Bash)
- **Workflow**: Gather context -> Diff -> Independent code-reviewer pass -> Validate author's review -> Verify AC -> Synthesize
- **Output**: Reviewer AI Check with risk score validation, missed issues, blockers vs non-blockers — designed to add as PR comment

## Installation

```
/plugin marketplace add preferredcredit/pci-claude-code-toolbox
/plugin install engineer-toolkit@pci-toolbox
```

## Usage

### Author Workflow (before creating PR)

1. Run `/author-review`
2. Provide context when asked (branch, Jira story, acceptance criteria, systems touched)
3. Review the output
4. Copy the **AI Review Summary** into your PR description

### Reviewer Workflow (when reviewing someone else's PR)

1. Run `/reviewer-check`
2. Provide the PR link and the author's AI Review Summary
3. Review the output
4. Add the **Reviewer AI Check** as a PR comment

### How It Works

```
/author-review
    |
    +-- Gathers context (branch, story, AC)
    +-- Reads the diff and changed files
    +-- Assesses complexity (Simple vs Complex)
    |
    +-- Launches code-reviewer agent (Sonnet) --- always
    |   +-- Logic errors, security, performance, maintainability
    |
    +-- Launches architect-review agent (Opus) --- complex changes only
    |   +-- Design decisions, cost of change, backward compatibility
    |
    +-- Synthesizes findings into structured output
```

```
/reviewer-check
    |
    +-- Gathers context (PR, author's review)
    +-- Reads the diff and changed files
    |
    +-- Launches independent code-reviewer pass --- always
    |   +-- Catches issues the author's review missed
    |
    +-- Validates author's review
    |   +-- Risk score, cost of change, coverage
    |
    +-- Produces Reviewer AI Check output
```

## Development

Part of the PCI Claude Code Toolbox marketplace.

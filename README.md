# PCI Claude Code Toolbox

PCI's plugin marketplace to distribute Claude Code extensions across teams.

## Available Plugins

### [QA Playwright](plugins/qa-playwright/README.md) - QA tools for Playwright testing and automation.

### [Engineer Toolkit](plugins/engineer-toolkit/README.md) - Engineering tools for code review and architecture analysis.

**Agents:**
- `code-reviewer` - Code quality analysis (sonnet)
- `architect-review` - Architecture review and design (opus)

**Skills:**
- `/author-review` - Author self-review before creating a PR
- `/reviewer-check` - Reviewer validation of someone else's PR

## Installation

### Add the Marketplace

From any Claude Code session, add the PCI toolbox marketplace:

```
/plugin marketplace add preferredcredit/pci-claude-code-toolbox
```

### Install Plugins

Install individual plugins from the marketplace:

```
/plugin install qa-playwright@pci-toolbox
```

### Update Marketplace

To get the latest plugin versions:

```
/plugin marketplace update pci-toolbox
```

### Validation

Validate the marketplace structure:

```bash
claude plugin validate .
```

Or from within Claude Code:

```
/plugin validate .
```

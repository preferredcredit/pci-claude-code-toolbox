# PCI Claude Code Toolbox

PCI's plugin marketplace to distribute Claude Code extensions across teams.

## Available Plugins

### [QA Playwright](plugins/qa-playwright/README.md) - QA tools for Playwright testing and automation.

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

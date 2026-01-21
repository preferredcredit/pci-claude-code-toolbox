# PCI Claude Code Toolbox

PCI's plugin marketplace to distribute Claude Code extensions across teams.

## Available Plugins

### QA Playwright
QA tools for Playwright testing and automation.

**Features:**
- `/qa-check` - Review and analyze Playwright test code for best practices and improvements

## Installation

### Add the Marketplace

From any Claude Code session, add the PCI toolbox marketplace:

```
/plugin marketplace add scel-pci/pci-claude-code-toolbox
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

## Local Testing

To test the marketplace locally before publishing:

```
/plugin marketplace add ./path/to/pci-claude-code-toolbox
/plugin install qa-playwright@pci-toolbox
```

## Plugin Development

### Directory Structure

```
pci-claude-code-toolbox/
├── .claude-plugin/
│   └── marketplace.json          # Marketplace catalog
├── plugins/
│   └── qa-playwright/
│       ├── .claude-plugin/
│       │   └── plugin.json       # Plugin manifest
│       ├── skills/
│       │   └── qa-check/
│       │       └── SKILL.md      # Skill definition
│       └── README.md             # Plugin documentation
└── README.md
```

### Adding a New Plugin

1. Create plugin directory: `mkdir -p plugins/your-plugin/.claude-plugin`
2. Add plugin manifest: `plugins/your-plugin/.claude-plugin/plugin.json`
3. Add your plugin's skills, commands, agents, etc.
4. Register in marketplace: Add entry to `.claude-plugin/marketplace.json`
5. Test locally before committing

### Validation

Validate the marketplace structure:

```bash
claude plugin validate .
```

Or from within Claude Code:

```
/plugin validate .
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add or modify plugins
4. Test your changes locally
5. Submit a pull request

## License

MIT

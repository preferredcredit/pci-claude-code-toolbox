# QA Playwright Plugin

A Claude Code plugin providing QA tools for Playwright testing and automation.

## Features

- **`/qa-check`** - Review and analyze Playwright test code for best practices, coverage, and potential improvements

## Installation

From any Claude Code session, add the PCI toolbox marketplace and install this plugin:

```
/plugin marketplace add scel-pci/pci-claude-code-toolbox
/plugin install qa-playwright@pci-toolbox
```

## Usage

### QA Check

Select Playwright test code in your editor and run:

```
/qa-check
```

This will analyze your tests and provide recommendations for:
- Test coverage and completeness
- Best practices and patterns
- Potential flaky tests
- Accessibility testing opportunities
- Performance testing considerations
- Test organization and structure

## Development

This plugin is part of the PCI Claude Code Toolbox marketplace. To contribute or modify:

1. Clone the repository
2. Make changes to the plugin files
3. Test locally with `/plugin marketplace add ./path/to/pci-claude-code-toolbox`
4. Submit a pull request

## License

MIT

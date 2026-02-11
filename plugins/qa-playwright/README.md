# QA Playwright Plugin

Claude Code plugin providing Playwright testing tools. 

Make a change

## Features

### /playwright-init Command

Initialize a new Playwright E2E testing project with best practices.

```
/playwright-init
```

Guides you through:
- Single-app or multi-app structure selection
- playwright.config.ts configuration
- Base page objects and fixtures
- Smoke tests
- Documentation generation (CLAUDE.md, playwright-commands.md)

### /playwright-create-test Command

Create new Playwright E2E tests for a specific feature.

```
/playwright-create-test login flow
```

Guides you through:
- Gathering requirements and acceptance criteria
- Creating a test plan for approval
- Creating/updating page objects
- Writing tests with proper structure
- Running and validating tests

### /playwright-review Command

Review Playwright tests against best practices and project standards.

```
/playwright-review tests/e2e/login.spec.ts
```

Evaluates:
- Selector quality (getByRole, getByTestId vs fragile CSS)
- Waiting patterns (auto-wait vs hardcoded delays)
- Test independence and isolation
- Assertion quality
- Flakiness risk

### playwright-engineer Subagent

A TypeScript Playwright specialist that Claude delegates to for E2E test work:

- **Adapts to your project** - Discovers existing patterns before writing code
- **Test creation** - Write maintainable tests using Page Object Model
- **Best practices** - Enforces proper selectors, waits, and structure
- **Anti-pattern detection** - Flags issues and suggests improvements

Claude automatically delegates Playwright tasks to this subagent.

## Prerequisites

Install the Playwright MCP server to enable browser automation capabilities:

```
claude mcp add playwright npx @playwright/mcp@latest
```

## Installation

```
/plugin marketplace add preferredcredit/pci-claude-code-toolbox
/plugin install qa-playwright@pci-toolbox
```

## Usage Examples

**Initialize a new project:**
```
/playwright-init
```

**Ask Claude naturally** - it will delegate to the subagent:
- "Create a Playwright test for the login flow"
- "Set up Page Object Model for the dashboard"
- "Review the checkout tests for best practices"
- "Fix the flaky test in auth.spec.ts"

## Development

Part of the PCI Claude Code Toolbox marketplace.

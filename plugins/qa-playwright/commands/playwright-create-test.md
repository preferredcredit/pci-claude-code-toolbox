---
name: playwright-create-test
description: Create new Playwright E2E tests for a specific feature with page objects, fixtures, and proper test organization
disable-model-invocation: true
argument-hint: "[describe what to test]"
---

# Playwright Test Generation

Create new Playwright E2E tests for: **$ARGUMENTS**

Follow PCI standards and existing project patterns.

## Required Information

Gather from the user if not provided:
- **Feature or page to test** (e.g., "login flow", "checkout process", "user dashboard")
- **Acceptance criteria** or expected behaviors
- **Specific scenarios** to cover
- **Application URL** (if not already configured)

## Process

### Step 1: Gather Context

**Understand the feature:**
- What is being tested?
- What are the expected behaviors?
- What are the acceptance criteria?

**Explore the existing test infrastructure:**
- Check for existing page objects in `tests/pages/` or `shared/pages/`
- Check for existing tests in `tests/e2e/` or `apps/*/tests/`
- Check for existing fixtures in `tests/fixtures/` or `shared/fixtures/`
- Review `playwright.config.ts` for base URL and project structure

**Identify application selectors:**
- Ask the user about the feature and how best to access it
- Or explore the application to identify stable selectors
- Suggest adding `data-testid` attributes if selectors are fragile

### Step 2: Plan Test Scenarios

Create a test plan before writing code:

```markdown
## Test Plan: {Feature Name}

### Page Object Needed
- [ ] {PageName}.page.ts - {description of page/component}

### Test Scenarios

#### Happy Path
1. {Primary success scenario}

#### Validation & Errors
1. {Invalid input scenario}
2. {Error state scenario}

#### Edge Cases
1. {Edge case 1}
2. {Edge case 2}

#### Authentication (if applicable)
- Requires logged-in user: {yes/no}
- Roles to test: {list}

### Dependencies
- API mocking needed: {yes/no - which endpoints}
- Test data fixtures: {list}
- Pre-conditions: {setup requirements}
```

**Present the test plan to the user for approval before implementing.**

### Step 3: Create/Update Page Objects

If the feature needs a page object:

1. Check if one already exists for this page
2. If not, create following the pattern:

```typescript
// tests/pages/{feature}.page.ts
import { Page, Locator } from '@playwright/test';
import { BasePage } from './base.page';

export class {FeatureName}Page extends BasePage {
  // Locators
  readonly {element}Locator: Locator;

  constructor(page: Page) {
    super(page);
    this.{element}Locator = page.getByTestId('{test-id}');
  }

  get url(): string {
    return '/{path}';
  }

  // Actions
  async {actionName}(): Promise<void> {
    // Implementation
  }
}
```

**Page Object Guidelines:**
- Locators in constructor using `getByTestId` or ARIA queries
- Actions as async methods
- No assertions in page objects
- Inherit from BasePage

### Step 4: Write Tests

Use the `playwright-engineer` agent to implement tests.

**Test File Structure:**

```typescript
import { test, expect } from '@playwright/test';
import { {FeatureName}Page } from '../../pages/{feature}.page';

test.describe('{Feature Name}', () => {
  let featurePage: {FeatureName}Page;

  test.beforeEach(async ({ page }) => {
    featurePage = new {FeatureName}Page(page);
    await featurePage.goto();
  });

  test.describe('Happy Path', () => {
    test('should {expected behavior}', async ({ page }) => {
      // Arrange
      // Act
      // Assert
    });
  });

  test.describe('Validation', () => {
    test('should show error when {invalid condition}', async ({ page }) => {
      // Test implementation
    });
  });

  test.describe('Edge Cases', () => {
    test('should handle {edge case}', async ({ page }) => {
      // Test implementation
    });
  });
});
```

**Test Writing Guidelines:**
- One behavior per test
- Clear, descriptive test names starting with "should"
- Arrange-Act-Assert pattern
- Use page objects for element interaction
- Mock external APIs when needed


### Step 5: Run and Validate

Execute the new tests to ensure they work:

```bash
# Run the new test file
npx playwright test tests/e2e/{feature}/{feature}.spec.ts

# Run in headed mode to verify visual behavior
npx playwright test tests/e2e/{feature}/{feature}.spec.ts --headed

# Run multiple times to check for flakiness
npx playwright test tests/e2e/{feature}/{feature}.spec.ts --repeat-each=3
```

**Validation Checklist:**
- [ ] All tests pass consistently
- [ ] Tests run in under 30 seconds
- [ ] No flaky behavior (pass 3 consecutive runs)
- [ ] Tests work in CI mode: `CI=true npx playwright test`

### Step 6: Report Summary

Provide a summary of what was created:

```markdown
## Tests Created: {Feature Name}

### Files Created/Modified
- `tests/pages/{feature}.page.ts` - Page object
- `tests/e2e/{feature}/{feature}.spec.ts` - Test file
- `tests/fixtures/auth.fixture.ts` - Auth fixture (if created)

### Test Coverage
| Scenario | Test | Status |
|----------|------|--------|
| {scenario} | should {behavior} | Pass |
| {scenario} | should {behavior} | Pass |

### Page Object Methods
- `goto()` - Navigate to page
- `{method}()` - {description}

### Run Command
```bash
npm run test:e2e -- tests/e2e/{feature}/{feature}.spec.ts
```

### Notes

## Important Guidelines

- **KISS** - Keep it simple stupid
- **Follow existing patterns** - Match the style of existing tests in the project
- **One behavior per test** - Keep tests focused and independent
- **Use page objects** - Don't put selectors directly in test files
- **Mock external dependencies** - Tests should not depend on external services
- **Avoid flakiness** - No arbitrary waits, use proper Playwright waiting
- **Run tests before completing** - Don't leave failing tests

## Workflow Summary

```
1. Gather requirements from user
2. Explore existing test infrastructure
3. Create test plan → GET USER APPROVAL
4. Create/update page objects
5. Write tests (use playwright-engineer agent)
6. Add API mocking if needed
7. Add auth fixtures if needed
8. Run and validate tests
9. Report summary to user
```

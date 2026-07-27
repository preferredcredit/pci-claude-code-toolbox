---
description: Review a Pull Request from Azure DevOps by PR number or URL
arguments:
  - name: pr_input
    description: PR number or ADO PR URL
    required: true
---

# Mobile PR Code Review

You are reviewing a Pull Request from Azure DevOps. The input is: `$ARGUMENTS`

## Step 1: Parse Input

Extract the PR number from the input. It may be:
- A bare number (e.g., `12345`)
- An ADO URL (extract the PR ID from the URL path)

## Step 2: Fetch PR Metadata

Use `mcp__ado__repo_get_pull_request_by_id` with the PR number and project `mobile` to get:
- Title, description
- Source and target branches
- Repository name (to determine if this is iOS or Android)
- Author

Tell the user what PR you found (title, repo, author, source → target branch).

## Step 3: Look Up Jira Story

Extract the Jira story key (format `PF-###`) from one of these sources (check in order):
1. The PR title (e.g., "PF-456: Add login screen")
2. The source branch name (e.g., `fb/PF-456` or `feature/PF-456-login`)
3. Commit messages in the PR description

If a `PF-###` key is found, use `mcp__plugin_atlassian_atlassian__getJiraIssue` to fetch the story details. Extract:
- **Summary** — what the story is about
- **Description** — acceptance criteria, requirements, expected behavior
- **Status** — current workflow state
- **Story type** — bug, story, task, etc.

Present a brief summary of the Jira story to the user so they can see what the PR is meant to accomplish.

Use this context throughout the rest of the review to:
- Verify the PR changes actually address what the story requires
- Flag if the PR appears to be missing functionality described in the story
- Flag if the PR introduces changes that seem unrelated to the story scope

If no `PF-###` key is found, note this to the user and proceed without Jira context.

## Step 4: Determine Review Context

Based on the repository name:
- If it contains "ios" → this is a **Swift/iOS** review. Focus on Swift conventions, iOS patterns (UIKit/SwiftUI), memory management, retain cycles, proper use of optionals, async/await patterns.
- If it contains "android" → this is a **Kotlin/Android** review. Focus on Kotlin conventions, Android lifecycle, coroutines, null safety, Compose patterns.

## Step 5: Get the Changes

Use `mcp__ado__repo_list_pull_request_threads` to see any existing review comments.

Then launch an Agent with `isolation: "worktree"` to:
1. Fetch/checkout the source branch
2. Get the diff between source and target branches (`git diff target...source`)
3. Read the full context of changed files (not just the diff — read the complete files so you understand the surrounding code)
4. Analyze the changes against the review criteria below

## Step 6: Review Criteria

Evaluate the code changes against these criteria:

### Critical (must fix)
- **Bugs**: Logic errors, off-by-one, null/nil dereference, race conditions
- **Security**: Hardcoded secrets, injection vulnerabilities, insecure data storage
- **Crashes**: Force unwraps without safety (Swift), unhandled exceptions (Kotlin)

### Important (should fix)
- **Error handling**: Missing or swallowed errors, unhelpful error messages
- **Resource management**: Memory leaks, unclosed resources, retain cycles (iOS)
- **Concurrency**: Thread safety issues, main thread violations for UI
- **API misuse**: Incorrect framework/library usage

### Story Alignment (if Jira context available)
- **Missing requirements**: Acceptance criteria or described functionality not addressed by the changes
- **Scope creep**: Changes that go beyond what the story describes without clear justification
- **Partial implementation**: Story requirements only partially met

### Suggestions (nice to have)
- **Readability**: Unclear naming, overly complex logic, missing context
- **Conventions**: Deviations from project patterns visible in surrounding code
- **Simplification**: Redundant code, opportunities to use standard library

### Out of Scope (do NOT flag)
- Style preferences (formatting, brace placement) — trust the linter
- Missing documentation on self-explanatory code
- Test coverage opinions unless something is clearly untestable

## Step 7: Present Findings

Present the review organized by file, with findings grouped by severity (Critical → Important → Story Alignment → Suggestions). For each finding:
- File and line range
- What the issue is
- Why it matters
- A suggested fix (code snippet if helpful)

If the code looks good, say so! Not every PR needs nitpicks.

## Step 8: Offer to Post

After presenting findings locally, ask the user if they'd like to post any of the comments as review threads on the PR in ADO using `mcp__ado__repo_create_pull_request_thread`. Let them choose which findings to post.

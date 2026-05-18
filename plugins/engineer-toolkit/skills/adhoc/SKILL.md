---
name: adhoc
description: Scaffold a new adhoc work item under Active\<slug>\ with the standard issue shape but no Jira link. Accepts either explicit `<slug> "<title>"` or a free-form task description (slug + title are inferred and confirmed).
argument-hint: <slug> "<title>" | <free-form task description>
disable-model-invocation: true
user-invocable: true
allowed-tools: Read, Write, Glob
---

In this skill, `<workspace>` refers to the Workspace path defined in the workspace `CLAUDE.md` `## Configuration` block.

# Adhoc

Create a new adhoc work item — investigation, debugging spike, cross-repo audit, or any work that doesn't have a Jira ticket. The item lives in `Active\<slug>\` alongside Jira-keyed items and is picked up by `/work` like any other Active item.

## Arguments

Two accepted forms:

1. **Explicit:** `/adhoc <slug> "<title>"` — used directly.
2. **Free-form:** `/adhoc <task description in plain English>` — infer slug + title from the description, then confirm with the user before scaffolding.

If the entire args string is empty, respond `Usage: /adhoc <slug> "<title>"  OR  /adhoc <free-form description>` and stop.

### Detecting the form

Treat the args as **explicit** if they match the shape `^\s*[a-z0-9-]+\s+".+"\s*$` — a kebab-case token followed by a quoted string and nothing else. Otherwise treat them as **free-form**.

### Free-form handling

1. From the user's description, propose:
   - `slug` — kebab-case, 3–6 words, descriptive of the work. Avoid leading articles ("the", "a"). Convert spaces to hyphens, lowercase everything, strip punctuation.
   - `title` — a short sentence-case human-readable title. Use Jira-key references verbatim if present (e.g., "CO-401", "CHANGE-10561").
2. Show the user:
   ```
   Proposed adhoc:
   - Slug:  <slug>
   - Title: <title>

   Proceed? (yes / change slug / change title)
   ```
3. Only scaffold after the user confirms. If the user redirects (e.g. "call it foo-bar instead"), update and re-confirm.

This confirmation step exists because slugs are sticky — they appear in the folder name, the file name, and every Discussion entry. A second of confirmation saves a rename later.

## Validation

(Applies in both forms, *after* the slug is determined.)

1. **Slug format** — must match `^[a-z][a-z0-9-]*[a-z0-9]$` (lowercase, kebab-case, no leading/trailing hyphen, no underscores). If invalid:
   - Explicit form: respond `Invalid slug. Use kebab-case: lowercase letters, numbers, and hyphens. Example: socure-test-investigation` and stop.
   - Free-form: silently regenerate a valid slug, then re-confirm with the user.

2. **Uniqueness** — Use Glob to check `<workspace>\Active\<slug>\`, `<workspace>\Complete\<slug>\`, and `<workspace>\Archive\<slug>\`. If any exists, respond:
   ```
   <slug> already exists in <Active|Complete|Archive>\. Pick a different slug.
   ```
   and stop. (Free-form callers should propose an alternative slug before stopping.)

3. **Jira-key collision** — if the slug, when upper-cased, matches the Jira-key pattern `^[A-Z]+-\d+$` (e.g., `co-322`, `ngu-100`), respond:
   ```
   Slug looks like a Jira key. Use /jira-import for ticketed work, or pick a descriptive slug.
   ```
   and stop.

## Behavior

1. Create the folder: `<workspace>\Active\<slug>\`
2. Create the file: `<workspace>\Active\<slug>\<slug>.md` with this exact content (substituting `<title>` and, for free-form, seeding the Description with the user's original task text):

```markdown
go
# <title>

Status: Planning
Tier:
Priority: Medium
Branch:
PR:
Blocked:

## Discussion
_(Newest first - format: [agent] message)_

## Description

<original free-form description, if any — otherwise leave blank>
```

3. Confirm: `Created Active\<slug>\<slug>.md. Ready for agent.`

The absence of a `Jira:` line is the marker that distinguishes this from a ticketed item. `/work` uses that absence to skip Jira-specific phases (sync, outbound transition).

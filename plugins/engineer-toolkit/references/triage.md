# Triage

Shared triage procedure for `/work` — both the autonomous **full pass** and a **targeted** focused session (`/work <item>`). Triage assigns the **Tier** that gates which workflow phases run, using the generic `architect` agent for the judgment, and uses the architect's **confidence score** to decide whether to auto-advance past the human gate.

`<workspace>` and `<CloudId>` come from the workspace `CLAUDE.md` `## Configuration` block.

## Tier criteria

| Tier | Spec | Plan | When it fits | Examples |
|------|------|------|--------------|----------|
| **Trivial** | skip | skip | One obvious change, no design decisions, no ambiguity | Version bump, rename, one-line fix, doc typo, config value |
| **Standard** | skip | write `plan.md` | A handful of files, follows existing patterns, no architectural decisions | Add a field end-to-end, new endpoint mirroring an existing one, targeted bug fix across a few files |
| **Full** | write `spec.md` | write `plan.md` | New surface area, cross-repo, ambiguous requirements, or real design decisions | New feature/service, message-contract or schema change, anything touching multiple systems or needing a design |

Tier is **locked once written**. A resumed item that already has a `Tier:` value skips triage entirely and uses the existing value.

## Confidence threshold

```
THRESHOLD = 80   (integer, 0–100)
```

- **confidence ≥ 80** → auto-advance: act on the tier without waiting for a human.
- **confidence < 80** → stop at the human gate and surface the architect's open questions.

## Procedure

1. **Refresh first.** Before triage, the relevant repo(s) in `<workspace>\PlanningWorkspace` must be at `origin/main` (see the caller's pull-latest rule). The architect reads from there; stale trees produce wrong tiers.
2. **Dispatch the architect.** Use the Task tool with `subagent_type: architect` and the [Triage prompt](#triage-prompt) below. The architect reads the issue and the relevant code and returns the [output contract](#output-contract).
3. **Parse** the returned `TIER` / `CONFIDENCE` / `RATIONALE` / `OPEN_QUESTIONS` block.
4. **Write `Tier:`** to the issue file (insert after the `Status:` line, or update an existing `Tier:` line).
5. **Log Discussion:** `[Triage] Tier=<tier> (confidence <n>): <rationale>`. If `confidence < 80`, append the open questions to the same entry.
6. **Apply the confidence gate** per the caller's mode (below).

### Auto-advance by mode

**Full pass (`/work`, autonomous):**
- **≥ 80** — proceed in the same run without stopping: run the tier's phases end-to-end (Full: `brainstorming` → `writing-plans` → execute; Standard: `writing-plans` → execute; Trivial: execute), then Review and Wrap. The high-confidence triage also stands in for the plan-review gate — do **not** pause for human plan approval. The item keeps its `go` line until the run reaches its terminal state (Code Review / Development Complete).
- **< 80** — write `Tier:`, log the `[Triage]` entry with open questions, **remove the `go` line, and stop.** The user reviews and re-adds `go` to continue.

**Targeted (`/work <item>`, focused session in chat):**
- **≥ 80** — print a non-blocking heads-up and continue through the phases without the confirm prompt:
  ```
  Triage: <Tier> (confidence <n>). <one-line rationale> — proceeding.
  ```
  (The item's `go` flag was already cleared when the session claimed it; progression is conversational, not `go`-gated.)
- **< 80** — fall back to the interactive confirm prompt (a chat turn):
  ```
  Proposed tier: <Trivial|Standard|Full>
  Confidence: <n>
  Reasoning: <one sentence>
  Open questions: <none | list>

  Confirm? (yes / no / different tier)
  ```
  Wait for the user, then write the confirmed `Tier:` and continue the session.

## Triage prompt

Pass this to the `architect` agent (substitute the bracketed values). Keep the output-contract section verbatim — it is machine-parsed.

```
You are triaging a unit of work to decide how much process it needs. Read the
issue and the relevant code, then assign a Tier.

ISSUE FILE: <absolute path to the issue .md file>
PLANNING REPOS (read-only, already refreshed to origin/main):
<workspace>\PlanningWorkspace\<repo>, ...

Read the issue description, then investigate the actual code it touches (use
Read/Grep/Glob across the planning repos). Assess scope, blast radius, cost of
change, and ambiguity.

Choose ONE tier:
- Trivial — one obvious change, no design decisions, no ambiguity (version bump,
  rename, one-line fix, doc/config tweak).
- Standard — a handful of files, follows existing patterns, no architectural
  decisions (add a field end-to-end, endpoint mirroring an existing one,
  targeted multi-file bug fix).
- Full — new surface area, cross-repo, ambiguous requirements, or real design
  decisions (new feature/service, message-contract or schema change, anything
  spanning multiple systems).

Then rate your CONFIDENCE 0–100 that this tier is correct and safe to act on
without further human input:
- 80–100: requirements and blast radius are clear; low risk to proceed
  autonomously.
- 50–79: plausible but with real unknowns a human should check.
- 0–49: genuinely ambiguous; you are guessing.
Calibrate honestly — do not inflate to be agreeable or deflate to be safe. If
anything material is unknown or underspecified, that caps confidence below 80
and belongs in OPEN_QUESTIONS.

End your reply with EXACTLY this block and nothing after it:

TIER: <Trivial|Standard|Full>
CONFIDENCE: <integer 0-100>
RATIONALE: <1-3 sentences>
OPEN_QUESTIONS: <none, or a short bullet list of what's unresolved>
```

## Output contract

The architect's reply must end with this fenced-style block (the skill parses the four fields):

```
TIER: Standard
CONFIDENCE: 85
RATIONALE: Adds one nullable column and surfaces it through an existing endpoint; mirrors the AccountNote pattern. No schema-breaking or cross-repo work.
OPEN_QUESTIONS: none
```

If parsing fails (missing fields, non-integer confidence), treat it as `confidence < 80`: stop at the human gate and report the raw architect output.

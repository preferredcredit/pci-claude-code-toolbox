# Library Promotion (`/qa` Step 8)

Optional tail step in `/qa` Phase 3, executed only when the run finished with `status: passed`. Identifies reusable patterns from the just-completed run and offers to promote them into `<workspace>\QA\HowTos\` for reuse on future runs.

Skip this step entirely if `status` is `failed` or `blocked` — partial or incorrect sequences should not become reusable how-tos.

## Detection

Scan the `## Execution Log` for inlined step sequences that could become reusable how-tos. Look for:

- 2+ consecutive steps that together form a single domain operation (e.g., "navigate → fill borrower form → submit → capture id" = `create-borrower`).
- Manual-step prompts describing a discrete user action with clear inputs and outputs.
- Sequences that referenced no existing how-to (you authored them inline during plan composition).

For each candidate sequence, propose a how-to name (kebab-case, derived from the operation, e.g., `create-borrower`, `originate-deal`). Check `<workspace>\QA\HowTos\` for name collisions; if a collision exists, append a numeric suffix or pick a more specific name.

## Prompt (one per candidate, do not batch)

```
Detected a reusable pattern in steps <N>-<M>:
  <one-line summary of the sequence>
  Inputs:  <comma-separated input names>
  Outputs: <comma-separated output names>

Save as `QA\HowTos\<proposed-name>.md`?
  Y — yes, save as proposed
  R — rename, then save (I'll ask for the new name)
  N — no, skip this one
```

Wait for response.

- **Y** — write the how-to file using the template below. Append `[promoted] Steps <N>-<M> → QA\HowTos\<proposed-name>.md` to the Execution Log.
- **R** — ask `What name? (kebab-case, no path or .md extension)`, validate (kebab-case format, no collision). On valid input, write file and log `[promoted]` entry. On invalid input, ask again or fall back to `N` after two tries.
- **N** — skip silently. Move to next candidate.

If the user replies with anything other than `Y | R | N`, re-ask once; on second invalid response, default to `N` for that candidate.

After all candidates handled (or if no candidates found): continue to Phase 4 of `/qa`.

## How-to template

```markdown
---
name: <kebab-case-name>
description: <one-line description derived from the sequence>
inputs: [<list of input names extracted from the sequence>]
outputs: [<list of output names captured in the sequence>]
---

# How-To: <Title Case Name>

## Steps

<numbered list of steps copied from the inlined sequence, preserving [automated]/[manual]/[assertion] tags. Replace concrete values from the source run with `{{var}}` placeholders where they correspond to inputs.>

## Notes

- Promoted from run `<TARGET>` on <YYYY-MM-DD>.
```

## Scope notes

- Library promotion applies only to **how-tos** in v1.
- Test data templates and named scenarios are NOT auto-promoted; the user can request those explicitly after the run.

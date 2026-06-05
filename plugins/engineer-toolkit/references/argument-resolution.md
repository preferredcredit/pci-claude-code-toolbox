# Argument Resolution

Standard algorithm for resolving `<arg>` to a single workspace directory across the orchestrator skills (`/work`, `/smoke`, `/qa`). Resolution runs BEFORE any VPN / network probe so that argument errors don't waste a probe.

## Standard algorithm

Apply against `<workspace>\Active\` (first match wins):

1. **Exact directory match** — case-insensitive. Glob `<workspace>\Active\<arg>\`.
2. **Upper-cased Jira-key match** — if `<arg>` matches `^[a-zA-Z]+-\d+$`, upper-case it and try as an exact match (`co-322` → `CO-322`).
3. **Substring match** — case-insensitive substring against all `Active\` directory names.

## Outcomes

- **Zero matches** — print `No active item matches '<arg>'.` and stop.
- **Multiple matches** — print `Multiple matches for '<arg>': <comma-separated list>. Be more specific.` and stop.
- **One match** — store the resolved directory name as `<TARGET>` and proceed.

## Variants

### Auto-scaffold fallback (`/work`)

`/work` replaces the zero-matches outcome with a fallback step 4, so naming a not-yet-imported Jira key pulls it in on the fly instead of erroring:

4. **Auto-scaffold**
   - If `<arg>` upper-cased matches `^[A-Z]+-\d+$` (looks like a Jira key): run `/jira-import <UPPER-ARG>` via the Skill tool. After import succeeds, set the target to the newly created `Active\<UPPER-ARG>\`. If import fails, print the failure and stop.
   - Otherwise (looks like an adhoc slug): print `Adhoc slug '<arg>' doesn't exist. Create it first with /adhoc <slug> "<title>".` and stop.

The other three outcomes (multiple-matches, one-match, plus the standard zero-matches error if step 4 doesn't apply) are unchanged.

The on-the-fly import needs Atlassian (Jira Cloud), not the on-prem VPN. For `/work`, the freshly scaffolded item is `Planning` with no `Tier:`, so the normal Phase 3 flow runs **triage** on it immediately — `/work <KEY>` becomes pull + triage in one command.

### Multi-root search (`/qa` only)

`/qa` searches two trees because the QA run folder (`QA\Active\<arg>\`) can exist independently of the issue folder (`Active\<arg>\`) — the first-QA-run-for-a-ticket case. Resolution becomes 5 steps:

1. Exact directory match in `<workspace>\QA\Active\<arg>\`.
2. Upper-cased Jira-key match against `<workspace>\QA\Active\`.
3. Exact directory match in `<workspace>\Active\<arg>\`.
4. Upper-cased Jira-key match against `<workspace>\Active\`.
5. Substring match across **both** `QA\Active\` and `Active\` directory names. Combine candidates from both trees before applying the multiple-matches outcome.

Outcomes are the same shape but the zero-matches message is `No item matches '<arg>'.` (drops the `active` qualifier since two trees were searched).

## Notes

- Resolution is mechanical. It does not read the issue file's content (status, mode, etc.) — those checks belong to phases that run after resolution succeeds.
- Argument resolution is the only place where input validation happens. Once a `<TARGET>` is stored, downstream phases treat it as a verified directory name.
- The Jira-key regex `^[A-Z]+-\d+$` is the same pattern used elsewhere in the workflow to distinguish ticketed vs adhoc items.

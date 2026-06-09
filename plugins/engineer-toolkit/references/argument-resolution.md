# Argument Resolution

Standard algorithm for resolving `<arg>` to a single workspace directory across the orchestrator skills (`/smoke`, `/qa`). Resolution runs BEFORE any VPN / network probe so that argument errors don't waste a probe.

(`/work` resolves its argument via `scan-queue.ps1 -Target <arg>` instead — same exact → Jira-key → substring order, plus a `jirakey-miss` outcome that triggers inline Jira import. See the `/work` skill.)

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

# Playwright Driver Dispatch Prompt

The literal prompt template `/smoke` Phase 4 Step 1 sends to the `playwright-driver` subagent via the Task tool. The driver is a pure function: prompt in, structured return out — it does not read or write `smoke.md`. The orchestrator (`/smoke`) owns file I/O.

## Template

Substitute the Plan steps (from `## Plan` in `smoke.md`), the Apps list (name — URL — log path tuples from earlier phases), the primary URL, the Screenshots dir, and the per-host profile directory.

```
Plan:
1. action: <action>
   expect: <expect>
2. action: ...
   expect: ...
...

Apps (name — URL — log path):
  - <repo> — <url> — <log path>
  ...

Playwright launch configuration:
  args:
    - "--auth-server-allowlist=localhost,*.preferredcredit.net"
    - "--auth-negotiate-delegate-allowlist=localhost,*.preferredcredit.net"
  context.ignoreHTTPSErrors: true
  userDataDir: <workspace>\.smoke\profile\<primary-host>\
  headless: true  (relaunch headed on auth-wall detection per your procedure)

Primary URL: <primary_url>

Screenshots dir: <workspace>\Active\<TARGET>\Screenshots\

Starting step: <N>     (omit this line entirely if starting from step 1)

Walk the plan and return: Verdict line + ## Step Results block per your return-format spec.
```

## Notes

- `Starting step: <N>` is omitted on the first dispatch and added on every re-dispatch after an auth-fallback round (so the driver resumes at the right step).
- The `--auth-server-allowlist` and `--auth-negotiate-delegate-allowlist` values are PCI-specific (Windows Integrated Auth against `*.preferredcredit.net` apps). If the workspace ever targets a different domain, update both flags.
- `userDataDir` is keyed per primary host so the cached session cookies don't collide across different apps.

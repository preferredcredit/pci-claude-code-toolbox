# PF Toolkit

The **Public Facing (PF) team's** shared Claude Code plugin — a home for the tooling the team uses day
to day. Anything that helps the PF workflow belongs here: skills, slash commands, subagents, and
references, across whatever the team works on (the mobile apps, the APIs, releases, Jira, ADO, and
whatever comes next). It's meant to grow over time as the team finds things worth sharing.

Everything here runs against PCI's own systems (Jira `preferredcredit.atlassian.net`, Azure DevOps, the
mobile repos). Most actions that write or change state pause for an explicit confirmation first; a few
are intentionally fire-and-forget where the result is easy to undo — e.g. `mobile-prep-build` bumps the
build and commits **locally** without prompting, since that commit can simply be amended. Each
skill/command notes its own behavior.

## What's in it today

### Skills
Model-invocable (Claude surfaces the right one from natural language) and also runnable as a slash command.

| Skill | What it does |
|---|---|
| `/create-pf-issue` | Creates a **Story** (or Task) in the `PF` project in the team's format: drafts the three body fields (**Description**, **Technical Details**, **QA Details**), sets **System Component** — inferred from the repo you're in — and defaults **Product Manager** / **QA Person** to Carissa and Kelly. Parent epic is opt-in. Previews every field and requires an explicit `yes` before writing. |
| `/create-change-from-release` | Builds the release **Change** record in Jira for a whole PF release/hotfix from a release **version**: reads the `fixVersion`, gathers every issue, derives the distinct **System Components** for the Release Steps, sets the CHANGE custom fields (approver, validator, reason, risk, dates, request type), links every release issue via `Relates`, and flags the manual Related-Work step. |

> Not to be confused with `engineer-toolkit`'s `create-change-issue`, which builds a single-deploy CAB
> from one dev ticket. `create-change-from-release` is driven by a whole release **version** and links
> every issue in it.

### Commands
The mobile build/review loop (`pci-mobile-ios` / `pci-mobile-android`).

| Command | What it does | Notes |
|---|---|---|
| `/mobile-prep-build` | Bumps the build number, assembles release notes from merged PRs, and commits | Args: `ios` or `android`, optionally a marketing version (e.g. `android 6.27.0`), and optionally a repo-root path. Reads/writes the mobile repos and ADO PRs. Finds the repos under `C:\Repos\PCIMobile` by default; if your clone lives elsewhere, pass the root as an argument or set the `PCIMOBILE_ROOT` env var (it also auto-detects when run from inside the repo). |
| `/mobile-review-pr` | Reviews an Azure DevOps PR (iOS/Android) against the code and its linked Jira story | Arg: a PR number or ADO PR URL. |

## Requirements

Depends on the piece you're using — connect what it needs:

- **Atlassian MCP** — for `create-change-from-release` and the Jira lookup in `mobile-review-pr`.
- **Azure DevOps (ADO) MCP** — for the PR/build data in `mobile-prep-build` and `mobile-review-pr`.

If a required server isn't connected, the skill/command stops and asks you to connect it rather than
guessing.

## Installation

```
/plugin marketplace add preferredcredit/pci-claude-code-toolbox
/plugin install pf-toolkit@pci-toolbox
```

## Adding to the toolkit

This is the PF team's shared space — add to it. Drop new work into the matching folder and it's picked
up automatically (no manifest wiring needed):

- **Skills** → `skills/<name>/SKILL.md` (+ optional `references/`) — for model-invocable workflows.
- **Commands** → `commands/<name>.md` — for slash commands.
- **Subagents** → `agents/<name>.md`.
- **Shared references** → `references/`.

Keep names descriptive and scoped (e.g. the `mobile-` prefix for mobile-only commands), list the new
item in this README, and bump the `version` in `.claude-plugin/plugin.json`.

## Development

Part of the PCI Claude Code Toolbox marketplace (`pci-toolbox`).

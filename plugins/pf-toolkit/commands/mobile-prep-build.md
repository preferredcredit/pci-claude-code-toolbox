---
description: Bump build number, assemble release notes from merged PRs, and commit — supports iOS and Android
arguments:
  - name: platform_and_version
    description: "Platform (ios or android), optionally followed by a marketing version. Examples: 'ios', 'android 6.27.0', 'ios 6.26.0'"
    required: true
---

# Mobile Prep Build

Prepare a mobile project for a new build by bumping the build number and assembling release notes from merged PRs.

User input: `$ARGUMENTS`

## Step 0: Parse Arguments

Parse the user input to extract:
- **Platform**: must be `ios` or `android` (case-insensitive). If not provided, ask.
- **Marketing version** (optional): a version string like `6.27.0`. If omitted, keep the current version.

Set these variables based on platform:

### iOS
- `REPO_DIR` = `C:/Repos/PCIMobile/pci-mobile-ios`
- `ADO_REPO_ID` = `pci-mobile-ios`

### Android
- `REPO_DIR` = `C:/Repos/PCIMobile/pci-mobile-android`
- `ADO_REPO_ID` = `pci-mobile-android`

---

## Step 1: Determine Current Versions

### iOS
- Read `{REPO_DIR}/PCIMobile.xcodeproj/project.pbxproj`
- Find the current `CURRENT_PROJECT_VERSION` (ignore test targets set to `1`)
- Find the current `MARKETING_VERSION` (ignore test targets set to `1.0`)
- Read `{REPO_DIR}/PCIMobile/release-notes.md`

### Android
- Read `{REPO_DIR}/app/build.gradle.kts`
- Find `versionCode = NNNN` (integer)
- Find `versionName = "X.X.X"`
- Read `{REPO_DIR}/release-notes.md`

---

## Step 2: Calculate New Build Number

### iOS
Format: `YYYY.M.count` (e.g., `2026.3.2`)
- Parse the current build number into year, month, count
- Get today's date
- If current year and month match today → increment count by 1
- If today is a new month or year → reset count to 1 with new year/month

Example: `2026.3.1` + still March 2026 → `2026.3.2`. New month → `2026.4.1`.

### Android
Format: simple integer (e.g., `3001`)
- New build number = current versionCode + 1

Example: `3001` → `3002`

---

## Step 3: Determine Marketing Version

- If the user provided a marketing version argument, use that
- Otherwise, keep the current marketing version unchanged

---

## Step 4: Find Merged PRs Since Last Prep Build

Run from `{REPO_DIR}`:

```bash
git fetch origin
```

Find the most recent prep-build commit by searching for the commit message pattern:
```bash
git log origin/development --grep="Prep build" --oneline -1
```

Get all merge commits on development since that prep-build commit:
```bash
git log <prep_build_commit>..origin/development --merges --oneline
```

If no prep-build commit is found (first time), fall back to the most recent version tag (`git tag --sort=-creatordate | head -1`).

For each merge commit that looks like a PR merge (message usually contains "Merged PR #XXX"), extract the PR number. Then use `mcp__ado__repo_get_pull_request_by_id` with `project: "Mobile"` and `repositoryId: "{ADO_REPO_ID}"` to fetch each PR's title and description.

Build a list of release note entries. For each PR:
- Look at the PR title and source branch name for a work item ID (like `PF-59`, `PF-161`, etc.)
- Create an entry with the work item ID and a brief description
- If no work item ID is found, use the PR title directly

---

## Step 5: Show Summary and Apply

Present a brief summary to the user:
- **Platform**: iOS or Android
- **Current build** → **New build**
- **Marketing version**: (changed or unchanged)
- **Release notes to add**: the list of entries from merged PRs

Then immediately proceed to apply the changes — do not wait for confirmation. The commit can be amended afterward if any tweaks are needed.

---

## Step 6: Apply Changes

### iOS — Update project.pbxproj

In `{REPO_DIR}/PCIMobile.xcodeproj/project.pbxproj`:
- Replace ALL occurrences of the old `CURRENT_PROJECT_VERSION = <old>;` with the new value — but ONLY for app target lines (the ones with a version like `2026.X.X`). Do NOT touch test target lines (they stay at `1`).
- If the marketing version changed, do the same for `MARKETING_VERSION` — only app target lines (matching old marketing version), NOT test targets (they stay at `1.0`).

### iOS — Update release-notes.md

In `{REPO_DIR}/PCIMobile/release-notes.md`:
- If the marketing version changed, add a new `### Version X.X.X` header after the `## Release Notes` line, followed by a blank line
- Add a new `### Build YYYY.M.N` header under the current version
- Add all release note entries as bullet points using `-` prefix
- Keep existing content below

Format:
```
# PCI Mobile
## Release Notes

### Version X.X.X    ← only if version changed, otherwise keep existing

### Build YYYY.M.N   ← new build entry
- PF-XX: description
- PF-YY: description

### Build YYYY.M.P   ← previous build entry (already existed)
- ...
```

### Android — Update build.gradle.kts

In `{REPO_DIR}/app/build.gradle.kts`:
- Replace `versionCode = <old>` with `versionCode = <new>`
- If the marketing version changed, replace `versionName = "<old>"` with `versionName = "<new>"`

### Android — Update release-notes.md

In `{REPO_DIR}/release-notes.md`:
- If the marketing version changed, update the `## Version X.X.X` header at the top
- Add a new `## NNNN` header (the new versionCode) below the version header
- Add all release note entries as bullet points using `*` prefix (Android uses asterisks)
- Keep existing content below

Format:
```
# PCI Mobile Release Notes
## Version X.X.X     ← update if version changed

## NNNN              ← new build entry
* PF-XX: description
* PF-YY: description

## PPPP              ← previous build entry (already existed)
* ...
```

---

## Step 7: Commit

Stage ONLY the changed files and commit from `{REPO_DIR}` with message:

For iOS:
```
Prep build YYYY.M.N for version X.X.X
```

For Android:
```
Prep build NNNN for version X.X.X
```

Do NOT push — just commit locally on the current branch.

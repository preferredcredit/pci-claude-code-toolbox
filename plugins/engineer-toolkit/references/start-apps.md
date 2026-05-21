# Start Apps (`/smoke` Phase 2)

Concrete commands for the two start modes in `/smoke` Phase 2. The skill body owns the orchestration (which mode, what gets logged, when to abort); this file owns the literal command strings.

Substitute `<workspace>`, `<TARGET>`, `<repo>`, `<port>`, `<solution>`, `<startup_project>`, `<launch_profile>`, `<ready_signal>`, `<log path>` from values resolved in the skill's earlier phases.

## `--vs` mode (user starts apps in Visual Studio)

The user starts each app manually and pastes the log path. Validate that the path the user supplies actually exists and is fresh:

```powershell
$exists = Test-Path "<path>"
$age = if ($exists) { (Get-Date) - (Get-Item "<path>").LastWriteTime } else { $null }
```

If `-not $exists` or `$age.TotalMinutes -gt 5`, re-prompt the user. Store accepted paths in memory and set `apps_started_by: vs` in `smoke.md` frontmatter.

## Default mode (Claude starts apps)

### Step 1: Port probe (per app)

```powershell
$listening = Get-NetTCPConnection -LocalPort <port> -State Listen -ErrorAction SilentlyContinue
```

If listening, prompt `R | K | A` (reuse running / kill PID / abort). On `K`, identify the owning PID and `Stop-Process -Id <pid> -Force` before proceeding.

### Step 2: Build (per repo, once)

```bash
cd "<workspace>/Active/<TARGET>/AgentWorkspace/<repo>"
dotnet build "<solution>"
```

Non-zero exit → halt, surface the error, abort.

### Step 3: Spawn (per app, in dependency order)

```bash
cd "<workspace>/Active/<TARGET>/AgentWorkspace/<repo>"
dotnet run --project "<startup_project>" --launch-profile <launch_profile> > "<workspace>/Active/<TARGET>/<repo>.log" 2>&1
```

Spawn via Bash with `run_in_background: true`. Capture the returned shell ID for cleanup.

### Step 4: Ready-signal poll (per app, 60s timeout)

```powershell
$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $deadline) {
  if (Select-String -Path "<log path>" -Pattern "<ready_signal>" -SimpleMatch -Quiet) { break }
  Start-Sleep -Milliseconds 500
}
if ((Get-Date) -ge $deadline) { abort "Ready-signal timeout for <repo>." }
```

After all apps signal ready: set `apps_started_by: claude` in `smoke.md` frontmatter; record PID + shell ID per app for cleanup.

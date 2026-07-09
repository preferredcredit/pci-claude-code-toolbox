<#
.SYNOPSIS
  Re-runnable front-half of /work: VPN probe + Active-queue scan.

.DESCRIPTION
  Performs the two mechanical, deterministic steps of /work in one pass so they
  can be re-run any time without dispatching subagents:

    1. VPN probe   - resolves the on-prem host (gates git clone/push).
    2. Queue scan  - enumerates <Workspace>\Active\*, reads each <dir>\<dir>.md,
                     detects the `go` flag (first non-empty line starts with go),
                     and captures Status/Priority/Tier and whether the item is
                     ticketed (has a Jira: line).

  Emits a single JSON object: { vpn, workspace, target, resolution, items[] }.
  Each item carries a `queued` boolean (true when go-flagged).
  Items are pre-sorted by Priority (High>Medium>Low; unknown=Medium) then name.

  When -Target is supplied, `resolution` reports how the argument resolved
  against the top-level Active directory names (exact -> upper-cased Jira-key
  -> substring, first match wins):
    status = 'one'          resolvedTarget names the single match; items[] scans it.
    status = 'multiple'     candidates[] lists the ambiguous matches; items[] empty.
    status = 'zero'         no match and the arg is not a Jira key (adhoc miss).
    status = 'jirakey-miss' no local folder but the arg looks like a Jira key;
                            importKey holds the upper-cased key for /work to import.
  Resolution uses Get-ChildItem -Directory only (no recursion, no file globbing),
  so it never returns build artifacts under AgentWorkspace\.

  Dispatch, sorting beyond this, and all judgment stay with the caller. This
  script never modifies issue files and never dispatches anything.

.PARAMETER Workspace
  Workspace root containing the Active\ folder. Required — comes from the
  workspace CLAUDE.md ## Configuration block; the /work skill passes it in.
  There are no environment-specific defaults.

.PARAMETER VpnHost
  On-prem host to probe for VPN connectivity. Empty = skip the probe
  (reported ok=true).

.PARAMETER Target
  Targeted mode: resolve this argument to a single Active directory (exact ->
  upper-cased Jira-key -> substring) and scan only that directory. The outcome
  is reported in the `resolution` block; items[] is populated only on a single
  match.

.PARAMETER SkipVpn
  Skip the VPN probe (reports ok=true with a note). Useful for offline scans.

.EXAMPLE
  powershell -NoProfile -File scan-queue.ps1 -Workspace C:\ClaudeWorkspace -VpnHost tfs.example.net
.EXAMPLE
  powershell -NoProfile -File scan-queue.ps1 -Workspace C:\ClaudeWorkspace -VpnHost tfs.example.net -Target CO-322
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Workspace,
    [string]$VpnHost = '',
    [string]$Target,
    [switch]$SkipVpn
)

$ErrorActionPreference = 'Stop'

function Test-Vpn {
    param([string]$HostName)
    if (-not $HostName) {
        return [ordered]@{ host = $HostName; ok = $true; detail = 'no host configured; probe skipped' }
    }
    try {
        $res = Resolve-DnsName -Name $HostName -ErrorAction Stop -QuickTimeout
        $ok  = [bool]$res
        return [ordered]@{ host = $HostName; ok = $ok; detail = if ($ok) { 'resolving' } else { 'no records' } }
    } catch {
        return [ordered]@{ host = $HostName; ok = $false; detail = $_.Exception.Message }
    }
}

function Get-Field {
    param([string[]]$Lines, [string]$Name)
    $escaped = [regex]::Escape($Name)
    foreach ($l in $Lines) {
        if ($l -match "^\s*$escaped\s*:\s*(.*)$") { return $Matches[1].Trim() }
    }
    return ''
}

function Resolve-Target {
    param([string]$Arg, [string[]]$Names)

    $resolution = [ordered]@{
        arg            = $Arg
        status         = $null   # one | multiple | zero | jirakey-miss
        resolvedTarget = $null
        candidates     = @()
        importKey      = $null
    }

    # 1. exact directory match (case-insensitive)
    $exact = @($Names | Where-Object { $_ -ieq $Arg })
    if ($exact.Count -ge 1) {
        $resolution.status = 'one'; $resolution.resolvedTarget = $exact[0]; return $resolution
    }

    # 2. upper-cased Jira-key exact match (co-322 -> CO-322)
    $looksLikeKey = $Arg -match '^[a-zA-Z]+-\d+$'
    if ($looksLikeKey) {
        $upper = $Arg.ToUpper()
        $keyMatch = @($Names | Where-Object { $_ -ieq $upper })
        if ($keyMatch.Count -ge 1) {
            $resolution.status = 'one'; $resolution.resolvedTarget = $keyMatch[0]; return $resolution
        }
    }

    # 3. substring match (case-insensitive)
    $argLower = $Arg.ToLower()
    $sub = @($Names | Where-Object { $_.ToLower().Contains($argLower) })
    if ($sub.Count -eq 1) {
        $resolution.status = 'one'; $resolution.resolvedTarget = $sub[0]; return $resolution
    }
    if ($sub.Count -gt 1) {
        $resolution.status = 'multiple'; $resolution.candidates = $sub; return $resolution
    }

    # zero matches: a Jira-key-shaped arg becomes an import signal; otherwise adhoc miss
    if ($looksLikeKey) {
        $resolution.status = 'jirakey-miss'; $resolution.importKey = $Arg.ToUpper()
    } else {
        $resolution.status = 'zero'
    }
    return $resolution
}

$activeRoot = Join-Path $Workspace 'Active'
if (-not (Test-Path $activeRoot)) {
    Write-Error "Active folder not found: $activeRoot"
    exit 2
}

$vpn = if ($SkipVpn) {
    [ordered]@{ host = $VpnHost; ok = $true; detail = 'probe skipped (-SkipVpn)' }
} else {
    Test-Vpn -HostName $VpnHost
}

$priRank = @{ 'high' = 0; 'medium' = 1; 'low' = 2 }

$allDirs = Get-ChildItem -Path $activeRoot -Directory
$resolution = $null
$dirs = $allDirs
if ($Target) {
    $resolution = Resolve-Target -Arg $Target -Names @($allDirs.Name)
    if ($resolution.status -eq 'one') {
        $dirs = @($allDirs | Where-Object { $_.Name -ieq $resolution.resolvedTarget })
    } else {
        # multiple / zero / jirakey-miss: nothing to scan; caller acts on resolution
        $dirs = @()
    }
}

$items = foreach ($d in $dirs) {
    $issueFile = Join-Path $d.FullName "$($d.Name).md"
    if (-not (Test-Path $issueFile)) { continue }

    # One unreadable item must not take down the whole scan — emit an error row and keep going.
    try {
        $raw = Get-Content -LiteralPath $issueFile -Raw
    } catch {
        [pscustomobject]@{
            dir        = $d.Name
            goFlagged  = $false
            queued     = $false
            status     = $null
            priority   = $null
            tier       = $null
            ticketed   = $false
            error      = $_.Exception.Message
        }
        continue
    }
    $lines = $raw -split "\r?\n"

    $firstNonEmpty = ($lines | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
    $goFlagged = [bool]($firstNonEmpty -and ($firstNonEmpty.TrimStart() -match '^go(\s|$)'))
    $ticketed   = [bool]($lines | Where-Object { $_ -match '^\s*Jira\s*:' })

    [pscustomobject]@{
        dir        = $d.Name
        goFlagged  = $goFlagged
        queued     = $goFlagged
        status     = Get-Field -Lines $lines -Name 'Status'
        priority   = Get-Field -Lines $lines -Name 'Priority'
        tier       = Get-Field -Lines $lines -Name 'Tier'
        ticketed   = $ticketed
    }
}

$items = @($items) | Sort-Object `
    @{ Expression = { $r = $priRank[("" + $_.priority).ToLower()]; if ($null -eq $r) { 1 } else { $r } } }, `
    dir

$out = [ordered]@{
    vpn        = $vpn
    workspace  = $Workspace
    target     = $Target
    resolution = $resolution
    items      = @($items)
}

$out | ConvertTo-Json -Depth 5

<#
.SYNOPSIS
  Re-runnable front-half of /work: VPN probe + Active-queue scan.

.DESCRIPTION
  Performs the two mechanical, deterministic steps of /work in one pass so they
  can be re-run any time without dispatching subagents:

    1. VPN probe   - resolves the on-prem host (gates git clone/push). Skipped
                     (reported ok=true) when -VpnHost is empty.
    2. Queue scan  - enumerates <Workspace>\Active\*, reads each <dir>\<dir>.md,
                     detects the `go` flag (first non-empty line starts with go),
                     detects `Mode: direct`, and captures Status/Priority/Tier and
                     whether the item is ticketed (has a Jira: line).

  Emits a single JSON object: { vpn, workspace, target, items[] }.
  Each item carries a `queued` boolean (go-flagged AND not Mode: direct).
  Items are pre-sorted by Priority (High>Medium>Low; unknown=Medium) then name.

  Dispatch, sorting beyond this, and all judgment stay with the caller. This
  script never modifies issue files and never dispatches anything.

  Workspace and VpnHost come from the workspace CLAUDE.md ## Configuration block;
  the /work skill passes them in. There are no environment-specific defaults.

.PARAMETER Workspace
  Workspace root containing the Active\ folder. Required.

.PARAMETER VpnHost
  On-prem host to probe for VPN connectivity. Empty = skip the probe.

.PARAMETER Target
  Targeted mode: scan only this Active directory (case-insensitive exact match).

.PARAMETER SkipVpn
  Skip the VPN probe (reports ok=true with a note).

.EXAMPLE
  powershell -NoProfile -File scan-queue.ps1 -Workspace C:\ClaudeWorkspace -VpnHost tfs.preferredcredit.net
.EXAMPLE
  powershell -NoProfile -File scan-queue.ps1 -Workspace C:\ClaudeWorkspace -VpnHost git.corp.local -Target CO-322
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

$dirs = Get-ChildItem -Path $activeRoot -Directory
if ($Target) { $dirs = $dirs | Where-Object { $_.Name -ieq $Target } }

$items = foreach ($d in $dirs) {
    $issueFile = Join-Path $d.FullName "$($d.Name).md"
    if (-not (Test-Path $issueFile)) { continue }

    $raw   = Get-Content -LiteralPath $issueFile -Raw
    $lines = $raw -split "\r?\n"

    $firstNonEmpty = ($lines | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
    $goFlagged  = [bool]($firstNonEmpty -and ($firstNonEmpty.TrimStart() -match '^go(\s|$)'))
    $modeDirect = [bool]($lines | Where-Object { $_ -match '^\s*Mode\s*:\s*direct\s*$' })
    $ticketed   = [bool]($lines | Where-Object { $_ -match '^\s*Jira\s*:' })

    [pscustomobject]@{
        dir        = $d.Name
        goFlagged  = $goFlagged
        modeDirect = $modeDirect
        queued     = ($goFlagged -and -not $modeDirect)
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
    vpn       = $vpn
    workspace = $Workspace
    target    = $Target
    items     = @($items)
}

$out | ConvertTo-Json -Depth 5

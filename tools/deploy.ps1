# Deploy only runtime addon files from this repo to the live RoR AddOns folder.
# Copies: EZGuard.mod + root runtime Lua + libs\
# Removes anything else under Dest (.git, docs, README, old backups, workspace files, etc.).
#
# Usage:
#   .\tools\deploy.ps1
#   .\tools\deploy.ps1 -WhatIf
#   .\tools\deploy.ps1 -Dest "D:\Games\...\Interface\AddOns\EZGuard"

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Dest = "C:\Users\talla\Games\Return of Reckoning\Interface\AddOns\EZGuard"
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Dest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Dest)
$DestParent = Split-Path -Parent $Dest
$ModSrc = Join-Path $RepoRoot "EZGuard.mod"

$RootFiles = @(
    "EZGuard.mod",
    "EZGuard.lua",
    "EZGuard_Config.lua"
)

$RuntimeDirs = @(
    "libs"
)

function Test-IsReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path -Force
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

if (-not (Test-Path -LiteralPath $ModSrc)) {
    throw "EZGuard.mod missing under $RepoRoot - refuse to deploy"
}
foreach ($name in $RootFiles) {
    $path = Join-Path $RepoRoot $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required runtime file missing: $name"
    }
}
foreach ($dir in $RuntimeDirs) {
    $path = Join-Path $RepoRoot $dir
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required runtime folder missing: $dir\"
    }
}
if (-not (Test-Path -LiteralPath $DestParent)) {
    throw "AddOns parent missing: $DestParent"
}
$destLeaf = Split-Path -Leaf $Dest
if ($destLeaf -ne "EZGuard") {
    throw "Dest must be an EZGuard folder (leaf name EZGuard), got: $destLeaf ($Dest)"
}
$parentLeaf = Split-Path -Leaf $DestParent
if ($parentLeaf -ne "AddOns") {
    throw "Dest parent must be an AddOns folder, got: $parentLeaf ($DestParent)"
}

$resolvedRepo = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
$resolvedDest = [IO.Path]::GetFullPath($Dest).TrimEnd('\')
$repoPrefix = $resolvedRepo + [IO.Path]::DirectorySeparatorChar
$destPrefix = $resolvedDest + [IO.Path]::DirectorySeparatorChar
if (
    $resolvedDest -ieq $resolvedRepo -or
    $resolvedDest.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    $resolvedRepo.StartsWith($destPrefix, [StringComparison]::OrdinalIgnoreCase)
) {
    throw "Dest must not overlap the git clone: dest=$resolvedDest repo=$resolvedRepo"
}
if (Test-IsReparsePoint -Path $Dest) {
    throw "Dest is a junction/symlink; refuse to deploy: $Dest"
}

Write-Host "Repo:   $RepoRoot"
Write-Host "Dest:   $Dest"
Write-Host ("Copy:   " + ($RootFiles -join ", ") + " + " + (($RuntimeDirs | ForEach-Object { "$_\" }) -join " "))

if (-not $PSCmdlet.ShouldProcess($Dest, "Deploy runtime addon files and prune extras")) {
    exit 0
}

New-Item -ItemType Directory -Force -Path $Dest | Out-Null

function Invoke-RobocopyMirror {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (Test-IsReparsePoint -Path $Destination) {
        throw "Runtime folder is a junction/symlink; refuse to mirror: $Destination"
    }

    $robocopyArgs = @(
        $Source,
        $Destination,
        "/MIR",
        "/R:2", "/W:1",
        "/NFL", "/NDL", "/NP", "/NJH"
    )
    # Swallow robocopy stdout so callers only receive the exit code.
    & robocopy @robocopyArgs | Out-Null
    $rc = $LASTEXITCODE
    # Robocopy: 0-7 = success (with optional extras); >=8 = failure
    if ($rc -ge 8) {
        throw "robocopy failed ($Source -> $Destination) with exit code $rc"
    }
    return $rc
}

$lastRc = 0
foreach ($dir in $RuntimeDirs) {
    $src = Join-Path $RepoRoot $dir
    $dst = Join-Path $Dest $dir
    $lastRc = Invoke-RobocopyMirror -Source $src -Destination $dst
}

foreach ($name in $RootFiles) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot $name) -Destination (Join-Path $Dest $name) -Force
}

# Keep Dest as a runtime-only tree: remove anything that is not an allowed root entry.
$allowed = @{}
foreach ($name in $RootFiles) { $allowed[$name] = $true }
foreach ($dir in $RuntimeDirs) { $allowed[$dir] = $true }

Get-ChildItem -LiteralPath $Dest -Force | ForEach-Object {
    if ($allowed.ContainsKey($_.Name)) { return }
    Write-Host "Prune: $($_.FullName)"
    if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        # DirectoryInfo/FileInfo.Delete removes the link itself on Windows PowerShell 5.1.
        $_.Delete()
    } else {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
}

$destMod = Join-Path $Dest "EZGuard.mod"
if (-not (Test-Path -LiteralPath $destMod)) {
    throw "Deploy incomplete: missing EZGuard.mod under $Dest"
}
foreach ($dir in $RuntimeDirs) {
    if (-not (Test-Path -LiteralPath (Join-Path $Dest $dir))) {
        throw "Deploy incomplete: missing $dir\ under $Dest"
    }
}

$fileCount = 0
foreach ($dir in $RuntimeDirs) {
    $fileCount += @(Get-ChildItem -LiteralPath (Join-Path $Dest $dir) -Recurse -File).Count
}
$fileCount += $RootFiles.Count

Write-Host "Deploy OK (runtime files: $fileCount, last robocopy exit $lastRc). Reload UI in-game (/reload)."
exit 0

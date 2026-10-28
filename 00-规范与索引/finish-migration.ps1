# work_doc migration finisher.
# IMPORTANT: this file is intentionally pure ASCII. All Chinese folder names come
# from UTF-8 data files, because Windows PowerShell 5.1 reads .ps1 as ANSI.
# Usage: powershell -ExecutionPolicy Bypass -File "00-<dir>\finish-migration.ps1"

param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$mapFile = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.tsv' |
    Where-Object { $_.Name -ne 'img-refs.tsv' } | Select-Object -First 1
$imgFile = Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'img-refs.tsv' | Select-Object -First 1
if (-not $mapFile) { throw 'mapping tsv not found next to this script' }

$moved = 0; $done = 0; $skipped = 0
$failed = @(); $missing = @(); $legacyDirs = @()

function Read-Utf8Lines([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) -split "`r?`n"
}

foreach ($line in (Read-Utf8Lines $mapFile.FullName)) {
    if (-not $line -or $line.Trim() -eq '' -or $line.StartsWith('#')) { continue }
    $parts = $line -split "`t", 2
    if ($parts.Count -lt 2) { continue }

    if ($parts[0].Trim() -eq '!DIR') { $legacyDirs += $parts[1].Trim(); continue }

    $src = $parts[0].Trim()
    $dst = $parts[1].Trim()
    $srcExists = Test-Path -LiteralPath $src
    $dstExists = Test-Path -LiteralPath $dst

    if (-not $srcExists) {
        if ($dstExists) { $done++ } else { $missing += $src }
        continue
    }
    if ($dstExists) { $skipped++; continue }

    $dir = Split-Path -Parent $dst
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    if ($DryRun) { $moved++; Write-Host ('  would move: ' + $src); continue }
    try {
        Move-Item -LiteralPath $src -Destination $dst -Force
        $moved++
    } catch {
        $failed += ($src + '  ::  ' + $_.Exception.Message)
    }
}

if ($DryRun) {
    Write-Host ''
    Write-Host ('DRY RUN: ' + $moved + ' moves planned, ' + $skipped + ' skipped, ' + $missing.Count + ' not found. Nothing changed.')
    $missing | ForEach-Object { Write-Host ('  not found: ' + $_) }
    exit 0
}

# ---- rewrite image references ----
$fixed = 0
if ($imgFile) {
    foreach ($line in (Read-Utf8Lines $imgFile.FullName)) {
        if (-not $line -or $line.Trim() -eq '' -or $line.StartsWith('#')) { continue }
        $c = $line -split "`t", 3
        if ($c.Count -lt 3) { continue }
        $file = $c[0].Trim(); $old = $c[1].Trim(); $new = $c[2].Trim()
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $text = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
        if ($text.Contains($old)) {
            $text = $text.Replace($old, $new)
            [System.IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding($false)))
            $fixed++
        }
    }
}

# ---- drop empty legacy folders ----
$removedDirs = 0
foreach ($legacy in $legacyDirs) {
    if (-not (Test-Path -LiteralPath $legacy)) { continue }
    $rest = @(Get-ChildItem -LiteralPath $legacy -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '_keep.md' })
    if ($rest.Count -eq 0) {
        Remove-Item -LiteralPath $legacy -Recurse -Force
        $removedDirs++
        Write-Host ('  removed empty folder: ' + $legacy)
    } else {
        Write-Host ('  KEPT (still ' + $rest.Count + ' files): ' + $legacy)
    }
}

# ---- clean Word lock files ----
$locks = 0
Get-ChildItem -Filter '~$*.docx' -File -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Force
    $locks++
}

Write-Host ''
Write-Host ('moved=' + $moved + ' alreadyDone=' + $done + ' skipped=' + $skipped + ' imgRefsFixed=' + $fixed + ' dirsRemoved=' + $removedDirs + ' locks=' + $locks + ' failed=' + $failed.Count + ' missing=' + $missing.Count)

if ($missing.Count -gt 0) {
    Write-Host '--- source and target both absent (check manually) ---'
    $missing | ForEach-Object { Write-Host ('  ' + $_) }
}
if ($failed.Count -gt 0) {
    Write-Host '--- failed, close any program locking these and run again (idempotent) ---'
    $failed | ForEach-Object { Write-Host ('  ' + $_) }
}

git add -A
Write-Host ''
Write-Host 'git status:'
git status --short
Write-Host ''
Write-Host "Review the list, then run:  git commit -m 'chore: reorganize docs by function domain'"

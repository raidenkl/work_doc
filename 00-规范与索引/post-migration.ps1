# work_doc post-migration fixer (pure ASCII; Chinese paths are discovered at runtime).
# Step 1: rewrite image links that still point at photo/ into _assets/<doc name>/
# Step 2: delete leftover _keep.md placeholders
# Step 3: keep .workbuddy/ out of git, then stage + commit
#
# Usage: powershell -ExecutionPolicy Bypass -File "00-<dir>\post-migration.ps1" [-DryRun]

param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$catPattern = '^\d\d-'
$fixedFiles = 0
$fixedLinks = 0

$mdFiles = Get-ChildItem -LiteralPath $root -Recurse -Filter '*.md' -File |
    Where-Object { $_.FullName -notmatch '\\\.workbuddy\\' -and $_.FullName -notmatch '\\\.git\\' }

foreach ($f in $mdFiles) {
    $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    if ($text -notmatch 'photo/') { continue }

    $before = ([regex]::Matches($text, 'photo/')).Count
    $repl = '(_assets/' + $f.BaseName + '/'
    $new = [regex]::Replace($text, '\([^)\r\n]*?photo/', $repl)

    if ($new -ne $text) {
        if (-not $DryRun) {
            [System.IO.File]::WriteAllText($f.FullName, $new, $utf8NoBom)
        }
        $after = ([regex]::Matches($new, 'photo/')).Count
        $fixedLinks += ($before - $after)
        $fixedFiles++
        Write-Host ('  ' + $f.FullName.Replace($root + '\', '') + '  links fixed: ' + ($before - $after))
    }
}

$keeps = Get-ChildItem -LiteralPath $root -Recurse -Filter '_keep.md' -File |
    Where-Object { $_.FullName -notmatch '\\\.workbuddy\\' }
foreach ($k in $keeps) {
    if (-not $DryRun) { Remove-Item -LiteralPath $k.FullName -Force }
    Write-Host ('  removed placeholder: ' + $k.FullName.Replace($root + '\', ''))
}

Write-Host ''
Write-Host ('files changed=' + $fixedFiles + ' links fixed=' + $fixedLinks + ' placeholders removed=' + $keeps.Count)

if ($DryRun) {
    Write-Host 'DRY RUN: nothing written, nothing committed.'
    exit 0
}

$ignorePath = Join-Path $root '.gitignore'
$ignore = ''
if (Test-Path -LiteralPath $ignorePath) {
    $ignore = [System.IO.File]::ReadAllText($ignorePath, [System.Text.Encoding]::UTF8)
}
if ($ignore -notmatch '(?m)^\s*\.workbuddy/?\s*$') {
    $sep = ''
    if ($ignore.Length -gt 0 -and -not $ignore.EndsWith("`n")) { $sep = "`r`n" }
    [System.IO.File]::WriteAllText($ignorePath, $ignore + $sep + '.workbuddy/' + "`r`n", $utf8NoBom)
    Write-Host '  .gitignore: added .workbuddy/'
}

git rm -r --cached --quiet .workbuddy 2>$null
git add -A
Write-Host ''
Write-Host 'staged:'
git status --short

$pending = git status --porcelain
if ($pending) {
    git commit -q -m "chore: reorganize docs by function domain"
    Write-Host ''
    Write-Host 'committed:'
    git log --oneline -1
} else {
    Write-Host ''
    Write-Host 'nothing to commit'
}

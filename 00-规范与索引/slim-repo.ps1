# Slim down .git by repacking, and optionally purging large binaries from history.
# Pure ASCII on purpose.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File "00-<dir>\slim-repo.ps1"                        # dry look: sizes only
#   powershell -ExecutionPolicy Bypass -File "00-<dir>\slim-repo.ps1" -Repack                # git gc only (safe)
#   powershell -ExecutionPolicy Bypass -File "00-<dir>\slim-repo.ps1" -PurgeHistory -Yes     # rewrite history
#
# -PurgeHistory removes these paths from EVERY commit (23 commits), then gc:
#     *.deb              72 MB total, four kernel packages, useless for a docs repo
#     imx415_*.json       2 MB, imx415 tuning file (already deleted from the tree)
# It rewrites commit ids, so the remote needs `git push --force`.
#
# NOT touched: the 123 MB .git/lfs store (debian11 qt touch archive, tracked via
# Git LFS). Delete it by hand only if you move that archive to a GitHub Release:
#     git rm --cached "<path to the .7z>"; git lfs prune; git commit -m "chore: drop lfs archive"

param(
    [switch]$Repack,
    [switch]$PurgeHistory,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Get-GitSizeMB {
    $git = Join-Path $root '.git'
    if (-not (Test-Path -LiteralPath $git)) { return 0 }
    $sum = (Get-ChildItem -LiteralPath $git -Recurse -File -Force -ErrorAction SilentlyContinue |
        Measure-Object Length -Sum).Sum
    return [math]::Round($sum / 1MB, 1)
}

function Show-Breakdown {
    Write-Host ''
    Write-Host ('  .git total : ' + (Get-GitSizeMB) + ' MB')
    $lfs = Join-Path $root '.git\lfs'
    if (Test-Path -LiteralPath $lfs) {
        $s = (Get-ChildItem -LiteralPath $lfs -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum).Sum
        Write-Host ('  .git/lfs   : ' + [math]::Round($s / 1MB, 1) + ' MB  (Git LFS objects)')
    }
    $co = git count-objects -vH
    $co | Where-Object { $_ -match 'size|count|packs' } | ForEach-Object { Write-Host ('  ' + $_) }
    Write-Host ''
}

Write-Host '=== current ==='
Show-Breakdown

if (-not $Repack -and -not $PurgeHistory) {
    Write-Host 'Nothing to do. Add -Repack (safe) or -PurgeHistory -Yes (rewrites history).'
    exit 0
}

$dirty = git status --porcelain
if ($dirty) {
    Write-Host 'ABORT: working tree is not clean. Commit or stash first.'
    exit 1
}

if ($PurgeHistory -and -not $Yes) {
    Write-Host 'Would rewrite all commits to drop: *.deb , imx415_*.json'
    Write-Host 'Re-run with:  -PurgeHistory -Yes'
    Write-Host 'After that the remote needs:  git push --force origin main'
    exit 0
}

# ---- backup first ----
$backupDir = Join-Path $env:USERPROFILE 'work_doc_backup'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bundle = Join-Path $backupDir ('work_doc-' + $stamp + '.bundle')
git bundle create $bundle --all | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host 'ABORT: bundle backup failed.'; exit 1 }
Write-Host ('backup bundle: ' + $bundle)

# ---- optional history purge ----
if ($PurgeHistory) {
    $env:FILTER_BRANCH_SQUELCH_WARNING = '1'
    $filter = 'git rm -q --cached --ignore-unmatch "*.deb" "imx415_*.json"'
    Write-Host ''
    Write-Host 'rewriting all commits (this can take a minute)...'
    git filter-branch --force --index-filter $filter --prune-empty --tag-name-filter cat -- --all
    if ($LASTEXITCODE -ne 0) { Write-Host 'ABORT: filter-branch failed, history unchanged.'; exit 1 }

    $orig = @(git for-each-ref --format='%(refname)' refs/original/)
    foreach ($r in $orig) { git update-ref -d $r }
    git reflog expire --expire=now --all
    Write-Host ('  dropped ' + $orig.Count + ' backup refs')
}

# ---- repack ----
Write-Host ''
Write-Host 'repacking...'
git gc --prune=now -f
if ($LASTEXITCODE -ne 0) { Write-Host 'WARN: git gc returned non-zero.' }

Write-Host '=== after ==='
Show-Breakdown

if ($PurgeHistory) {
    Write-Host 'History rewritten. To publish:'
    Write-Host '    git push --force origin main'
    Write-Host 'Anyone else who cloned this repo must re-clone.'
    Write-Host ''
    Write-Host ('Rollback if needed: git clone ' + $bundle + ' work_doc_restore')
}

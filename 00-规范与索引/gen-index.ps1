# Regenerate the document index block inside README.md from each doc's front-matter.
# Pure ASCII on purpose: Windows PowerShell 5.1 reads .ps1 as ANSI, so any Chinese
# literal here would be mangled. All Chinese text is read from the .md files.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File "00-<dir>\gen-index.ps1"          # rewrite README
#   powershell -ExecutionPolicy Bypass -File "00-<dir>\gen-index.ps1" -Check   # report only
#
# Block boundaries in README.md:  <!-- INDEX:BEGIN -->  ...  <!-- INDEX:END -->

param([switch]$Check)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$readme = Join-Path $root 'README.md'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$enc = [System.Text.Encoding]::UTF8

function Get-FrontMatter([string]$path) {
    $lines = [System.IO.File]::ReadAllText($path, $enc) -split "`r?`n"
    if ($lines.Count -gt 0) { $lines[0] = $lines[0].TrimStart([char]0xFEFF) }
    if ($lines.Count -lt 3 -or $lines[0].Trim() -ne '---') { return $null }
    $fm = @{}
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l.Trim() -eq '---') { return $fm }
        $p = $l.IndexOf(':')
        if ($p -le 0) { continue }
        $k = $l.Substring(0, $p).Trim()
        $v = $l.Substring($p + 1).Trim()
        if ($v.StartsWith('[') -and $v.EndsWith(']')) { $v = $v.Substring(1, $v.Length - 2) }
        $v = $v.Trim('"').Trim("'").Trim()
        if ($k) { $fm[$k] = $v }
    }
    return $fm
}

$cats = Get-ChildItem -LiteralPath $root -Directory |
    Where-Object { $_.Name -match '^\d\d-' -and $_.Name -notmatch '^00-' } |
    Sort-Object Name

$sb = New-Object System.Text.StringBuilder
$rows = 0
$warn = @()

foreach ($cat in $cats) {
    $files = Get-ChildItem -LiteralPath $cat.FullName -Recurse -File |
        Where-Object { $_.Extension -in '.md', '.pdf', '.docx' -and $_.Name -ne '_keep.md' } |
        Sort-Object FullName

    $mdBase = @{}
    $pdfBase = @{}
    foreach ($f in $files) {
        if ($f.Extension -eq '.md') { $mdBase[$f.BaseName] = $true }
        if ($f.Extension -eq '.pdf') { $pdfBase[$f.BaseName] = $true }
    }

    [void]$sb.AppendLine('### ' + $cat.Name)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| 文档 | 说明 | 板卡 | 格式 | 更新 |')
    [void]$sb.AppendLine('|---|---|---|---|---|')

    foreach ($f in $files) {
        if ($f.Extension -ne '.md' -and $mdBase.ContainsKey($f.BaseName)) { continue }
        if ($f.Extension -eq '.docx' -and $pdfBase.ContainsKey($f.BaseName)) { continue }

        $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')

        if ($f.Extension -eq '.md') {
            $fm = Get-FrontMatter $f.FullName
            if (-not $fm) { $warn += ($rel + '  ::  no front-matter'); $fm = @{} }
            elseif (-not $fm.ContainsKey('summary')) { $warn += ($rel + '  ::  no summary') }

            $title = if ($fm['title']) { $fm['title'] } else { $f.BaseName }
            $sum = if ($fm['summary']) { $fm['summary'] } else { '—' }
            $board = if ($fm['board']) { $fm['board'] } else { '—' }
            $fmt = if ($fm['formats']) { ($fm['formats'] -replace '\s*,\s*', '+') } else { 'md' }
            $upd = if ($fm['updated']) { $fm['updated'] } else { '—' }
        } else {
            $title = $f.BaseName
            $sum = '—'
            $board = '—'
            $fmt = $f.Extension.TrimStart('.').ToLower()
            $upd = '—'
        }

        [void]$sb.AppendLine('| [' + $title + '](' + $rel + ') | ' + $sum + ' | ' + $board + ' | ' + $fmt + ' | ' + $upd + ' |')
        $rows++
    }
    [void]$sb.AppendLine('')
}

Write-Host ('indexed files: ' + $rows)
if ($warn.Count -gt 0) {
    Write-Host '--- fields missing (row still emitted with fallback) ---'
    $warn | ForEach-Object { Write-Host ('  ' + $_) }
}

if ($Check) {
    Write-Host 'CHECK mode: README not modified.'
    exit 0
}

$begin = '<!-- INDEX:BEGIN -->'
$end = '<!-- INDEX:END -->'
$text = [System.IO.File]::ReadAllText($readme, $enc)
$i1 = $text.IndexOf($begin)
$i2 = $text.IndexOf($end)
if ($i1 -lt 0 -or $i2 -lt 0 -or $i2 -lt $i1) { throw ('markers not found in README.md: ' + $begin + ' / ' + $end) }

$body = $sb.ToString().TrimEnd()
$newText = $text.Substring(0, $i1 + $begin.Length) + "`r`n`r`n" + $body + "`r`n`r`n" + $text.Substring($i2)
[System.IO.File]::WriteAllText($readme, $newText, $utf8NoBom)
Write-Host 'README.md index block updated.'

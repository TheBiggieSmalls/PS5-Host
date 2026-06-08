# ============================================================
#  update_payloads.ps1
#  Called by update_payloads.bat - keep both files together.
# ============================================================

$ErrorActionPreference = 'Stop'

$root        = Split-Path -Parent $MyInvocation.MyCommand.Path
$payloadsDir = Join-Path $root 'payloads'
$appcache    = Join-Path $root 'cache.appcache'
$payloadMap  = Join-Path $root 'payload_map.js'
$utf8nobom   = [System.Text.UTF8Encoding]::new($false)

# ---- Sanity checks ------------------------------------------
foreach ($p in @($payloadsDir, $appcache, $payloadMap)) {
    if (-not (Test-Path $p)) {
        Write-Host "[ERROR] Not found: $p" -ForegroundColor Red
        exit 1
    }
}

Write-Host "  Root    : $root"
Write-Host "  Payloads: $payloadsDir"
Write-Host ""

function Get-SHA256 {
    param($path)
    return (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower()
}

$changed      = $false
$newFiles     = @()
$updatedFiles = @()

$acLines = [System.IO.File]::ReadAllLines($appcache)
$pmLines = [System.IO.File]::ReadAllLines($payloadMap)

# Get-ChildItem -Include requires -Recurse to filter by extension on a path,
# so we use a wildcard in the path directly instead.
$ignoredFiles = @('elfldr-ps5.elf')

$files = @(Get-ChildItem -Path "$payloadsDir\*.elf") + @(Get-ChildItem -Path "$payloadsDir\*.bin") |
         Where-Object { $ignoredFiles -notcontains $_.Name }

Write-Host "  Found $($files.Count) payload file(s) in payloads\"
Write-Host ""

foreach ($f in $files) {
    $fname    = $f.Name
    $entry    = "payloads/$fname"
    $realHash = Get-SHA256 $f.FullName

    # Find existing line index in appcache
    $matchIdx = -1
    for ($i = 0; $i -lt $acLines.Count; $i++) {
        if ($acLines[$i] -match [regex]::Escape($entry)) {
            $matchIdx = $i
            break
        }
    }

    if ($matchIdx -lt 0) {
        # ── NEW file ─────────────────────────────────────────
        Write-Host "[NEW]  $fname" -ForegroundColor Cyan
        Write-Host "       Hash: $realHash"

        # Insert before NETWORK: line
        $newLine = "$entry #$realHash"
        $netIdx  = -1
        for ($i = 0; $i -lt $acLines.Count; $i++) {
            if ($acLines[$i].Trim() -eq 'NETWORK:') { $netIdx = $i; break }
        }
        if ($netIdx -ge 0) {
            $acLines = $acLines[0..($netIdx - 1)] + $newLine + $acLines[$netIdx..($acLines.Count - 1)]
        } else {
            $acLines += $newLine
        }

        # Add stub to payload_map.js before closing ];
        $stub = @(
            '    {',
            "        displayTitle: `"$fname`",",
            '        description: "TODO: add description",',
            "        fileName: `"$fname`",",
            '        author: "TODO: add author",',
            '        projectSource: "TODO: add source URL",',
            '        binarySource: "TODO: add binary URL",',
            '        version: "1.0",',
            '        toPort: 9021',
            '    },'
        )
        $closeIdx = -1
        for ($i = $pmLines.Count - 1; $i -ge 0; $i--) {
            if ($pmLines[$i].Trim() -eq '];') { $closeIdx = $i; break }
        }
        if ($closeIdx -ge 0) {
            $pmLines = $pmLines[0..($closeIdx - 1)] + $stub + $pmLines[$closeIdx..($pmLines.Count - 1)]
        }
        [System.IO.File]::WriteAllLines($payloadMap, $pmLines, $utf8nobom)

        Write-Host "[OK]   Added to cache.appcache + stub added to payload_map.js" -ForegroundColor Green
        $newFiles += $fname
        $changed   = $true

    } else {
        # ── EXISTING file - check hash ────────────────────────
        $storedLine = $acLines[$matchIdx]
        if ($storedLine -match '#([0-9a-fA-F]+)') {
            $storedHash = $Matches[1].ToLower()
        } else {
            $storedHash = ''
        }

        if ($storedHash -eq $realHash) {
            Write-Host "[OK]   $fname - hash matches" -ForegroundColor Green
        } else {
            Write-Host "[UPD]  $fname - hash mismatch!" -ForegroundColor Yellow
            Write-Host "       Stored : $storedHash"
            Write-Host "       Actual : $realHash"
            $acLines[$matchIdx] = "$entry #$realHash"
            Write-Host "[OK]   Hash updated in cache.appcache" -ForegroundColor Green
            $updatedFiles += $fname
            $changed       = $true
        }
    }
    Write-Host ""
}

# ── Save appcache and rehash payload_map.js if anything changed
if ($changed) {
    [System.IO.File]::WriteAllLines($appcache, $acLines, $utf8nobom)

    Write-Host "Updating payload_map.js hash in cache.appcache..." -ForegroundColor Cyan
    $pmHash   = Get-SHA256 $payloadMap
    $acLines2 = [System.IO.File]::ReadAllLines($appcache)
    for ($i = 0; $i -lt $acLines2.Count; $i++) {
        if ($acLines2[$i] -match 'payload_map\.js') {
            $acLines2[$i] = "payload_map.js #$pmHash"
            break
        }
    }
    [System.IO.File]::WriteAllLines($appcache, $acLines2, $utf8nobom)
    Write-Host "[OK]   payload_map.js hash updated to $pmHash" -ForegroundColor Green
    Write-Host ""
}

# ── Summary ───────────────────────────────────────────────────
Write-Host "============================================================"
if (-not $changed) {
    Write-Host "  Everything is up to date. No changes made." -ForegroundColor Green
} else {
    if ($newFiles.Count -gt 0) {
        Write-Host "  New payloads:" -ForegroundColor Cyan
        $newFiles | ForEach-Object { Write-Host "    + $_" }
        Write-Host "  -> Fill in the TODO fields in payload_map.js" -ForegroundColor Yellow
    }
    if ($updatedFiles.Count -gt 0) {
        Write-Host "  Hash-updated payloads:" -ForegroundColor Yellow
        $updatedFiles | ForEach-Object { Write-Host "    ~ $_" }
    }
}
Write-Host "============================================================"

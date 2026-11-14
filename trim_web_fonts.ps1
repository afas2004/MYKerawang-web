# Removes icon fonts the app never uses from a finished web build.
#
# Flutter web downloads EVERY font in assets/FontManifest.json before the
# first frame. lucide_icons_flutter declares six extra weights (100-600);
# unused ones are not shrunk by icon tree-shaking, so each costs ~180 KB
# (about 900 KB together) on every first visit. A weight is kept only if
# some file under lib/ imports its library (lucide_icons_<weight>.dart).
#
# Run after `flutter build web` (deploy_web.bat does this).
param([string]$Build = 'build\web')

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $Build 'assets\FontManifest.json'
if (-not (Test-Path $manifestPath)) { throw "No $manifestPath - build first." }

$used = @{}
Get-ChildItem -Recurse -Filter *.dart lib | Select-String -Pattern 'lucide_icons_(\d00)\.dart' -AllMatches |
  ForEach-Object { $_.Matches } | ForEach-Object { $used[$_.Groups[1].Value] = $true }

$families = Get-Content $manifestPath -Raw | ConvertFrom-Json
$keep = @()
$removedKb = 0
foreach ($f in $families) {
  if ($f.family -match '^packages/lucide_icons_flutter/Lucide(\d00)$' -and -not $used[$Matches[1]]) {
    foreach ($font in $f.fonts) {
      $file = Join-Path $Build ('assets\' + $font.asset)
      if (Test-Path $file) {
        $removedKb += [math]::Round((Get-Item $file).Length / 1KB)
        Remove-Item $file
      }
    }
    Write-Host "  dropped $($f.family)"
  } else {
    $keep += $f
  }
}

# Compact JSON, UTF-8 without BOM (Flutter parses it with a strict decoder).
$json = ConvertTo-Json -InputObject $keep -Depth 10 -Compress
[IO.File]::WriteAllText((Resolve-Path $manifestPath), $json)
Write-Host "  kept $($keep.Count) font families, removed about $removedKb KB"

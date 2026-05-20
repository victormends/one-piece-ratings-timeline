param(
  [string]$OutputPath,
  [switch]$RefreshRatings,
  [switch]$UseCachedRatings
)

if ($RefreshRatings -and $UseCachedRatings) { throw 'Use either -RefreshRatings or -UseCachedRatings, not both.' }
if (-not $RefreshRatings -and -not $UseCachedRatings) { $RefreshRatings = $true }

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot 'data\generated\entry-metadata.json' }
$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }

& (Join-Path $PSScriptRoot 'generate.ps1') -RefreshRatings:$RefreshRatings -UseCachedRatings:$UseCachedRatings | Out-Null

$htmlPath = Join-Path $repoRoot 'docs\index.html'
$html = [System.IO.File]::ReadAllText($htmlPath)
function Get-JsonBlock([string]$id) {
  return [regex]::Match($html, '<script id="' + [regex]::Escape($id) + '" type="application/json">(?<json>[\s\S]*?)</script>').Groups['json'].Value
}

$episodes = Get-JsonBlock 'episode-data' | ConvertFrom-Json
$sagas = Get-JsonBlock 'saga-data' | ConvertFrom-Json
$subSagas = Get-JsonBlock 'sub-saga-data' | ConvertFrom-Json
$sagaMap = @{}
foreach ($saga in $sagas) { $sagaMap[$saga.key] = $saga.label }
$subSagaMap = @{}
foreach ($subSaga in $subSagas) { $subSagaMap[$subSaga.key] = $subSaga.label }

$categoryLabels = @{
  manga = 'Manga Canon'
  mixed = 'Mixed Canon/Filler'
  filler = 'Filler'
  anime = 'Anime Canon'
  movie = 'Movie'
  special = 'TV Special'
  recap = 'Recap / Remake'
  ova = 'OVA'
  short = 'Short'
}

$entries = foreach ($entry in ($episodes | Sort-Object sortKey)) {
  [pscustomobject]@{
    displayCode = [string]$entry.displayCode
    title = [string]$entry.title
    sagaKey = [string]$entry.saga
    sagaLabel = [string]$sagaMap[$entry.saga]
    subSagaKey = [string]$entry.subSaga
    subSagaLabel = [string]$subSagaMap[$entry.subSaga]
    category = [string]$entry.category
    categoryLabel = [string]$categoryLabels[$entry.category]
    mediaKind = [string]$entry.mediaKind
    placement = [string]$entry.placement
    aired = if ($entry.PSObject.Properties.Name -contains 'aired') { [string]$entry.aired } else { $null }
  }
}

[pscustomobject]@{
  version = 1
  generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
  source = 'scripts/generate.ps1 episode-data, stripped to safe metadata'
  entries = @($entries)
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{ Output = $OutputPath; Entries = @($entries).Count } | ConvertTo-Json

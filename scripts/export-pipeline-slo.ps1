param(
  [ValidateSet('ci', 'refresh')]
  [string]$Mode = 'ci',
  [double]$WarnStaleHours = 24,
  [double]$FailStaleHours = 72,
  [switch]$EnforceFreshnessSlo
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$qualityReportPath = Join-Path $repoRoot 'data\generated\quality-report.json'
$catalogDbReportPath = Join-Path $repoRoot 'data\generated\catalog-db-report.json'
$sloOutputPath = Join-Path $repoRoot 'data\generated\ops-slo-report.json'

if (-not (Test-Path -LiteralPath $qualityReportPath)) { throw "Missing quality report: $qualityReportPath" }
if (-not (Test-Path -LiteralPath $catalogDbReportPath)) { throw "Missing catalog DB report: $catalogDbReportPath" }

$quality = Get-Content -LiteralPath $qualityReportPath -Raw | ConvertFrom-Json
$catalogDb = Get-Content -LiteralPath $catalogDbReportPath -Raw | ConvertFrom-Json

$nowUtc = [datetime]::UtcNow
$snapshotFiles = @(
  @{ Name = 'seriesgraph-season-ratings.json'; Path = (Join-Path $repoRoot 'data\seriesgraph-season-ratings.json') },
  @{ Name = 'one-piece-english-titles.json';   Path = (Join-Path $repoRoot 'data\one-piece-english-titles.json') },
  @{ Name = 'one-piece-episode-meta.json';     Path = (Join-Path $repoRoot 'data\one-piece-episode-meta.json') }
)

$snapshots = @()
$sloWarnings = New-Object System.Collections.Generic.List[string]
$sloBreaches = New-Object System.Collections.Generic.List[string]

foreach ($snap in $snapshotFiles) {
  if (Test-Path -LiteralPath $snap.Path) {
    $item = Get-Item -LiteralPath $snap.Path
    $ageHours = [math]::Round(($nowUtc - $item.LastWriteTimeUtc).TotalHours, 2)
    $state = if ($ageHours -gt $FailStaleHours) {
      'breach'
    } elseif ($ageHours -gt $WarnStaleHours) {
      'warn'
    } else {
      'ok'
    }
    if ($state -eq 'warn') {
      $sloWarnings.Add("$($snap.Name) age ${ageHours}h exceeds warning threshold (${WarnStaleHours}h)")
    } elseif ($state -eq 'breach') {
      $sloBreaches.Add("$($snap.Name) age ${ageHours}h exceeds failure threshold (${FailStaleHours}h)")
    }
    $snapshots += [ordered]@{
      file = $snap.Name
      present = $true
      bytes = $item.Length
      lastWriteUtc = $item.LastWriteTimeUtc.ToString('o')
      ageHours = $ageHours
      status = $state
    }
  } else {
    $snapshots += [ordered]@{
      file = $snap.Name
      present = $false
      bytes = 0
      lastWriteUtc = $null
      ageHours = $null
      status = if ($Mode -eq 'refresh') { 'missing' } else { 'not_applicable_in_ci' }
    }
    if ($Mode -eq 'refresh') {
      $sloWarnings.Add("$($snap.Name) not present in workspace during scheduled refresh")
    }
  }
}

$sloStatus = if ($sloBreaches.Count -gt 0 -or -not $catalogDb.integrity_ok -or $quality.errors.Count -gt 0) {
  'breach'
} elseif ($sloWarnings.Count -gt 0 -or $quality.warnings.Count -gt 0) {
  'warn'
} else {
  'healthy'
}

$sloReport = [ordered]@{
  version = 1
  mode = $Mode
  generatedAtUtc = $nowUtc.ToString('o')
  sloStatus = $sloStatus
  thresholds = [ordered]@{
    warnStaleHours = $WarnStaleHours
    failStaleHours = $FailStaleHours
  }
  qualityGate = [ordered]@{
    episodes = $quality.catalog.episodes
    maximumEpisode = $quality.catalog.maximum
    dateCoveragePercent = $quality.dates.coveragePercent
    synopsisCoveragePercent = $quality.synopses.coveragePercent
    chapterAdaptationCoveragePercent = $quality.chapterAdaptations.coveragePercent
    errorCount = @($quality.errors).Count
    warningCount = @($quality.warnings).Count
  }
  sqliteCatalog = [ordered]@{
    entriesTotal = $catalogDb.entries_total
    tvEpisodes = $catalogDb.tv_episodes
    chapterMappings = $catalogDb.chapter_mappings
    appearanceTags = $catalogDb.appearance_tags
    appearanceLinks = $catalogDb.appearance_links
    dbSizeBytes = $catalogDb.db_size_bytes
    buildMs = $catalogDb.build_ms
    ftsP95Ms = $catalogDb.fts_p95_ms
    integrityOk = $catalogDb.integrity_ok
    foreignKeyViolations = $catalogDb.foreign_key_violations
  }
  snapshots = $snapshots
  warnings = @($sloWarnings)
  breaches = @($sloBreaches)
}

$jsonText = ($sloReport | ConvertTo-Json -Depth 6) + "`n"
[System.IO.File]::WriteAllText($sloOutputPath, $jsonText, [System.Text.UTF8Encoding]::new($false))
Write-Output $jsonText

if ($env:GITHUB_STEP_SUMMARY) {
  $summary = @"
### Pipeline Observability & DBRE Integrity Summary ($Mode)

| Metric | Value |
|---|---|
| Overall Status | ``$sloStatus`` |
| TV Episodes / Total Catalog Rows | $($quality.catalog.episodes) / $($catalogDb.entries_total) (max E$($quality.catalog.maximum)) |
| Date / Synopsis / Adaptation Coverage | $($quality.dates.coveragePercent)% / $($quality.synopses.coveragePercent)% / $($quality.chapterAdaptations.coveragePercent)% |
| SQLite Integrity & FK Check | ``integrity_ok=$($catalogDb.integrity_ok)``, ``fk_violations=$($catalogDb.foreign_key_violations)`` |
| Normalized Catalog Size & Build Time | $([math]::Round($catalogDb.db_size_bytes / 1KB, 1)) KB in $($catalogDb.build_ms) ms |
| FTS5 20-Query P95 Latency | $($catalogDb.fts_p95_ms) ms |
| Chapter / Appearance Links | $($catalogDb.chapter_mappings) chapters / $($catalogDb.appearance_links) appearances |

"@
  Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summary -Encoding UTF8
}

if ($EnforceFreshnessSlo -and $sloBreaches.Count -gt 0) {
  throw "Freshness SLO breached: $($sloBreaches -join '; ')"
}

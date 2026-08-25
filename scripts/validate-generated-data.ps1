param(
  [string]$HtmlPath,
  [string]$BaselinePath,
  [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $HtmlPath) { $HtmlPath = Join-Path $repoRoot 'docs\index.html' }
if (-not $BaselinePath) { $BaselinePath = Join-Path $repoRoot 'data\quality-baseline.json' }
if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot 'data\generated\quality-report.json' }
. (Join-Path $PSScriptRoot 'provider-utils.ps1')

if (-not (Test-Path -LiteralPath $HtmlPath)) { throw "Missing generated page: $HtmlPath" }
if (-not (Test-Path -LiteralPath $BaselinePath)) { throw "Missing quality baseline: $BaselinePath" }

$html = [System.IO.File]::ReadAllText($HtmlPath)
$match = [regex]::Match($html, '<script id="episode-data" type="application/json">(?<json>[\s\S]*?)</script>')
if (-not $match.Success) { throw 'Generated page is missing the episode-data block.' }
$entries = $match.Groups['json'].Value | ConvertFrom-Json
$episodes = @($entries | Where-Object { $_.mediaKind -eq 'episode' } | Sort-Object episode)
$baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
if ($episodes.Count -eq 0) { $errors.Add('Generated page contains no TV episodes.') }

$maximum = if ($episodes.Count) { [int]$episodes[-1].episode } else { 0 }
if ($maximum -lt [int]$baseline.minimumPublishedEpisode) {
  $errors.Add("Maximum episode regressed to $maximum; baseline is $($baseline.minimumPublishedEpisode).")
}

$numbers = @{}; foreach ($episode in $episodes) { $numbers[[int]$episode.episode] = $true }
$missingNumbers = New-Object System.Collections.Generic.List[int]
for ($number=1; $number -le $maximum; $number++) { if (-not $numbers.ContainsKey($number)) { $missingNumbers.Add($number) } }
if ($missingNumbers.Count) { $errors.Add("Episode sequence has gaps: $($missingNumbers -join ', ')") }

$missingDates = @($episodes | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.aired) })
$missingSynopses = @($episodes | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.originalNote) })
$lowQuality = @($episodes | Where-Object { Test-LowQualitySynopsis -Value ([string]$_.originalNote) -Title ([string]$_.title) })
$invalidStatus = @($episodes | Where-Object { $_.synopsisStatus -notin @('reviewed','source-derived') })
$tooLong = @($episodes | Where-Object { ([string]$_.originalNote).Length -gt 320 })
$encodingArtifacts = @($episodes | Where-Object {
  $text = "$(($_.title)) $(($_.originalNote))"
  (Get-EncodingArtifactCount $text) -gt 0
})
$episodesWithAdaptations = @($episodes | Where-Object { @($_.adaptations | Where-Object { $null -ne $_ }).Count -gt 0 })
$invalidAdaptations = New-Object System.Collections.Generic.List[string]
$adaptationMaximum = 0
foreach ($episode in $episodes) {
  foreach ($adaptation in @($episode.adaptations)) {
    if (-not $adaptation) { continue }
    $chapter = [int]$adaptation.chapter
    $expectedUrl = "https://onepiece.fandom.com/wiki/Chapter_$chapter"
    if ($chapter -lt 1 -or [string]::IsNullOrWhiteSpace([string]$adaptation.pages) -or [string]$adaptation.url -ne $expectedUrl) {
      $invalidAdaptations.Add("E$($episode.episode): chapter=$($adaptation.chapter), pages=$($adaptation.pages), url=$($adaptation.url)")
    }
    if ([int]$episode.episode -gt $adaptationMaximum) { $adaptationMaximum = [int]$episode.episode }
  }
}

$dateCoverage = if ($episodes.Count) { [math]::Round(100 * ($episodes.Count - $missingDates.Count) / $episodes.Count, 2) } else { 0 }
$synopsisCoverage = if ($episodes.Count) { [math]::Round(100 * ($episodes.Count - $missingSynopses.Count) / $episodes.Count, 2) } else { 0 }
$adaptationCoverage = if ($episodes.Count) { [math]::Round(100 * $episodesWithAdaptations.Count / $episodes.Count, 2) } else { 0 }
if ($dateCoverage -lt [double]$baseline.minimumDateCoveragePercent) { $errors.Add("Date coverage is $dateCoverage%; expected at least $($baseline.minimumDateCoveragePercent)%.") }
if ($synopsisCoverage -lt [double]$baseline.minimumSynopsisCoveragePercent) { $errors.Add("Synopsis coverage is $synopsisCoverage%; expected at least $($baseline.minimumSynopsisCoveragePercent)%.") }
if ($adaptationCoverage -lt [double]$baseline.minimumAdaptationCoveragePercent) { $errors.Add("Chapter-adaptation coverage is $adaptationCoverage%; expected at least $($baseline.minimumAdaptationCoveragePercent)%.") }
if ($adaptationMaximum -lt [int]$baseline.minimumAdaptationMaximumEpisode) { $errors.Add("Chapter-adaptation data ends at episode $adaptationMaximum; baseline is $($baseline.minimumAdaptationMaximumEpisode).") }
if ($invalidAdaptations.Count) { $errors.Add("$($invalidAdaptations.Count) malformed chapter-adaptation mapping(s): $($invalidAdaptations -join '; ')") }
if ($lowQuality.Count) { $errors.Add("$($lowQuality.Count) generated synopsis value(s) are empty, template-only, title-only, or truncated after an abbreviation.") }
if ($invalidStatus.Count) { $errors.Add("$($invalidStatus.Count) episode synopsis value(s) have no valid editorial status.") }
if ($tooLong.Count) { $errors.Add("$($tooLong.Count) episode synopsis value(s) exceed 320 characters.") }
if ($encodingArtifacts.Count) { $errors.Add("$($encodingArtifacts.Count) episode title/synopsis value(s) contain likely encoding artifacts.") }

$appearanceMaximum = 0
$appearanceMatch = [regex]::Match($html, '<script id="appearance-audits" type="application/json">(?<json>[\s\S]*?)</script>')
if ($appearanceMatch.Success) {
  $appearance = $appearanceMatch.Groups['json'].Value | ConvertFrom-Json
  foreach ($tag in $appearance.tags.PSObject.Properties) {
    foreach ($field in @('appears','focused','flashback','remote')) {
      foreach ($item in @($tag.Value.$field)) {
        $candidate = if ($item -is [array]) { [int]$item[-1] } else { [int]$item }
        if ($candidate -gt $appearanceMaximum) { $appearanceMaximum = $candidate }
      }
    }
  }
  if ($appearanceMaximum -lt $maximum) { $warnings.Add("Appearance audit ends at episode $appearanceMaximum while the catalog ends at $maximum.") }
} else { $warnings.Add('Generated page is missing the appearance-audits block.') }

$report = [ordered]@{
  version = 1
  generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
  catalog = [ordered]@{ episodes=$episodes.Count; maximum=$maximum; gaps=$missingNumbers.Count }
  dates = [ordered]@{ coveragePercent=$dateCoverage; missing=@($missingDates | ForEach-Object episode) }
  synopses = [ordered]@{
    coveragePercent=$synopsisCoverage
    missing=@($missingSynopses | ForEach-Object episode)
    lowQuality=@($lowQuality | ForEach-Object episode)
    invalidStatus=@($invalidStatus | ForEach-Object episode)
    tooLong=@($tooLong | ForEach-Object episode)
  }
  chapterAdaptations = [ordered]@{
    coveragePercent=$adaptationCoverage
    episodes=$episodesWithAdaptations.Count
    maximumEpisode=$adaptationMaximum
    invalid=$invalidAdaptations.Count
  }
  encodingArtifacts = @($encodingArtifacts | ForEach-Object episode)
  appearanceMaximumEpisode = $appearanceMaximum
  errors = @($errors)
  warnings = @($warnings)
}

$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
if ($errors.Count) { exit 1 }

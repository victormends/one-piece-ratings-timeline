$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$docsPath = Join-Path $repoRoot 'docs\index.html'
$generatedDir = Join-Path $repoRoot 'data\generated'
$imdbCacheDir = Join-Path $repoRoot 'data\cache\imdb'
$notesDir = Join-Path $repoRoot 'notes'

foreach ($dir in @($generatedDir, $imdbCacheDir, $notesDir)) {
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
}

$checkpointEpisodes = @(1, 44, 130, 516, 600, 889, 1088, 1089, 1122, 1155, 1156, 1160)
$checkpointMedia = @('M10', 'M15', 'SP14', 'R4', 'R7')
$checkpointMediaImdbIds = @{
  M10 = 'tt1485763'
  M15 = 'tt16183464'
  R7 = 'tt11744496'
}
$onePieceParentTconst = 'tt0388629'

function Get-JsonBlock([string]$html, [string]$id) {
  $match = [regex]::Match($html, '<script id="' + [regex]::Escape($id) + '" type="application/json">(?<json>[\s\S]*?)</script>')
  if (-not $match.Success) { throw "Could not find JSON block: $id" }
  return $match.Groups['json'].Value
}

function Ensure-ImdbFile([string]$fileName) {
  $path = Join-Path $imdbCacheDir $fileName
  if (Test-Path -LiteralPath $path) { return $path }
  $uri = "https://datasets.imdbws.com/$fileName"
  Invoke-WebRequest -Uri $uri -OutFile $path -UseBasicParsing
  return $path
}

function Open-GzipText([string]$path) {
  $fileStream = [System.IO.File]::OpenRead($path)
  $gzipStream = [System.IO.Compression.GzipStream]::new($fileStream, [System.IO.Compression.CompressionMode]::Decompress)
  $reader = [System.IO.StreamReader]::new($gzipStream)
  return [pscustomobject]@{ Reader = $reader; Gzip = $gzipStream; File = $fileStream }
}

function Close-GzipText($handle) {
  $handle.Reader.Close()
  $handle.Gzip.Close()
  $handle.File.Close()
}

function Get-OnePieceEpisodeRows([string]$episodePath) {
  $rows = New-Object System.Collections.Generic.List[object]
  $handle = Open-GzipText $episodePath
  try {
    $header = $handle.Reader.ReadLine() -split "`t"
    $index = @{}
    for ($i = 0; $i -lt $header.Count; $i++) { $index[$header[$i]] = $i }
    while (($line = $handle.Reader.ReadLine()) -ne $null) {
      $parts = $line -split "`t", -1
      if ($parts[$index.parentTconst] -ne $onePieceParentTconst) { continue }
      $rows.Add([pscustomobject]@{
        tconst = $parts[$index.tconst]
        parentTconst = $parts[$index.parentTconst]
        seasonNumber = $parts[$index.seasonNumber]
        episodeNumber = $parts[$index.episodeNumber]
      })
    }
  } finally {
    Close-GzipText $handle
  }
  return $rows
}

function Get-BasicsForTconsts([string]$basicsPath, [System.Collections.Generic.HashSet[string]]$wanted) {
  $basics = @{}
  $handle = Open-GzipText $basicsPath
  try {
    $header = $handle.Reader.ReadLine() -split "`t"
    $index = @{}
    for ($i = 0; $i -lt $header.Count; $i++) { $index[$header[$i]] = $i }
    while (($line = $handle.Reader.ReadLine()) -ne $null) {
      $parts = $line -split "`t", -1
      $tconst = $parts[$index.tconst]
      if (-not $wanted.Contains($tconst)) { continue }
      $basics[$tconst] = [pscustomobject]@{
        tconst = $tconst
        titleType = $parts[$index.titleType]
        primaryTitle = $parts[$index.primaryTitle]
        originalTitle = $parts[$index.originalTitle]
        startYear = $parts[$index.startYear]
        runtimeMinutes = $parts[$index.runtimeMinutes]
      }
    }
  } finally {
    Close-GzipText $handle
  }
  return $basics
}

function Get-RatingsForTconsts([string]$ratingsPath, [System.Collections.Generic.HashSet[string]]$wanted) {
  $ratings = @{}
  $handle = Open-GzipText $ratingsPath
  try {
    $header = $handle.Reader.ReadLine() -split "`t"
    $index = @{}
    for ($i = 0; $i -lt $header.Count; $i++) { $index[$header[$i]] = $i }
    while (($line = $handle.Reader.ReadLine()) -ne $null) {
      $parts = $line -split "`t", -1
      $tconst = $parts[$index.tconst]
      if (-not $wanted.Contains($tconst)) { continue }
      $ratings[$tconst] = [pscustomobject]@{
        tconst = $tconst
        averageRating = [double]$parts[$index.averageRating]
        numVotes = [int]$parts[$index.numVotes]
      }
    }
  } finally {
    Close-GzipText $handle
  }
  return $ratings
}

function Find-BasicsByTitleTokens([string]$basicsPath, [string[]]$normalizedTitles) {
  $candidates = @{}
  foreach ($title in $normalizedTitles) { $candidates[$title] = New-Object System.Collections.Generic.List[object] }

  $handle = Open-GzipText $basicsPath
  try {
    $header = $handle.Reader.ReadLine() -split "`t"
    $index = @{}
    for ($i = 0; $i -lt $header.Count; $i++) { $index[$header[$i]] = $i }
    while (($line = $handle.Reader.ReadLine()) -ne $null) {
      $parts = $line -split "`t", -1
      $titleType = $parts[$index.titleType]
      if ($titleType -notin @('movie', 'tvMovie', 'tvSpecial', 'video')) { continue }

      $primaryTitle = $parts[$index.primaryTitle]
      $originalTitle = $parts[$index.originalTitle]
      $primaryNorm = Normalize-Title $primaryTitle
      $originalNorm = Normalize-Title $originalTitle
      if (-not ($primaryNorm.Contains('one piece') -or $originalNorm.Contains('one piece'))) { continue }

      foreach ($wantedTitle in $normalizedTitles) {
        if (-not ($primaryNorm.Contains($wantedTitle) -or $wantedTitle.Contains($primaryNorm) -or $originalNorm.Contains($wantedTitle) -or $wantedTitle.Contains($originalNorm))) { continue }
        $candidates[$wantedTitle].Add([pscustomobject]@{
          tconst = $parts[$index.tconst]
          titleType = $titleType
          primaryTitle = $primaryTitle
          originalTitle = $originalTitle
          startYear = $parts[$index.startYear]
          runtimeMinutes = $parts[$index.runtimeMinutes]
        })
      }
    }
  } finally {
    Close-GzipText $handle
  }

  return $candidates
}

function Find-AkasByTitleTokens([string]$akasPath, [string[]]$normalizedTitles) {
  $candidates = @{}
  foreach ($title in $normalizedTitles) { $candidates[$title] = New-Object System.Collections.Generic.List[object] }

  $handle = Open-GzipText $akasPath
  try {
    $header = $handle.Reader.ReadLine() -split "`t"
    $index = @{}
    for ($i = 0; $i -lt $header.Count; $i++) { $index[$header[$i]] = $i }
    while (($line = $handle.Reader.ReadLine()) -ne $null) {
      $parts = $line -split "`t", -1
      $akaTitle = $parts[$index.title]
      $akaNorm = Normalize-Title $akaTitle
      if (-not $akaNorm.Contains('one piece')) { continue }

      foreach ($wantedTitle in $normalizedTitles) {
        $isStrongMatch = $akaNorm -eq $wantedTitle -or $akaNorm.Contains($wantedTitle)
        if (-not $isStrongMatch) { continue }
        $candidates[$wantedTitle].Add([pscustomobject]@{
          tconst = $parts[$index.titleId]
          akaTitle = $akaTitle
          region = $parts[$index.region]
          language = $parts[$index.language]
          types = $parts[$index.types]
          attributes = $parts[$index.attributes]
        })
      }
    }
  } finally {
    Close-GzipText $handle
  }

  return $candidates
}

function Normalize-Title([string]$value) {
  if (-not $value) { return '' }
  return ($value.ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim()
}

$html = [System.IO.File]::ReadAllText($docsPath)
$currentEntries = Get-JsonBlock $html 'episode-data' | ConvertFrom-Json
$currentEpisodeMap = @{}
$currentMediaMap = @{}
foreach ($entry in $currentEntries) {
  if ($entry.mediaKind -eq 'episode' -and $entry.episode) { $currentEpisodeMap[[int]$entry.episode] = $entry }
  if ($entry.mediaKind -ne 'episode' -and $entry.displayCode) { $currentMediaMap[$entry.displayCode] = $entry }
}

$episodePath = Ensure-ImdbFile 'title.episode.tsv.gz'
$basicsPath = Ensure-ImdbFile 'title.basics.tsv.gz'
$ratingsPath = Ensure-ImdbFile 'title.ratings.tsv.gz'

$imdbEpisodeRows = @(Get-OnePieceEpisodeRows $episodePath)
$wanted = [System.Collections.Generic.HashSet[string]]::new()
foreach ($row in $imdbEpisodeRows) { [void]$wanted.Add($row.tconst) }
$basics = Get-BasicsForTconsts $basicsPath $wanted
$ratings = Get-RatingsForTconsts $ratingsPath $wanted

$imdbByEpisodeNumber = @{}
foreach ($row in $imdbEpisodeRows) {
  $episodeNumber = 0
  if ([int]::TryParse([string]$row.episodeNumber, [ref]$episodeNumber)) {
    if (-not $imdbByEpisodeNumber.ContainsKey($episodeNumber)) { $imdbByEpisodeNumber[$episodeNumber] = @() }
    $imdbByEpisodeNumber[$episodeNumber] += $row
  }
}

$sampleRows = foreach ($episode in $checkpointEpisodes) {
  $current = $currentEpisodeMap[$episode]
  $matches = @($imdbByEpisodeNumber[$episode])
  $match = if ($matches.Count -eq 1) { $matches[0] } else { $null }
  $basic = if ($match -and $basics.ContainsKey($match.tconst)) { $basics[$match.tconst] } else { $null }
  $rating = if ($match -and $ratings.ContainsKey($match.tconst)) { $ratings[$match.tconst] } else { $null }
  $currentTitleNorm = Normalize-Title $current.title
  $imdbTitleNorm = Normalize-Title $basic.primaryTitle
  $confidence = if (-not $match) { 'missing' } elseif ($matches.Count -gt 1) { 'ambiguous' } elseif ($currentTitleNorm -and $imdbTitleNorm -and ($currentTitleNorm -eq $imdbTitleNorm -or $currentTitleNorm.Contains($imdbTitleNorm) -or $imdbTitleNorm.Contains($currentTitleNorm))) { 'verified-title' } else { 'number-match-title-differs' }
  [pscustomobject]@{
    globalEpisode = $episode
    currentTitle = $current.title
    currentRating = $current.rating
    currentVotes = $current.votes
    imdbTconst = if ($match) { $match.tconst } else { $null }
    imdbSeasonNumber = if ($match) { $match.seasonNumber } else { $null }
    imdbEpisodeNumber = if ($match) { $match.episodeNumber } else { $null }
    imdbTitle = if ($basic) { $basic.primaryTitle } else { $null }
    imdbRating = if ($rating) { $rating.averageRating } else { $null }
    imdbVotes = if ($rating) { $rating.numVotes } else { $null }
    candidateCount = $matches.Count
    confidence = $confidence
  }
}

$mediaWanted = [System.Collections.Generic.HashSet[string]]::new()
foreach ($tconst in $checkpointMediaImdbIds.Values) {
  [void]$mediaWanted.Add($tconst)
}
$mediaBasics = Get-BasicsForTconsts $basicsPath $mediaWanted
$mediaRatings = Get-RatingsForTconsts $ratingsPath $mediaWanted

$mediaRows = foreach ($code in $checkpointMedia) {
  $entry = $currentMediaMap[$code]
  $imdbTconst = if ($checkpointMediaImdbIds.ContainsKey($code)) { $checkpointMediaImdbIds[$code] } else { $null }
  $basic = if ($imdbTconst -and $mediaBasics.ContainsKey($imdbTconst)) { $mediaBasics[$imdbTconst] } else { $null }
  $rating = if ($imdbTconst -and $mediaRatings.ContainsKey($imdbTconst)) { $mediaRatings[$imdbTconst] } else { $null }
  $mappingStatus = if (-not $imdbTconst) { 'manual-imdb-id-needed' } elseif ($basic) { 'manual-id-validated' } else { 'manual-id-not-found-in-basics' }
  [pscustomobject]@{
    code = $code
    title = if ($entry) { $entry.title } else { $null }
    category = if ($entry) { $entry.category } else { $null }
    currentRating = if ($entry) { $entry.rating } else { $null }
    currentVotes = if ($entry) { $entry.votes } else { $null }
    currentMalId = if ($entry) { $entry.malId } else { $null }
    placement = if ($entry) { $entry.placement } else { $null }
    imdbTconst = $imdbTconst
    imdbTitleType = if ($basic) { $basic.titleType } else { $null }
    imdbPrimaryTitle = if ($basic) { $basic.primaryTitle } else { $null }
    imdbOriginalTitle = if ($basic) { $basic.originalTitle } else { $null }
    imdbStartYear = if ($basic) { $basic.startYear } else { $null }
    imdbRuntimeMinutes = if ($basic) { $basic.runtimeMinutes } else { $null }
    imdbRating = if ($rating) { $rating.averageRating } else { $null }
    imdbVotes = if ($rating) { $rating.numVotes } else { $null }
    candidateCount = if ($imdbTconst) { 1 } else { 0 }
    mappingStatus = $mappingStatus
  }
}

$singleNumberMatches = @($imdbByEpisodeNumber.Keys | Where-Object { @($imdbByEpisodeNumber[$_]).Count -eq 1 }).Count
$duplicateNumberMatches = @($imdbByEpisodeNumber.Keys | Where-Object { @($imdbByEpisodeNumber[$_]).Count -gt 1 }).Count
$ratedEpisodes = @($imdbEpisodeRows | Where-Object { $ratings.ContainsKey($_.tconst) }).Count
$currentTvEpisodes = @($currentEntries | Where-Object { $_.mediaKind -eq 'episode' }).Count
$currentMediaEntries = @($currentEntries | Where-Object { $_.mediaKind -ne 'episode' }).Count
$currentEpisodeNumbers = @($currentEpisodeMap.Keys | Sort-Object)
$imdbEpisodeNumbers = @($imdbByEpisodeNumber.Keys | Sort-Object)
$missingCurrentEpisodes = @($currentEpisodeNumbers | Where-Object { -not $imdbByEpisodeNumber.ContainsKey($_) })
$extraImdbEpisodeNumbers = @($imdbEpisodeNumbers | Where-Object { -not $currentEpisodeMap.ContainsKey($_) })
$ratedCurrentEpisodes = @($currentEpisodeNumbers | Where-Object {
  if (-not $imdbByEpisodeNumber.ContainsKey($_)) { return $false }
  $candidates = @($imdbByEpisodeNumber[$_])
  return ($candidates | Where-Object { $ratings.ContainsKey($_.tconst) } | Select-Object -First 1) -ne $null
}).Count

$result = [pscustomobject]@{
  generatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  imdbParentTconst = $onePieceParentTconst
  currentTvEpisodes = $currentTvEpisodes
  currentMediaEntries = $currentMediaEntries
  imdbEpisodeRows = $imdbEpisodeRows.Count
  imdbEpisodeNumbersWithSingleCandidate = $singleNumberMatches
  imdbEpisodeNumbersWithDuplicates = $duplicateNumberMatches
  imdbRatedEpisodeRows = $ratedEpisodes
  currentEpisodesMissingFromImdb = $missingCurrentEpisodes
  extraImdbEpisodeNumbers = $extraImdbEpisodeNumbers
  currentEpisodesWithImdbRatings = $ratedCurrentEpisodes
  sampleEpisodes = $sampleRows
  sampleMedia = $mediaRows
}

$samplePath = Join-Path $generatedDir 'provider-sample-map.json'
$reportPath = Join-Path $notesDir 'provider-mapping-report.md'
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $samplePath -Encoding UTF8

$verified = @($sampleRows | Where-Object { $_.confidence -eq 'verified-title' }).Count
$numberDiff = @($sampleRows | Where-Object { $_.confidence -eq 'number-match-title-differs' }).Count
$missing = @($sampleRows | Where-Object { $_.confidence -eq 'missing' }).Count
$ambiguous = @($sampleRows | Where-Object { $_.confidence -eq 'ambiguous' }).Count

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Provider Mapping Feasibility Report')
$lines.Add('')
$lines.Add("Generated: $($result.generatedAt)")
$lines.Add('')
$lines.Add('## Scope')
$lines.Add('')
$lines.Add('This report tests whether IMDb non-commercial datasets can replace the current Series Graph ratings source without changing the production page yet. TMDb API mapping is not tested here because `TMDB_API_KEY` is not configured in this repo; it remains the next feasibility step.')
$lines.Add('')
$lines.Add('## IMDb Dataset Findings')
$lines.Add('')
$lines.Add('- IMDb parent tconst tested: ' + $onePieceParentTconst)
$lines.Add('- Current TV episodes in generated page: ' + $currentTvEpisodes)
$lines.Add('- Current non-TV media entries in generated page: ' + $currentMediaEntries)
$lines.Add('- IMDb episode rows found for parent: ' + $imdbEpisodeRows.Count)
$lines.Add('- IMDb episode numbers with one candidate: ' + $singleNumberMatches)
$lines.Add('- IMDb episode numbers with duplicate candidates: ' + $duplicateNumberMatches)
$lines.Add('- IMDb episode rows with ratings: ' + $ratedEpisodes)
$lines.Add('- Current episode numbers missing from IMDb: ' + $(if ($missingCurrentEpisodes.Count) { ($missingCurrentEpisodes -join ', ') } else { 'none' }))
$lines.Add('- Extra IMDb episode numbers not in current page: ' + $(if ($extraImdbEpisodeNumbers.Count) { ($extraImdbEpisodeNumbers -join ', ') } else { 'none' }))
$lines.Add('- Current TV episodes with IMDb ratings: ' + $ratedCurrentEpisodes + ' / ' + $currentTvEpisodes)
$lines.Add('')
$lines.Add('## Checkpoint Episode Results')
$lines.Add('')
$lines.Add('| Global Ep | Current Title | IMDb Ep | IMDb Title | Current Rating | IMDb Rating | IMDb Votes | Confidence |')
$lines.Add('|---:|---|---:|---|---:|---:|---:|---|')
foreach ($row in $sampleRows) {
  $lines.Add("| $($row.globalEpisode) | $($row.currentTitle -replace '\|','/') | $($row.imdbEpisodeNumber) | $($row.imdbTitle -replace '\|','/') | $($row.currentRating) | $($row.imdbRating) | $($row.imdbVotes) | $($row.confidence) |")
}
$lines.Add('')
$lines.Add('## Checkpoint Summary')
$lines.Add('')
$lines.Add('- Verified by title: ' + $verified)
$lines.Add('- Number match but title differs: ' + $numberDiff)
$lines.Add('- Missing: ' + $missing)
$lines.Add('- Ambiguous: ' + $ambiguous)
$lines.Add('')
$lines.Add('## Media Checkpoints')
$lines.Add('')
$lines.Add('| Code | Title | Category | Current Rating | IMDb Title | IMDb Rating | IMDb Votes | Candidates | Mapping Status |')
$lines.Add('|---|---|---|---:|---|---:|---:|---:|---|')
foreach ($row in $mediaRows) {
  $lines.Add("| $($row.code) | $($row.title -replace '\|','/') | $($row.category) | $($row.currentRating) | $($row.imdbPrimaryTitle -replace '\|','/') | $($row.imdbRating) | $($row.imdbVotes) | $($row.candidateCount) | $($row.mappingStatus) |")
}
$lines.Add('')
$lines.Add('## Preliminary Decision')
$lines.Add('')
if ($missing -eq 0 -and $ambiguous -eq 0 -and $numberDiff -le 4) {
  $lines.Add('IMDb looks feasible enough for a deeper migration spike, but title mismatches must be reviewed before replacing production data.')
} else {
  $lines.Add('IMDb mapping is not yet proven safe. Do not replace the production data source until mismatches, missing rows, and media mappings are resolved.')
}
$lines.Add('')
$lines.Add('## Next Tests')
$lines.Add('')
$lines.Add('- Add TMDb feasibility once `TMDB_API_KEY` is available.')
$lines.Add('- Add IMDb media search/mapping for movies, specials, recaps, OVAs, and shorts.')
$lines.Add('- Build an authoritative `provider-map.json` only after sampled mappings are manually reviewed.')

$lines | Set-Content -LiteralPath $reportPath -Encoding UTF8

[pscustomobject]@{
  Report = $reportPath
  SampleMap = $samplePath
  CurrentTvEpisodes = $currentTvEpisodes
  ImdbEpisodeRows = $imdbEpisodeRows.Count
  RatedRows = $ratedEpisodes
  VerifiedSamples = $verified
  TitleDiffSamples = $numberDiff
  MissingSamples = $missing
  AmbiguousSamples = $ambiguous
} | ConvertTo-Json

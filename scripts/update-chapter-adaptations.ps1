param(
  [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\chapter-adaptations.json')
)

$ErrorActionPreference = 'Stop'

$sourceUrl = 'https://onepiece.fandom.com/wiki/Template:WC'
$apiUrl = 'https://onepiece.fandom.com/api.php?action=query&prop=revisions&rvprop=content%7Cids%7Ctimestamp&rvslots=main&titles=Template%3AWC&format=json&formatversion=2&origin=*'
$headers = @{ 'User-Agent' = 'OnePieceRatingsTimeline/1.0 (https://github.com/victormends/one-piece-ratings-timeline)' }

$response = Invoke-RestMethod -Uri $apiUrl -Headers $headers
$page = $response.query.pages[0]
$revision = $page.revisions[0]
$wikitext = [string]$revision.slots.main.content
if ([string]::IsNullOrWhiteSpace($wikitext)) { throw 'Template:WC returned no wikitext.' }

$episodeMap = @{}
$sourceRows = 0
$mappingRows = 0
foreach ($line in ($wikitext -split "`n")) {
  $match = [regex]::Match($line, '\{\{WC/f\|\{\{\{1\}\}\}\|(?<args>[^}]*)\}\}')
  if (-not $match.Success) { continue }
  $sourceRows++

  $arguments = $match.Groups['args'].Value -split '\|'
  if ($arguments.Count -lt 3 -or (($arguments.Count - 1) % 2) -ne 0) {
    throw "Unexpected Template:WC row structure: $line"
  }
  if ($arguments[0] -notmatch '^Chapter (?<chapter>\d+)$') { continue }
  $chapter = [int]$Matches.chapter

  for ($index = 1; $index -lt $arguments.Count; $index += 2) {
    $anime = $arguments[$index].Trim()
    $pages = $arguments[$index + 1].Trim()
    if ($anime -notmatch '^Episode (?<episode>\d+)$') { continue }
    $episode = [int]$Matches.episode
    $key = [string]$episode
    if (-not $episodeMap.ContainsKey($key)) { $episodeMap[$key] = New-Object System.Collections.Generic.List[object] }
    $episodeMap[$key].Add([ordered]@{
      chapter = $chapter
      pages = $pages
      url = "https://onepiece.fandom.com/wiki/Chapter_$chapter"
    })
    $mappingRows++
  }
}

if ($sourceRows -lt 1000) { throw "Template:WC parsed only $sourceRows chapter rows; expected at least 1000." }
if ($mappingRows -lt 1500) { throw "Template:WC parsed only $mappingRows TV mappings; expected at least 1500." }

$orderedEpisodes = [ordered]@{}
$episodeNumbers = @($episodeMap.Keys | ForEach-Object { [int]$_ } | Sort-Object)
foreach ($episode in $episodeNumbers) {
  $items = @($episodeMap[[string]$episode] | Sort-Object chapter)
  $seen = @{}
  foreach ($item in $items) {
    $identity = "$($item.chapter)|$($item.pages)"
    if ($seen.ContainsKey($identity)) { throw "Duplicate adaptation mapping for episode $episode and chapter $($item.chapter), pages $($item.pages)." }
    $seen[$identity] = $true
  }
  $orderedEpisodes[[string]$episode] = $items
}

$result = [ordered]@{
  version = 1
  source = [ordered]@{
    name = 'One Piece Wiki Template:WC'
    url = $sourceUrl
    revisionId = [int64]$revision.revid
    revisionTimestamp = ([datetime]$revision.timestamp).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    license = 'CC BY-SA 3.0 unless otherwise noted by the source'
  }
  coverage = [ordered]@{
    sourceChapterRows = $sourceRows
    tvMappingRows = $mappingRows
    episodesWithMangaMaterial = $episodeNumbers.Count
    maximumMappedEpisode = [int]$episodeNumbers[-1]
  }
  episodes = $orderedEpisodes
}

$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$result | ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
  Output = $OutputPath
  Revision = [int64]$revision.revid
  Episodes = $episodeNumbers.Count
  MaximumEpisode = [int]$episodeNumbers[-1]
  Mappings = $mappingRows
} | ConvertTo-Json

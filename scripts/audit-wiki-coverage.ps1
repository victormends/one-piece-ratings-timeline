param(
  [string]$WikiAuditPath,
  [string]$AppearanceAuditPath,
  [string]$HtmlPath,
  [string]$OutputPath,
  [int]$MinimumRecurringEpisodes = 20
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $WikiAuditPath) { $WikiAuditPath = Join-Path $repoRoot 'data\generated\wiki-episode-audit.json' }
if (-not $AppearanceAuditPath) { $AppearanceAuditPath = Join-Path $repoRoot 'data\appearance-audits.json' }
if (-not $HtmlPath) { $HtmlPath = Join-Path $repoRoot 'docs\index.html' }
if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot 'data\generated\wiki-coverage-report.json' }
foreach ($path in @($WikiAuditPath,$AppearanceAuditPath,$HtmlPath)) { if (-not (Test-Path -LiteralPath $path)) { throw "Missing audit input: $path" } }

function Convert-ToAuditId([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  $text = $Value.Normalize([Text.NormalizationForm]::FormD)
  $builder = [Text.StringBuilder]::new()
  foreach ($character in $text.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$builder.Append($character) }
  }
  $id = (($builder.ToString().ToLowerInvariant() -replace '[^a-z0-9]+','-').Trim('-'))
  # The imported wiki uses the older "Kouzuki" romanization while the curated
  # audit uses "Kozuki". Canonicalize known spelling variants before matching.
  $id = $id -replace '^kouzuki-', 'kozuki-'
  return $id
}

function Expand-EpisodeItems([object[]]$Items) {
  $set = New-Object 'System.Collections.Generic.HashSet[int]'
  foreach ($item in @($Items)) {
    if ($item -is [array] -or $item -is [object[]]) {
      if ($item.Count -ne 2) { continue }
      for ($number=[int]$item[0]; $number -le [int]$item[1]; $number++) { [void]$set.Add($number) }
    } else { [void]$set.Add([int]$item) }
  }
  return ,$set
}

$wiki = Get-Content -LiteralPath $WikiAuditPath -Raw | ConvertFrom-Json
$appearance = Get-Content -LiteralPath $AppearanceAuditPath -Raw | ConvertFrom-Json
$appearanceMaximum = 0
foreach ($tagProperty in $appearance.tags.PSObject.Properties) {
  foreach ($field in @('appears','focused','flashback','remote')) {
    foreach ($item in @($tagProperty.Value.$field)) {
      $candidate = if ($item -is [array] -or $item -is [object[]]) { [int]$item[-1] } else { [int]$item }
      if ($candidate -gt $appearanceMaximum) { $appearanceMaximum = $candidate }
    }
  }
}
$html = [System.IO.File]::ReadAllText($HtmlPath)
$episodeMatch = [regex]::Match($html, '<script id="episode-data" type="application/json">(?<json>[\s\S]*?)</script>')
if (-not $episodeMatch.Success) { throw 'Generated page is missing episode-data.' }
$allPublished = $episodeMatch.Groups['json'].Value | ConvertFrom-Json
$published = @($allPublished | Where-Object { $_.mediaKind -eq 'episode' })
$publishedByNumber = @{}; foreach ($episode in $published) { $publishedByNumber[[string]$episode.episode] = $episode }

$termToTag = @{}
$tagTerms = @{}
foreach ($property in $appearance.tags.PSObject.Properties) {
  $tag = [string]$property.Name
  $terms = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($term in (@($property.Value.label) + @($property.Value.aliases))) {
    $id = Convert-ToAuditId ([string]$term)
    if ($id) { [void]$terms.Add($id); if (-not $termToTag.ContainsKey($id)) { $termToTag[$id] = $tag } }
  }
  $tagTerms[$tag] = @($terms | ForEach-Object { [string]$_ })
}

$wikiToTag = @{}
foreach ($character in $wiki.characterCatalog.PSObject.Properties) {
  $id = [string]$character.Name
  $candidates = @($id, (Convert-ToAuditId ([string]$character.Value.name)), (Convert-ToAuditId ([string]$character.Value.label))) | Where-Object { $_ }
  foreach ($candidate in $candidates) {
    if ($termToTag.ContainsKey($candidate)) { $wikiToTag[$id] = $termToTag[$candidate]; break }
  }
}

$wikiEpisodesById = @{}
$wikiComparableEpisodesById = @{}
foreach ($episodeProperty in $wiki.episodes.PSObject.Properties) {
  $number = [int]$episodeProperty.Name
  foreach ($character in @($episodeProperty.Value.characters)) {
    $id = [string]$character.id
    if (-not $wikiEpisodesById.ContainsKey($id)) { $wikiEpisodesById[$id] = New-Object 'System.Collections.Generic.HashSet[int]' }
    [void]$wikiEpisodesById[$id].Add($number)
    # Keep mentions and document-only references in the research dataset, but
    # do not compare them to the curated on-screen appearance buckets.
    if ([string]$character.context -in @('present','flashback','silhouette','imagined')) {
      if (-not $wikiComparableEpisodesById.ContainsKey($id)) { $wikiComparableEpisodesById[$id] = New-Object 'System.Collections.Generic.HashSet[int]' }
      [void]$wikiComparableEpisodesById[$id].Add($number)
    }
  }
}

$recentCharacterCounts = @{}
foreach ($episodeProperty in $wiki.episodes.PSObject.Properties) {
  if ([int]$episodeProperty.Name -le $appearanceMaximum) { continue }
  foreach ($character in @($episodeProperty.Value.characters | Where-Object { [string]$_.context -in @('present','flashback','silhouette','imagined') })) {
    $id = [string]$character.id
    if (-not $recentCharacterCounts.ContainsKey($id)) { $recentCharacterCounts[$id] = 0 }
    $recentCharacterCounts[$id]++
  }
}
$recentAppearanceCandidates = @($recentCharacterCounts.GetEnumerator() | Sort-Object @{Expression='Value';Descending=$true}, Name | ForEach-Object {
  $catalog = $wiki.characterCatalog.PSObject.Properties[[string]$_.Key]
  [pscustomobject][ordered]@{
    id = [string]$_.Key
    name = if ($catalog) { [string]$catalog.Value.name } else { [string]$_.Key }
    episodes = [int]$_.Value
    mappedTag = if ($wikiToTag.ContainsKey([string]$_.Key)) { [string]$wikiToTag[[string]$_.Key] } else { $null }
  }
})

# Several redirects (for example, "Chopper" and "Tony Tony Chopper") can map
# to the same curated tag. Compare each tag only once, using the wiki identity
# with the broadest episode coverage as its representative.
$tagToWikiId = @{}
foreach ($wikiId in $wikiToTag.Keys) {
  $tag = $wikiToTag[$wikiId]
  if (-not $tagToWikiId.ContainsKey($tag)) { $tagToWikiId[$tag] = $wikiId; continue }
  $currentId = $tagToWikiId[$tag]
  $currentCount = if ($wikiEpisodesById.ContainsKey($currentId)) { $wikiEpisodesById[$currentId].Count } else { 0 }
  $candidateCount = if ($wikiEpisodesById.ContainsKey($wikiId)) { $wikiEpisodesById[$wikiId].Count } else { 0 }
  if ($candidateCount -gt $currentCount) { $tagToWikiId[$tag] = $wikiId }
}

$tagComparisons = New-Object System.Collections.Generic.List[object]
foreach ($tag in $tagToWikiId.Keys) {
  $wikiId = $tagToWikiId[$tag]
  $entry = $appearance.tags.PSObject.Properties[$tag].Value
  $audited = New-Object 'System.Collections.Generic.HashSet[int]'
  foreach ($field in @('appears','focused','flashback')) {
    foreach ($number in (Expand-EpisodeItems @($entry.$field))) { if ($number -le [int]$wiki.coverage.maximumEpisode) { [void]$audited.Add($number) } }
  }
  $wikiListedEpisodes = $wikiEpisodesById[$wikiId]
  $wikiEpisodes = if ($wikiComparableEpisodesById.ContainsKey($wikiId)) { $wikiComparableEpisodesById[$wikiId] } else { New-Object 'System.Collections.Generic.HashSet[int]' }
  $intersection = 0; foreach ($number in $wikiEpisodes) { if ($audited.Contains($number)) { $intersection++ } }
  $tagComparisons.Add([pscustomobject][ordered]@{
    tag = $tag
    wikiCharacterId = $wikiId
    wikiListedEpisodes = $wikiListedEpisodes.Count
    comparisonContexts = @('present','flashback','silhouette','imagined')
    wikiEpisodes = $wikiEpisodes.Count
    auditedEpisodes = $audited.Count
    intersection = $intersection
    wikiCoveragePercent = [math]::Round(100 * $intersection / [math]::Max(1,$wikiEpisodes.Count), 1)
    missingFromAudit = $wikiEpisodes.Count - $intersection
    auditNotInWikiList = $audited.Count - $intersection
  })
}

$missingRecurring = @($wiki.topCharacters | Where-Object { $_.episodes -ge $MinimumRecurringEpisodes -and -not $wikiToTag.ContainsKey([string]$_.id) } | Select-Object id,name,episodes)
$zeroRecall = New-Object System.Collections.Generic.List[object]
$techniqueDebutChecks = New-Object System.Collections.Generic.List[int]
foreach ($episodeProperty in $wiki.episodes.PSObject.Properties) {
  $number = [int]$episodeProperty.Name; $wikiEpisode = $episodeProperty.Value
  if ([int]$wikiEpisode.techniqueDebutCount -gt 0) { $techniqueDebutChecks.Add($number) }
  if (-not $publishedByNumber.ContainsKey([string]$number)) { continue }
  $summaryIds = @($wikiEpisode.summaryCharacterIds)
  if (-not $summaryIds.Count) { continue }
  $synopsisId = Convert-ToAuditId ([string]$publishedByNumber[[string]$number].originalNote)
  $covered = New-Object System.Collections.Generic.List[string]
  foreach ($wikiId in $summaryIds) {
    $terms = New-Object System.Collections.Generic.List[string]
    $terms.Add([string]$wikiId)
    $catalogProperty = $wiki.characterCatalog.PSObject.Properties[[string]$wikiId]
    if ($catalogProperty) {
      foreach ($catalogValue in @($catalogProperty.Value.name, $catalogProperty.Value.label)) {
        $catalogId = Convert-ToAuditId ([string]$catalogValue)
        if ($catalogId) {
          $terms.Add($catalogId)
          $nameParts = @($catalogId -split '-' | Where-Object { $_.Length -ge 4 -and $_ -notin @('monkey','charlotte','donquixote','kouzuki','kozuki','vegapunk') })
          if ($nameParts.Count) { $terms.Add([string]$nameParts[-1]) }
        }
      }
    }
    if ($wikiToTag.ContainsKey([string]$wikiId)) { foreach ($term in @($tagTerms[$wikiToTag[[string]$wikiId]])) { $terms.Add([string]$term) } }
    foreach ($term in $terms) {
      if ($term.Length -ge 3 -and ("-$synopsisId-").Contains("-$term-")) { $covered.Add([string]$wikiId); break }
    }
  }
  if ($covered.Count -eq 0) {
    $zeroRecall.Add([ordered]@{ episode=$number; wikiSummaryCharacters=$summaryIds; synopsisStatus=[string]$publishedByNumber[[string]$number].synopsisStatus })
  }
}

$publishedMaximum = [int](($published | Measure-Object episode -Maximum).Maximum)
$sortedTagComparisons = @($tagComparisons | Sort-Object @{Expression={ [int]$_.missingFromAudit };Descending=$true})
$zeroRecallRows = @($zeroRecall | ForEach-Object { $_ })
$report = [ordered]@{
  version = 1
  generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
  wikiMaximumEpisode = [int]$wiki.coverage.maximumEpisode
  publishedMaximumEpisode = $publishedMaximum
  unauditedRecentEpisodes = if ($publishedMaximum -gt [int]$wiki.coverage.maximumEpisode) { @(([int]$wiki.coverage.maximumEpisode + 1)..$publishedMaximum) } else { @() }
  appearanceMaximumEpisode = $appearanceMaximum
  episodesBeyondAppearanceAudit = if ($publishedMaximum -gt $appearanceMaximum) { @(($appearanceMaximum + 1)..$publishedMaximum) } else { @() }
  recentAppearanceCandidates = $recentAppearanceCandidates
  appearanceTags = @($appearance.tags.PSObject.Properties).Count
  matchedCharacterTags = $tagToWikiId.Count
  recurringCharactersWithoutTag = $missingRecurring
  tagComparisons = $sortedTagComparisons
  synopsisChecks = [ordered]@{
    episodesWithZeroWikiSummaryCharacterRecall = $zeroRecallRows
    count = $zeroRecall.Count
  }
  eventChecks = [ordered]@{
    episodesWithTechniqueDebutSignal = @($techniqueDebutChecks | Sort-Object)
    note = 'Technique-debut and zero-summary-character results are review queues, not proof that an important event is absent.'
  }
}

$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
[pscustomobject]@{
  Output=$OutputPath
  MatchedCharacterTags=$tagToWikiId.Count
  RecurringCharactersWithoutTag=$missingRecurring.Count
  ZeroSummaryCharacterRecall=$zeroRecall.Count
  TechniqueDebutReviewQueue=$techniqueDebutChecks.Count
  RecentEpisodesBeyondLocalWikiSnapshot=@($report.unauditedRecentEpisodes).Count
  EpisodesBeyondAppearanceAudit=@($report.episodesBeyondAppearanceAudit).Count
} | ConvertTo-Json -Depth 5

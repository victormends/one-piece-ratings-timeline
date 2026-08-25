param(
  [string]$AuditPath,
  [string]$SummaryPath,
  [string]$HtmlPath,
  [int]$ThroughEpisode = 0
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $AuditPath) { $AuditPath = Join-Path $repoRoot 'data\generated\wiki-episode-audit.json' }
if (-not $SummaryPath) { $SummaryPath = Join-Path $repoRoot 'data\wiki-audit-summary.json' }
if (-not $HtmlPath) { $HtmlPath = Join-Path $repoRoot 'docs\index.html' }
. (Join-Path $PSScriptRoot 'provider-utils.ps1')
if (-not (Test-Path -LiteralPath $AuditPath)) { throw "Run import-one-piece-wiki.ps1 first; missing $AuditPath" }

function Convert-ToAuditId([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  $text = (($Value -split '#')[0]).Normalize([Text.NormalizationForm]::FormD)
  $builder = [Text.StringBuilder]::new()
  foreach ($character in $text.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$builder.Append($character) }
  }
  return (($builder.ToString().ToLowerInvariant() -replace '[^a-z0-9]+','-').Trim('-'))
}

function Get-WikiSection([string]$Text, [string]$Heading) {
  $match = [regex]::Match($Text, '(?s)==' + [regex]::Escape($Heading) + '==\s*(?<value>.*?)(?=\r?\n==[^=]|$)')
  if (-not $match.Success) { return $null }
  $value = $match.Groups['value'].Value.Trim()
  if (-not $value -or $value -match '^==') { return $null }
  return $value
}

function Get-CharacterContext([string]$Line) {
  if ($Line -match '(?i)flashback') { return 'flashback' }
  if ($Line -match '(?i)newspaper|poster|photograph|photo') { return 'document' }
  if ($Line -match '(?i)fantasy|imagination|dream') { return 'imagined' }
  if ($Line -match '(?i)silhouette') { return 'silhouette' }
  if ($Line -match '(?i)mentioned|voice only') { return 'mentioned' }
  return 'present'
}

function Convert-WikiPage([object]$Page) {
  if ($Page.missing -or $Page.title -notmatch '^Episode\s+(\d+)$') { return $null }
  $text = [string]$Page.revisions[0].slots.main.content
  $shortSummary = Get-WikiSection -Text $text -Heading 'Short Summary'
  $characterSection = Get-WikiSection -Text $text -Heading 'Characters in Order of Appearance'
  $characterRows = New-Object System.Collections.Generic.List[object]
  $episodeCharacterIds = New-Object 'System.Collections.Generic.HashSet[string]'
  if ($characterSection) {
    foreach ($line in ($characterSection -split '\r?\n')) {
      if ($line -notmatch '^\s*\*+\s*\[\[(?<target>[^\]|#]+)(?:#[^\]|]*)?(?:\|(?<label>[^\]]+))?\]\]') { continue }
      $target = $Matches.target.Trim()
      $label = if ($Matches.label) { $Matches.label.Trim() } else { $target }
      $id = Convert-ToAuditId $target
      if (-not $id -or -not $episodeCharacterIds.Add($id)) { continue }
      $characterRows.Add([ordered]@{ id=$id; context=(Get-CharacterContext $line) })
      if ($script:audit.characterCatalog.PSObject.Properties.Name -notcontains $id) {
        $script:audit.characterCatalog | Add-Member -NotePropertyName $id -NotePropertyValue ([pscustomobject][ordered]@{ name=$target; label=$label })
      }
    }
  }
  $summaryCharacterIds = New-Object 'System.Collections.Generic.HashSet[string]'
  if ($shortSummary) {
    foreach ($link in [regex]::Matches($shortSummary, '\[\[(?<target>[^\]|#]+)(?:#[^\]|]*)?(?:\|[^\]]+)?\]\]')) {
      $id = Convert-ToAuditId $link.Groups['target'].Value
      if ($episodeCharacterIds.Contains($id)) { [void]$summaryCharacterIds.Add($id) }
    }
  }
  $techDebut = [regex]::Match($text, '(?m)^\|\s*techDebut\s*=\s*(?<value>.*?)\s*$')
  $sortedSummaryCharacterIds = New-Object System.Collections.Generic.List[string]
  foreach ($summaryId in $summaryCharacterIds) { $sortedSummaryCharacterIds.Add([string]$summaryId) }
  return [ordered]@{
    pageTitle = [string]$Page.title
    pageId = [string]$Page.pageid
    source = 'api'
    revisionTimestamp = ([datetime]$Page.revisions[0].timestamp).ToUniversalTime().ToString('o')
    hasShortSummary = [bool]$shortSummary
    shortSummaryLength = if ($shortSummary) { $shortSummary.Length } else { 0 }
    summaryCharacterIds = @($sortedSummaryCharacterIds | Sort-Object)
    characters = @($characterRows | ForEach-Object { $_ })
    techniqueDebutCount = if ($techDebut.Success -and $techDebut.Groups['value'].Value.Trim()) { [regex]::Matches($techDebut.Groups['value'].Value, '\[\[').Count } else { 0 }
  }
}

$script:audit = Get-Content -LiteralPath $AuditPath -Raw | ConvertFrom-Json
if (-not $ThroughEpisode) {
  if (-not (Test-Path -LiteralPath $HtmlPath)) { throw 'ThroughEpisode was not supplied and the generated page is missing.' }
  $html = [System.IO.File]::ReadAllText($HtmlPath)
  $match = [regex]::Match($html, '<script id="episode-data" type="application/json">(?<json>[\s\S]*?)</script>')
  if (-not $match.Success) { throw 'Generated page is missing episode-data.' }
  $allPublished = ConvertFrom-Json -InputObject $match.Groups['json'].Value
  $episodeNumbers = @($allPublished | Where-Object { $_.mediaKind -eq 'episode' } | ForEach-Object { [int]$_.episode })
  if (-not $episodeNumbers.Count) { throw 'Generated page contains no TV episodes.' }
  $ThroughEpisode = [int](($episodeNumbers | Measure-Object -Maximum).Maximum)
}

$currentMaximum = [int]$audit.coverage.maximumEpisode
$requested = if ($ThroughEpisode -gt $currentMaximum) { @(($currentMaximum + 1)..$ThroughEpisode) } else { @() }
for ($offset = 0; $offset -lt $requested.Count; $offset += 25) {
  $end = [math]::Min($offset + 24, $requested.Count - 1)
  $numbers = @($requested[$offset..$end])
  $titles = ($numbers | ForEach-Object { "Episode $_" }) -join '|'
  $uri = 'https://onepiece.fandom.com/api.php?action=query&prop=revisions&titles=' + [uri]::EscapeDataString($titles) + '&rvslots=main&rvprop=timestamp%7Cids%7Ccontent&formatversion=2&format=json&origin=*'
  $response = Invoke-ProviderText -Uri $uri -ProviderName 'One Piece Wiki API' | ConvertFrom-Json
  foreach ($page in @($response.query.pages)) {
    if ($page.title -notmatch '^Episode\s+(\d+)$') { continue }
    $number = [int]$Matches[1]
    $parsed = Convert-WikiPage $page
    if ($parsed) {
      $key = [string]$number
      $existing = $audit.episodes.PSObject.Properties[$key]
      if ($existing) { $existing.Value = [pscustomobject]$parsed }
      else { $audit.episodes | Add-Member -NotePropertyName $key -NotePropertyValue ([pscustomobject]$parsed) }
    }
  }
}

$numbers = @($audit.episodes.PSObject.Properties.Name | ForEach-Object { [int]$_ } | Sort-Object)
$maximum = if ($numbers.Count) { [int]$numbers[-1] } else { 0 }
$gaps = @(); for ($number=1; $number -le $maximum; $number++) { if ($audit.episodes.PSObject.Properties.Name -notcontains [string]$number) { $gaps += $number } }
if ($maximum -lt $ThroughEpisode -or $gaps.Count) { throw "Wiki incremental update is incomplete (maximum=$maximum; requested=$ThroughEpisode; gaps=$($gaps -join ','))." }

$characterCounts = @{}
foreach ($episodeProperty in $audit.episodes.PSObject.Properties) {
  $episode = $episodeProperty.Value
  foreach ($character in @($episode.characters)) {
    $id = [string]$character.id
    if (-not $characterCounts.ContainsKey($id)) { $characterCounts[$id] = 0 }
    $characterCounts[$id]++
  }
}
$topCharacters = @($characterCounts.GetEnumerator() | Sort-Object @{Expression='Value';Descending=$true}, Name | ForEach-Object {
  [ordered]@{ id=$_.Key; name=$audit.characterCatalog.PSObject.Properties[$_.Key].Value.name; episodes=[int]$_.Value }
})
$episodeValues = @($audit.episodes.PSObject.Properties | ForEach-Object { $_.Value })
$withSummary = @($episodeValues | Where-Object hasShortSummary).Count
$withCharacters = @($episodeValues | Where-Object { @($_.characters).Count -gt 0 }).Count
$audit.version = 1
$audit.generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
$apiSource = [pscustomobject][ordered]@{ url='https://onepiece.fandom.com/api.php'; refreshedThroughEpisode=$maximum }
if ($audit.source.PSObject.Properties.Name -contains 'api') { $audit.source.api = $apiSource } else { $audit.source | Add-Member -NotePropertyName api -NotePropertyValue $apiSource }
$audit.coverage = [ordered]@{ episodes=@($audit.episodes.PSObject.Properties).Count; maximumEpisode=$maximum; gaps=$gaps; episodesWithShortSummary=$withSummary; episodesWithCharacters=$withCharacters; distinctCharacters=@($audit.characterCatalog.PSObject.Properties).Count }
$audit.topCharacters = $topCharacters
$audit.errors = @()
$audit | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $AuditPath -Encoding UTF8

$summary = [ordered]@{
  version = 1
  generatedAt = $audit.generatedAt
  source = $audit.source
  coverage = $audit.coverage
  topCharacters = @($topCharacters | Select-Object -First 200)
  knownMissingSections = [ordered]@{
    shortSummary = @($audit.episodes.PSObject.Properties | Where-Object { -not $_.Value.hasShortSummary } | ForEach-Object { [int]$_.Name } | Sort-Object)
    characters = @($audit.episodes.PSObject.Properties | Where-Object { @($_.Value.characters).Count -eq 0 } | ForEach-Object { [int]$_.Name } | Sort-Object)
  }
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
[pscustomobject]@{ Output=$AuditPath; Summary=$SummaryPath; Added=$requested.Count; Episodes=@($audit.episodes.PSObject.Properties).Count; Maximum=$maximum; WithSummary=$withSummary; WithCharacters=$withCharacters; DistinctCharacters=@($audit.characterCatalog.PSObject.Properties).Count } | ConvertTo-Json -Depth 5

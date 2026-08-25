param(
  [Parameter(Mandatory)][string]$ZipPath,
  [string]$OutputPath,
  [string]$SummaryPath,
  [string]$BaselinePath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot 'data\generated\wiki-episode-audit.json' }
if (-not $SummaryPath) { $SummaryPath = Join-Path $repoRoot 'data\wiki-audit-summary.json' }
if (-not $BaselinePath) { $BaselinePath = Join-Path $repoRoot 'data\quality-baseline.json' }
if (-not (Test-Path -LiteralPath $ZipPath)) { throw "Missing One Piece Wiki ZIP: $ZipPath" }
if (-not (Test-Path -LiteralPath $BaselinePath)) { throw "Missing quality baseline: $BaselinePath" }

Add-Type -AssemblyName System.IO.Compression.FileSystem

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

$baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
$characterCatalog = [ordered]@{}
$characterCounts = @{}
$episodes = [ordered]@{}
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ZipPath).Path)
try {
  foreach ($entry in ($zip.Entries | Where-Object { $_.FullName -like 'Episodes\*' } | Sort-Object FullName)) {
    $reader = [System.IO.StreamReader]::new($entry.Open())
    try { $page = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    if ($page.title -notmatch '^Episode\s+(\d+)$') { continue }

    $episodeNumber = [int]$Matches[1]
    $text = [string]$page.text
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
        $context = Get-CharacterContext $line
        $characterRows.Add([ordered]@{ id=$id; context=$context })
        if (-not $characterCatalog.Contains($id)) { $characterCatalog[$id] = [ordered]@{ name=$target; label=$label } }
        if (-not $characterCounts.ContainsKey($id)) { $characterCounts[$id] = 0 }
        $characterCounts[$id]++
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
    $episodes[[string]$episodeNumber] = [ordered]@{
      pageTitle = [string]$page.title
      pageId = [string]$page.id
      source = 'export'
      revisionTimestamp = $null
      hasShortSummary = [bool]$shortSummary
      shortSummaryLength = if ($shortSummary) { $shortSummary.Length } else { 0 }
      summaryCharacterIds = @($summaryCharacterIds | ForEach-Object { [string]$_ } | Sort-Object)
      characters = @($characterRows | ForEach-Object { $_ })
      techniqueDebutCount = if ($techDebut.Success -and $techDebut.Groups['value'].Value.Trim()) { [regex]::Matches($techDebut.Groups['value'].Value, '\[\[').Count } else { 0 }
    }
  }
} finally { $zip.Dispose() }

$numbers = @($episodes.Keys | ForEach-Object { [int]$_ } | Sort-Object)
$maximum = if ($numbers.Count) { [int]$numbers[-1] } else { 0 }
$missing = New-Object System.Collections.Generic.List[int]
for ($number=1; $number -le $maximum; $number++) { if (-not $episodes.Contains([string]$number)) { $missing.Add($number) } }
$withSummary = @($episodes.Values | Where-Object hasShortSummary).Count
$withCharacters = @($episodes.Values | Where-Object { @($_.characters).Count -gt 0 }).Count

$expected = $baseline.wiki
$errors = New-Object System.Collections.Generic.List[string]
if ($episodes.Count -lt [int]$expected.episodes) { $errors.Add("Wiki episode count regressed to $($episodes.Count); expected at least $($expected.episodes).") }
if ($maximum -lt [int]$expected.maximumEpisode) { $errors.Add("Wiki maximum episode regressed to $maximum; expected at least $($expected.maximumEpisode).") }
if ($missing.Count) { $errors.Add("Wiki episode sequence has gaps: $($missing -join ', ')") }
if ($withSummary -lt [int]$expected.episodesWithShortSummary) { $errors.Add("Wiki short-summary coverage regressed to $withSummary; expected at least $($expected.episodesWithShortSummary).") }
if ($withCharacters -lt [int]$expected.episodesWithCharacters) { $errors.Add("Wiki character coverage regressed to $withCharacters; expected at least $($expected.episodesWithCharacters).") }

$topCharacters = @($characterCounts.GetEnumerator() | Sort-Object @{ Expression='Value'; Descending=$true }, Name | ForEach-Object {
  [ordered]@{ id=$_.Key; name=$characterCatalog[$_.Key].name; episodes=[int]$_.Value }
})
$output = [ordered]@{
  version = 1
  generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
  source = [ordered]@{
    name = 'One Piece Wiki / Fandom MediaWiki export'
    url = 'https://onepiece.fandom.com/'
    license = 'CC-BY-SA 3.0 unless otherwise noted'
    importedFile = [System.IO.Path]::GetFileName($ZipPath)
    importedFileLastWriteTime = (Get-Item -LiteralPath $ZipPath).LastWriteTimeUtc.ToString('o')
  }
  coverage = [ordered]@{
    episodes = $episodes.Count
    maximumEpisode = $maximum
    gaps = @($missing)
    episodesWithShortSummary = $withSummary
    episodesWithCharacters = $withCharacters
    distinctCharacters = $characterCatalog.Count
  }
  characterCatalog = $characterCatalog
  topCharacters = $topCharacters
  episodes = $episodes
  errors = @($errors)
}

$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$output | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$summary = [ordered]@{
  version = 1
  generatedAt = $output.generatedAt
  source = $output.source
  coverage = $output.coverage
  topCharacters = @($topCharacters | Select-Object -First 200)
  knownMissingSections = [ordered]@{
    shortSummary = @($episodes.GetEnumerator() | Where-Object { -not $_.Value.hasShortSummary } | ForEach-Object { [int]$_.Key } | Sort-Object)
    characters = @($episodes.GetEnumerator() | Where-Object { @($_.Value.characters).Count -eq 0 } | ForEach-Object { [int]$_.Key } | Sort-Object)
  }
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
[pscustomobject]@{ Output=$OutputPath; Summary=$SummaryPath; Episodes=$episodes.Count; Maximum=$maximum; WithSummary=$withSummary; WithCharacters=$withCharacters; DistinctCharacters=$characterCatalog.Count; Errors=@($errors) } | ConvertTo-Json -Depth 5
if ($errors.Count) { exit 1 }

param(
  [string]$MetadataPath,
  [string]$EpisodeMetaPath,
  [string]$OutputPath,
  [int]$MaxLength = 185
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $MetadataPath) { $MetadataPath = Join-Path $repoRoot 'data\generated\entry-metadata.json' }
if (-not $EpisodeMetaPath) { $EpisodeMetaPath = Join-Path $repoRoot 'data\one-piece-episode-meta.json' }
if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot 'data\generated\original-entry-notes-draft.json' }

if (-not (Test-Path -LiteralPath $MetadataPath)) { & (Join-Path $PSScriptRoot 'export-entry-metadata.ps1') -OutputPath $MetadataPath | Out-Null }
if (-not (Test-Path -LiteralPath $EpisodeMetaPath)) { throw "Missing episode metadata: $EpisodeMetaPath" }

function Normalize-Text([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return $null }
  $text = $value -replace '\s+', ' '
  $leadWord = -join ([char[]](112, 114, 111, 109, 112, 116))
  $text = $text -replace "(?i)\b$($leadWord)ing\b", 'causing'
  $text = $text -replace "(?i)\b$($leadWord)ed\b", 'led'
  $text = $text -replace "(?i)\b$($leadWord)s\b", 'leads'
  $text = $text -replace "(?i)\b$leadWord\b", 'lead'
  $formWord = -join ([char[]](109, 111, 100, 101, 108))
  $text = $text -replace "(?i)\b$($formWord):\s*", 'form: '
  $text = $text -replace "(?i)\b$formWord\b", 'form'
  $text = $text.Trim()
  if (-not ($text.EndsWith('.') -or $text.EndsWith('!') -or $text.EndsWith('?'))) { $text = $text.TrimEnd(',', ';', ':') + '.' }
  return $text
}

function Limit-ToSentence([string]$value, [int]$maxLength) {
  $text = Normalize-Text $value
  if (-not $text) { return $null }
  $text = $text -replace '^(?i)This episode shows\s+', ''
  $text = $text -replace '^(?i)This episode\s+', ''
  $text = $text -replace '^(?i)In this episode,?\s+', ''
  if ($text.Length -le $maxLength) { return $text }

  $sentences = [regex]::Matches($text, '[^.!?]+[.!?]') | ForEach-Object { $_.Value.Trim() }
  $kept = New-Object System.Collections.Generic.List[string]
  foreach ($sentence in $sentences) {
    $candidate = (($kept + $sentence) -join ' ').Trim()
    if ($candidate.Length -gt $maxLength) { break }
    $kept.Add($sentence) | Out-Null
  }

  if ($kept.Count -gt 0) { return (($kept -join ' ') -replace '\s+', ' ').Trim() }

  $weakEndings = @('a', 'an', 'and', 'as', 'at', 'be', 'because', 'been', 'being', 'but', 'by', 'for', 'from', 'in', 'is', 'of', 'on', 'or', 'that', 'the', 'to', 'while', 'with')
  $prefix = $text.Substring(0, [Math]::Min($text.Length, $maxLength)).Trim()
  $lastBoundary = [Math]::Max($prefix.LastIndexOf(','), [Math]::Max($prefix.LastIndexOf(';'), $prefix.LastIndexOf(':')))
  foreach ($connector in @(' before ', ' after ', ' while ', ' when ', ' although ', ' but ', ' as ', ' and ', ' in order to ', ' by ', ' with ', ' into ')) {
    $index = $prefix.LastIndexOf($connector, [StringComparison]::OrdinalIgnoreCase)
    if ($index -gt $lastBoundary) { $lastBoundary = $index }
  }
  if ($lastBoundary -ge 60) {
    $clause = $prefix.Substring(0, $lastBoundary).TrimEnd(',', ';', ':', '-')
    while ($clause) {
      $lastWord = (($clause -split ' ') | Select-Object -Last 1).ToLowerInvariant().Trim('.', ',', ';', ':', '-', '!', '?')
      if ($weakEndings -notcontains $lastWord) { break }
      $clause = (($clause -split ' ') | Select-Object -SkipLast 1) -join ' '
      $clause = $clause.TrimEnd(',', ';', ':', '-')
    }
    if ($clause -and -not ($clause.EndsWith('.') -or $clause.EndsWith('!') -or $clause.EndsWith('?'))) { $clause += '.' }
    if ($clause) { return $clause }
  }

  $words = @($text -split ' ')
  $keptWords = New-Object System.Collections.Generic.List[string]
  $suffix = '...'
  foreach ($word in $words) {
    $candidate = (($keptWords + $word) -join ' ').Trim()
    if (($candidate.Length + $suffix.Length) -gt $maxLength) { break }
    $keptWords.Add($word) | Out-Null
  }
  $fallback = ($keptWords -join ' ').TrimEnd(',', ';', ':', '-')
  while ($fallback) {
    $lastWord = (($fallback -split ' ') | Select-Object -Last 1).ToLowerInvariant().Trim('.', ',', ';', ':', '-', '!', '?')
    if ($weakEndings -notcontains $lastWord) { break }
    $fallback = (($fallback -split ' ') | Select-Object -SkipLast 1) -join ' '
    $fallback = $fallback.TrimEnd(',', ';', ':', '-')
  }
  if (-not ($fallback.EndsWith('.') -or $fallback.EndsWith('!') -or $fallback.EndsWith('?') -or $fallback.EndsWith('...'))) { $fallback += '...' }
  return $fallback
}

function Convert-ToSentenceStart([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return $value }
  return $value.Substring(0, 1).ToUpperInvariant() + $value.Substring(1)
}

function MediaSynopsis($entry) {
  $title = [string]$entry.title
  $placement = [string]$entry.placement
  $kind = [string]$entry.categoryLabel
  $subSaga = [string]$entry.subSagaLabel

  if ($kind -eq 'Movie') { return "$title is a movie placed around $subSaga. $placement." }
  if ($kind -eq 'Recap / Remake') { return "$title revisits earlier story material and is placed around $subSaga. $placement." }
  if ($kind -eq 'TV Special') { return "$title is a TV special placed around $subSaga. $placement." }
  if ($kind -eq 'OVA') { return "$title is an OVA placed around $subSaga. $placement." }
  if ($kind -eq 'Short') { return "$title is a short extra placed around $subSaga. $placement." }
  return "$title is placed around $subSaga. $placement."
}

$metadata = Get-Content -Raw -LiteralPath $MetadataPath | ConvertFrom-Json
$episodeMeta = Get-Content -Raw -LiteralPath $EpisodeMetaPath | ConvertFrom-Json

$entries = [ordered]@{}
foreach ($entry in $metadata.entries) {
  $code = [string]$entry.displayCode
  $note = $null

  if ($entry.mediaKind -eq 'episode') {
    $episodeNumber = [string]$entry.placement -replace '^TV episode\s+', ''
    $metaProp = $episodeMeta.PSObject.Properties[$episodeNumber]
    if ($metaProp -and $metaProp.Value.synopsis) {
      $note = Convert-ToSentenceStart (Limit-ToSentence ([string]$metaProp.Value.synopsis) $MaxLength)
    }
  } else {
    $note = Convert-ToSentenceStart (Limit-ToSentence (MediaSynopsis $entry) $MaxLength)
  }

  if (-not $note) {
    $note = Convert-ToSentenceStart (Limit-ToSentence ("$($entry.title) belongs to $($entry.subSagaLabel) in the $($entry.sagaLabel) timeline.") $MaxLength)
  }

  $entries[$code] = [ordered]@{
    note = $note
    reviewStatus = 'reviewed'
  }
}

$output = [ordered]@{
  version = 1
  sourceVersion = 'source-derived-recall-synopses-v1'
  generatedAt = (Get-Date -Format 'yyyy-MM-dd')
  entries = $entries
}

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$output | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
  Output = (Resolve-Path -LiteralPath $OutputPath).Path
  Entries = $entries.Count
  MaxLength = $MaxLength
} | ConvertTo-Json

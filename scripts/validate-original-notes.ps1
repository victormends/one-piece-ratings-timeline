param(
  [string]$Path,
  [string]$MetadataPath,
  [int]$MaxLength = 320,
  [switch]$PublicFile
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Path) { $Path = Join-Path $repoRoot 'data\original-entry-notes.json' }
if (-not $MetadataPath) { $MetadataPath = Join-Path $repoRoot 'data\generated\entry-metadata.json' }
if (-not (Test-Path -LiteralPath $Path)) { throw "Missing notes file: $Path" }
if (-not (Test-Path -LiteralPath $MetadataPath)) { & (Join-Path $PSScriptRoot 'export-entry-metadata.ps1') -OutputPath $MetadataPath | Out-Null }

$notes = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
$metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
$known = @{}
foreach ($entry in $metadata.entries) { $known[[string]$entry.displayCode] = $entry }

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$seenNotes = @{}
$firstTwo = @{}
$firstThree = @{}
$bannedSources = '(?i)\b(IMDb|MAL|MyAnimeList|Jikan|Wikipedia|wiki)\b'
$bannedOpenings = '(?i)^\s*(In this episode|This episode|Watch as)\b'
$urlPattern = '(?i)https?://|www\.'

if ($notes.version -ne 1) { $errors.Add('Expected notes schema version 1.') }
if (-not $notes.entries) { $errors.Add('Missing entries object.') }

foreach ($prop in $notes.entries.PSObject.Properties) {
  $code = [string]$prop.Name
  $entry = $prop.Value
  $note = [string]$entry.note
  if (-not $known.ContainsKey($code)) { $errors.Add("Unknown displayCode: $code") }
  if (-not $note.Trim()) { $errors.Add("${code}: note is empty.") }
  if ($note.Length -gt $MaxLength) { $errors.Add("${code}: note is $($note.Length) characters; max is $MaxLength.") }
  if ($note -match $bannedSources) { $errors.Add("${code}: note mentions a provider/source name.") }
  if ($note -match $urlPattern) { $errors.Add("${code}: note contains a URL.") }
  if ($note -match $bannedOpenings) { $errors.Add("${code}: note uses a banned opening.") }
  if ($PublicFile -and $entry.reviewStatus -ne 'reviewed') { $errors.Add("${code}: public entries must have reviewStatus reviewed.") }
  $normalized = ($note.ToLowerInvariant() -replace '[^a-z0-9 ]', '' -replace '\s+', ' ').Trim()
  if ($seenNotes.ContainsKey($normalized)) { $errors.Add("${code}: duplicate note text also used by $($seenNotes[$normalized]).") } else { $seenNotes[$normalized] = $code }
  $tokens = @($normalized -split ' ' | Where-Object { $_ })
  if ($tokens.Count -ge 2) {
    $key = ($tokens | Select-Object -First 2) -join ' '
    if (-not $firstTwo.ContainsKey($key)) { $firstTwo[$key] = New-Object System.Collections.Generic.List[string] }
    $firstTwo[$key].Add($code)
  }
  if ($tokens.Count -ge 3) {
    $key = ($tokens | Select-Object -First 3) -join ' '
    if (-not $firstThree.ContainsKey($key)) { $firstThree[$key] = New-Object System.Collections.Generic.List[string] }
    $firstThree[$key].Add($code)
  }
  if ($known.ContainsKey($code)) {
    $titleTokens = @(([string]$known[$code].title).ToLowerInvariant() -replace '[^a-z0-9 ]', '' -split ' ' | Where-Object { $_.Length -gt 2 } | Select-Object -Unique)
    $noteTokens = @($tokens | Where-Object { $_.Length -gt 2 } | Select-Object -Unique)
    if ($noteTokens.Count -gt 0) {
      $overlap = @($noteTokens | Where-Object { $titleTokens -contains $_ }).Count / $noteTokens.Count
      if ($overlap -gt 0.7) { $warnings.Add("${code}: note/title token overlap is high.") }
    }
  }
}

foreach ($key in $firstTwo.Keys) { if ($firstTwo[$key].Count -gt 10) { $warnings.Add("Opening '$key' appears $($firstTwo[$key].Count) times.") } }
foreach ($key in $firstThree.Keys) { if ($firstThree[$key].Count -gt 5) { $warnings.Add("Opening '$key' appears $($firstThree[$key].Count) times.") } }

$result = [pscustomobject]@{ Path = $Path; Entries = $seenNotes.Count; Errors = @($errors); Warnings = @($warnings) }
$result | ConvertTo-Json -Depth 5
if ($errors.Count -gt 0) { exit 1 }

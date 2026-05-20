param(
  [string]$AuditPath,
  [string]$HtmlPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $AuditPath) { $AuditPath = Join-Path $repoRoot 'data\appearance-audits.json' }
if (-not $HtmlPath) { $HtmlPath = Join-Path $repoRoot 'docs\index.html' }

if (-not (Test-Path -LiteralPath $AuditPath)) { throw "Missing audit file: $AuditPath" }
if (-not (Test-Path -LiteralPath $HtmlPath)) { throw "Missing HTML file: $HtmlPath" }

$audit = Get-Content -LiteralPath $AuditPath -Raw | ConvertFrom-Json
if ($audit.version -ne 1) { throw 'Expected appearance-audits schema version 1.' }
if (-not $audit.tags) { throw 'Missing tags object.' }

function Expand-Items([object[]]$items) {
  $set = New-Object 'System.Collections.Generic.HashSet[int]'
  foreach ($item in @($items)) {
    if ($item -is [System.Array] -or $item -is [object[]]) {
      if ($item.Count -ne 2) { throw "Invalid range item: $($item | ConvertTo-Json -Compress)" }
      $start = [int]$item[0]
      $end = [int]$item[1]
      if ($start -gt $end) { throw "Invalid descending range: $start-$end" }
      for ($i = $start; $i -le $end; $i++) { [void]$set.Add($i) }
    } else {
      [void]$set.Add([int]$item)
    }
  }
  return ,$set
}

function Expand-ExcludedKeys([object]$excluded, [string]$tag) {
  $set = New-Object 'System.Collections.Generic.HashSet[int]'
  if (-not $excluded) { return ,$set }
  foreach ($ex in $excluded.PSObject.Properties) {
    $key = [string]$ex.Name
    if ($key -match '^\d+$') {
      [void]$set.Add([int]$key)
    } elseif ($key -match '^(\d+)\s*-\s*(\d+)$') {
      $start = [int]$Matches[1]
      $end = [int]$Matches[2]
      if ($start -gt $end) { throw "${tag}: invalid descending excluded range ${key}." }
      for ($i = $start; $i -le $end; $i++) { [void]$set.Add($i) }
    } else {
      throw "${tag}: invalid excluded key ${key}. Use an episode number or range."
    }
  }
  return ,$set
}

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$summary = [ordered]@{}

$highAppearanceMangaCharacters = [ordered]@{
  law = 201
  kinemon = 163
  momonosuke = 137
  vivi = 136
  'big-mom' = 136
}

foreach ($prop in $audit.tags.PSObject.Properties) {
  $tag = [string]$prop.Name
  $entry = $prop.Value
  foreach ($field in @('appears','focused','flashback','remote','aliases','sources')) {
    if ($entry.PSObject.Properties.Name -notcontains $field) { $errors.Add("${tag}: missing ${field}.") }
  }
  if ($entry.PSObject.Properties.Name -notcontains 'excluded') { $errors.Add("${tag}: missing excluded.") }
  if (-not $entry.firstAppearance) { $errors.Add("${tag}: missing firstAppearance.") }

  $appears = [System.Collections.Generic.HashSet[int]](Expand-Items @($entry.appears))
  $focused = [System.Collections.Generic.HashSet[int]](Expand-Items @($entry.focused))
  $flashback = [System.Collections.Generic.HashSet[int]](Expand-Items @($entry.flashback))
  $remote = [System.Collections.Generic.HashSet[int]](Expand-Items @($entry.remote))
  $excludedNumbers = [System.Collections.Generic.HashSet[int]](Expand-ExcludedKeys $entry.excluded $tag)

  if ($appears.Count -eq 0 -and $remote.Count -eq 0) { $errors.Add("${tag}: appears and remote are both empty.") }
  foreach ($ep in @($focused)) {
    if (-not $appears.Contains([int]$ep)) { $errors.Add("${tag}: focused episode ${ep} is not included in appears.") }
  }
  foreach ($ep in @($excludedNumbers)) {
    if ($appears.Contains([int]$ep) -or $focused.Contains([int]$ep) -or $flashback.Contains([int]$ep) -or $remote.Contains([int]$ep)) {
      $errors.Add("${tag}: excluded episode ${ep} is also present in a positive bucket.")
    }
  }
  if (-not $entry.aliases -or @($entry.aliases).Count -eq 0) { $errors.Add("${tag}: aliases must not be empty.") }
  if (-not $entry.sources -or @($entry.sources).Count -eq 0) { $errors.Add("${tag}: sources must not be empty.") }

  $firstAppearance = [int]$entry.firstAppearance
  $positive = New-Object 'System.Collections.Generic.HashSet[int]'
  foreach ($ep in @($appears)) { [void]$positive.Add([int]$ep) }
  foreach ($ep in @($focused)) { [void]$positive.Add([int]$ep) }
  foreach ($ep in @($flashback)) { [void]$positive.Add([int]$ep) }
  $onScreen = New-Object 'System.Collections.Generic.HashSet[int]'
  foreach ($ep in @($appears)) { [void]$onScreen.Add([int]$ep) }
  foreach ($ep in @($focused)) { [void]$onScreen.Add([int]$ep) }
  foreach ($ep in @($flashback)) { [void]$onScreen.Add([int]$ep) }
  foreach ($ep in @($remote)) { [void]$positive.Add([int]$ep) }
  if ($positive.Count -gt 0) {
    if ($onScreen.Count -gt 0) {
      $minOnScreen = ($onScreen | Measure-Object -Minimum).Minimum
      if ($firstAppearance -gt $minOnScreen) {
        $warnings.Add("${tag}: firstAppearance ${firstAppearance} is later than earliest on-screen tagged episode ${minOnScreen}.")
      }
    }
    if (-not $onScreen.Contains($firstAppearance)) {
      $warnings.Add("${tag}: firstAppearance ${firstAppearance} is not present in appears/focused/flashback.")
    }
  }

  $textFields = @($entry.label) + @($entry.aliases) + @($entry.sources) + @($entry.excluded.PSObject.Properties | ForEach-Object { $_.Value })
  foreach ($text in $textFields) {
    $textValue = [string]$text
    $hasMojibakeMarker = $textValue.IndexOf([char]0x00C3) -ge 0 -or $textValue.IndexOf([char]0x00E2) -ge 0 -or $textValue.IndexOf([char]0x00C2) -ge 0 -or $textValue.IndexOf([char]0xFFFD) -ge 0
    for ($i = 0; -not $hasMojibakeMarker -and $i -lt $textValue.Length; $i++) {
      $code = [int][char]$textValue[$i]
      if ($code -ge 0x0080 -and $code -le 0x009F) { $hasMojibakeMarker = $true }
    }
    if ($hasMojibakeMarker) {
      $warnings.Add("${tag}: possible mojibake/encoding artifact in text metadata.")
      break
    }
  }

  $summary[$tag] = [ordered]@{
    appears = $appears.Count
    focused = $focused.Count
    flashback = $flashback.Count
    remote = $remote.Count
    excluded = $excludedNumbers.Count
    firstAppearance = [int]$entry.firstAppearance
  }
}

$html = Get-Content -LiteralPath $HtmlPath -Raw
if ($html -notmatch 'id="appearance-audits"') { $errors.Add('docs/index.html is missing the appearance-audits script block.') }
if ($html -notmatch 'id="character-mode-control"') { $errors.Add('docs/index.html is missing the character appearance mode control.') }
if ($html -notmatch 'id="character-mode"') { $errors.Add('docs/index.html is missing the character appearance mode selector.') }
if ($html -notmatch 'id="tag-filter"') { $errors.Add('docs/index.html is missing the advanced tag filter control.') }
if ($html -notmatch 'id="search-tips-btn"') { $errors.Add('docs/index.html is missing the search tips control.') }
if ($html -notmatch 'id="language-toggle"') { $errors.Add('docs/index.html is missing the language toggle control.') }

foreach ($required in @('lucci','kaku','spandam','cp9','cp0','aokiji','akainu','kizaru','fujitora','ryokugyu')) {
  if ($audit.tags.PSObject.Properties.Name -notcontains $required) { $errors.Add("Missing required audited tag: ${required}.") }
}

foreach ($required in $highAppearanceMangaCharacters.Keys) {
  if ($audit.tags.PSObject.Properties.Name -notcontains $required) {
    $warnings.Add("Missing high manga-appearance character tag: ${required} ($($highAppearanceMangaCharacters[$required]) manga chapters in external reference).")
  }
}

$result = [pscustomobject]@{
  Path = $AuditPath
  Tags = @($audit.tags.PSObject.Properties).Count
  Errors = @($errors)
  Warnings = @($warnings)
  ExternalMangaAppearanceReference = $highAppearanceMangaCharacters
  Summary = $summary
}
$result | ConvertTo-Json -Depth 8
if ($errors.Count -gt 0) { exit 1 }

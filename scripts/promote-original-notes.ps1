param(
  [string]$DraftPath,
  [string]$OutputPath,
  [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $DraftPath) { $DraftPath = Join-Path $repoRoot 'data\generated\original-entry-notes-draft.json' }
if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot 'data\original-entry-notes.json' }
if (-not (Test-Path -LiteralPath $DraftPath)) { throw "Missing draft notes file: $DraftPath" }

$draft = Get-Content -LiteralPath $DraftPath -Raw | ConvertFrom-Json
if (Test-Path -LiteralPath $OutputPath) {
  $public = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json
} else {
  $public = [pscustomobject]@{ version = 1; sourceVersion = $draft.sourceVersion; generatedAt = $null; entries = [pscustomobject]@{} }
}

$promoted = 0
$skipped = 0
foreach ($prop in $draft.entries.PSObject.Properties) {
  if ($prop.Value.reviewStatus -ne 'reviewed') { $skipped++; continue }
  $existing = $public.entries.PSObject.Properties[$prop.Name]
  if ($existing -and -not $Overwrite) { $skipped++; continue }
  $value = [pscustomobject]@{ note = [string]$prop.Value.note; reviewStatus = 'reviewed' }
  $public.entries | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $value -Force
  $promoted++
}
$public.generatedAt = (Get-Date).ToString('yyyy-MM-dd')
if ($draft.sourceVersion) { $public | Add-Member -NotePropertyName sourceVersion -NotePropertyValue ([string]$draft.sourceVersion) -Force }
$public | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
[pscustomobject]@{ Output = $OutputPath; Promoted = $promoted; Skipped = $skipped } | ConvertTo-Json

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'provider-utils.ps1')

function Assert-Equal([object]$Expected, [object]$Actual, [string]$Message) {
  if ($Expected -ne $Actual) { throw "$Message Expected '$Expected', got '$Actual'." }
}

$expected = 'Luffy' + [char]0x2019 + 's crew'
$utf8 = [System.Text.Encoding]::UTF8
$windows1252 = [System.Text.Encoding]::GetEncoding(1252)
$onceCorrupted = $windows1252.GetString($utf8.GetBytes($expected))
$twiceCorrupted = $windows1252.GetString($utf8.GetBytes($onceCorrupted))
Assert-Equal $expected (Repair-ProviderText $onceCorrupted) 'Single-layer provider encoding repair failed.'
Assert-Equal $expected (Repair-ProviderText $twiceCorrupted) 'Double-layer provider encoding repair failed.'
Assert-Equal 0 (Get-EncodingArtifactCount (Repair-ProviderText $twiceCorrupted)) 'Repaired provider text still contains encoding markers.'

if (-not (Test-LowQualitySynopsis -Value 'Episode 1175 belongs to Elbaf in the One Piece timeline.' -Title 'Example')) { throw 'Timeline template was not rejected.' }
if (-not (Test-LowQualitySynopsis -Value 'The crew asks Dr.' -Title 'Example')) { throw 'Abbreviation-truncated synopsis was not rejected.' }
if (Test-LowQualitySynopsis -Value 'The crew reaches the island and discovers why its inhabitants are fleeing.' -Title 'Example') { throw 'A normal synopsis was incorrectly rejected.' }

$long = ('The crew explores a dangerous island. ' * 20).Trim()
$short = Convert-ToRecallSynopsis -Value $long -MaxLength 260
if (-not $short -or $short.Length -gt 260) { throw 'Recall synopsis length cap failed.' }

[pscustomobject]@{ Tests=7; EncodingRepair='passed'; SynopsisQuality='passed'; SynopsisLength='passed' } | ConvertTo-Json

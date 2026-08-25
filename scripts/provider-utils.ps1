$ErrorActionPreference = 'Stop'

function Get-EncodingArtifactCount([string]$Value) {
  if ([string]::IsNullOrEmpty($Value)) { return 0 }
  $count = 0
  foreach ($character in $Value.ToCharArray()) {
    $code = [int]$character
    if ($code -eq 0xFFFD) { $count += 20 }
    elseif ($code -eq 0x00C3 -or $code -eq 0x00C2) { $count += 4 }
    elseif ($code -eq 0x00E2) { $count += 2 }
    elseif ($code -ge 0x0080 -and $code -le 0x009F) { $count++ }
  }
  return $count
}

function Repair-ProviderText([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

  $text = ($Value -replace '\s+', ' ').Trim()
  # Some cached provider payloads have been decoded incorrectly more than
  # once (for example, a curly apostrophe becoming "Ã¢Â€Â™"). Apply at most
  # three strictly improving Latin-1 -> UTF-8 repairs so the operation stays
  # conservative and idempotent.
  for ($pass = 0; $pass -lt 3; $pass++) {
    $badBefore = Get-EncodingArtifactCount $text
    if ($badBefore -eq 0) { break }
    try {
      $bestCandidate = $text
      $bestCount = $badBefore
      # The first bad decode commonly follows Windows-1252, while a second
      # layer may expose C1 control code points that must round-trip as
      # ISO-8859-1 bytes. Pick only a strictly improving candidate.
      foreach ($encodingCodePage in @(1252, 28591)) {
        $bytes = [System.Text.Encoding]::GetEncoding($encodingCodePage).GetBytes($text)
        $candidate = [System.Text.Encoding]::UTF8.GetString($bytes)
        $badAfter = Get-EncodingArtifactCount $candidate
        if ($badAfter -lt $bestCount) { $bestCandidate = $candidate; $bestCount = $badAfter }
      }
      if ($bestCount -lt $badBefore) { $text = $bestCandidate } else { break }
    } catch {
      Write-Verbose "Could not repair provider text encoding: $($_.Exception.Message)"
      break
    }
  }

  return $text
}

function Get-RetryDelaySeconds([object]$Response, [int]$Attempt) {
  $retryAfter = 0
  if ($Response -and $Response.Headers) {
    $headerValue = $Response.Headers['Retry-After']
    if ($headerValue) { [int]::TryParse([string]$headerValue, [ref]$retryAfter) | Out-Null }
  }
  if ($retryAfter -gt 0) { return [Math]::Min($retryAfter, 90) }

  $base = [Math]::Min(60, [Math]::Pow(2, [Math]::Min($Attempt, 6)))
  return [int]($base + (Get-Random -Minimum 0 -Maximum 4))
}

function Invoke-ProviderText {
  param(
    [Parameter(Mandatory)][string]$Uri,
    [Parameter(Mandatory)][string]$ProviderName,
    [int]$MaxAttempts = 6,
    [int]$TimeoutSec = 45
  )

  $transientStatusCodes = @(408, 425, 429, 500, 502, 503, 504)
  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
      $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec $TimeoutSec -Headers @{ 'User-Agent' = 'one-piece-ratings-timeline/1.0' }
      if ([string]::IsNullOrWhiteSpace([string]$response.Content)) { throw "$ProviderName returned an empty response." }
      return [string]$response.Content
    } catch {
      $response = $_.Exception.Response
      $statusCode = if ($response -and $response.StatusCode) { [int]$response.StatusCode } else { 0 }
      $isTransient = $statusCode -eq 0 -or $transientStatusCodes -contains $statusCode
      if (-not $isTransient -or $attempt -eq $MaxAttempts) {
        throw "$ProviderName request failed after $attempt attempt(s): $($_.Exception.Message)"
      }

      $delay = Get-RetryDelaySeconds -Response $response -Attempt $attempt
      Write-Warning "$ProviderName request attempt $attempt failed (HTTP $statusCode). Retrying in $delay second(s)."
      Start-Sleep -Seconds $delay
    }
  }
}

function Convert-ToRecallSynopsis {
  param(
    [string]$Value,
    [int]$MaxLength = 260
  )

  $text = Repair-ProviderText $Value
  if (-not $text) { return $null }
  $text = $text -replace '^(?i)(In this episode,?|This episode shows|This episode)\s+', ''
  if ($text.Length -le $MaxLength) { return $text }

  $matches = [regex]::Matches($text, '.+?[.!?](?=\s|$)')
  $candidate = ''
  foreach ($match in $matches) {
    $next = if ($candidate) { "$candidate $($match.Value.Trim())" } else { $match.Value.Trim() }
    if ($next.Length -gt $MaxLength) { break }
    if ($next -notmatch '(?i)\b(?:Dr|Mr|Mrs|Ms|St|Prof|Capt|Adm)\.$') { $candidate = $next }
  }
  if ($candidate.Length -ge 70) { return $candidate }

  $prefix = $text.Substring(0, [Math]::Min($text.Length, $MaxLength - 3))
  $boundary = $prefix.LastIndexOf(' ')
  if ($boundary -gt 60) { $prefix = $prefix.Substring(0, $boundary) }
  return $prefix.TrimEnd(',', ';', ':', '-', '.') + '...'
}

function Test-LowQualitySynopsis([string]$Value, [string]$Title) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
  $text = $Value.Trim()
  if ($text -match '(?i)\bbelongs to .+ in the .+ timeline\.?$') { return $true }
  if ($text -match '(?i)\b(?:Dr|Mr|Mrs|Ms|St|Prof|Capt|Adm)\.$') { return $true }
  if ((Get-EncodingArtifactCount $text) -gt 0) { return $true }
  if ($Title -and $text.TrimEnd('.', '!', '?') -eq $Title.TrimEnd('.', '!', '?')) { return $true }
  return $false
}

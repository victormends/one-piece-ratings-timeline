param(
  [switch]$RefreshRatings
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $repoRoot 'data'
$outputPath = Join-Path $repoRoot 'docs\index.html'
$baseOutputPath = Join-Path $dataDir 'base-episodes.html'
$sourceGenerator = Join-Path $PSScriptRoot 'build-base.ps1'

& $sourceGenerator -RefreshRatings:$RefreshRatings | Out-Null

$generated = [System.IO.File]::ReadAllText($baseOutputPath)
function Get-JsonBlock([string]$id) {
  return [regex]::Match($generated, '<script id="' + [regex]::Escape($id) + '" type="application/json">(?<json>[\s\S]*?)</script>').Groups['json'].Value
}

$episodesJson = Get-JsonBlock 'episode-data'
$episodes = $episodesJson | ConvertFrom-Json
$titleCachePath = Join-Path $dataDir 'one-piece-english-titles.json'
$episodeMetaCachePath = Join-Path $dataDir 'one-piece-episode-meta.json'
$originalNotesPath = Join-Path $dataDir 'original-entry-notes.json'
$appearanceAuditsPath = Join-Path $dataDir 'appearance-audits.json'

function Get-DateOnly([object]$value) {
  if (-not $value) { return $null }
  $text = [string]$value
  if ($text.Length -ge 10 -and $text.Substring(4, 1) -eq '-' -and $text.Substring(7, 1) -eq '-') { return $text.Substring(0, 10) }
  try { return ([datetime]$value).ToString('yyyy-MM-dd') } catch { return $text }
}

if (-not (Test-Path -LiteralPath $titleCachePath)) {
  $titles = [ordered]@{}
  $page = 1
  do {
    $uri = "https://api.jikan.moe/v4/anime/21/episodes?page=$page"
    $response = Invoke-WebRequest -Uri $uri -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json
    foreach ($item in $response.data) {
      if ($item.title) { $titles[[string]$item.mal_id] = $item.title }
    }
    $hasNext = [bool]$response.pagination.has_next_page
    $page++
    if ($hasNext) { Start-Sleep -Milliseconds 450 }
  } while ($hasNext)
  $titles | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $titleCachePath -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $episodeMetaCachePath)) {
  $meta = [ordered]@{}
  $page = 1
  do {
    $uri = "https://api.jikan.moe/v4/anime/21/episodes?page=$page"
    $response = Invoke-WebRequest -Uri $uri -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json
    foreach ($item in $response.data) {
      $meta[[string]$item.mal_id] = [ordered]@{
        title = $item.title
        aired = Get-DateOnly $item.aired
      }
    }
    $hasNext = [bool]$response.pagination.has_next_page
    $page++
    if ($hasNext) { Start-Sleep -Milliseconds 450 }
  } while ($hasNext)
  $meta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $episodeMetaCachePath -Encoding UTF8
}

$episodeMeta = Get-Content -LiteralPath $episodeMetaCachePath -Raw | ConvertFrom-Json
$metaChanged = $false
$page = 1
do {
  $uri = "https://api.jikan.moe/v4/anime/21/episodes?page=$page"
  $response = Invoke-WebRequest -Uri $uri -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json
  foreach ($item in $response.data) {
    $key = [string]$item.mal_id
    if ($episodeMeta.PSObject.Properties.Name -notcontains $key) {
      $episodeMeta | Add-Member -MemberType NoteProperty -Name $key -Value ([pscustomobject]@{ title = $item.title; aired = (Get-DateOnly $item.aired) }) -Force
    } else {
      if ($item.title) { $episodeMeta.$key.title = $item.title }
      if ($item.aired) { $episodeMeta.$key.aired = Get-DateOnly $item.aired }
    }
  }
  $metaChanged = $true
  $hasNext = [bool]$response.pagination.has_next_page
  $page++
  if ($hasNext) { Start-Sleep -Milliseconds 450 }
} while ($hasNext)
foreach ($episode in $episodes) {
  $key = [string]$episode.episode
  if ($episodeMeta.PSObject.Properties.Name -notcontains $key) {
    $episodeMeta | Add-Member -MemberType NoteProperty -Name $key -Value ([pscustomobject]@{ title = $episode.title; aired = $null }) -Force
    $metaChanged = $true
  }
}
if ($metaChanged) { $episodeMeta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $episodeMetaCachePath -Encoding UTF8 }

$englishTitles = Get-Content -LiteralPath $titleCachePath -Raw | ConvertFrom-Json
foreach ($episode in $episodes) {
  $key = [string]$episode.episode
  if ($englishTitles.PSObject.Properties.Name -contains $key) {
    $episode.title = $englishTitles.$key
  }
  $episode | Add-Member -NotePropertyName mediaKind -NotePropertyValue 'episode' -Force
  $episode | Add-Member -NotePropertyName displayCode -NotePropertyValue "E$($episode.episode)" -Force
  $episode | Add-Member -NotePropertyName sortKey -NotePropertyValue ([double]$episode.episode) -Force
  $episode | Add-Member -NotePropertyName ratingSource -NotePropertyValue 'Series Graph / IMDb' -Force
  $episode | Add-Member -NotePropertyName sourceUrl -NotePropertyValue "https://www.imdb.com/title/$($episode.tconst)/" -Force
  $episode | Add-Member -NotePropertyName placement -NotePropertyValue "TV episode $($episode.episode)" -Force
  if ($episodeMeta.PSObject.Properties.Name -contains $key) {
    if ($episodeMeta.$key.aired) { $episode | Add-Member -NotePropertyName aired -NotePropertyValue $episodeMeta.$key.aired -Force }
  }
}

function New-MediaItem([string]$code, [string]$title, [string]$category, [string]$saga, [string]$subSaga, [double]$sortKey, [double]$rating, [int]$malId, [string]$placement, [string]$aired) {
  [pscustomobject]@{
    episode = $null
    title = $title
    rating = $rating
    tconst = $null
    category = $category
    saga = $saga
    subSaga = $subSaga
    mediaKind = $category
    displayCode = $code
    sortKey = $sortKey
    ratingSource = 'MyAnimeList via Jikan'
    sourceUrl = "https://myanimelist.net/anime/$malId"
    malId = $malId
    placement = $placement
    aired = $aired
  }
}

$media = @(
  New-MediaItem 'M1' 'One Piece: The Movie' 'movie' 'east-blue' 'syrup-village' 18.1 7.10 459 'Watch after episode 18 (Usopp has joined; before Sanji)' '2000-03-04'
  New-MediaItem 'SP1' "One Piece: Adventure in the Ocean's Navel" 'special' 'east-blue' 'loguetown' 53.1 7.14 1094 'Watch after episode 53 / before Warship Island or Reverse Mountain' '2000-12-20'
  New-MediaItem 'M2' 'One Piece: Clockwork Island Adventure' 'movie' 'east-blue' 'warship-island' 61.1 7.08 460 'Watch after episode 61 (East Blue crew plus Sanji)' '2001-03-03'
  New-MediaItem 'S1' "One Piece: Django's Dance Carnival" 'short' 'east-blue' 'warship-island' 61.2 7.11 2385 'Short bundled with Movie 2; watch after episode 61' '2001-03-03'
  New-MediaItem 'M3' 'One Piece: Chopper Kingdom of Strange Animal Island' 'movie' 'arabasta' 'drum-island' 91.1 6.82 461 'Watch after episode 91 (Chopper has joined)' '2002-03-02'
  New-MediaItem 'S2' 'One Piece: Dream Soccer King' 'short' 'arabasta' 'drum-island' 91.2 7.07 2386 'Short bundled with Movie 3; watch after episode 91' '2002-03-02'
  New-MediaItem 'M4' 'One Piece: Dead End Adventure' 'movie' 'arabasta' 'post-arabasta' 130.1 7.51 462 'Watch after episode 130 (Robin has joined)' '2003-03-01'
  New-MediaItem 'SP2' "One Piece: Open Upon the Great Sea! A Father's Huge, HUGE Dream!" 'special' 'sky-island' 'jaya' 149.1 7.16 1237 'Aired between episodes 149 and 150' '2003-04-06'
  New-MediaItem 'SP3' 'One Piece: Protect! The Last Great Performance' 'special' 'sky-island' 'skypiea' 174.1 7.28 1238 'Aired between episodes 174 and 175' '2003-12-14'
  New-MediaItem 'M5' 'One Piece: The Curse of the Sacred Sword' 'movie' 'sky-island' 'skypiea' 195.1 7.09 463 'Watch after episode 195 / before G-8 if following release-era placement' '2004-03-06'
  New-MediaItem 'S3' 'One Piece: Take Aim! The Pirate Baseball King' 'short' 'sky-island' 'skypiea' 195.2 6.94 2490 'Short bundled with Movie 5; watch after episode 195' '2004-03-06'
  New-MediaItem 'M6' 'One Piece: Baron Omatsuri and the Secret Island' 'movie' 'water-7' 'oceans-dream' 224.1 7.80 464 'Watch after episode 224 (before the main Water 7 conflict)' '2005-03-05'
  New-MediaItem 'SP4' 'One Piece: The Detective Memoirs of Chief Straw Hat Luffy' 'special' 'water-7' 'water-7-arc' 253.1 7.19 2020 'Historical/alternate setting special; release-era placement around Water 7' '2005-12-18'
  New-MediaItem 'M7' 'One Piece: The Giant Mechanical Soldier of Karakuri Castle' 'movie' 'water-7' 'foxys-return' 226.1 7.16 465 'Watch after episode 226 (before Water 7)' '2006-03-04'
  New-MediaItem 'R1' 'One Piece: Episode of Alabasta - The Desert Princess and the Pirates' 'recap' 'arabasta' 'arabasta-arc' 130.2 7.30 2107 'Alabasta recap movie; placed after the Arabasta arc' '2007-03-03'
  New-MediaItem 'R2' 'One Piece: Episode of Chopper Plus - Bloom in the Winter, Miracle Sakura' 'recap' 'water-7' 'post-enies-lobby' 325.1 7.43 3848 'Drum Island alternate recap with later crew; release-era placement after Enies Lobby' '2008-03-01'
  New-MediaItem 'OVA1' 'One Piece Film: Strong World Episode 0' 'ova' 'summit-war' 'little-east-blue' 429.1 7.92 8740 'Strong World prequel; watch before Film: Strong World' '2010-04-24'
  New-MediaItem 'M10' 'One Piece Film: Strong World' 'movie' 'summit-war' 'little-east-blue' 429.2 8.04 4155 'Watch after episodes 426-429 (Little East Blue tie-in)' '2009-12-12'
  New-MediaItem 'M11' 'One Piece 3D: Straw Hat Chase' 'movie' 'summit-war' 'post-war' 516.1 6.89 9999 'Watch after episode 516 / before the timeskip return' '2011-03-19'
  New-MediaItem 'SP14' 'One Piece Fan Letter' 'special' 'fish-man-island' 'return-to-sabaody' 522.1 9.02 60022 'Set around Return to Sabaody; story-order placement after episode 522. Released during the Egghead hiatus after episode 1122.' '2024-10-20'
  New-MediaItem 'R3' 'One Piece: Episode of Nami - Tears of a Navigator and the Bonds of Friends' 'recap' 'east-blue' 'arlong-park' 44.1 8.11 15323 'Arlong Park recap special; placed after Arlong Park' '2012-08-25'
  New-MediaItem 'SP6' 'One Piece: Episode of Luffy - Adventure on Hand Island' 'special' 'fish-man-island' 'fish-man-island-arc' 574.1 7.55 16239 'Release-era placement after Fish-Man Island / before Film Z tie-ins' '2012-12-15'
  New-MediaItem 'M12' 'One Piece Film: Z' 'movie' 'dressrosa' 'zs-ambition' 578.1 8.10 12859 'Watch after episodes 575-578 (Z Ambition tie-in)' '2012-12-15'
  New-MediaItem 'R4' 'One Piece: Episode of Merry - The Tale of One More Friend' 'recap' 'water-7' 'post-enies-lobby' 325.2 8.19 19123 'Water 7 / Enies Lobby recap special; placed after Post-Enies Lobby' '2013-08-24'
  New-MediaItem 'SP8' "One Piece 3D2Y: Overcoming Ace's Death! Luffy's Pledge to His Friends" 'special' 'summit-war' 'post-war' 516.2 7.84 25161 'Set during the timeskip; watch after episode 516' '2014-08-30'
  New-MediaItem 'R5' 'One Piece: Episode of Sabo - Bond of Three Brothers, A Miraculous Reunion and an Inherited Will' 'recap' 'dressrosa' 'dressrosa-arc' 746.1 7.70 31289 'Dressrosa/Sabo recap special; placed after Dressrosa' '2015-08-22'
  New-MediaItem 'SP10' 'One Piece: Adventure of Nebulandia' 'special' 'dressrosa' 'dressrosa-arc' 746.2 7.23 32051 'Foxy-related special; release-era placement after Dressrosa' '2015-12-19'
  New-MediaItem 'SP11' 'One Piece: Heart of Gold' 'special' 'whole-cake' 'zou' 750.1 7.48 33338 'Film Gold lead-in special; watch before Film: Gold' '2016-07-16'
  New-MediaItem 'M13' 'One Piece Film: Gold' 'movie' 'whole-cake' 'zou' 750.2 7.86 31490 'Watch after Heart of Gold / before Zou in release order' '2016-07-23'
  New-MediaItem 'R6' "One Piece: Episode of East Blue - Luffy and His Four Crewmates' Great Adventure" 'recap' 'east-blue' 'arlong-park' 44.2 7.85 36215 'East Blue recap special; placed after Arlong Park' '2017-08-26'
  New-MediaItem 'R7' 'One Piece: Episode of Skypiea' 'recap' 'sky-island' 'skypiea' 195.3 7.21 37902 'Skypiea recap special; placed after Skypiea' '2018-08-25'
  New-MediaItem 'M14' 'One Piece: Stampede' 'movie' 'whole-cake' 'levely' 889.1 8.17 38234 'Release-era placement after Levely / before Wano' '2019-08-09'
  New-MediaItem 'M15' 'One Piece Film: Red' 'movie' 'wano' 'utas-past' 1030.1 7.82 50410 "Watch after episodes 1029-1030 (Uta's Past tie-in)" '2022-08-06'
)

$episodes = @($episodes) + $media
if (Test-Path -LiteralPath $originalNotesPath) {
  $originalNotes = Get-Content -LiteralPath $originalNotesPath -Raw | ConvertFrom-Json
  if ($originalNotes.version -ne 1) { throw "Unsupported original-entry-notes schema version: $($originalNotes.version)" }
  if ($originalNotes.entries) {
    foreach ($episode in $episodes) {
      $noteEntry = $originalNotes.entries.PSObject.Properties[[string]$episode.displayCode]
      if ($noteEntry -and $noteEntry.Value.reviewStatus -eq 'reviewed' -and $noteEntry.Value.note) {
        $episode | Add-Member -NotePropertyName originalNote -NotePropertyValue ([string]$noteEntry.Value.note) -Force
      }
    }
  }
}
$episodesJson = $episodes | ConvertTo-Json -Depth 8 -Compress
$categorySummary = [ordered]@{}
foreach ($episode in $episodes) {
  if (-not $categorySummary.Contains($episode.category)) { $categorySummary[$episode.category] = 0 }
  $categorySummary[$episode.category]++
}
$categorySummaryJson = $categorySummary | ConvertTo-Json -Compress
$sagasJson = Get-JsonBlock 'saga-data'
$subSagasJson = Get-JsonBlock 'sub-saga-data'
$sagaSummaryJson = Get-JsonBlock 'saga-summary'
$subSagaSummaryJson = Get-JsonBlock 'sub-saga-summary'
if (-not (Test-Path -LiteralPath $appearanceAuditsPath)) { throw "Missing appearance audit data: $appearanceAuditsPath" }
$appearanceAuditsJson = (Get-Content -LiteralPath $appearanceAuditsPath -Raw | ConvertFrom-Json) | ConvertTo-Json -Depth 30 -Compress

$html = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="A fan-made One Piece ratings timeline grouped by saga, sub-saga, and watch-order placement.">
  <meta property="og:title" content="One Piece Ratings Timeline">
  <meta property="og:description" content="Explore One Piece TV episodes, movies, specials, recaps, OVAs, and shorts by rating and saga.">
  <meta property="og:type" content="website">
  <meta name="twitter:card" content="summary_large_image">
  <!-- Generated by scripts/generate.ps1. Do not edit docs/index.html directly. -->
  <title>One Piece Ratings Explorer</title>
  <style>
    :root { color-scheme: dark; --bg:#10131a; --panel:#181c25; --panel2:#202633; --text:#f6f7fb; --muted:#9ca7b8; --line:rgba(255,255,255,.09); --accent:#7dd3fc; }
    * { box-sizing:border-box; }
    body { margin:0; min-height:100vh; background:radial-gradient(circle at top left,rgba(125,211,252,.16),transparent 34rem),linear-gradient(135deg,#0b0e14 0%,var(--bg) 55%,#151827 100%); color:var(--text); font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
    main { width:min(1760px,calc(100% - 36px)); margin:0 auto; padding:16px 0 30px; }
    .layout { display:grid; grid-template-columns:195px 1fr; gap:14px; align-items:start; }
    aside { position:sticky; top:7px; display:grid; gap:5px; max-height:calc(100vh - 14px); }
    .poster { min-height:88px; border-radius:14px; overflow:hidden; background:linear-gradient(155deg,#1d4ed8,#0f172a 52%,#7f1d1d); border:1px solid var(--line); box-shadow:0 14px 34px rgba(0,0,0,.28); padding:9px; display:flex; flex-direction:column; justify-content:flex-end; }
    .poster h1 { margin:0; font-size:1.08rem; line-height:.95; letter-spacing:-.07em; }
    .poster p { margin:4px 0 0; color:#d9e6f3; line-height:1.22; font-size:.62rem; }
    .stat-card,.jump-card,.top5-card { border:1px solid var(--line); border-radius:11px; background:rgba(24,28,37,.82); padding:5px 7px; }
    .stat-card { display:flex; align-items:baseline; justify-content:space-between; gap:7px; }
    .stat-card strong { display:block; font-size:.8rem; letter-spacing:-.04em; } .stat-card span { color:var(--muted); font-size:.58rem; text-align:right; }
    .top5-card h2 { margin:0 0 4px; font-size:.56rem; letter-spacing:.12em; text-transform:uppercase; color:var(--muted); }
    .top5-list { display:grid; gap:2px; }
    .top5-item { display:flex; align-items:center; gap:5px; font-size:.62rem; padding:2px 3px; border-radius:5px; text-decoration:none; color:var(--text); }
    .top5-item:hover { background:rgba(255,255,255,.07); }
    .top5-rank { color:var(--muted); font-size:.52rem; font-weight:700; min-width:12px; text-align:right; }
    .top5-dot { flex:0 0 auto; width:6px; height:6px; border-radius:999px; background:var(--c); box-shadow:0 0 7px var(--c); }
    .top5-code { font-weight:700; min-width:28px; }
    .top5-score { color:var(--muted); font-size:.58rem; margin-left:auto; white-space:nowrap; }
    .jump-card { min-height:0; overflow:hidden; }
    .jump-card h2 { margin:0 0 4px; font-size:.56rem; letter-spacing:.12em; text-transform:uppercase; color:var(--muted); }
    .jump-list { display:grid; gap:2px; max-height:calc(100vh - 310px); overflow:auto; padding-right:2px; scrollbar-width:thin; }
    .jump-fab { display:none; }
    #jump-overlay { display:none; }
    .jump-link { display:flex; align-items:center; justify-content:space-between; gap:7px; border:1px solid transparent; border-radius:7px; color:var(--text); text-decoration:none; padding:3px 5px; background:rgba(255,255,255,.035); font-size:.62rem; }
    .jump-link:hover,.jump-link:focus-visible { border-color:rgba(125,211,252,.38); background:rgba(125,211,252,.12); outline:0; }
    .jump-link span:first-child { display:flex; align-items:center; gap:5px; min-width:0; }
    .jump-link i { flex:0 0 auto; width:7px; height:7px; border-radius:999px; background:var(--jump-color); box-shadow:0 0 9px var(--jump-color); }
    .jump-link b { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-weight:650; }
    .jump-link small { color:var(--muted); font-size:.58rem; white-space:nowrap; }
    .side-note { color:var(--muted); font-size:.58rem; line-height:1.24; margin:0; }
    /* Search tips button + overlay */
    .search-tips-btn { flex:0 0 auto; width:22px; height:22px; border-radius:999px; border:1px solid var(--line); background:rgba(255,255,255,.045); color:var(--muted); font-size:.72rem; font-weight:700; cursor:pointer; display:flex; align-items:center; justify-content:center; line-height:1; padding:0; transition:border-color .15s,color .15s; }
    .search-tips-btn:hover { border-color:rgba(125,211,252,.5); color:var(--accent); }
    #search-tips-overlay { display:none; position:fixed; inset:0; z-index:200; align-items:center; justify-content:center; background:rgba(0,0,0,.55); backdrop-filter:blur(4px); }
    #search-tips-overlay.open { display:flex; }
    #search-tips-panel { background:var(--panel); border:1px solid rgba(255,255,255,.14); border-radius:14px; padding:16px 18px; width:min(420px,calc(100vw - 32px)); max-height:calc(100vh - 48px); overflow-y:auto; box-shadow:0 24px 60px rgba(0,0,0,.6); }
    #search-tips-panel h2 { margin:0 0 12px; font-size:.72rem; letter-spacing:.1em; text-transform:uppercase; color:var(--muted); }
    #search-tips-panel dl { margin:0; display:grid; grid-template-columns:auto 1fr; gap:3px 12px; }
    #search-tips-panel dt { font-family:ui-monospace,monospace; font-size:.72rem; color:var(--accent); white-space:nowrap; padding:2px 0; }
    #search-tips-panel dd { margin:0; font-size:.72rem; color:var(--muted); line-height:1.3; padding:2px 0; }
    #search-tips-panel hr { border:none; border-top:1px solid var(--line); margin:8px 0; }
    #search-tips-panel p { margin:10px 0 0; font-size:.72rem; }
    #search-tips-panel a { color:var(--accent); text-decoration:none; }
    #search-tips-panel a:hover { text-decoration:underline; }
    #search-tips-close { margin-top:14px; display:block; width:100%; padding:6px; border:1px solid var(--line); border-radius:8px; background:rgba(255,255,255,.05); color:var(--text); font:inherit; font-size:.72rem; cursor:pointer; }
    #search-tips-close:hover { background:rgba(255,255,255,.1); }
    .content { min-width:0; }
    .topbar { position:sticky; top:0; z-index:8; display:grid; gap:5px; border:1px solid var(--line); border-radius:12px; background:rgba(24,28,37,.9); backdrop-filter:blur(14px); padding:6px 8px; box-shadow:0 12px 30px rgba(0,0,0,.24); margin-bottom:9px; }
    .controls { display:flex; flex-direction:column; gap:4px; }
    .controls-row { display:flex; flex-wrap:wrap; gap:4px; align-items:center; }
    .control { display:inline-flex; align-items:center; gap:4px; border:1px solid var(--line); border-radius:999px; background:rgba(255,255,255,.045); padding:4px 6px; }
    .control span { color:var(--muted); font-size:.54rem; text-transform:uppercase; letter-spacing:.08em; }
    .multi-filter { position:relative; }
    .filter-toggle { min-width:106px; border:1px solid var(--line); border-radius:999px; background:rgba(255,255,255,.045); color:var(--text); padding:4px 6px; cursor:pointer; font:inherit; font-size:.64rem; display:flex; align-items:center; justify-content:space-between; gap:5px; }
    .filter-toggle b { color:var(--muted); font-size:.52rem; text-transform:uppercase; letter-spacing:.08em; font-weight:800; }
    .filter-toggle .label { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
    .filter-toggle::after { content:"v"; color:var(--muted); font-size:.52rem; }
    .multi-filter.open .filter-toggle { background:rgba(125,211,252,.12); border-color:rgba(125,211,252,.35); }
    .filter-menu { position:absolute; top:calc(100% + 4px); left:0; z-index:30; width:max-content; min-width:170px; max-width:min(260px,calc(100vw - 24px)); max-height:min(210px,calc(100vh - 96px)); overflow:auto; border:1px solid rgba(255,255,255,.14); border-radius:9px; background:rgba(12,15,22,.97); box-shadow:0 14px 36px rgba(0,0,0,.5); padding:4px; display:none; scrollbar-width:thin; }
    .multi-filter.open .filter-menu { display:grid; gap:2px; }
    .filter-option { display:flex; align-items:center; gap:5px; padding:4px 5px; border-radius:6px; color:#d8deea; cursor:pointer; font-size:.64rem; line-height:1.1; }
    .filter-option:hover { background:rgba(125,211,252,.12); }
    .filter-option input { accent-color:#38bdf8; }
    .button { border:1px solid var(--line); border-radius:999px; background:rgba(125,211,252,.08); color:var(--text); padding:4px 6px; cursor:pointer; font:inherit; font-size:.64rem; }
    .button:hover { background:rgba(125,211,252,.16); }
    .button.active { background:rgba(125,211,252,.22); border-color:rgba(125,211,252,.5); color:#7dd3fc; }
    .search-wrap { position:relative; display:inline-flex; align-items:center; }
    .search-wrap svg { position:absolute; left:6px; width:11px; height:11px; color:var(--muted); pointer-events:none; }
    #search { border:1px solid var(--line); border-radius:999px; background:rgba(255,255,255,.045); color:var(--text); padding:4px 6px 4px 20px; font:inherit; font-size:.64rem; width:140px; outline:0; }
    #search:focus { border-color:rgba(125,211,252,.45); background:rgba(125,211,252,.07); }
    #search::placeholder { color:var(--muted); }
    .rating-row { display:flex; align-items:center; gap:7px; flex-wrap:wrap; }
    .rating-row label { color:var(--muted); font-size:.58rem; text-transform:uppercase; letter-spacing:.08em; white-space:nowrap; }
    .sort-filter { position:relative; }
    .sort-filter .filter-toggle { min-width:110px; }
    .sort-filter.open .filter-toggle { background:rgba(125,211,252,.12); border-color:rgba(125,211,252,.35); }
    .sort-filter.open .filter-menu { display:grid; gap:2px; }
    .sort-option { display:flex; align-items:center; padding:5px 7px; border-radius:6px; color:#d8deea; cursor:pointer; font-size:.64rem; line-height:1.1; }
    .sort-option:hover { background:rgba(125,211,252,.12); }
    .sort-option.selected { color:#7dd3fc; font-weight:700; }
    .dim-label { display:inline-flex; align-items:center; gap:4px; cursor:pointer; font-size:.64rem; border:1px solid var(--line); border-radius:999px; padding:4px 6px; background:rgba(255,255,255,.045); white-space:nowrap; user-select:none; }
    .dim-label:hover { background:rgba(125,211,252,.10); }
    .dim-label input { accent-color:#38bdf8; cursor:pointer; }
    .legend { display:flex; flex-wrap:wrap; gap:4px 6px; font-size:.58rem; line-height:1.05; }
    .tier-btn { display:inline-flex; align-items:center; gap:4px; border:1px solid transparent; border-radius:999px; padding:3px 7px; cursor:pointer; font:inherit; font-size:.58rem; background:rgba(255,255,255,.055); color:var(--muted); transition:opacity .12s, border-color .12s, background .12s; }
    .tier-btn .dot { flex-shrink:0; }
    .tier-btn:hover { background:rgba(255,255,255,.10); color:var(--text); }
    .tier-btn.off { opacity:.35; background:rgba(255,255,255,.02); }
    .tier-btn.on { border-color:rgba(255,255,255,.22); color:var(--text); background:rgba(255,255,255,.07); }
    .dot { width:6px; height:6px; border-radius:999px; background:var(--c); box-shadow:0 0 8px var(--c); }
    .status { color:var(--muted); font-size:.62rem; }
    .saga { scroll-margin-top:82px; border:1px solid var(--line); border-radius:16px; background:rgba(24,28,37,.72); overflow:hidden; margin-bottom:12px; box-shadow:0 14px 36px rgba(0,0,0,.22); }
    .saga-header { display:flex; justify-content:space-between; gap:9px; align-items:center; padding:10px 12px; border-bottom:1px solid var(--line); background:linear-gradient(90deg,color-mix(in srgb,var(--saga-color) 18%,transparent),rgba(255,255,255,.025)); }
    .saga-header-left { display:flex; align-items:center; gap:9px; min-width:0; flex:1; }
    .saga-title { display:flex; align-items:center; gap:7px; font-size:.8rem; font-weight:800; white-space:nowrap; }
    .saga-title i { width:9px; height:9px; border-radius:999px; background:var(--saga-color); box-shadow:0 0 12px var(--saga-color); }
    .saga-sparkline { flex:1; min-width:60px; max-width:180px; height:12px; border-radius:3px; overflow:hidden; display:flex; gap:1px; align-items:flex-end; opacity:.82; }
    .saga-sparkline-bar { flex:1; min-width:1px; border-radius:1px; height:100%; }
    .saga-sparkline-bar.bar-dimmed { height:45%; background:#3a3f4a !important; }
    .saga-meta { color:var(--muted); font-size:.68rem; white-space:nowrap; flex-shrink:0; }
    .sub-saga { padding:9px 12px 11px; border-bottom:1px solid rgba(255,255,255,.055); scroll-margin-top:82px; }
    .sub-saga:last-child { border-bottom:0; }
    .sub-head { display:flex; justify-content:space-between; gap:9px; align-items:baseline; margin-bottom:6px; }
    .sub-title { display:flex; align-items:center; gap:6px; }
    .sub-title i { width:7px; height:7px; border-radius:999px; background:var(--sub-saga-color); box-shadow:0 0 10px var(--sub-saga-color); }
    .sub-head h3 { margin:0; font-size:.72rem; } .sub-head span { color:var(--muted); font-size:.62rem; }
    .episode-grid { display:grid; grid-template-columns:repeat(auto-fill,48px); gap:2px; }
    .tile { position:relative; width:48px; height:29px; border:0; border-radius:0; background:transparent; cursor:pointer; overflow:hidden; color:var(--text-color); font:inherit; padding:0; box-shadow:none; transition:transform .13s ease, filter .13s ease, opacity .13s ease; }
    .tile:hover,.tile:focus-visible { transform:translateY(-1px); filter:saturate(1.08) brightness(1.03); outline:2px solid rgba(255,255,255,.32); z-index:2; }
    .tile.dimmed { background:#1e2128; color:#5a6070; opacity:.28; filter:grayscale(1) saturate(0) brightness(.6); box-shadow:none; }
    .tile.dimmed::after { background:#6b7280; }
    .tile.dimmed .epno { color:rgba(255,255,255,.28); }
    .tile.dimmed .score { color:#9aa3b5; text-shadow:none; }
    .tile::after { display:none; }
    .tile-svg { display:block; width:100%; height:100%; }
    .tile-rect { fill:var(--rating-color); }
    .score { fill:var(--text-color); stroke:var(--text-stroke-color); stroke-width:1.15px; paint-order:stroke fill; font-family:var(--font-ui); font-size:17.3px; font-weight:700; opacity:.96; text-anchor:start; dominant-baseline:middle; }
    .epno { fill:var(--episode-text-color); stroke:var(--text-stroke-color); stroke-width:.65px; paint-order:stroke fill; font-family:var(--font-ui); font-size:9.7px; font-weight:700; opacity:.9; text-anchor:start; dominant-baseline:middle; }
    .tooltip { position:fixed; max-width:310px; pointer-events:none; border:1px solid rgba(255,255,255,.14); border-radius:11px; background:rgba(10,13,19,.94); padding:9px 10px; box-shadow:0 14px 38px rgba(0,0,0,.45); opacity:0; transition:opacity 120ms ease; z-index:20; }
    .tooltip.visible { opacity:1; } .tooltip.pointer-on { pointer-events:auto; } .tooltip.touch-active { pointer-events:auto; } .tooltip strong { display:block; margin-bottom:4px; font-size:.78rem; } .tooltip span { color:var(--muted); font-size:.66rem; line-height:1.32; }
    .tooltip-actions { display:flex; flex-wrap:wrap; align-items:center; gap:6px; margin-top:6px; }
    .tooltip-source-link { display:inline-block; margin-top:6px; padding:4px 10px; border-radius:6px; background:rgba(125,211,252,.15); border:1px solid rgba(125,211,252,.35); color:#7dd3fc; font-size:.68rem; text-decoration:none; cursor:pointer; }
    .tooltip-actions .tooltip-source-link { margin-top:0; }
    .tooltip-source-link:hover { background:rgba(125,211,252,.28); }
    .tooltip-tag-btn { width:25px; height:25px; border-radius:6px; border:1px solid rgba(255,255,255,.18); background:rgba(255,255,255,.06); color:var(--accent); font-size:.78rem; font-weight:800; cursor:pointer; }
    .tooltip-tag-btn:hover,.tooltip-tag-btn[aria-expanded="true"] { background:rgba(125,211,252,.18); border-color:rgba(125,211,252,.45); }
    .tooltip-tags { display:none; flex-basis:100%; gap:4px; flex-wrap:wrap; padding-top:2px; }
    .tooltip-tags.visible { display:flex; }
    .tooltip-tag-chip { border:1px solid rgba(255,255,255,.13); border-radius:999px; padding:2px 6px; background:rgba(255,255,255,.055); color:#d6deea; font-size:.58rem; line-height:1.2; }
    .tag-filter { position:relative; }
    .tag-filter-panel { display:none; position:absolute; top:calc(100% + 6px); right:0; width:min(520px,92vw); max-height:min(620px,70vh); overflow:auto; border:1px solid rgba(255,255,255,.14); border-radius:12px; background:rgba(10,13,19,.98); box-shadow:0 18px 44px rgba(0,0,0,.48); padding:10px; z-index:30; }
    .tag-filter.open .tag-filter-panel { display:block; }
    .tag-filter-section + .tag-filter-section { margin-top:10px; padding-top:8px; border-top:1px solid rgba(255,255,255,.08); }
    .tag-filter-section h3 { margin:0 0 6px; color:var(--muted); font-size:.64rem; letter-spacing:.06em; text-transform:uppercase; }
    .tag-filter-tags { display:flex; flex-wrap:wrap; gap:5px; }
    .tag-filter-chip { display:inline-flex; align-items:center; gap:3px; border:1px solid rgba(255,255,255,.12); border-radius:999px; background:rgba(255,255,255,.045); padding:3px 4px 3px 7px; color:#d6deea; font-size:.62rem; }
    .tag-filter-chip b { font-weight:700; }
    .tag-tree-header { display:flex; align-items:center; gap:8px; margin-bottom:8px; }
    .tag-tree-back { border:1px solid rgba(255,255,255,.14); border-radius:999px; background:rgba(255,255,255,.05); color:var(--text); cursor:pointer; font:inherit; font-size:.62rem; padding:3px 8px; }
    .tag-tree-title { color:var(--muted); font-size:.66rem; font-weight:800; letter-spacing:.06em; text-transform:uppercase; }
    .tag-tree-list { display:grid; gap:6px; }
    .tag-tree-node { display:flex; align-items:center; justify-content:space-between; gap:6px; width:100%; border:1px solid rgba(255,255,255,.12); border-radius:10px; background:rgba(255,255,255,.045); color:#d6deea; font-size:.68rem; padding:4px 5px 4px 9px; text-align:left; }
    .tag-tree-node:hover { background:rgba(125,211,252,.12); border-color:rgba(125,211,252,.32); }
    .tag-tree-node-main { flex:1; border:0; background:none; color:inherit; cursor:pointer; font:inherit; padding:3px 0; text-align:left; }
    .tag-tree-node-main::after { content:">"; color:var(--muted); font-size:.72rem; margin-left:6px; }
    .tag-tree-node-actions { display:flex; gap:3px; }
    .tag-tree-leaf { border-radius:10px; justify-content:space-between; padding:6px 6px 6px 9px; }
    .tag-tree-leaf b { flex:1; }
    .tag-tree-leaf small { color:var(--muted); font-size:.58rem; margin-right:4px; }
    .tag-op { width:19px; height:19px; border:1px solid rgba(125,211,252,.28); border-radius:999px; background:rgba(125,211,252,.08); color:#7dd3fc; cursor:pointer; font:700 .66rem var(--font-ui); line-height:1; }
    .tag-op:hover { background:rgba(125,211,252,.22); }
    .character-mode-label { display:inline-flex; align-items:center; gap:5px; border:1px solid var(--line); border-radius:999px; background:rgba(255,255,255,.045); color:var(--muted); padding:4px 7px; font-size:.62rem; white-space:nowrap; }
    .character-mode-label select { border:0; border-radius:999px; background:rgba(125,211,252,.12); color:#d6deea; font:700 .62rem var(--font-ui); padding:2px 5px; outline:none; }
    .empty { border:1px dashed var(--line); border-radius:14px; color:var(--muted); padding:18px; text-align:center; background:rgba(255,255,255,.025); }
    .jump-fab { display:none; position:fixed; bottom:18px; right:18px; z-index:50; width:46px; height:46px; border-radius:999px; border:1px solid rgba(125,211,252,.35); background:rgba(12,15,22,.95); backdrop-filter:blur(12px); color:#7dd3fc; font-size:1.1rem; cursor:pointer; box-shadow:0 6px 24px rgba(0,0,0,.5); transition:opacity .2s; }
    .jump-fab:hover { background:rgba(30,40,60,.98); }
    .jump-fab.fab-visible { display:flex; align-items:center; justify-content:center; }
    #jump-overlay { display:none; position:fixed; inset:0; z-index:49; background:rgba(10,13,19,.96); backdrop-filter:blur(8px); padding:16px; flex-direction:column; gap:10px; touch-action:none; overflow:hidden; }
    #jump-overlay.open { display:flex; }
    body.overlay-open { overflow:hidden; position:fixed; width:100%; }
    #jump-overlay-header { display:flex; align-items:center; justify-content:space-between; }
    #jump-overlay-header h2 { margin:0; font-size:.9rem; }
    #jump-overlay-close { background:none; border:1px solid var(--line); border-radius:999px; color:var(--text); padding:5px 12px; cursor:pointer; font:inherit; font-size:.72rem; }
    #jump-overlay-grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(140px,1fr)); gap:6px; }
    .overlay-jump-link { display:flex; align-items:center; gap:8px; border:1px solid var(--line); border-radius:10px; color:var(--text); text-decoration:none; padding:9px 10px; background:rgba(255,255,255,.04); font-size:.72rem; }
    .overlay-jump-link:hover { background:rgba(125,211,252,.12); border-color:rgba(125,211,252,.38); }
    .overlay-jump-link i { flex:0 0 auto; width:9px; height:9px; border-radius:999px; background:var(--jump-color); box-shadow:0 0 10px var(--jump-color); }
    .overlay-jump-link b { font-weight:700; }
    .overlay-jump-link small { color:var(--muted); font-size:.64rem; margin-left:auto; white-space:nowrap; }
    /* Topbar jump bar */
    #topbar-jump { display:flex; flex-wrap:wrap; gap:4px; padding:5px 0 2px; }
    #topbar-jump a { display:inline-flex; align-items:center; gap:5px; border:1px solid var(--line); border-radius:999px; color:var(--text); text-decoration:none; padding:3px 8px; font-size:.6rem; background:rgba(255,255,255,.04); white-space:nowrap; }
    #topbar-jump a:hover { background:rgba(125,211,252,.12); border-color:rgba(125,211,252,.38); }
    #topbar-jump a i { flex:0 0 auto; width:7px; height:7px; border-radius:999px; background:var(--jump-color); }
    /* Overlay body layout */
    #jump-overlay-body { display:flex; flex-direction:column; gap:12px; overflow:auto; flex:1; }
    .overlay-filter-row { display:flex; flex-wrap:wrap; gap:6px; align-items:center; }
    .overlay-tier-row { display:flex; flex-wrap:wrap; gap:5px; }
    .overlay-section-title { margin:4px 0 2px; font-size:.72rem; color:var(--muted); text-transform:uppercase; letter-spacing:.06em; }
    /* In overlay the multi-filter dropdowns open upward and are clipped by the overlay scroll */
    #jump-overlay .multi-filter .filter-menu, #jump-overlay .sort-filter .filter-menu { max-height:200px; }
    @media (min-width:901px) { main { width:min(1760px,calc(100% - 108px)); } #topbar-jump { display:none; } }
    @media (max-width:900px) { .layout { grid-template-columns:1fr; } aside { position:static; grid-template-columns:1fr 1fr; max-height:none; } .poster { min-height:90px; } .jump-card { display:none; } .saga { scroll-margin-top:14px; } }
    @media (max-width:640px) { main { width:min(100% - 20px,1760px); padding-top:12px; } aside { grid-template-columns:1fr; } .topbar { position:static; } .episode-grid { grid-template-columns:repeat(auto-fill,48px); } .saga-header,.sub-head { display:grid; } .saga-sparkline { max-width:100%; } }
  </style>
</head>
<body>
  <main>
    <div class="layout">
      <aside>
        <section class="poster"><h1>One Piece Ratings</h1><p>Grouped by saga and sub-saga. Filter without covering the chart.</p></section>
        <section class="stat-card"><strong id="count">--</strong><span>shown entries</span></section>
        <section class="stat-card"><strong id="average">--</strong><span>average rating</span></section>
        <section class="top5-card"><h2>Top episodes</h2><div id="top5-list" class="top5-list"></div></section>
        <nav class="jump-card" aria-label="Jump to saga"><h2>Jump to saga</h2><div id="saga-jump-list" class="jump-list"></div></nav>
        <p class="side-note">TV ratings use a Series Graph / IMDb snapshot. Movies, specials, OVAs, and shorts use MyAnimeList scores via Jikan, so compare across source types cautiously.</p>
      </aside>
      <section class="content">
        <div class="topbar">
          <div class="controls">
            <div class="controls-row">
              <div class="multi-filter" id="type-filter"><button class="filter-toggle" type="button"><b>Type</b><span class="label">All types</span></button><div class="filter-menu"></div></div>
              <div class="multi-filter" id="saga-filter"><button class="filter-toggle" type="button"><b>Saga</b><span class="label">All sagas</span></button><div class="filter-menu"></div></div>
              <div class="multi-filter" id="sub-saga-filter"><button class="filter-toggle" type="button"><b>Sub-saga</b><span class="label">All sub-sagas</span></button><div class="filter-menu"></div></div>
              <button class="button" id="reset" type="button">Reset all</button>
              <button class="button" id="filler-only" type="button">Filler only</button>
              <button class="button" id="canon-only" type="button" title="Manga, mixed, and anime-original TV episodes; excludes filler and non-TV media.">Non-filler TV</button>
              <button class="button" id="episodes-only" type="button">Episodes only</button>
              <button class="button" id="media-only" type="button">Media only</button>
              <div class="tag-filter" id="tag-filter"><button class="button" id="tag-filter-toggle" type="button" title="Add search tags with AND, OR, or exclusion">Tags</button><div class="tag-filter-panel" id="tag-filter-panel"></div></div>
              <label class="character-mode-label" id="character-mode-control" title="Choose whether character tags match any real appearance or only focused episodes">Characters <select id="character-mode"><option value="appears">Appears</option><option value="focused">Focused</option></select></label>
            </div>
            <div class="controls-row" id="tier-legend" aria-label="Rating tier filter">
              <div class="search-wrap"><svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2"><circle cx="9" cy="9" r="6"/><path d="m15 15 3 3"/></svg><input id="search" type="search" placeholder="Search titles..." autocomplete="off"></div>
              <button class="search-tips-btn" id="search-tips-btn" type="button" title="Search syntax help" aria-haspopup="dialog">?</button>
              <label class="dim-label" title="Keep non-matching tiles visible but grayed out"><input type="checkbox" id="dim-toggle" checked> Dim</label>
              <div class="sort-filter" id="sort-filter"><button class="filter-toggle" type="button"><b>Sort</b><span class="label" id="sort-label">Watch order</span></button><div class="filter-menu sort-menu"></div></div>
              <button class="tier-btn on" type="button" data-tier="cinema" style="--c:#1DA1F2"><i class="dot" style="--c:#1DA1F2"></i>Absolute Cinema 9.6+</button>
              <button class="tier-btn on" type="button" data-tier="awesome" style="--c:#186A3B"><i class="dot" style="--c:#186A3B"></i>Awesome 8.6&ndash;9.5</button>
              <button class="tier-btn on" type="button" data-tier="great" style="--c:#28B463"><i class="dot" style="--c:#28B463"></i>Great 8.0&ndash;8.5</button>
              <button class="tier-btn on" type="button" data-tier="good" style="--c:#F4D03F"><i class="dot" style="--c:#F4D03F"></i>Good 7.0&ndash;7.9</button>
              <button class="tier-btn on" type="button" data-tier="regular" style="--c:#F39C12"><i class="dot" style="--c:#F39C12"></i>Regular 6.0&ndash;6.9</button>
              <button class="tier-btn on" type="button" data-tier="bad" style="--c:#E74C3C"><i class="dot" style="--c:#E74C3C"></i>Bad 5.0&ndash;5.9</button>
              <button class="tier-btn on" type="button" data-tier="garbage" style="--c:#633974"><i class="dot" style="--c:#633974"></i>Garbage &lt;5.0</button>
            </div>
          </div>
          <div id="status" class="status" hidden></div>
          <nav id="topbar-jump" aria-label="Jump to saga"></nav>
        </div>
        <div id="saga-output"></div>
      </section>
    </div>
  </main>
  <button class="jump-fab" id="jump-fab" aria-label="Open filters and navigation" title="Filters &amp; navigation">&#9776;</button>
  <div id="jump-overlay" role="dialog" aria-modal="true" aria-label="Filters and navigation">
    <div id="jump-overlay-header"><h2>Filters &amp; Navigation</h2><button id="jump-overlay-close" type="button">Close</button></div>
    <div id="jump-overlay-body">
      <div id="jump-overlay-filters">
        <div class="overlay-filter-row" id="overlay-row1"></div>
        <div class="overlay-filter-row" id="overlay-row2"></div>
        <div class="overlay-tier-row" id="overlay-tier-row"></div>
      </div>
      <h3 class="overlay-section-title">Jump to saga</h3>
      <div id="jump-overlay-grid"></div>
    </div>
  </div>
  <div id="tooltip" class="tooltip" role="status" aria-live="polite"></div>
  <div id="search-tips-overlay" role="dialog" aria-modal="true" aria-label="Search syntax help">
    <div id="search-tips-panel">
      <h2>Search tips</h2>
      <dl>
        <dt>ace</dt>              <dd>prefix match - finds words <em>starting</em> with "ace"</dd>
        <dt>ace &lt;Enter&gt;</dt><dd>exact whole-word match only</dd>
        <dt>a+b</dt>              <dd>AND - both terms must match</dd>
        <dt>a or b</dt>           <dd>OR - either term matches (also: a|b)</dd>
        <dt>-nami</dt>            <dd>exclude episodes mentioning Nami</dd>
        <dt>-(nami,usopp)</dt>    <dd>exclude multiple terms at once</dd>
        <dt>whitebeard pirates + -luffy</dt><dd>faction search, excluding Luffy mentions</dd>
        <dt>whitebeard pirates + -(luffy,ace)</dt><dd>faction search with grouped exclusions</dd>
        <dt>400-500</dt>          <dd>episode number range filter</dd>
      </dl>
      <hr>
      <dl>
        <dt>wano</dt>             <dd>shows only Wano episodes</dd>
        <dt>-wano</dt>            <dd>excludes all Wano episodes</dd>
        <dt>alabasta</dt>         <dd>also accepts: arabasta, skypiea, marineford...</dd>
        <dt>canon</dt>            <dd>manga / mixed / anime canon only</dd>
        <dt>filler</dt>           <dd>filler episodes only</dd>
        <dt>non-canon</dt>        <dd>filler + OVA + movie + special + recap</dd>
        <dt>ova / movie</dt>      <dd>filter by media type</dd>
      </dl>
      <hr>
      <dl>
        <dt>flashback</dt>        <dd>major past-era flashback episodes</dd>
        <dt>backstory</dt>        <dd>character origin / backstory episodes</dd>
        <dt>debut</dt>            <dd>Straw Hat crew first appearances</dd>
        <dt>recap</dt>            <dd>recap / clip-show episodes</dd>
        <dt>death</dt>            <dd>expands to: die, died, killed, sacrifice, executed...</dd>
      </dl>
      <hr>
      <dl>
        <dt>faction</dt>          <dd>Find episodes focusing on groups/characters:</dd>
        <dt></dt>                 <dd><em>Yonko:</em> whitebeard, shanks, blackbeard, big mom, kaido</dd>
        <dt></dt>                 <dd><em>Crews:</em> heart pirates, kid pirates, donquixote, roger...</dd>
        <dt></dt>                 <dd><em>Marines:</em> admirals, cp9, cp0, akainu, aokiji...</dd>
        <dt></dt>                 <dd><em>Warlords:</em> shichibukai, crocodile, doflamingo, law...</dd>
        <dt></dt>                 <dd><em>Other:</em> supernovas, minks, celestial dragons, wano samurai</dd>
      </dl>
      <p><a href="https://github.com/victormends/one-piece-ratings-timeline#search-guide" target="_blank" rel="noopener">For full search details and examples</a></p>
      <button id="search-tips-close" type="button">Close</button>
    </div>
  </div>
  <script id="episode-data" type="application/json">__EPISODES_JSON__</script>
  <script id="category-summary" type="application/json">__CATEGORY_SUMMARY_JSON__</script>
  <script id="saga-data" type="application/json">__SAGAS_JSON__</script>
  <script id="sub-saga-data" type="application/json">__SUB_SAGAS_JSON__</script>
  <script id="appearance-audits" type="application/json">__APPEARANCE_AUDITS_JSON__</script>
  <script id="saga-summary" type="application/json">__SAGA_SUMMARY_JSON__</script>
  <script id="sub-saga-summary" type="application/json">__SUB_SAGA_SUMMARY_JSON__</script>
  <script>
    const CATEGORY_META = { manga:{label:"Manga Canon",color:"#22c55e"}, mixed:{label:"Mixed Canon/Filler",color:"#f59e0b"}, filler:{label:"Filler",color:"#ef4444"}, anime:{label:"Anime Canon",color:"#38bdf8"}, movie:{label:"Movie",color:"#a855f7"}, special:{label:"TV Special",color:"#06b6d4"}, recap:{label:"Recap / Remake",color:"#f97316"}, ova:{label:"OVA",color:"#ec4899"}, short:{label:"Short",color:"#84cc16"} };

    // i18n
    const LANG = navigator.language.toLowerCase().startsWith("pt") ? "pt" : "en";
    const I18N = {
      en: {
        siteTitle: "One Piece Ratings", siteDesc: "Grouped by saga and sub-saga. Filter without covering the chart.",
        shownEntries: "shown entries", averageRating: "average rating", topEpisodes: "Top episodes",
        jumpToSaga: "Jump to saga", sideNote: "TV ratings use a Series Graph / IMDb snapshot. Movies, specials, OVAs, and shorts use MyAnimeList scores via Jikan, so compare across source types cautiously.",
        labelType: "Type", labelSaga: "Saga", labelSubSaga: "Sub-saga",
        allTypes: "All types", allSagas: "All sagas", allSubSagas: "All sub-sagas",
        resetAll: "Reset all", fillerOnly: "Filler only", nonFillerTV: "Non-filler TV",
        nonFillerTVTitle: "Manga, mixed, and anime-original TV episodes; excludes filler and non-TV media.",
        episodesOnly: "Episodes only", mediaOnly: "Media only",
        searchPlaceholder: "Search titles...", dimLabel: "Dim",
        dimLabelTitle: "Keep non-matching tiles visible but grayed out",
        labelSort: "Sort", sortWatchOrder: "Watch order",
        sortRatingDesc: "Rating \u2193", sortRatingAsc: "Rating \u2191",
        tierCinema: "Absolute Cinema 9.6+", tierAwesome: "Awesome 8.6\u20139.5",
        tierGreat: "Great 8.0\u20138.5", tierGood: "Good 7.0\u20137.9",
        tierRegular: "Regular 6.0\u20136.9", tierBad: "Bad 5.0\u20135.9", tierGarbage: "Garbage <5.0",
        filtersNav: "Filters & Navigation", closeBtn: "Close",
        openIMDb: "See on IMDb", openMAL: "See on MyAnimeList",
        synopsis: "Synopsis", rating: "Rating", aired: "Aired/released",
        translating: "Translating...", noTranslation: "(translation unavailable)",
      },
      pt: {
        siteTitle: "One Piece Ratings", siteDesc: "Agrupado por saga e sub-saga. Filtre sem esconder o gr\u00e1fico.",
        shownEntries: "epis\u00f3dios exibidos", averageRating: "m\u00e9dia das notas", topEpisodes: "Top epis\u00f3dios",
        jumpToSaga: "Ir para saga", sideNote: "Notas de epis\u00f3dios de TV v\u00eam do IMDb (Series Graph). Filmes, especiais, OVAs e curtas usam notas do MyAnimeList via Jikan. Compare com cuidado entre fontes diferentes.",
        labelType: "Tipo", labelSaga: "Saga", labelSubSaga: "Sub-saga",
        allTypes: "Todos os tipos", allSagas: "Todas as sagas", allSubSagas: "Todas as sub-sagas",
        resetAll: "Resetar tudo", fillerOnly: "S\u00f3 filler", nonFillerTV: "TV sem filler",
        nonFillerTVTitle: "Epis\u00f3dios de TV manga, misto e anime-original; exclui filler e m\u00eddia n\u00e3o-TV.",
        episodesOnly: "S\u00f3 epis\u00f3dios", mediaOnly: "S\u00f3 m\u00eddia",
        searchPlaceholder: "Buscar t\u00edtulos...", dimLabel: "Esc.",
        dimLabelTitle: "Manter tiles sem correspond\u00eancia vis\u00edveis, por\u00e9m esmaecidos",
        labelSort: "Ordem", sortWatchOrder: "Ordem de exibi\u00e7\u00e3o",
        sortRatingDesc: "Nota \u2193", sortRatingAsc: "Nota \u2191",
        tierCinema: "Cinema Absoluto 9,6+", tierAwesome: "Incr\u00edvel 8,6\u20139,5",
        tierGreat: "\u00d3timo 8,0\u20138,5", tierGood: "Bom 7,0\u20137,9",
        tierRegular: "Regular 6,0\u20136,9", tierBad: "Ruim 5,0\u20135,9", tierGarbage: "P\u00e9ssimo <5,0",
        filtersNav: "Filtros & Navega\u00e7\u00e3o", closeBtn: "Fechar",
        openIMDb: "Ver no IMDb", openMAL: "Ver no MyAnimeList",
        synopsis: "Sinopse", rating: "Nota", aired: "Exibido/lan\u00e7ado",
        translating: "Traduzindo...", noTranslation: "(tradu\u00e7\u00e3o indispon\u00edvel)",
      }
    };
    const T = I18N[LANG];

    function applyI18n() {
      document.querySelector("h1") && (document.querySelector("h1").textContent = T.siteTitle);
      const siteDescEl = document.querySelector(".poster p");
      if (siteDescEl) siteDescEl.textContent = T.siteDesc;
      document.querySelectorAll(".stat-card span").forEach((el, i) => {
        if (i === 0) el.textContent = T.shownEntries;
        if (i === 1) el.textContent = T.averageRating;
      });
      const top5h = document.querySelector(".top5-card h2");
      if (top5h) top5h.textContent = T.topEpisodes;
      document.querySelectorAll(".jump-card h2, nav[aria-label='Jump to saga'] h2").forEach(h => h.textContent = T.jumpToSaga);
      const sideNote = document.querySelector(".side-note");
      if (sideNote) sideNote.textContent = T.sideNote;
      ["#type-filter","#saga-filter","#sub-saga-filter","#sort-filter"].forEach((sel, i) => {
        const b = document.querySelector(sel + " .filter-toggle b");
        if (b) b.textContent = [T.labelType,T.labelSaga,T.labelSubSaga,T.labelSort][i];
      });
      const btns = {"#reset":T.resetAll,"#filler-only":T.fillerOnly,"#episodes-only":T.episodesOnly,"#media-only":T.mediaOnly};
      Object.entries(btns).forEach(([sel,txt]) => { const el=document.querySelector(sel); if(el) el.textContent=txt; });
      const canonBtn = document.querySelector("#canon-only");
      if (canonBtn) { canonBtn.textContent = T.nonFillerTV; canonBtn.title = T.nonFillerTVTitle; }
      const searchInput = document.querySelector("#search");
      if (searchInput) searchInput.placeholder = T.searchPlaceholder;
      const dimLabelEl = document.querySelector(".dim-label");
      if (dimLabelEl) { dimLabelEl.title = T.dimLabelTitle; dimLabelEl.childNodes[dimLabelEl.childNodes.length-1].textContent = " " + T.dimLabel; }
      const tierLabels=["cinema","awesome","great","good","regular","bad","garbage"];
      const tierKeys=["tierCinema","tierAwesome","tierGreat","tierGood","tierRegular","tierBad","tierGarbage"];
      tierLabels.forEach((t,i) => {
        const btn=document.querySelector(`.tier-btn[data-tier="${t}"]`);
        if(btn){const dot=btn.querySelector("i");btn.textContent=T[tierKeys[i]];if(dot)btn.prepend(dot);}
      });
      const overlayH2=document.querySelector("#jump-overlay-header h2");
      if(overlayH2)overlayH2.textContent=T.filtersNav;
      const closeBtn=document.querySelector("#jump-overlay-close");
      if(closeBtn)closeBtn.textContent=T.closeBtn;
      const jumpOverlayTitle=document.querySelector(".overlay-section-title");
      if(jumpOverlayTitle)jumpOverlayTitle.textContent=T.jumpToSaga;
    }
    const episodes = JSON.parse(document.querySelector("#episode-data").textContent);
    // Clean up Jikan/IMDb fallback text: "Title belongs to X in the Final Saga timeline."
    const BELONGS_RE = /\s+belongs to .+ in the .+ timeline\.?\s*$/i;
    episodes.forEach(ep => { if (ep.originalNote) { const cleaned = ep.originalNote.replace(BELONGS_RE, "").trim(); ep.originalNote = cleaned || null; } });

    // Invisible tag system
    // Tags applied to episodes by number. Multiple tags per episode allowed.
    // Searchable via keywords; never displayed directly.
    const EP_TAGS = {
      // flashback: episodes whose core content is a past-era flashback
      flashback: new Set([
        4, 36, 41, 100, 135, 187, 426, 460, 461, 466,
        275, 276, 277, 278, 312, 379, 380,
        493, 494, 495, 496,
        540, 541, 612, 639, 651,
        702, 703, 705, 836,
        960, 961, 962, 963, 964, 965, 966, 967, 968, 969,
        970, 971, 972, 973, 974,
        1129, 1130
      ]),
      // backstory: character-focused origin/past episodes (subset of flashback)
      backstory: new Set([
        36, 41,           // Nami's past (Arlong Park)
        135,              // Zoro's past (wandering swordsman)
        187,              // Noland & Calgara legend
        275, 276, 277, 278, // Robin's past (Ohara / Akainu flashback)
        379, 380,         // Brook's past
        493, 494, 495, 496, // Luffy, Ace, Sabo childhood
        540, 541,         // Fisher Tiger / Fish-Man Island past
        651,              // Rebecca & Toy Soldier
        702, 703, 705,    // Law & Corazon
        836,              // Big Mom's past
        960, 961, 962, 963, 964, 965, 966, 967, 968, 969,
        970, 971, 972, 973, 974, // Oden's life
        1129, 1130        // Kuma's past / God Valley
      ]),
      // first-appearance: episodes introducing a major Straw Hat crew member
      "first-appearance": new Set([
        1,    // Luffy
        2,    // Zoro (properly joins)
        8,    // Nami (joins crew)
        9,    // Usopp (joins crew)
        20,   // Sanji (joins crew)
        67,   // Chopper (joins crew)
        130,  // Robin (joins crew)
        229,  // Franky (introduced)
        230,  // Rob Lucci (Galley-La debut)
        253,  // Franky (joins crew)
        337,  // Brook (introduced)
        381,  // Brook (joins crew)
        278   // Akainu / Sakazuki (Ohara flashback)
      ]),
      // recap: episodes that are primarily recap/clip shows
      recap: new Set([]) // populated from category below
    };
    // Auto-tag recap episodes from category field
    episodes.forEach(ep => { if (ep.category === "recap" || ep.mediaKind === "recap") EP_TAGS.recap.add(ep.episode); });

    // Faction tag system
    // Helper: build a Set from a mix of numbers and [start,end] range pairs
    function makeTagSet(...items) {
      const s = new Set();
      for (const x of items) {
        if (Array.isArray(x)) { for (let i = x[0]; i <= x[1]; i++) s.add(i); }
        else s.add(x);
      }
      return s;
    }
    // Faction tags - episode number sets for each named group
    const FACTION_TAGS = {
      // Yonko / Emperors
      "shanks":           makeTagSet(1,2,3,4,314,315,438,439,489,490,516,597,907,1073,[1086,1090],[1116,1120]),
      "whitebeard":       makeTagSet([453,516],[960,968],151,234,312,316,437,438,439),
      "big-mom":          makeTagSet([783,877],651,652,[999,1031],[1056,1068],[866,868]),
      "kaido":            makeTagSet([890,1085],726,727,728,742,743,777,778),
      "blackbeard":       makeTagSet(222,225,304,306,378,381,[441,452],[453,516],[517,520],579,594,762,925,951,952,956,[1086,1088]),
      // Pirate Crews
      "whitebeard-pirates": makeTagSet([453,516],[960,968],151,234,312,316,437,[438,442]),
      "red-hair-pirates": makeTagSet(1,2,3,4,314,315,438,439,489,490,516,597,907,1073,[1086,1090],[1116,1120]),
      "blackbeard-pirates": makeTagSet(222,225,304,306,378,381,[441,452],[453,516],[517,520],579,594,762,925,951,952,956,[1086,1088]),
      "big-mom-pirates":  makeTagSet([783,877],651,652,[999,1031],[1056,1068]),
      "beast-pirates":    makeTagSet([890,1085],726,727,728,742,743,777,778),
      "heart-pirates":    makeTagSet([629,699],[700,732],[392,405],501,502,503,[523,526],[780,782],[909,913],[999,1031],[1056,1068]),
      "kid-pirates":      makeTagSet([392,405],[517,522],579,[780,782],[955,958],[999,1031],[1035,1075]),
      "buggy-pirates":    makeTagSet([4,8],[46,53],75,77,[443,449],[516,523],[591,594],[780,781],879,880,956),
      "baroque-works":    makeTagSet([62,135],[155,159],213,214,[441,449]),
      "donquixote-pirates": makeTagSet([629,699],[700,780],151,152,153,223,224,225,511,512,513,514,578,579,580),
      "sun-pirates":      makeTagSet([31,45],[521,526],[540,544],[575,628]),
      "roger-pirates":    makeTagSet([959,968],314,315,400,880,907,956,[1090,1093]),
      "revolutionary-army": makeTagSet(52,53,100,314,315,516,[552,559],579,596,630,[737,762],[878,908],[1086,1090]),
      // Marines / World Government
      "marines":          makeTagSet([48,53],[224,228],[264,312],[385,405],[406,452],[453,516],[629,640],[878,908],[1086,1105]),
      "cipher-pol":       makeTagSet([228,325],[756,762],[878,889],[1054,1105]),
      "cp9":              makeTagSet([228,325]),
      "cp0":              makeTagSet([756,762],[878,889],[1054,1085],[1086,1105]),
      "celestial-dragons": makeTagSet([385,405],516,[556,559],[629,630],[702,703],[756,762],[878,908],[1086,1110]),
      // Admirals
      "akainu":           makeTagSet(278,[453,516],881,956),
      "aokiji":           makeTagSet([225,228],278,[453,476],625),
      "kizaru":           makeTagSet([398,405],[453,476],[1086,1105]),
      "fujitora":         makeTagSet([700,801],[878,888]),
      "ryokugyu":         makeTagSet([1073,1086]),
      // Warlords / Shichibukai
      "shichibukai":      makeTagSet(151,152,153,[223,228],[233,235],[316,318],[382,384],[392,421],[441,516],[878,889]),
      "crocodile":        makeTagSet([62,135],[155,159],213,214,[441,449],[453,512]),
      "doflamingo":       makeTagSet(151,152,153,[223,228],[511,514],[578,580],[629,640],[700,780]),
      "jinbe":            makeTagSet([430,452],[453,516],[521,526],[540,544],[575,628],[840,877]),
      "hancock":          makeTagSet([408,421],[453,516],[516,524],746,747,879,880),
      "moriah":           makeTagSet([326,384],[463,476]),
      "mihawk":           makeTagSet(24,25,26,50,51,[223,228],[385,386],[453,516],[524,526],[557,559],878,879,956),
      "kuma":             makeTagSet([233,235],[316,318],[382,384],[399,405],[484,500],[516,526],[557,559],[878,888],[1086,1105]),
      "law":              makeTagSet([392,405],[501,503],[516,526],[629,699],[700,732],[780,782],[909,913],[999,1031],[1056,1068]),
      // Other Groups
      "supernovas":       makeTagSet([385,405],[517,526],579,[780,782],[955,958],[975,985],[999,1031],[1035,1075]),
      "impel-down":       makeTagSet([422,452]),
      "minks":            makeTagSet([751,779],[975,985],[986,995],[1009,1020]),
      "wano-samurai":     makeTagSet([739,747],[892,900],[909,974],[975,1085]),
    };
    // Merge faction tags into EP_TAGS so matchesTerm can find them
    for (const [key, set] of Object.entries(FACTION_TAGS)) EP_TAGS[key] = set;

    // Research tags are derived from the local title/synopsis text, then refined
    // with manual anchors for concepts the summaries rarely spell out directly.
    function ensureTagSet(tag) {
      if (!EP_TAGS[tag]) EP_TAGS[tag] = new Set();
      return EP_TAGS[tag];
    }
    function addTagItems(tag, ...items) {
      const set = ensureTagSet(tag);
      for (const item of items) {
        if (Array.isArray(item)) { for (let i = item[0]; i <= item[1]; i++) set.add(i); }
        else set.add(item);
      }
    }
    function aliasToRegex(alias) {
      const source = alias
        .toLowerCase()
        .replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
        .replace(/[\s_-]+/g, "[\\s_-]+");
      return new RegExp("(^|[^a-z0-9])" + source + "(?=[^a-z0-9]|$)", "i");
    }
    const AUTO_TAG_RULES = {
      // Powers / combat systems
      "devil-fruit": ["devil fruit","devil fruits","fruit power","fruit powers","df power"],
      logia: ["logia","smoke-smoke","flame-flame","sand-sand","rumble-rumble","ice-ice","glint-glint","magma-magma","dark-dark","swamp-swamp","gas-gas","flare-flare"],
      zoan: ["zoan","human-human fruit","hito hito","dragon fruit","ancient zoan","mythical zoan","animal kingdom pirates","tobi roppo"],
      paramecia: ["paramecia","gum-gum","gomu gomu","op-op","ope ope","string-string","hobby-hobby","barrier-barrier","flower-flower","revive-revive","soul-soul","quake-quake"],
      haki: ["haki","busoshoku","kenbunshoku","haoshoku","conqueror's haki","conquerors haki","armament haki","observation haki","supreme king"],
      "conquerors-haki": ["conqueror's haki","conquerors haki","haoshoku","color of the supreme king","supreme king"],
      "armament-haki": ["armament haki","busoshoku","color of arms","buso"],
      "observation-haki": ["observation haki","kenbunshoku","mantra","color of observation"],
      awakening: ["awakening","awakened","devil fruit awakening"],
      gear: ["gear second","gear third","gear fourth","gear 2","gear 3","gear 4","gear 5","boundman","snakeman"],
      nika: ["nika","sun god","joyboy","joy boy","gear 5"],
      // Lore / institutions
      poneglyph: ["poneglyph","road poneglyph","rio poneglyph"],
      "ancient-weapon": ["ancient weapon","pluton","poseidon","uranus"],
      "void-century": ["void century","blank century","ancient kingdom"],
      "buster-call": ["buster call"],
      bounty: ["bounty","bounties","wanted poster","wanted posters"],
      "world-government": ["world government","government","five elders","gorosei","imu","holy land","mariejois"],
      // Themes / event types
      "plot-twist": ["truth","true identity","identity","secret","mystery","reveals","revealed","unexpected","surprise","shocking"],
      betrayal: ["betrayal","betray","betrays","traitor","treason","deceive","deceived","trap","double-cross"],
      comedy: ["funny","comedy","hilarious","ridiculous","antics","gag","nonsense"],
      tragedy: ["tragedy","tragic","sorrow","mournful","cry","tears","sad","devastating"],
      death: ["death","dies","died","dead","killed","execution","executed","sacrifice","farewell"],
      loss: ["loss","lost","defeat","defeated","falls","farewell","mourning"],
      hype: ["hype","epic","legendary","ultimate","powerhouse","overwhelming","fierce","all-out","decisive"],
      political: ["kingdom","king","queen","princess","royal","throne","government","warlord","reverie","celestial dragon","world noble"],
      action: ["attack","assault","pursuit","escape","chase","clash","strike","blast","rampage"],
      battle: ["battle","war","battlefield","duel","showdown","versus","vs.","fight","fights"],
      fight: ["fight","fights","fighting","duel","versus","vs.","clash","face off","faces off"],
      reveal: ["reveal","reveals","revealed","truth","identity","secret","discovers","learns"],
      rescue: ["rescue","rescues","save","saves","saving","protect","protects"],
      escape: ["escape","escapes","flee","flees","run away","break out","jail break"],
      alliance: ["alliance","ally","allies","team up","join forces","pact"],
      training: ["training","train","trains","lesson","mentor"],
      tournament: ["tournament","colosseum","block a","block b","block c","block d","battle royale"],
      war: ["war","battlefield","marineford","raid","onigashima","buster call"],
      // Character-name indexing beyond the manually curated faction tags
      luffy: ["luffy","straw hat"], zoro: ["zoro","roronoa"], nami: ["nami"], usopp: ["usopp","sogeking"], sanji: ["sanji"], chopper: ["chopper"], robin: ["robin","nico robin"], franky: ["franky"], brook: ["brook"],
      ace: ["ace","fire fist"], sabo: ["sabo"], garp: ["garp"], sengoku: ["sengoku"], smoker: ["smoker"], koby: ["koby","coby"], lucci: ["lucci","rob lucci"], kaku: ["kaku"], dragon: ["dragon","monkey d dragon"],
      yamato: ["yamato"], oden: ["oden","kozuki oden"], kinemon: ["kin'emon","kinemon"], momonosuke: ["momonosuke"], carrot: ["carrot"], pedro: ["pedro"], katakuri: ["katakuri"],
      arlong: ["arlong"], rayleigh: ["rayleigh"], corazon: ["corazon","rosinante"], killer: ["killer"], magellan: ["magellan"], ivankov: ["ivankov","ivankov-san"],
      marco: ["marco"], jozu: ["jozu"], vista: ["vista"], beckman: ["beckman","benn beckman"], yasopp: ["yasopp"], burgess: ["burgess","jesus burgess"], shiryu: ["shiryu"], "van augur": ["van augur"], lafitte: ["lafitte"],
      perospero: ["perospero"], pudding: ["pudding","charlotte pudding"], cracker: ["cracker","charlotte cracker"], king: ["king"], queen: ["queen"], jack: ["jack"], bepo: ["bepo"], shachi: ["shachi"], penguin: ["penguin"],
      alvida: ["alvida"], cabaji: ["cabaji"], mohji: ["mohji"], "mr 1": ["mr 1","mr. 1","daz bones"], "bon clay": ["bon clay","mr 2","mr. 2"], "mr 3": ["mr 3","mr. 3","galdino"],
      trebol: ["trebol"], pica: ["pica"], sugar: ["sugar"], "fisher tiger": ["fisher tiger"], hody: ["hody","hody jones"], spandam: ["spandam"], nekomamushi: ["nekomamushi","cat viper"], inuarashi: ["inuarashi","dogstorm"], scabbards: ["scabbards","nine red scabbards","akazaya"]
    };
    const AUTO_TAG_REGEXES = Object.fromEntries(Object.entries(AUTO_TAG_RULES).map(([tag, aliases]) => [tag, aliases.map(aliasToRegex)]));
    episodes.forEach(ep => {
      if (ep.episode == null) return;
      const haystack = `${ep.title} ${ep.originalNote || ""}`.toLowerCase();
      for (const [tag, regexes] of Object.entries(AUTO_TAG_REGEXES)) {
        if (regexes.some(rx => rx.test(haystack))) ensureTagSet(tag).add(ep.episode);
      }
    });
    const MANUAL_RESEARCH_TAGS = {
      "devil-fruit": makeTagSet([1,8],[80,91],[92,130],[144,195],[225,228],[264,312],[326,384],[385,405],[453,516],[579,628],[629,746],[783,877],[890,1085],[1086,1130]),
      logia: makeTagSet([48,53],[92,130],[144,195],[225,228],299,304,306,[453,489],[579,628],625,737,738,739,925,[1086,1093]),
      zoan: makeTagSet([80,91],[264,312],[422,452],[726,746],[890,1085],[1086,1130]),
      paramecia: makeTagSet([1,130],[326,384],[629,746],[783,877],[999,1068]),
      haki: makeTagSet(389,397,413,479,[516,522],548,569,570,[646,649],[726,746],[855,877],[915,934],978,[1015,1028],[1033,1034],[1061,1076]),
      "conquerors-haki": makeTagSet(389,413,479,548,569,[646,649],726,727,[870,877],915,978,1015,[1028,1034],[1061,1076]),
      "armament-haki": makeTagSet([516,522],548,569,[646,649],[726,746],[855,877],[915,934],[1015,1034]),
      "observation-haki": makeTagSet([516,522],548,569,[855,877],[1015,1034]),
      awakening: makeTagSet([726,746],[733,746],[1069,1076],[1100,1130]),
      gear: makeTagSet([272,309],[516,522],726,727,728,[733,746],[870,877],[1015,1028],[1069,1076]),
      nika: makeTagSet([1070,1076],[1080,1086]),
      "buster-call": makeTagSet([275,278],[303,312]),
      tragedy: makeTagSet(44,[275,278],312,[379,380],[482,489],[493,496],[540,541],[651,660],[702,705],836,[960,974],[1129,1130]),
      "plot-twist": makeTagSet(119,120,151,236,242,278,312,325,405,458,483,517,594,597,628,642,647,658,659,700,744,746,765,766,767,808,835,836,877,889,957,958,967,968,1015,1071,1072,1080,1086,1088,1118,1129,1130),
      betrayal: makeTagSet([66,75],[106,108],[251,269],[293,312],[431,433],472,[642,660],[700,705],[765,767],[880,889],[1054,1070]),
      death: makeTagSet(44,111,127,312,380,[482,489],[493,505],[540,541],[702,705],835,836,[960,974],[1066,1068],[1129,1130]),
      loss: makeTagSet(44,312,380,[482,489],[493,505],[540,541],[651,660],[702,705],835,836,[960,974],[1066,1068],[1129,1130]),
      hype: makeTagSet(24,37,119,151,227,278,309,312,377,405,458,463,474,483,489,516,517,594,597,646,649,726,733,746,808,870,877,957,958,982,1015,1017,1028,1033,1061,1071,1072,1076,1080,1081,1086,1088,1115,1116,1117,1118),
      political: makeTagSet([62,130],[151,153],[227,228],[275,278],[303,312],[385,405],[453,516],[629,660],[700,746],[878,889],[956,958],[1080,1130]),
      action: makeTagSet([1,61],[92,130],[144,195],[264,312],[326,384],[385,405],[422,516],[579,746],[783,877],[890,1085],[1086,1130]),
      battle: makeTagSet([24,44],[92,130],[144,195],[264,312],[326,384],[385,405],[422,516],[579,746],[783,877],[890,1085],[1086,1130]),
      fight: makeTagSet([24,44],[92,130],[144,195],[264,312],[326,384],[385,405],[422,516],[579,746],[783,877],[890,1085],[1086,1130]),
      reveal: makeTagSet(100,119,151,227,236,242,278,312,325,405,517,594,597,628,642,647,658,659,700,744,746,765,766,767,808,835,836,877,889,957,958,967,968,1015,1071,1072,1080,1086,1088,1118,1129,1130),
      lucci: makeTagSet([230,312],746,886,1053,[1097,1155])
    };
    for (const [tag, set] of Object.entries(MANUAL_RESEARCH_TAGS)) for (const ep of set) ensureTagSet(tag).add(ep);

    const appearanceAuditData = JSON.parse(document.querySelector("#appearance-audits").textContent);
    function setFromAuditItems(items = []) { return makeTagSet(...items); }
    const APPEARANCE_TAGS = Object.fromEntries(Object.entries(appearanceAuditData.tags || {}).map(([tag, audit]) => [tag, {
      label: audit.label || tag,
      aliases: audit.aliases || [],
      appears: setFromAuditItems(audit.appears),
      focused: setFromAuditItems(audit.focused),
      flashback: setFromAuditItems(audit.flashback),
      remote: setFromAuditItems(audit.remote),
      excluded: new Map(Object.entries(audit.excluded || {}).flatMap(([key, reason]) => {
        const match = key.match(/^(\d+)\s*-\s*(\d+)$/);
        if (!match) return [[Number(key), reason]];
        const start = Number(match[1]), end = Number(match[2]);
        const out = [];
        for (let ep = start; ep <= end; ep++) out.push([ep, reason]);
        return out;
      })),
      firstAppearance: audit.firstAppearance || null,
      sources: audit.sources || []
    }]));
    const AUDITED_SOURCE_NOTES = Object.fromEntries(Object.entries(APPEARANCE_TAGS).map(([tag, audit]) => [tag, audit.sources.join(" | ")]));
    function unionSets(...sets) {
      const out = new Set();
      sets.forEach(set => set && set.forEach(value => out.add(value)));
      return out;
    }
    function getAppearanceSet(tagName, { includeRemote = true, mode = "appears" } = {}) {
      const audit = APPEARANCE_TAGS[tagName];
      if (!audit) return EP_TAGS[tagName] || new Set();
      const base = mode === "focused" ? audit.focused : audit.appears;
      return includeRemote ? unionSets(base, audit.flashback, audit.remote) : unionSets(base, audit.flashback);
    }
    function isAppearanceExcluded(epNo, tagName) {
      const audit = APPEARANCE_TAGS[tagName];
      return !!(audit && audit.excluded && audit.excluded.has(epNo));
    }
    function hasAppearanceTag(epNo, tagName, options) {
      if (epNo == null || isAppearanceExcluded(epNo, tagName)) return false;
      return getAppearanceSet(tagName, options).has(epNo);
    }

    // Tag synonym keywords -> tag name. Search will expand these before matching.
    const TAG_KEYWORDS = {
      flashback:          ["flashback","flashbacks","past","backstory"],
      backstory:          ["backstory","backstories","origin","origins","childhood","past"],
      "first-appearance": ["first appearance","first-appearance","debut","debuts","joins","joining"],
      recap:              ["recap","recaps","filler recap","summary"],
      // Factions - Yonko
      "shanks":           ["shanks","red hair shanks","red hair pirates","red force"],
      "whitebeard":       ["whitebeard","edward newgate","moby dick","whitebeard pirates"],
      "big-mom":          ["big mom","charlotte linlin","totto land","big mom pirates"],
      "kaido":            ["kaido","beast pirates","beasts pirates","onigashima","animal kingdom pirates","oni"],
      "blackbeard":       ["blackbeard","marshall d teach","teach","blackbeard pirates","black beard"],
      // Factions - Pirate Crews
      "whitebeard-pirates": ["whitebeard crew","yonko whitebeard"],
      "red-hair-pirates": ["red hair crew","shanks crew","red force crew"],
      "blackbeard-pirates": ["blackbeard crew","blackbeard gang"],
      "big-mom-pirates":  ["big mom crew","charlotte family","whole cake crew"],
      "beast-pirates":    ["beast crew","kaido crew","flying six","tobi roppo"],
      "heart-pirates":    ["heart pirates","law crew","polar tang","trafalgar law","law pirates"],
      "kid-pirates":      ["kid pirates","eustass kid","captain kid","kid crew"],
      "buggy-pirates":    ["buggy","buggy the clown","buggy pirates","buggy's delivery"],
      "baroque-works":    ["baroque works","crocodile org","mr zero","criminal","baroque"],
      "donquixote-pirates": ["donquixote","doflamingo","dressrosa family","joker","heavenly demon","birdcage","flamingo","donquixote pirates"],
      "sun-pirates":      ["sun pirates","arlong","arlong pirates","fisher tiger","fish-man pirates","fishman pirates"],
      "roger-pirates":    ["roger pirates","gol d roger","roger crew","pirate king crew","oro jackson"],
      "revolutionary-army": ["revolutionary army","dragon","monkey d dragon","revolutionaries","sabo","army"],
      // Factions - Marines / Gov
      "marines":          ["marine","marines","navy","world government military","marine hq"],
      "cipher-pol":       ["cipher pol","cipher pol agents"],
      "cp9":              ["cp9","cp-9","rob lucci","lucci","spandam"],
      "cp0":              ["cp0","cp-0","seraphim","world government agents"],
      "celestial-dragons": ["celestial dragons","world nobles","saint","tenryuubito","holy land","five elders","gorosei","imu","mariejois"],
      // Admirals
      "akainu":           ["akainu","sakazuki","fleet admiral","magma man"],
      "aokiji":           ["aokiji","kuzan","ice admiral","ice man"],
      "kizaru":           ["kizaru","borsalino","light admiral"],
      "fujitora":         ["fujitora","issho","blind admiral"],
      "ryokugyu":         ["ryokugyu","aramaki","green bull"],
      // Warlords
      "shichibukai":      ["shichibukai","warlord","seven warlords","warlords of the sea"],
      "crocodile":        ["crocodile","sir crocodile","mr 0","mr zero"],
      "doflamingo":       ["doflamingo","donquixote doflamingo","joker"],
      "jinbe":            ["jinbe","jimbei","jinbei","knight of the sea"],
      "hancock":          ["hancock","boa hancock","pirate empress","kuja","amazon lily"],
      "moriah":           ["moriah","moria","gecko moriah","thriller bark villain","shadow king"],
      "mihawk":           ["mihawk","dracule mihawk","hawk eyes","greatest swordsman","hawkeye"],
      "kuma":             ["kuma","bartholomew kuma","tyrant kuma","pacifista"],
      "law":              ["trafalgar law","law","surgeon of death","heart captain"],
      // Other Groups
      "supernovas":       ["supernova","supernovas","worst generation","eleven supernovas","rookie pirates"],
      "impel-down":       ["impel down","great gaol","level 6","magellan","impel"],
      "minks":            ["mink","minks","zou","mokomo","sulong","nekomamushi","inuarashi","carrot"],
      "wano-samurai":     ["wano samurai","kozuki","scabbards","nine red scabbards","akazaya","oden","kinemon","samurai"],
    };
    // Build reverse map: keyword -> tagname
    const KEYWORD_TO_TAG = new Map();
    for (const [tag, kws] of Object.entries(TAG_KEYWORDS)) {
      for (const kw of kws) KEYWORD_TO_TAG.set(kw.toLowerCase(), tag);
    }
    for (const [tag, aliases] of Object.entries(AUTO_TAG_RULES)) {
      KEYWORD_TO_TAG.set(tag.toLowerCase(), tag);
      for (const alias of aliases) KEYWORD_TO_TAG.set(alias.toLowerCase(), tag);
    }
    for (const [tag, audit] of Object.entries(APPEARANCE_TAGS)) {
      KEYWORD_TO_TAG.set(tag.toLowerCase(), tag);
      for (const alias of audit.aliases || []) KEYWORD_TO_TAG.set(alias.toLowerCase(), tag);
    }
    const SEARCH_TAG_ALIASES = Object.fromEntries(Object.entries(APPEARANCE_TAGS).map(([tag, audit]) => [tag, [tag, ...(audit.aliases || []), ...(AUTO_TAG_RULES[tag] || []), ...(TAG_KEYWORDS[tag] || [])]]));
    const TAG_TEXT_REGEXES = new Map();
    function getTagTextRegexes(tagName) {
      if (TAG_TEXT_REGEXES.has(tagName)) return TAG_TEXT_REGEXES.get(tagName);
      const aliases = new Set([tagName, tagName.replace(/-/g, " ")]);
      if (SEARCH_TAG_ALIASES[tagName]) SEARCH_TAG_ALIASES[tagName].forEach(alias => aliases.add(alias));
      if (AUTO_TAG_RULES[tagName]) AUTO_TAG_RULES[tagName].forEach(alias => aliases.add(alias));
      if (TAG_KEYWORDS[tagName]) TAG_KEYWORDS[tagName].forEach(alias => aliases.add(alias));
      for (const [keyword, mappedTag] of KEYWORD_TO_TAG.entries()) {
        if (mappedTag === tagName) aliases.add(keyword);
      }
      const regexes = [...aliases].filter(Boolean).map(aliasToRegex);
      TAG_TEXT_REGEXES.set(tagName, regexes);
      return regexes;
    }
    function matchesTagName(e, tagName, haystack) {
      if (e.episode != null && isAppearanceExcluded(e.episode, tagName)) return false;
      if (APPEARANCE_TAGS[tagName] && characterMode === "focused") return hasAppearanceTag(e.episode, tagName, { mode: "focused" });
      return hasAppearanceTag(e.episode, tagName, { mode: characterMode })
        || getTagTextRegexes(tagName).some(rx => rx.test(haystack));
    }
    function resolvePrefixTagNames(inner) {
      if (inner.length < 3) return [];
      const matches = new Set();
      for (const tag of new Set([...Object.keys(EP_TAGS), ...Object.keys(APPEARANCE_TAGS)])) {
        if (tag.toLowerCase().startsWith(inner)) matches.add(tag);
      }
      for (const [keyword, tag] of KEYWORD_TO_TAG.entries()) {
        if (keyword.startsWith(inner)) matches.add(tag);
      }
      return [...matches];
    }

    const STRAW_HAT_TAGS = [
      { label: "Monkey D. Luffy", tag: "luffy" },
      { label: "Roronoa Zoro", tag: "zoro" },
      { label: "Nami", tag: "nami" },
      { label: "Usopp", tag: "usopp" },
      { label: "Sanji", tag: "sanji" },
      { label: "Tony Tony Chopper", tag: "chopper" },
      { label: "Nico Robin", tag: "robin" },
      { label: "Franky", tag: "franky" },
      { label: "Brook", tag: "brook" },
      { label: "Jinbe / Jimbei", tag: "jinbe" },
    ];
    const WHITEBEARD_TAGS = [
      { label: "Whitebeard", tag: "whitebeard" },
      { label: "Portgas D. Ace", tag: "ace" },
      { label: "Marco", tag: "marco" },
      { label: "Jozu", tag: "jozu" },
      { label: "Vista", tag: "vista" },
    ];
    const RED_HAIR_TAGS = [
      { label: "Shanks", tag: "shanks" },
      { label: "Benn Beckman", tag: "beckman" },
      { label: "Lucky Roux", tag: "lucky roux" },
      { label: "Yasopp", tag: "yasopp" },
    ];
    const BLACKBEARD_TAGS = [
      { label: "Blackbeard / Teach", tag: "blackbeard" },
      { label: "Burgess", tag: "burgess" },
      { label: "Shiryu", tag: "shiryu" },
      { label: "Van Augur", tag: "van augur" },
      { label: "Lafitte", tag: "lafitte" },
    ];
    const BIG_MOM_TAGS = [
      { label: "Big Mom", tag: "big-mom" },
      { label: "Katakuri", tag: "katakuri" },
      { label: "Perospero", tag: "perospero" },
      { label: "Pudding", tag: "pudding" },
      { label: "Cracker", tag: "cracker" },
    ];
    const BEAST_TAGS = [
      { label: "Kaido", tag: "kaido" },
      { label: "King", tag: "king" },
      { label: "Queen", tag: "queen" },
      { label: "Jack", tag: "jack" },
      { label: "Yamato", tag: "yamato" },
    ];
    const HEART_TAGS = [
      { label: "Trafalgar Law", tag: "law" },
      { label: "Bepo", tag: "bepo" },
      { label: "Shachi", tag: "shachi" },
      { label: "Penguin", tag: "penguin" },
    ];
    const KID_TAGS = [
      { label: "Eustass Kid", tag: "kid-pirates" },
      { label: "Killer", tag: "killer" },
      { label: "Heat", tag: "heat" },
      { label: "Wire", tag: "wire" },
    ];
    const BUGGY_TAGS = [
      { label: "Buggy", tag: "buggy" },
      { label: "Alvida", tag: "alvida" },
      { label: "Cabaji", tag: "cabaji" },
      { label: "Mohji", tag: "mohji" },
    ];
    const BAROQUE_TAGS = [
      { label: "Crocodile", tag: "crocodile" },
      { label: "Nico Robin", tag: "robin" },
      { label: "Mr. 1", tag: "mr 1" },
      { label: "Mr. 2 Bon Clay", tag: "bon clay" },
      { label: "Mr. 3", tag: "mr 3" },
    ];
    const DONQUIXOTE_TAGS = [
      { label: "Doflamingo", tag: "doflamingo" },
      { label: "Corazon", tag: "corazon" },
      { label: "Trebol", tag: "trebol" },
      { label: "Pica", tag: "pica" },
      { label: "Sugar", tag: "sugar" },
    ];
    const SUN_TAGS = [
      { label: "Jinbe / Jimbei", tag: "jinbe" },
      { label: "Fisher Tiger", tag: "fisher tiger" },
      { label: "Arlong", tag: "arlong" },
      { label: "Hody Jones", tag: "hody" },
    ];
    const ROGER_TAGS = [
      { label: "Gol D. Roger", tag: "roger-pirates" },
      { label: "Rayleigh", tag: "rayleigh" },
      { label: "Kozuki Oden", tag: "oden" },
      { label: "Shanks", tag: "shanks" },
      { label: "Buggy", tag: "buggy" },
    ];
    const MARINE_TAGS = [
      { label: "Akainu / Sakazuki", tag: "akainu" },
      { label: "Aokiji / Kuzan", tag: "aokiji" },
      { label: "Kizaru / Borsalino", tag: "kizaru" },
      { label: "Fujitora / Issho", tag: "fujitora" },
      { label: "Ryokugyu / Aramaki", tag: "ryokugyu" },
      { label: "Garp", tag: "garp" },
      { label: "Sengoku", tag: "sengoku" },
      { label: "Smoker", tag: "smoker" },
      { label: "Koby", tag: "koby" },
    ];
    const CIPHER_POL_TAGS = [
      { label: "CP9", tag: "cp9" },
      { label: "CP0", tag: "cp0" },
      { label: "Rob Lucci", tag: "lucci" },
      { label: "Kaku", tag: "kaku" },
      { label: "Spandam", tag: "spandam" },
    ];
    const REVOLUTIONARY_TAGS = [
      { label: "Dragon", tag: "dragon" },
      { label: "Sabo", tag: "sabo" },
      { label: "Ivankov", tag: "ivankov" },
      { label: "Kuma", tag: "kuma" },
    ];
    const MINK_TAGS = [
      { label: "Nekomamushi", tag: "nekomamushi" },
      { label: "Inuarashi", tag: "inuarashi" },
      { label: "Carrot", tag: "carrot" },
      { label: "Pedro", tag: "pedro" },
    ];
    const WANO_TAGS = [
      { label: "Kozuki Oden", tag: "oden" },
      { label: "Kin'emon", tag: "kinemon" },
      { label: "Momonosuke", tag: "momonosuke" },
      { label: "Yamato", tag: "yamato" },
      { label: "Nine Red Scabbards", tag: "scabbards" },
    ];
    const TAG_TREE = [
      { label: "Story tags", children: [
        { label: "Flashback", tag: "flashback" },
        { label: "Backstory", tag: "backstory" },
        { label: "First appearance", tag: "first-appearance" },
        { label: "Recap", tag: "recap" },
      ] },
      { label: "Power systems", children: [
        { label: "Devil Fruits", tag: "devil-fruit", children: [
          { label: "Logia", tag: "logia" },
          { label: "Zoan", tag: "zoan" },
          { label: "Paramecia", tag: "paramecia" },
          { label: "Awakening", tag: "awakening" },
          { label: "Nika / Gear 5", tag: "nika" },
        ] },
        { label: "Haki", tag: "haki", children: [
          { label: "Conqueror's Haki", tag: "conquerors-haki" },
          { label: "Armament Haki", tag: "armament-haki" },
          { label: "Observation Haki", tag: "observation-haki" },
        ] },
        { label: "Gear techniques", tag: "gear" },
      ] },
      { label: "Lore / worldbuilding", children: [
        { label: "Poneglyphs", tag: "poneglyph" },
        { label: "Ancient Weapons", tag: "ancient-weapon" },
        { label: "Void Century", tag: "void-century" },
        { label: "Buster Call", tag: "buster-call" },
        { label: "Bounties", tag: "bounty" },
        { label: "World Government", tag: "world-government" },
      ] },
      { label: "Themes / events", children: [
        { label: "Plot twist", tag: "plot-twist" },
        { label: "Betrayal / treason", tag: "betrayal" },
        { label: "Comedy", tag: "comedy" },
        { label: "Tragedy", tag: "tragedy" },
        { label: "Death", tag: "death" },
        { label: "Loss", tag: "loss" },
        { label: "Hype", tag: "hype" },
        { label: "Political", tag: "political" },
        { label: "Action", tag: "action" },
        { label: "Battle", tag: "battle" },
        { label: "Fight", tag: "fight" },
        { label: "Reveal", tag: "reveal" },
        { label: "Rescue", tag: "rescue" },
        { label: "Escape", tag: "escape" },
        { label: "Alliance", tag: "alliance" },
        { label: "Training", tag: "training" },
        { label: "Tournament", tag: "tournament" },
        { label: "War", tag: "war" },
      ] },
      { label: "Characters", children: [
        { label: "Straw Hats", tag: "straw hat", children: STRAW_HAT_TAGS },
        { label: "Yonko / Emperors", tag: "yonko", children: [
          { label: "Shanks", tag: "shanks" },
          { label: "Whitebeard", tag: "whitebeard" },
          { label: "Big Mom", tag: "big-mom" },
          { label: "Kaido", tag: "kaido" },
          { label: "Blackbeard", tag: "blackbeard" },
        ] },
        { label: "Admirals", tag: "admiral", children: [
          { label: "Akainu / Sakazuki", tag: "akainu" },
          { label: "Aokiji / Kuzan", tag: "aokiji" },
          { label: "Kizaru / Borsalino", tag: "kizaru" },
          { label: "Fujitora / Issho", tag: "fujitora" },
          { label: "Ryokugyu / Aramaki", tag: "ryokugyu" },
        ] },
        { label: "Warlords", tag: "shichibukai", children: [
          { label: "All Shichibukai", tag: "shichibukai" },
          { label: "Crocodile", tag: "crocodile" },
          { label: "Doflamingo", tag: "doflamingo" },
          { label: "Jinbe / Jimbei", tag: "jinbe" },
          { label: "Boa Hancock", tag: "hancock" },
          { label: "Gecko Moriah", tag: "moriah" },
          { label: "Dracule Mihawk", tag: "mihawk" },
          { label: "Bartholomew Kuma", tag: "kuma" },
          { label: "Trafalgar Law", tag: "law" },
        ] },
        { label: "Worst Generation", tag: "supernovas", children: [
          { label: "All Supernovas", tag: "supernovas" },
          { label: "Trafalgar Law", tag: "law" },
          { label: "Eustass Kid", tag: "kid-pirates" },
          { label: "Monkey D. Luffy", tag: "luffy" },
          { label: "Roronoa Zoro", tag: "zoro" },
        ] },
      ] },
      { label: "Pirate crews", children: [
        { label: "Straw Hat Pirates", tag: "straw hat", children: STRAW_HAT_TAGS },
        { label: "Whitebeard Pirates", tag: "whitebeard-pirates", children: WHITEBEARD_TAGS },
        { label: "Red Hair Pirates", tag: "red-hair-pirates", children: RED_HAIR_TAGS },
        { label: "Blackbeard Pirates", tag: "blackbeard-pirates", children: BLACKBEARD_TAGS },
        { label: "Big Mom Pirates", tag: "big-mom-pirates", children: BIG_MOM_TAGS },
        { label: "Beast Pirates", tag: "beast-pirates", children: BEAST_TAGS },
        { label: "Heart Pirates", tag: "heart-pirates", children: HEART_TAGS },
        { label: "Kid Pirates", tag: "kid-pirates", children: KID_TAGS },
        { label: "Buggy Pirates", tag: "buggy-pirates", children: BUGGY_TAGS },
        { label: "Baroque Works", tag: "baroque-works", children: BAROQUE_TAGS },
        { label: "Donquixote Pirates", tag: "donquixote-pirates", children: DONQUIXOTE_TAGS },
        { label: "Sun Pirates", tag: "sun-pirates", children: SUN_TAGS },
        { label: "Roger Pirates", tag: "roger-pirates", children: ROGER_TAGS },
      ] },
      { label: "Government / Marines", children: [
        { label: "Marines", tag: "marines", children: MARINE_TAGS },
        { label: "Cipher Pol", tag: "cipher-pol", children: CIPHER_POL_TAGS },
        { label: "CP9", tag: "cp9", children: CIPHER_POL_TAGS.filter(item => ["cp9","lucci","kaku","spandam"].includes(item.tag)) },
        { label: "CP0", tag: "cp0", children: CIPHER_POL_TAGS.filter(item => ["cp0","lucci","kaku"].includes(item.tag)) },
        { label: "Celestial Dragons", tag: "celestial-dragons", children: [
          { label: "Gorosei", tag: "gorosei" },
          { label: "Imu", tag: "imu" },
          { label: "World Nobles", tag: "celestial-dragons" },
        ] },
      ] },
      { label: "Places / groups", children: [
        { label: "Revolutionary Army", tag: "revolutionary-army", children: REVOLUTIONARY_TAGS },
        { label: "Impel Down", tag: "impel-down", children: [
          { label: "Magellan", tag: "magellan" },
          { label: "Ivankov", tag: "ivankov" },
          { label: "Prisoners", tag: "impel-down" },
        ] },
        { label: "Minks", tag: "minks", children: MINK_TAGS },
        { label: "Wano Samurai", tag: "wano-samurai", children: WANO_TAGS },
      ] },
    ];

    // Death/die synonym group
    const DEATH_SYNONYMS = new Set(["death","die","dies","died","dead","killed","kill","sacrifice","sacrificed","loss","lost","farewell","executed","execution"]);

    // Saga search aliases: search terms that map to saga/sub-saga keys
    const SAGA_ALIASES = {
      "east blue": "east-blue", "east-blue": "east-blue",
      "alabasta": "arabasta", "arabasta": "arabasta", "arlong": "east-blue",
      "skypiea": "sky-island", "sky island": "sky-island", "sky-island": "sky-island",
      "water 7": "water-7", "water-7": "water-7", "enies lobby": "water-7", "enies": "water-7",
      "thriller bark": "thriller-bark",
      "sabaody": "sabaody", "sabaody archipelago": "sabaody",
      "marineford": "summit-war", "summit war": "summit-war", "marine ford": "summit-war",
      "fish-man island": "fish-man-island", "fishman island": "fish-man-island", "fishman": "fish-man-island",
      "punk hazard": "punk-hazard",
      "dressrosa": "dressrosa",
      "zou": "zou",
      "whole cake": "whole-cake", "whole-cake island": "whole-cake", "big mom": "whole-cake",
      "wano": "wano",
      "levely": "levely",
      "final": "final"
    };

    // Category aliases for search
    const CATEGORY_ALIASES = {
      "canon": ["anime","manga","mixed"],
      "filler": ["filler"],
      "recap": ["recap"],
      "ova": ["ova"],
      "special": ["special"],
      "movie": ["movie"],
      "short": ["short"],
      "non-canon": ["filler","ova","special","movie","short","recap"]
    };

    // Episode tag lookup
    function getEpTags(ep) {
      const tags = [];
      const allTags = new Set([...Object.keys(EP_TAGS), ...Object.keys(APPEARANCE_TAGS)]);
      for (const tag of allTags) {
        if (hasAppearanceTag(ep.episode, tag, { includeRemote: false, mode: characterMode })) tags.push(tag);
      }
      return tags;
    }

    function tagLabel(tag) { return `#${tag}`; }

    // Range filter state
    let epRangeMin = null, epRangeMax = null; // null = no range filter

    const sagas = JSON.parse(document.querySelector("#saga-data").textContent);
    const subSagas = JSON.parse(document.querySelector("#sub-saga-data").textContent);
    const sagaMeta = Object.fromEntries(sagas.map(s => [s.key, s]));
    const subSagaMeta = Object.fromEntries(subSagas.map(s => [s.key, s]));
    const output = document.querySelector("#saga-output"), jumpList = document.querySelector("#saga-jump-list"), tooltip = document.querySelector("#tooltip"), status = document.querySelector("#status");
    tooltip.addEventListener("mouseenter", () => { tooltipHovering = true; cancelHideTimer(); cancelShowTimer(); });
    tooltip.addEventListener("mouseleave", () => { tooltipHovering = false; hideTip(false); });
    const isTouchDevice = ("ontouchstart" in window) || navigator.maxTouchPoints > 0;
    let lastTappedEpisode = null;
    const typeFilter = createMultiFilter("type-filter", Object.entries(CATEGORY_META).map(([value, meta]) => ({ value, label: meta.label })), T.allTypes);
    const sagaFilter = createMultiFilter("saga-filter", sagas.map(s => ({ value: s.key, label: s.label })), T.allSagas);
    const subSagaFilter = createMultiFilter("sub-saga-filter", subSagas.map(s => ({ value: s.key, label: s.label })), T.allSubSagas);

    function createMultiFilter(id, items, allLabel) {
      const root = document.querySelector(`#${id}`), menu = root.querySelector(".filter-menu"), label = root.querySelector(".label"), toggle = root.querySelector(".filter-toggle");
      const selected = new Set(items.map(item => item.value));
      for (const item of items) {
        const option = document.createElement("label"); option.className = "filter-option";
        const input = document.createElement("input"); input.type = "checkbox"; input.value = item.value; input.checked = true;
        const name = document.createElement("span"); name.textContent = item.label;
        option.append(input, name);
        input.addEventListener("change", event => { event.target.checked ? selected.add(item.value) : selected.delete(item.value); updateLabel(); saveHash(); render(); });
        menu.appendChild(option);
      }
      function updateLabel() {
        const picked = items.filter(item => selected.has(item.value));
        label.textContent = picked.length === items.length ? allLabel : picked.length === 1 ? picked[0].label : `${picked.length}/${items.length} selected`;
      }
      function setSelected(values) {
        selected.clear(); values.forEach(value => selected.add(value));
        menu.querySelectorAll("input").forEach(input => { input.checked = selected.has(input.value); });
        updateLabel();
      }
      toggle.addEventListener("click", event => { event.stopPropagation(); document.querySelectorAll(".multi-filter.open, .sort-filter.open, .tag-filter.open").forEach(open => { if (open !== root) open.classList.remove("open"); }); root.classList.toggle("open"); });
      updateLabel();
      return { has: value => selected.has(value), values: () => [...selected], setSelected, selectAll: () => setSelected(items.map(item => item.value)), clear: () => setSelected([]) };
    }

    function closeFilters() { document.querySelectorAll(".multi-filter.open, .sort-filter.open, .tag-filter.open").forEach(open => open.classList.remove("open")); }
    document.addEventListener("click", e => { closeFilters(); if (!e.target.closest(".tile") && !e.target.closest(".tooltip")) hideTip(true); });
    document.addEventListener("touchstart", e => {
      if (!e.target.closest(".tile") && !e.target.closest(".tooltip")) {
        hideTip(true); lastTappedEpisode = null;
      }
    }, { passive: true });
    document.addEventListener("keydown", event => { if (event.key === "Escape") { closeFilters(); hideTip(true); closeTipsOverlay(); } });
    document.querySelectorAll(".filter-menu, .sort-menu").forEach(menu => menu.addEventListener("click", event => event.stopPropagation()));

    const tagFilter = document.querySelector("#tag-filter");
    const tagFilterToggle = document.querySelector("#tag-filter-toggle");
    const tagFilterPanel = document.querySelector("#tag-filter-panel");
    function setSearchFromTag(tag, op) {
      const current = searchEl.value.trim();
      let next;
      if (op === "or") next = current ? `${current} | ${tag}` : tag;
      else if (op === "exclude") next = current ? `${current} + -${tag}` : `-${tag}`;
      else next = current ? `${current} + ${tag}` : tag;
      searchEl.value = next;
      updateSearchQuery(next, "prefix");
      saveHash(); render();
    }
    function createTagOps(tag) {
      const actions = document.createElement("span"); actions.className = "tag-tree-node-actions";
      [["+", "and", "Add with AND"], ["|", "or", "Add with OR"], ["-", "exclude", "Exclude this tag"]].forEach(([text, op, title]) => {
        const btn = document.createElement("button"); btn.type = "button"; btn.className = "tag-op"; btn.textContent = text; btn.title = `${title}: ${tag}`;
        btn.addEventListener("click", event => { event.stopPropagation(); setSearchFromTag(tag, op); });
        actions.appendChild(btn);
      });
      return actions;
    }
    function createTagLeaf(node) {
      const chip = document.createElement("span"); chip.className = "tag-filter-chip tag-tree-leaf";
      const label = document.createElement("b"); label.textContent = node.label;
      const term = document.createElement("small"); term.textContent = node.tag;
      chip.append(label, term, createTagOps(node.tag));
      return chip;
    }
    function renderTagTree(nodes = TAG_TREE, path = []) {
      tagFilterPanel.textContent = "";
      const header = document.createElement("div"); header.className = "tag-tree-header";
      if (path.length) {
        const back = document.createElement("button"); back.type = "button"; back.className = "tag-tree-back"; back.textContent = "Back";
        back.addEventListener("click", event => { event.stopPropagation(); const parent = path[path.length - 2]; renderTagTree(parent?.children || TAG_TREE, path.slice(0, -1)); });
        header.appendChild(back);
      }
      const title = document.createElement("span"); title.className = "tag-tree-title"; title.textContent = path[path.length - 1]?.label || "Tag categories";
      header.appendChild(title);
      const list = document.createElement("div"); list.className = "tag-tree-list";
      for (const node of nodes) {
        if (node.children) {
          const folder = document.createElement("div"); folder.className = "tag-tree-node";
          const main = document.createElement("button"); main.type = "button"; main.className = "tag-tree-node-main"; main.textContent = node.label;
          main.addEventListener("click", event => { event.stopPropagation(); renderTagTree(node.children, [...path, node]); });
          folder.appendChild(main);
          if (node.tag) folder.appendChild(createTagOps(node.tag));
          list.appendChild(folder);
        } else {
          list.appendChild(createTagLeaf(node));
        }
      }
      tagFilterPanel.append(header, list);
    }
    renderTagTree();
    tagFilterToggle.addEventListener("click", event => { event.stopPropagation(); const wasOpen = tagFilter.classList.contains("open"); closeFilters(); if (!wasOpen) renderTagTree(); tagFilter.classList.toggle("open", !wasOpen); });
    tagFilterPanel.addEventListener("click", event => event.stopPropagation());

    // Search tips overlay
    const tipsOverlay = document.querySelector("#search-tips-overlay");
    const tipsPanel  = document.querySelector("#search-tips-panel");
    function openTipsOverlay()  { tipsOverlay.classList.add("open"); }
    function closeTipsOverlay() { tipsOverlay.classList.remove("open"); }
    document.querySelector("#search-tips-btn").addEventListener("click", e => { e.stopPropagation(); openTipsOverlay(); });
    document.querySelector("#search-tips-close").addEventListener("click", closeTipsOverlay);
    tipsOverlay.addEventListener("click", e => { if (!tipsPanel.contains(e.target)) closeTipsOverlay(); });

    // Tier filter state (replaces rating range slider)
    const TIERS = [
      { key: "cinema",  min: 9.6,  max: Infinity },
      { key: "awesome", min: 8.6,  max: 9.599 },
      { key: "great",   min: 8.0,  max: 8.599 },
      { key: "good",    min: 7.0,  max: 7.999 },
      { key: "regular", min: 6.0,  max: 6.999 },
      { key: "bad",     min: 5.0,  max: 5.999 },
      { key: "garbage", min: -Infinity, max: 4.999 },
    ];
    function ratingTier(r) { return TIERS.find(t => r >= t.min && r <= t.max)?.key ?? "garbage"; }
    const activeTiers = new Set(TIERS.map(t => t.key));
    const tierBtns = document.querySelectorAll(".tier-btn");
    tierBtns.forEach(btn => {
      btn.addEventListener("click", () => {
        const tier = btn.dataset.tier;
        if (activeTiers.has(tier)) { activeTiers.delete(tier); btn.classList.replace("on", "off"); }
        else { activeTiers.add(tier); btn.classList.replace("off", "on"); }
        saveHash(); render();
      });
    });
    function setAllTiers(on) {
      TIERS.forEach(t => { if (on) activeTiers.add(t.key); else activeTiers.delete(t.key); });
      tierBtns.forEach(btn => { btn.classList.toggle("on", on); btn.classList.toggle("off", !on); });
    }

    // Sort state - custom dropdown
    let sortOrder = "watch";
    const sortOptions = [
      { value: "watch", label: T.sortWatchOrder },
      { value: "rating-desc", label: T.sortRatingDesc },
      { value: "rating-asc", label: T.sortRatingAsc }
    ];
    const sortFilterEl = document.querySelector("#sort-filter");
    const sortMenuEl = sortFilterEl.querySelector(".sort-menu");
    const sortLabelEl = document.querySelector("#sort-label");
    const sortToggleEl = sortFilterEl.querySelector(".filter-toggle");
    sortOptions.forEach(opt => {
      const item = document.createElement("div");
      item.className = "sort-option" + (opt.value === sortOrder ? " selected" : "");
      item.textContent = opt.label;
      item.dataset.sort = opt.value;
      item.addEventListener("click", () => {
        sortOrder = opt.value;
        sortLabelEl.textContent = opt.label;
        sortMenuEl.querySelectorAll(".sort-option").forEach(el => el.classList.remove("selected"));
        item.classList.add("selected");
        sortFilterEl.classList.remove("open");
        saveHash(); render();
      });
      sortMenuEl.appendChild(item);
    });
    sortToggleEl.addEventListener("click", e => {
      e.stopPropagation();
      const wasOpen = sortFilterEl.classList.contains("open");
      closeFilters();
      if (!wasOpen) sortFilterEl.classList.add("open");
    });

    // Dim mode state
    let dimMode = true;
    document.querySelector("#dim-toggle").addEventListener("change", e => { dimMode = e.target.checked; saveHash(); render(); });

    // Character audit mode: broader real appearances vs stricter focused episodes.
    let characterMode = "appears";
    const characterModeEl = document.querySelector("#character-mode");
    characterModeEl.addEventListener("change", e => { characterMode = e.target.value === "focused" ? "focused" : "appears"; saveHash(); render(); });

    // Search state
    let searchQuery = "";
    let searchTerms = []; // array of {term, negate, type, regex} for current mode
    let searchMode = "prefix"; // "prefix" | "exact"
    let searchOp = "and"; // "and" | "or"
    let searchDebounce = null;
    const searchEl = document.querySelector("#search");

    function escapeRegex(s) { return s.replace(/[[\]{}()*+?.,\\^$|#\s]/g, "\\$&"); }

    function buildTermRegex(term, mode) {
      const e = escapeRegex(term);
      if (mode === "exact") {
        // whole-word: at word boundary, but allow trailing apostrophe/s (ace's still matches "ace")
        return new RegExp("(?:^|\\s)" + e + "(?=[^a-zA-Z0-9]|$|'s?\\b)", "i");
      } else {
        // prefix-of-word: term appears at start of string or after whitespace
        return new RegExp("(?:^|\\s)" + e, "i");
      }
    }

    // Resolve a single lowercased inner term into a structured token object.
    // Used by both positive and negated paths so alias resolution is shared.
    function resolveSingleTerm(inner, negate, mode) {
      // Episode range: 400-500, e400-e500, e400-500
      const rangeMatch = inner.match(/^e?(\d+)-e?(\d+)$/);
      if (rangeMatch) {
        const lo = parseInt(rangeMatch[1]), hi = parseInt(rangeMatch[2]);
        return [{ term: inner, negate, type: "range", lo, hi }];
      }
      if (EP_TAGS[inner] || APPEARANCE_TAGS[inner]) return [{ term: inner, negate, type: "tag", tagName: inner }];
      // Tag keyword match (e.g. "flashback", "backstory", "first appearance", "recap")
      const tagName = KEYWORD_TO_TAG.get(inner);
      if (tagName) return [{ term: inner, negate, type: "tag", tagName }];
      const prefixTags = resolvePrefixTagNames(inner);
      if (prefixTags.length && (mode === "prefix" || prefixTags.length === 1)) return [{ term: inner, negate, type: "tag-prefix", tagNames: prefixTags, regex: buildTermRegex(inner, mode) }];
      // Saga alias: returns saga key
      const sagaKey = SAGA_ALIASES[inner];
      if (sagaKey) return [{ term: inner, negate, type: "saga", sagaKey }];
      // Category alias: returns array of category values
      const catValues = CATEGORY_ALIASES[inner];
      if (catValues) return [{ term: inner, negate, type: "category", catValues }];
      // Death/die synonym expansion
      if (DEATH_SYNONYMS.has(inner)) {
        const deathRegexes = [...DEATH_SYNONYMS].map(s => buildTermRegex(s, mode));
        return [{ term: inner, negate, type: "death-synonym", deathRegexes }];
      }
      // Plain text term
      return [{ term: inner, negate, type: "text", regex: buildTermRegex(inner, mode) }];
    }

    // Parse a single raw search term string into structured tokens.
    // Handles: exclusion (-nami, -(nami,usopp)), range (400-500, e400-e500),
    // tag keywords, saga aliases, category aliases, death synonyms, OR/AND.
    function parseSearchTerms(raw, mode) {
      const q = raw.trim();
      if (!q) return { terms: [], op: "and" };

      // Detect OR operator at top level: " or " or "|"
      let op = "and";
      let topParts;
      if (q.includes("|") || / or /i.test(q)) {
        op = "or";
        topParts = q.split(/\s+or\s+|\|/).map(s => s.trim()).filter(Boolean);
      } else if (q.includes("+")) {
        op = "and";
        topParts = q.split("+").map(s => s.trim()).filter(Boolean);
      } else {
        op = "and";
        topParts = [q];
      }

      const terms = [];
      for (const part of topParts) {
        const lpart = part.toLowerCase().trim();

        // Negation: starts with "-"
        if (lpart.startsWith("-")) {
          let inner = lpart.slice(1).trim();
          // Handle grouped: -(nami, usopp)
          if (inner.startsWith("(") && inner.endsWith(")")) {
            inner = inner.slice(1, -1);
          }
          // Multiple comma-separated exclusion terms - each resolved through alias/tag/saga logic
          const exParts = inner.split(",").map(s => s.trim()).filter(Boolean);
          for (const ex of exParts) {
            terms.push(...resolveSingleTerm(ex, true, mode));
          }
          continue;
        }

        // Positive term - resolved through same alias/tag/saga logic
        terms.push(...resolveSingleTerm(lpart, false, mode));
      }
      return { terms, op };
    }

    function updateSearchQuery(raw, mode) {
      searchQuery = raw.trim().toLowerCase();
      searchMode = mode || "prefix";
      const parsed = parseSearchTerms(raw, searchMode);
      searchTerms = parsed.terms;
      searchOp = parsed.op;
    }

    function matchesTerm(e, t, haystack, code) {
      switch (t.type) {
        case "range":
          return e.episode != null && e.episode >= t.lo && e.episode <= t.hi;
        case "tag":
          return matchesTagName(e, t.tagName, haystack);
        case "tag-prefix":
          return t.tagNames.some(tagName => matchesTagName(e, tagName, haystack));
        case "saga":
          return e.saga === t.sagaKey || e.subSaga === t.sagaKey;
        case "category":
          return t.catValues.includes(e.category) || t.catValues.includes(e.mediaKind);
        case "death-synonym":
          return t.deathRegexes.some(rx => rx.test(haystack));
        case "text":
        default:
          return code.includes(t.term) || t.regex.test(haystack);
      }
    }

    function matchesSearch(e) {
      if (!searchTerms.length) return true;
      const haystack = (e.title + " " + (e.originalNote || "")).toLowerCase();
      const code = e.displayCode.toLowerCase();

      // Negation terms always act as AND exclusions regardless of op
      for (const t of searchTerms) {
        if (t.negate && matchesTerm(e, { ...t, negate: false }, haystack, code)) return false;
      }
      const positiveTerms = searchTerms.filter(t => !t.negate);
      if (!positiveTerms.length) return true;

      if (searchOp === "or") {
        return positiveTerms.some(t => matchesTerm(e, t, haystack, code));
      } else {
        return positiveTerms.every(t => matchesTerm(e, t, haystack, code));
      }
    }

    function matchesRange(e) {
      if (epRangeMin === null && epRangeMax === null) return true;
      if (e.episode == null) return false;
      if (epRangeMin !== null && e.episode < epRangeMin) return false;
      if (epRangeMax !== null && e.episode > epRangeMax) return false;
      return true;
    }

    function commitSearch(raw) {
      if (searchDebounce) { clearTimeout(searchDebounce); searchDebounce = null; }
      updateSearchQuery(raw, "exact");
      saveHash(); render();
    }

    searchEl.addEventListener("input", e => {
      const raw = e.target.value;
      updateSearchQuery(raw, "prefix");
      setTimeout(() => { saveHash(); render(); }, 0);
    });
    searchEl.addEventListener("keydown", e => {
      if (e.key === "Enter") { commitSearch(searchEl.value); searchEl.blur(); }
    });
    searchEl.addEventListener("click", e => e.stopPropagation());

    const emptyRatingColor = "#6b7280";
    function ratingColor(r) { return r >= 9.6 ? "#1DA1F2" : r >= 8.6 ? "#186A3B" : r >= 8 ? "#28B463" : r >= 7 ? "#F4D03F" : r >= 6 ? "#F39C12" : r >= 5 ? "#E74C3C" : "#633974"; }
    function ratingTextColor(r) { return r >= 8.6 || r < 6 ? "rgb(255,255,255)" : "rgb(10,10,10)"; }
    function episodeTextColor(r) { return r >= 8.6 || r < 6 ? "rgba(255,255,255,.82)" : "rgba(10,10,10,.68)"; }
    function textStrokeColor(r) { return r >= 8.6 || r < 6 ? "rgba(0,0,0,.34)" : "rgba(255,255,255,.28)"; }
    function avg(list) { return list.reduce((sum, e) => sum + e.rating, 0) / list.length; }
    function avgText(list, digits) { return list.length ? avg(list).toFixed(digits) : "--"; }
    function dominantKind(list) {
      if (!list.length) return "No selection";
      const counts = new Map();
      for (const item of list) {
        const kind = subSagaMeta[item.subSaga]?.kind || CATEGORY_META[item.category]?.label || "Mixed";
        counts.set(kind, (counts.get(kind) || 0) + 1);
      }
      const ranked = [...counts.entries()].sort((a, b) => b[1] - a[1]);
      return ranked.length > 1 && ranked[0][1] === ranked[1][1] ? "Mixed" : ranked[0][0];
    }
    function matchesFilters(e) {
      if (!typeFilter.has(e.category)) return false;
      if (!sagaFilter.has(e.saga)) return false;
      if (!subSagaFilter.has(e.subSaga)) return false;
      if (!activeTiers.has(ratingTier(e.rating))) return false;
      if (searchTerms.length && !matchesSearch(e)) return false;
      return true;
    }
    function sortEpisodes(list) {
      if (sortOrder === "rating-desc") return [...list].sort((a, b) => b.rating - a.rating);
      if (sortOrder === "rating-asc") return [...list].sort((a, b) => a.rating - b.rating);
      return [...list].sort((a, b) => a.sortKey - b.sortKey);
    }
    function activeEpisodes() { return sortEpisodes(episodes.filter(matchesFilters)); }
    function sourceLabel(e) { return e.mediaKind === "episode" ? "IMDb" : "MyAnimeList"; }
    function entryLabel(e) { return e.mediaKind === "episode" ? `Episode ${e.episode}` : e.displayCode; }
    function jumpLabel(saga) { return saga.key === "sky-island" ? "Skypiea" : saga.label.replace(/ Island(?= Saga$)/, "").replace(/ Saga$/, ""); }
    function appendBreak(parent, count = 1) { for (let i = 0; i < count; i++) parent.appendChild(document.createElement("br")); }
    function appendText(parent, value) { parent.appendChild(document.createTextNode(value)); }
    function safeSourceUrl(value) {
      try {
        const url = new URL(value);
        return (url.protocol === "https:" && (url.hostname === "www.imdb.com" || url.hostname === "myanimelist.net")) ? url.href : null;
      } catch { return null; }
    }
    function openSource(e) {
      const safeUrl = safeSourceUrl(e.sourceUrl);
      if (!safeUrl) return;
      window.open(safeUrl, "_blank", "noopener,noreferrer");
    }

    // Synopsis translation (PT-BR, lazy via MyMemory)
    const synopsisCache = (() => {
      try { return JSON.parse(sessionStorage.getItem("op_synopsis_ptbr") || "{}"); } catch { return {}; }
    })();
    function saveSynopsisCache() {
      try { sessionStorage.setItem("op_synopsis_ptbr", JSON.stringify(synopsisCache)); } catch {}
    }
    async function translateSynopsis(key, text) {
      if (!text) return "";
      if (synopsisCache[key]) return synopsisCache[key];
      const url = `https://api.mymemory.translated.net/get?q=${encodeURIComponent(text)}&langpair=en|pt-BR`;
      try {
        const res = await fetch(url);
        const data = await res.json();
        const translated = data?.responseData?.translatedText || "";
        if (translated && translated.toLowerCase() !== text.toLowerCase()) {
          synopsisCache[key] = translated;
          saveSynopsisCache();
          return translated;
        }
      } catch {}
      return T.noTranslation;
    }

    function sourceLinkLabel(e) { return e.mediaKind === "episode" ? T.openIMDb : T.openMAL; }

    function showTip(event, e, isTouchMode) {
      const c = CATEGORY_META[e.category], s = sagaMeta[e.saga], ss = subSagaMeta[e.subSaga];
      tooltip.textContent = "";
      const title = document.createElement("strong");
      title.textContent = `${entryLabel(e)}: ${e.title}`;
      const detail = document.createElement("span");
      appendText(detail, `${c.label} / ${s.label} / ${ss.label}`);
      appendBreak(detail);
      appendText(detail, `${T.rating} ${e.rating.toFixed(1)} \u00B7 ${sourceLabel(e)}`);
      if (e.aired) { appendBreak(detail); appendText(detail, `${T.aired}: ${e.aired}`); }
      if (e.placement) { appendBreak(detail); appendText(detail, e.placement); }
      let synopsisNode = null;
      if (e.originalNote) {
        appendBreak(detail);
        if (LANG === "pt") {
          synopsisNode = document.createTextNode(`${T.synopsis}: ${T.translating}`);
          detail.appendChild(synopsisNode);
        } else {
          appendText(detail, `${T.synopsis}: ${e.originalNote}`);
        }
      }
      const safeUrl = safeSourceUrl(e.sourceUrl);
      const attachedTags = getEpTags(e);
      if (safeUrl || attachedTags.length) {
        appendBreak(detail, 2);
        const actions = document.createElement("span");
        actions.className = "tooltip-actions";
        if (safeUrl) {
          const source = document.createElement("a");
          source.className = "tooltip-source-link";
          source.href = safeUrl;
          source.target = "_blank";
          source.rel = "noopener noreferrer";
          source.textContent = sourceLinkLabel(e);
          actions.appendChild(source);
        }
        if (attachedTags.length) {
          const tagButton = document.createElement("button");
          tagButton.type = "button";
          tagButton.className = "tooltip-tag-btn";
          tagButton.textContent = "#";
          tagButton.title = "Show attached search tags";
          tagButton.setAttribute("aria-label", "Show attached search tags");
          tagButton.setAttribute("aria-expanded", "true");
          const tagWrap = document.createElement("span");
          tagWrap.className = "tooltip-tags visible";
          for (const tag of attachedTags) {
            const chip = document.createElement("span");
            chip.className = "tooltip-tag-chip";
            chip.textContent = tagLabel(tag);
            tagWrap.appendChild(chip);
          }
          function setTooltipTagsOpen(open) {
            tagWrap.classList.toggle("visible", open);
            tagButton.setAttribute("aria-expanded", open ? "true" : "false");
          }
          let tagHoldTimer = null;
          let heldTagsOpen = false;
          tagButton.addEventListener("pointerdown", event => {
            event.preventDefault();
            event.stopPropagation();
            heldTagsOpen = false;
            tagHoldTimer = setTimeout(() => { heldTagsOpen = true; setTooltipTagsOpen(true); }, 180);
          });
          ["pointerup", "pointercancel", "pointerleave"].forEach(type => tagButton.addEventListener(type, event => {
            event.stopPropagation();
            if (tagHoldTimer) { clearTimeout(tagHoldTimer); tagHoldTimer = null; }
            if (heldTagsOpen) setTooltipTagsOpen(false);
          }));
          tagButton.addEventListener("click", event => {
            event.preventDefault();
            event.stopPropagation();
            if (heldTagsOpen) { heldTagsOpen = false; return; }
            setTooltipTagsOpen(!tagWrap.classList.contains("visible"));
          });
          actions.append(tagButton, tagWrap);
        }
        detail.appendChild(actions);
      }
      tooltip.append(title, detail);
      cancelHideTimer();
      if (isTouchMode) {
        tooltip.classList.add("touch-active");
        tooltip.classList.remove("pointer-on");
      } else {
        tooltip.classList.add("pointer-on");
        tooltip.classList.remove("touch-active");
      }
      tooltip.classList.add("visible");

      const gap = 10;
      const pad = 8;
      const tileBox = event.currentTarget.getBoundingClientRect();
      const tipBox = tooltip.getBoundingClientRect();
      const left = Math.min(Math.max(tileBox.left + tileBox.width / 2 - tipBox.width / 2, pad), window.innerWidth - tipBox.width - pad);
      const topAbove = tileBox.top - tipBox.height - gap;
      const topBelow = tileBox.bottom + gap;
      const top = topAbove >= pad ? topAbove : Math.min(topBelow, window.innerHeight - tipBox.height - pad);
      tooltip.style.left = `${left}px`;
      tooltip.style.top = `${Math.max(pad, top)}px`;

      if (LANG === "pt" && e.originalNote && synopsisNode) {
        const episodeKey = `ep_${e.episode || e.displayCode}`;
        translateSynopsis(episodeKey, e.originalNote).then(translated => {
          if (tooltip.classList.contains("visible") && synopsisNode.parentNode) {
            synopsisNode.textContent = `${T.synopsis}: ${translated || e.originalNote}`;
            const tipBox2 = tooltip.getBoundingClientRect();
            const left2 = Math.min(Math.max(tileBox.left + tileBox.width / 2 - tipBox2.width / 2, pad), window.innerWidth - tipBox2.width - pad);
            const topAbove2 = tileBox.top - tipBox2.height - gap;
            const topBelow2 = tileBox.bottom + gap;
            const top2 = topAbove2 >= pad ? topAbove2 : Math.min(topBelow2, window.innerHeight - tipBox2.height - pad);
            tooltip.style.left = `${left2}px`;
            tooltip.style.top = `${Math.max(pad, top2)}px`;
          }
        });
      }
    }
    let tipHideTimer = null;
    let tipShowTimer = null;
    let tooltipHovering = false;
    function cancelHideTimer() { if (tipHideTimer) { clearTimeout(tipHideTimer); tipHideTimer = null; } }
    function cancelShowTimer() { if (tipShowTimer) { clearTimeout(tipShowTimer); tipShowTimer = null; } }
    function scheduleTip(event, episode) {
      if (tooltipHovering) return;
      const target = event.currentTarget;
      cancelHideTimer();
      cancelShowTimer();
      tipShowTimer = setTimeout(() => {
        tipShowTimer = null;
        if (!tooltipHovering) showTip({ currentTarget: target }, episode, false);
      }, 150);
    }
    function hideTip(immediate) {
      cancelShowTimer();
      cancelHideTimer();
      if (immediate) {
        tooltip.classList.remove("visible", "touch-active", "pointer-on");
      } else {
        tipHideTimer = setTimeout(() => { tooltip.classList.remove("visible", "touch-active", "pointer-on"); tipHideTimer = null; }, 300);
      }
    }

    function renderTop5(matched) {
      const top5List = document.querySelector("#top5-list");
      top5List.textContent = "";
      if (!matched.length) { top5List.textContent = "--"; return; }
      const sorted = [...matched].sort((a, b) => b.rating - a.rating).slice(0, 5);
      sorted.forEach((e, i) => {
        const item = document.createElement("a"); item.className = "top5-item"; item.href = `#sub-${e.subSaga}`; item.title = e.title;
        const rank = document.createElement("span"); rank.className = "top5-rank"; rank.textContent = `${i + 1}.`;
        const dot = document.createElement("span"); dot.className = "top5-dot"; dot.style.background = ratingColor(e.rating);
        const code = document.createElement("span"); code.className = "top5-code"; code.textContent = e.displayCode;
        const score = document.createElement("span"); score.className = "top5-score"; score.textContent = e.rating.toFixed(1);
        item.append(rank, dot, code, score);
        top5List.appendChild(item);
      });
    }

    function buildJumpLink(saga, className) {
      const sagaEpisodes = episodes.filter(e => e.saga === saga.key);
      const selectedSagaEpisodes = sagaEpisodes.filter(matchesFilters);
      const average = selectedSagaEpisodes.length ? avg(selectedSagaEpisodes) : null;
      const link = document.createElement("a");
      link.className = className; link.href = `#saga-${saga.key}`; link.style.setProperty("--jump-color", average === null ? emptyRatingColor : ratingColor(average));
      link.innerHTML = `<span><i></i><b>${jumpLabel(saga)}</b></span><small>${average === null ? "--" : average.toFixed(1)} avg | ${selectedSagaEpisodes.length}/${sagaEpisodes.length}</small>`;
      return link;
    }

    function buildTopbarJumpLink(saga) {
      const sagaEpisodes = episodes.filter(e => e.saga === saga.key);
      const selectedSagaEpisodes = sagaEpisodes.filter(matchesFilters);
      const average = selectedSagaEpisodes.length ? avg(selectedSagaEpisodes) : null;
      const link = document.createElement("a");
      link.href = `#saga-${saga.key}`; link.style.setProperty("--jump-color", average === null ? emptyRatingColor : ratingColor(average));
      link.innerHTML = `<i></i>${jumpLabel(saga)}`;
      link.title = `${saga.label}: avg ${average === null ? "--" : average.toFixed(1)}, ${selectedSagaEpisodes.length}/${sagaEpisodes.length}`;
      return link;
    }

    function renderJumpList() {
      jumpList.textContent = "";
      const overlayGrid = document.querySelector("#jump-overlay-grid");
      if (overlayGrid) overlayGrid.textContent = "";
      const topbarJump = document.querySelector("#topbar-jump");
      if (topbarJump) topbarJump.textContent = "";
      for (const saga of sagas) {
        jumpList.appendChild(buildJumpLink(saga, "jump-link"));
        if (overlayGrid) overlayGrid.appendChild(buildJumpLink(saga, "overlay-jump-link"));
        if (topbarJump) topbarJump.appendChild(buildTopbarJumpLink(saga));
      }
    }

    // FAB jump overlay - full filter panel
    const jumpFab = document.querySelector("#jump-fab");
    const jumpOverlay = document.querySelector("#jump-overlay");
    const jumpOverlayClose = document.querySelector("#jump-overlay-close");
    const overlayRow1 = document.querySelector("#overlay-row1");
    const overlayRow2 = document.querySelector("#overlay-row2");
    const overlayTierRow = document.querySelector("#overlay-tier-row");
    const controlsRow1 = document.querySelector(".controls-row:first-child");
    const controlsRow2 = document.querySelector("#tier-legend");

    // Ids of elements to reparent from row1
    const row1Ids = ["type-filter","saga-filter","sub-saga-filter","sort-filter","reset","filler-only","canon-only","episodes-only","media-only","tag-filter","character-mode-control"];
    let overlayOpen = false;

    function moveFiltersToOverlay() {
      if (!overlayRow1) return;
      overlayRow1.textContent = "";
      row1Ids.forEach(id => {
        const el = document.getElementById(id);
        if (el) overlayRow1.appendChild(el);
      });
      // Move search wrap + dim label
      overlayRow2.textContent = "";
      const sw = document.querySelector(".search-wrap");
      if (sw) {
        overlayRow2.appendChild(sw);
        // Sync search value
        const overlayInput = sw.querySelector("input");
        if (overlayInput) overlayInput.value = searchEl.value;
      }
      const dimLabel = document.querySelector(".dim-label");
      if (dimLabel) overlayRow2.appendChild(dimLabel);
      // Move tier buttons
      if (overlayTierRow) {
        overlayTierRow.textContent = "";
        document.querySelectorAll(".tier-btn").forEach(btn => overlayTierRow.appendChild(btn));
      }
      overlayOpen = true;
      document.body.classList.add("overlay-open");
      // Lock body scroll (iOS fix: save scroll position, apply top offset)
      const scrollY = window.scrollY;
      document.body.style.top = `-${scrollY}px`;
      document.body.dataset.scrollY = scrollY;
    }

    function moveFiltersToTopbar() {
      if (!controlsRow1) return;
      // Move row1 elements back
      row1Ids.forEach(id => {
        const el = document.getElementById(id);
        if (el) controlsRow1.appendChild(el);
      });
      // Move search wrap + dim label back to tier-legend row
      if (controlsRow2) {
        const sw = document.querySelector(".search-wrap");
        const dimLabel = document.querySelector(".dim-label");
        // Prepend search and dim at start of controlsRow2
        if (sw) controlsRow2.insertBefore(sw, controlsRow2.firstChild);
        if (dimLabel) {
          // insert after search
          const swEl = controlsRow2.querySelector(".search-wrap");
          if (swEl && swEl.nextSibling) controlsRow2.insertBefore(dimLabel, swEl.nextSibling);
          else controlsRow2.appendChild(dimLabel);
        }
        // Move tier buttons back
        const existingTiers = document.querySelectorAll(".tier-btn");
        existingTiers.forEach(btn => controlsRow2.appendChild(btn));
      }
      overlayOpen = false;
      document.body.classList.remove("overlay-open");
      // Restore scroll position (iOS scroll lock fix)
      const savedScrollY = parseInt(document.body.dataset.scrollY || "0", 10);
      document.body.style.top = "";
      window.scrollTo(0, savedScrollY);
    }

    // FAB visibility: show only when topbar is not intersecting viewport
    const topbarEl = document.querySelector(".topbar");
    if (topbarEl && jumpFab && "IntersectionObserver" in window) {
      const obs = new IntersectionObserver(entries => {
        jumpFab.classList.toggle("fab-visible", !entries[0].isIntersecting);
      }, { threshold: 0 });
      obs.observe(topbarEl);
    } else if (jumpFab) {
      // Fallback: always show on mobile
      jumpFab.classList.add("fab-visible");
    }

    if (jumpFab && jumpOverlay) {
      jumpFab.addEventListener("click", () => {
        if (jumpOverlay.classList.contains("open")) {
          moveFiltersToTopbar();
          jumpOverlay.classList.remove("open");
        } else {
          moveFiltersToOverlay();
          jumpOverlay.classList.add("open");
        }
      });
      function closeOverlay() {
        if (overlayOpen) moveFiltersToTopbar();
        jumpOverlay.classList.remove("open");
      }
      jumpOverlayClose && jumpOverlayClose.addEventListener("click", closeOverlay);
      jumpOverlay.addEventListener("click", e => { if (e.target === jumpOverlay) closeOverlay(); });
      document.addEventListener("keydown", e => { if (e.key === "Escape") closeOverlay(); });
    }

    // URL hash state
    function saveHash() {
      const params = new URLSearchParams();
      const allTypes = Object.keys(CATEGORY_META);
      const selTypes = allTypes.filter(k => typeFilter.has(k));
      if (selTypes.length !== allTypes.length) params.set("types", selTypes.join(","));
      const allSagas = sagas.map(s => s.key);
      const selSagas = allSagas.filter(k => sagaFilter.has(k));
      if (selSagas.length !== allSagas.length) params.set("sagas", selSagas.join(","));
      const allSubs = subSagas.map(s => s.key);
      const selSubs = allSubs.filter(k => subSagaFilter.has(k));
      if (selSubs.length !== allSubs.length) params.set("subs", selSubs.join(","));
      const allTiers = ["cinema","awesome","great","good","regular","bad","garbage"];
      const selTiers = allTiers.filter(t => activeTiers.has(t));
      if (selTiers.length !== allTiers.length) params.set("tiers", selTiers.join(","));
      if (sortOrder !== "watch") params.set("sort", sortOrder);
      if (dimMode) params.set("dim", "1");
      if (characterMode !== "appears") params.set("char", characterMode);
      if (searchQuery) params.set("q", searchQuery);
      const str = params.toString();
      history.replaceState(null, "", str ? `#${str}` : location.pathname + location.search);
    }
    function loadHash() {
      const hash = location.hash.startsWith("#") ? location.hash.slice(1) : "";
      if (!hash) return;
      const params = new URLSearchParams(hash);
      if (params.has("types")) typeFilter.setSelected(params.get("types").split(",").filter(Boolean));
      if (params.has("sagas")) sagaFilter.setSelected(params.get("sagas").split(",").filter(Boolean));
      if (params.has("subs")) subSagaFilter.setSelected(params.get("subs").split(",").filter(Boolean));
      if (params.has("tiers")) {
        const tiers = params.get("tiers").split(",").filter(Boolean);
        setAllTiers(false);
        tiers.forEach(t => { activeTiers.add(t); const btn = document.querySelector(`.tier-btn[data-tier="${t}"]`); if (btn) { btn.classList.add("on"); btn.classList.remove("off"); } });
      }
      if (params.has("sort")) {
        sortOrder = params.get("sort");
        const labels = { "rating-desc": T.sortRatingDesc, "rating-asc": T.sortRatingAsc, "watch": T.sortWatchOrder };
        sortLabelEl.textContent = labels[sortOrder] || T.sortWatchOrder;
        sortMenuEl.querySelectorAll(".sort-option").forEach(el => el.classList.toggle("selected", el.dataset.sort === sortOrder));
      }
      dimMode = params.get("dim") === "1";
      document.querySelector("#dim-toggle").checked = dimMode;
      characterMode = params.get("char") === "focused" ? "focused" : "appears";
      characterModeEl.value = characterMode;
      if (params.has("q")) { updateSearchQuery(params.get("q"), "exact"); searchEl.value = searchQuery; }
    }

    function render() {
      const shown = activeEpisodes();
      output.textContent = "";
      renderJumpList();
      if (!shown.length && !dimMode) {
        document.querySelector("#count").textContent = "0"; document.querySelector("#average").textContent = "--";
        renderTop5([]);
        status.textContent = "";
      } else {
        const matched = dimMode ? episodes.filter(matchesFilters) : shown;
        document.querySelector("#count").textContent = matched.length;
        document.querySelector("#average").textContent = matched.length ? avg(matched).toFixed(2) : "--";
        renderTop5(matched);
        status.textContent = "";
      }

      for (const saga of sagas) {
        const sagaEpisodes = episodes.filter(e => e.saga === saga.key).sort((a, b) => a.sortKey - b.sortKey);
        const selectedSagaEpisodes = sagaEpisodes.filter(matchesFilters);
        // In dim mode show saga even if 0 selected; in normal mode skip if nothing selected
        if (!dimMode && selectedSagaEpisodes.length === 0) continue;
        const section = document.createElement("section"); section.className = "saga"; section.id = `saga-${saga.key}`; section.style.setProperty("--saga-color", selectedSagaEpisodes.length ? ratingColor(avg(selectedSagaEpisodes)) : emptyRatingColor);

        // Build saga header with sparkline
        const header = document.createElement("header"); header.className = "saga-header";
        const left = document.createElement("div"); left.className = "saga-header-left";
        const titleDiv = document.createElement("div"); titleDiv.className = "saga-title";
        titleDiv.innerHTML = `<i></i>${saga.label} (avg ${avgText(selectedSagaEpisodes, 1)})`;
        const sparkline = document.createElement("div"); sparkline.className = "saga-sparkline";
        for (const ep of sagaEpisodes) {
          const matches = matchesFilters(ep);
          const bar = document.createElement("div"); bar.className = "saga-sparkline-bar";
          if (matches) {
            bar.style.background = ratingColor(ep.rating);
          } else {
            bar.classList.add("bar-dimmed"); // gray, shorter - always shown even when dim is off
          }
          sparkline.appendChild(bar);
        }
        left.append(titleDiv, sparkline);
        const meta = document.createElement("div"); meta.className = "saga-meta";
        meta.textContent = dimMode
          ? `${selectedSagaEpisodes.length}/${sagaEpisodes.length} selected | ${dominantKind(selectedSagaEpisodes)}`
          : `${selectedSagaEpisodes.length} shown | ${dominantKind(selectedSagaEpisodes)}`;
        header.append(left, meta);
        section.appendChild(header);
        const runs = [];
        for (const episode of sagaEpisodes) {
          const last = runs[runs.length - 1];
          if (last && last.sub.key === episode.subSaga) last.episodes.push(episode);
          else runs.push({ sub: subSagaMeta[episode.subSaga], episodes: [episode] });
        }
        // Build display runs: in non-dim mode, skip runs with no matching episodes and
        // merge consecutive runs of the same sub-saga key (even if separated by hidden runs).
        let mergedRuns;
        if (dimMode) {
          mergedRuns = runs;
        } else {
          mergedRuns = [];
          for (const run of runs) {
            const selectedCount = run.episodes.filter(matchesFilters).length;
            if (selectedCount === 0) continue; // skip hidden runs entirely
            const prev = mergedRuns[mergedRuns.length - 1];
            if (prev && prev.sub.key === run.sub.key) {
              prev.episodes.push(...run.episodes);
            } else {
              mergedRuns.push({ sub: run.sub, episodes: [...run.episodes] });
            }
          }
        }
        for (const run of mergedRuns) {
          const sub = run.sub;
          const subEpisodes = run.episodes; // always watch-order for structure
          if (!subEpisodes.length) continue;
          const selectedSubEpisodes = subEpisodes.filter(matchesFilters);
          // In normal mode, hide sub-sagas with no matching episodes
          if (!dimMode && selectedSubEpisodes.length === 0) continue;
          // In normal mode, render only matching tiles; in dim mode render all - but always apply sort
          const baseEpisodes = dimMode ? subEpisodes : selectedSubEpisodes;
          const renderEpisodes = sortEpisodes(baseEpisodes);
          const group = document.createElement("div"); group.className = "sub-saga"; group.id = `sub-${sub.key}`; group.style.setProperty("--sub-saga-color", selectedSubEpisodes.length ? ratingColor(avg(selectedSubEpisodes)) : emptyRatingColor);
          group.innerHTML = `<div class="sub-head"><div class="sub-title"><i></i><h3>${sub.label} (avg ${avgText(selectedSubEpisodes, 1)})</h3></div><span>${selectedSubEpisodes.length}/${subEpisodes.length} selected | ${sub.kind}</span></div><div class="episode-grid"></div>`;
          const grid = group.querySelector(".episode-grid");
          for (const episode of renderEpisodes) {
            const tile = document.createElement("button"); tile.className = "tile"; tile.type = "button";
            tile.style.setProperty("--rating-color", ratingColor(episode.rating)); tile.style.setProperty("--text-color", ratingTextColor(episode.rating)); tile.style.setProperty("--episode-text-color", episodeTextColor(episode.rating)); tile.style.setProperty("--text-stroke-color", textStrokeColor(episode.rating)); tile.style.setProperty("--type-color", CATEGORY_META[episode.category].color);
            if (!matchesFilters(episode)) tile.classList.add("dimmed");
            tile.innerHTML = `<svg class=\"tile-svg\" viewBox=\"0 0 58 29\" aria-hidden=\"true\"><rect class=\"tile-rect\" x=\"0\" y=\"0\" width=\"58\" height=\"29\" rx=\"3\" ry=\"3\"></rect><text class=\"epno\" x=\"4\" y=\"9\">${episode.displayCode}</text><text class=\"score\" x=\"27\" y=\"22\">${episode.rating.toFixed(1)}</text></svg>`;
            tile.setAttribute("aria-label", `${episode.displayCode}, ${episode.title}, rating ${episode.rating.toFixed(1)}. Open ${episode.ratingSource} source`);
            tile.addEventListener("mouseenter", event => scheduleTip(event, episode));
            tile.addEventListener("focus", event => showTip(event, episode, false));
            tile.addEventListener("mouseleave", () => { cancelShowTimer(); hideTip(false); });
            tile.addEventListener("blur", () => hideTip(true));
            tile.addEventListener("click", () => { if (!isTouchDevice) openSource(episode); });
            tile.addEventListener("touchstart", event => {
              event.preventDefault();
              if (tooltip.classList.contains("visible") && lastTappedEpisode === episode) {
                // Tap on same tile with tooltip open: close it
                hideTip(true);
                lastTappedEpisode = null;
              } else {
                // First tap (or tapping a different tile): show tooltip
                lastTappedEpisode = episode;
                showTip({ currentTarget: event.currentTarget }, episode, true);
              }
            }, { passive: false });
            grid.appendChild(tile);
          }
          section.appendChild(group);
        }
        output.appendChild(section);
      }
    }

    document.querySelector("#reset").addEventListener("click", () => {
      typeFilter.selectAll(); sagaFilter.selectAll(); subSagaFilter.selectAll();
      setAllTiers(true);
      sortOrder = "watch"; sortLabelEl.textContent = T.sortWatchOrder;
      sortMenuEl.querySelectorAll(".sort-option").forEach(el => el.classList.toggle("selected", el.dataset.sort === "watch"));
      document.querySelector("#dim-toggle").checked = true; dimMode = true;
      characterMode = "appears"; characterModeEl.value = characterMode;
      searchEl.value = ""; updateSearchQuery("", "exact");
      activePreset = null; updatePresetButtons();
      history.replaceState(null, "", location.pathname + location.search);
      render();
    });

    // Preset filter buttons: track active state, toggle off on second click
    let activePreset = null;
    const PRESETS = {
      "filler-only":    { types: ["filler"] },
      "canon-only":     { types: ["manga", "mixed", "anime"] },
      "episodes-only":  { types: ["manga", "mixed", "filler", "anime"] },
      "media-only":     { types: ["movie", "special", "recap", "ova", "short"] },
    };
    function updatePresetButtons() {
      Object.keys(PRESETS).forEach(id => {
        const btn = document.getElementById(id);
        if (btn) btn.classList.toggle("active", activePreset === id);
      });
    }
    Object.keys(PRESETS).forEach(id => {
      document.getElementById(id).addEventListener("click", () => {
        if (activePreset === id) {
          // Toggle off: reset types to all
          typeFilter.selectAll(); sagaFilter.selectAll(); subSagaFilter.selectAll();
          activePreset = null;
        } else {
          typeFilter.setSelected(PRESETS[id].types);
          sagaFilter.selectAll(); subSagaFilter.selectAll();
          activePreset = id;
        }
        updatePresetButtons();
        saveHash(); render();
      });
    });
    loadHash();
    applyI18n();
    render();
  </script>
</body>
</html>
'@

$html = $html.Replace('__EPISODES_JSON__', $episodesJson).Replace('__CATEGORY_SUMMARY_JSON__', $categorySummaryJson).Replace('__SAGAS_JSON__', $sagasJson).Replace('__SUB_SAGAS_JSON__', $subSagasJson).Replace('__APPEARANCE_AUDITS_JSON__', $appearanceAuditsJson).Replace('__SAGA_SUMMARY_JSON__', $sagaSummaryJson).Replace('__SUB_SAGA_SUMMARY_JSON__', $subSagaSummaryJson)
[System.IO.File]::WriteAllText($outputPath, $html, [System.Text.UTF8Encoding]::new($false))

[pscustomobject]@{ Output = $outputPath; Mode = 'compact-saga-grid' } | ConvertTo-Json

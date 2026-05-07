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
      $episodeMeta | Add-Member -NotePropertyName $key -NotePropertyValue ([pscustomobject]@{ title = $item.title; aired = (Get-DateOnly $item.aired) }) -Force
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
    $episodeMeta | Add-Member -NotePropertyName $key -NotePropertyValue ([pscustomobject]@{ title = $episode.title; aired = $null }) -Force
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
    .stat-card,.jump-card { border:1px solid var(--line); border-radius:11px; background:rgba(24,28,37,.82); padding:5px 7px; }
    .stat-card { display:flex; align-items:baseline; justify-content:space-between; gap:7px; }
    .stat-card strong { display:block; font-size:.8rem; letter-spacing:-.04em; } .stat-card span { color:var(--muted); font-size:.58rem; text-align:right; }
    .jump-card { min-height:0; overflow:hidden; }
    .jump-card h2 { margin:0 0 4px; font-size:.56rem; letter-spacing:.12em; text-transform:uppercase; color:var(--muted); }
    .jump-list { display:grid; gap:2px; max-height:calc(100vh - 250px); overflow:auto; padding-right:2px; scrollbar-width:thin; }
    .jump-link { display:flex; align-items:center; justify-content:space-between; gap:7px; border:1px solid transparent; border-radius:7px; color:var(--text); text-decoration:none; padding:3px 5px; background:rgba(255,255,255,.035); font-size:.62rem; }
    .jump-link:hover,.jump-link:focus-visible { border-color:rgba(125,211,252,.38); background:rgba(125,211,252,.12); outline:0; }
    .jump-link span:first-child { display:flex; align-items:center; gap:5px; min-width:0; }
    .jump-link i { flex:0 0 auto; width:7px; height:7px; border-radius:999px; background:var(--jump-color); box-shadow:0 0 9px var(--jump-color); }
    .jump-link b { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-weight:650; }
    .jump-link small { color:var(--muted); font-size:.58rem; white-space:nowrap; }
    .side-note { color:var(--muted); font-size:.58rem; line-height:1.24; margin:0; }
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
    .saga { scroll-margin-top:86px; border:1px solid var(--line); border-radius:16px; background:rgba(24,28,37,.72); overflow:hidden; margin-bottom:12px; box-shadow:0 14px 36px rgba(0,0,0,.22); }
    .saga-header { display:flex; justify-content:space-between; gap:9px; align-items:baseline; padding:10px 12px; border-bottom:1px solid var(--line); background:linear-gradient(90deg,color-mix(in srgb,var(--saga-color) 18%,transparent),rgba(255,255,255,.025)); }
    .saga-title { display:flex; align-items:center; gap:7px; font-size:.8rem; font-weight:800; }
    .saga-title i { width:9px; height:9px; border-radius:999px; background:var(--saga-color); box-shadow:0 0 12px var(--saga-color); }
    .saga-meta { color:var(--muted); font-size:.68rem; white-space:nowrap; }
    .sub-saga { padding:9px 12px 11px; border-bottom:1px solid rgba(255,255,255,.055); }
    .sub-saga:last-child { border-bottom:0; }
    .sub-head { display:flex; justify-content:space-between; gap:9px; align-items:baseline; margin-bottom:6px; }
    .sub-title { display:flex; align-items:center; gap:6px; }
    .sub-title i { width:7px; height:7px; border-radius:999px; background:var(--sub-saga-color); box-shadow:0 0 10px var(--sub-saga-color); }
    .sub-head h3 { margin:0; font-size:.72rem; } .sub-head span { color:var(--muted); font-size:.62rem; }
    .episode-grid { display:grid; grid-template-columns:repeat(auto-fill,48px); gap:2px; }
    .tile { position:relative; width:48px; height:29px; border:0; border-radius:0; background:transparent; cursor:pointer; overflow:hidden; color:var(--text-color); font:inherit; padding:0; box-shadow:none; transition:transform .13s ease, filter .13s ease, opacity .13s ease; }
    .tile:hover,.tile:focus-visible { transform:translateY(-1px); filter:saturate(1.08) brightness(1.03); outline:2px solid rgba(255,255,255,.32); z-index:2; }
    .tile.dimmed { background:#343946; color:#8d96a8; opacity:.43; filter:grayscale(1) saturate(.2); box-shadow:none; }
    .tile.dimmed::after { background:#6b7280; }
    .tile.dimmed .epno { color:rgba(255,255,255,.28); }
    .tile.dimmed .score { color:#9aa3b5; text-shadow:none; }
    .tile::after { display:none; }
    .tile-svg { display:block; width:100%; height:100%; }
    .tile-rect { fill:var(--rating-color); }
    .score { fill:var(--text-color); stroke:var(--text-stroke-color); stroke-width:1.15px; paint-order:stroke fill; font-family:var(--font-ui); font-size:17.3px; font-weight:700; opacity:.96; text-anchor:start; dominant-baseline:middle; }
    .epno { fill:var(--episode-text-color); stroke:var(--text-stroke-color); stroke-width:.65px; paint-order:stroke fill; font-family:var(--font-ui); font-size:9.7px; font-weight:700; opacity:.9; text-anchor:start; dominant-baseline:middle; }
    .tooltip { position:fixed; max-width:310px; pointer-events:none; border:1px solid rgba(255,255,255,.14); border-radius:11px; background:rgba(10,13,19,.94); padding:9px 10px; box-shadow:0 14px 38px rgba(0,0,0,.45); opacity:0; transition:opacity 120ms ease; z-index:20; }
    .tooltip.visible { opacity:1; } .tooltip strong { display:block; margin-bottom:4px; font-size:.78rem; } .tooltip span { color:var(--muted); font-size:.66rem; line-height:1.32; }
    .empty { border:1px dashed var(--line); border-radius:14px; color:var(--muted); padding:18px; text-align:center; background:rgba(255,255,255,.025); }
    @media (min-width:901px) { main { width:min(1760px,calc(100% - 108px)); } }
    @media (max-width:900px) { .layout { grid-template-columns:1fr; } aside { position:static; grid-template-columns:1fr 1fr; max-height:none; } .poster { min-height:90px; } .jump-card { grid-column:1/-1; } .jump-list { display:flex; max-height:none; overflow:auto; padding-bottom:2px; scrollbar-width:thin; } .jump-link { min-width:126px; } .saga { scroll-margin-top:14px; } }
    @media (max-width:640px) { main { width:min(100% - 20px,1760px); padding-top:12px; } aside { grid-template-columns:1fr; } .topbar { position:static; } .episode-grid { grid-template-columns:repeat(auto-fill,48px); } .saga-header,.sub-head { display:grid; } }
  </style>
</head>
<body>
  <main>
    <div class="layout">
      <aside>
        <section class="poster"><h1>One Piece Ratings</h1><p>Grouped by saga and sub-saga. Filter without covering the chart.</p></section>
        <section class="stat-card"><strong id="count">--</strong><span>shown entries</span></section>
        <section class="stat-card"><strong id="average">--</strong><span>average rating</span></section>
        <section class="stat-card"><strong id="best">--</strong><span>highest rated</span></section>
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
            </div>
            <div class="controls-row">
              <div class="search-wrap"><svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2"><circle cx="9" cy="9" r="6"/><path d="m15 15 3 3"/></svg><input id="search" type="search" placeholder="Search titles..." autocomplete="off"></div>
              <label class="dim-label" title="Keep non-matching tiles visible but grayed out"><input type="checkbox" id="dim-toggle"> Dim non-matching</label>
              <div class="sort-filter" id="sort-filter"><button class="filter-toggle" type="button"><b>Sort</b><span class="label" id="sort-label">Watch order</span></button><div class="filter-menu sort-menu"></div></div>
            </div>
          </div>
          <div class="legend" id="tier-legend" aria-label="Rating tier filter">
            <button class="tier-btn on" type="button" data-tier="cinema" style="--c:#1DA1F2"><i class="dot" style="--c:#1DA1F2"></i>Absolute Cinema 9.6+</button>
            <button class="tier-btn on" type="button" data-tier="awesome" style="--c:#186A3B"><i class="dot" style="--c:#186A3B"></i>Awesome 8.6–9.5</button>
            <button class="tier-btn on" type="button" data-tier="great" style="--c:#28B463"><i class="dot" style="--c:#28B463"></i>Great 8.0–8.5</button>
            <button class="tier-btn on" type="button" data-tier="good" style="--c:#F4D03F"><i class="dot" style="--c:#F4D03F"></i>Good 7.0–7.9</button>
            <button class="tier-btn on" type="button" data-tier="regular" style="--c:#F39C12"><i class="dot" style="--c:#F39C12"></i>Regular 6.0–6.9</button>
            <button class="tier-btn on" type="button" data-tier="bad" style="--c:#E74C3C"><i class="dot" style="--c:#E74C3C"></i>Bad 5.0–5.9</button>
            <button class="tier-btn on" type="button" data-tier="garbage" style="--c:#633974"><i class="dot" style="--c:#633974"></i>Garbage &lt;5.0</button>
          </div>
          <div id="status" class="status" hidden></div>
        </div>
        <div id="saga-output"></div>
      </section>
    </div>
  </main>
  <div id="tooltip" class="tooltip" role="status" aria-live="polite"></div>
  <script id="episode-data" type="application/json">__EPISODES_JSON__</script>
  <script id="category-summary" type="application/json">__CATEGORY_SUMMARY_JSON__</script>
  <script id="saga-data" type="application/json">__SAGAS_JSON__</script>
  <script id="sub-saga-data" type="application/json">__SUB_SAGAS_JSON__</script>
  <script id="saga-summary" type="application/json">__SAGA_SUMMARY_JSON__</script>
  <script id="sub-saga-summary" type="application/json">__SUB_SAGA_SUMMARY_JSON__</script>
  <script>
    const CATEGORY_META = { manga:{label:"Manga Canon",color:"#22c55e"}, mixed:{label:"Mixed Canon/Filler",color:"#f59e0b"}, filler:{label:"Filler",color:"#ef4444"}, anime:{label:"Anime Canon",color:"#38bdf8"}, movie:{label:"Movie",color:"#a855f7"}, special:{label:"TV Special",color:"#06b6d4"}, recap:{label:"Recap / Remake",color:"#f97316"}, ova:{label:"OVA",color:"#ec4899"}, short:{label:"Short",color:"#84cc16"} };
    const episodes = JSON.parse(document.querySelector("#episode-data").textContent);
    const sagas = JSON.parse(document.querySelector("#saga-data").textContent);
    const subSagas = JSON.parse(document.querySelector("#sub-saga-data").textContent);
    const sagaMeta = Object.fromEntries(sagas.map(s => [s.key, s]));
    const subSagaMeta = Object.fromEntries(subSagas.map(s => [s.key, s]));
    const output = document.querySelector("#saga-output"), jumpList = document.querySelector("#saga-jump-list"), tooltip = document.querySelector("#tooltip"), status = document.querySelector("#status");
    const typeFilter = createMultiFilter("type-filter", Object.entries(CATEGORY_META).map(([value, meta]) => ({ value, label: meta.label })), "All types");
    const sagaFilter = createMultiFilter("saga-filter", sagas.map(s => ({ value: s.key, label: s.label })), "All sagas");
    const subSagaFilter = createMultiFilter("sub-saga-filter", subSagas.map(s => ({ value: s.key, label: s.label })), "All sub-sagas");

    function createMultiFilter(id, items, allLabel) {
      const root = document.querySelector(`#${id}`), menu = root.querySelector(".filter-menu"), label = root.querySelector(".label"), toggle = root.querySelector(".filter-toggle");
      const selected = new Set(items.map(item => item.value));
      for (const item of items) {
        const option = document.createElement("label"); option.className = "filter-option";
        const input = document.createElement("input"); input.type = "checkbox"; input.value = item.value; input.checked = true;
        const name = document.createElement("span"); name.textContent = item.label;
        option.append(input, name);
        input.addEventListener("change", event => { event.target.checked ? selected.add(item.value) : selected.delete(item.value); updateLabel(); render(); });
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
      toggle.addEventListener("click", event => { event.stopPropagation(); document.querySelectorAll(".multi-filter.open, .sort-filter.open").forEach(open => { if (open !== root) open.classList.remove("open"); }); root.classList.toggle("open"); });
      updateLabel();
      return { has: value => selected.has(value), values: () => [...selected], setSelected, selectAll: () => setSelected(items.map(item => item.value)), clear: () => setSelected([]) };
    }

    function closeFilters() { document.querySelectorAll(".multi-filter.open, .sort-filter.open").forEach(open => open.classList.remove("open")); }
    document.addEventListener("click", closeFilters);
    document.addEventListener("keydown", event => { if (event.key === "Escape") { closeFilters(); hideTip(); } });
    document.querySelectorAll(".filter-menu, .sort-menu").forEach(menu => menu.addEventListener("click", event => event.stopPropagation()));

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
        render();
      });
    });
    function setAllTiers(on) {
      TIERS.forEach(t => { if (on) activeTiers.add(t.key); else activeTiers.delete(t.key); });
      tierBtns.forEach(btn => { btn.classList.toggle("on", on); btn.classList.toggle("off", !on); });
    }

    // Sort state — custom dropdown
    let sortOrder = "watch";
    const sortOptions = [
      { value: "watch", label: "Watch order" },
      { value: "rating-desc", label: "Rating \u2193" },
      { value: "rating-asc", label: "Rating \u2191" }
    ];
    const sortFilterEl = document.querySelector("#sort-filter");
    const sortMenuEl = sortFilterEl.querySelector(".sort-menu");
    const sortLabelEl = document.querySelector("#sort-label");
    const sortToggleEl = sortFilterEl.querySelector(".filter-toggle");
    sortOptions.forEach(opt => {
      const item = document.createElement("div");
      item.className = "sort-option" + (opt.value === sortOrder ? " selected" : "");
      item.textContent = opt.label;
      item.addEventListener("click", () => {
        sortOrder = opt.value;
        sortLabelEl.textContent = opt.label;
        sortMenuEl.querySelectorAll(".sort-option").forEach(el => el.classList.remove("selected"));
        item.classList.add("selected");
        sortFilterEl.classList.remove("open");
        render();
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
    let dimMode = false;
    document.querySelector("#dim-toggle").addEventListener("change", e => { dimMode = e.target.checked; render(); });

    // Search state
    let searchQuery = "";
    const searchEl = document.querySelector("#search");
    searchEl.addEventListener("input", e => { searchQuery = e.target.value.trim().toLowerCase(); render(); });
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
      if (searchQuery && !e.title.toLowerCase().includes(searchQuery) && !e.displayCode.toLowerCase().includes(searchQuery)) return false;
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
    function showTip(event, e) {
      const c = CATEGORY_META[e.category], s = sagaMeta[e.saga], ss = subSagaMeta[e.subSaga];
      tooltip.textContent = "";
      const title = document.createElement("strong");
      title.textContent = `${entryLabel(e)}: ${e.title}`;
      const detail = document.createElement("span");
      appendText(detail, `${c.label} / ${s.label} / ${ss.label}`);
      appendBreak(detail);
      appendText(detail, `Rating ${e.rating.toFixed(1)} \u00B7 ${sourceLabel(e)}`);
      if (e.aired) { appendBreak(detail); appendText(detail, `Aired/released: ${e.aired}`); }
      if (e.placement) { appendBreak(detail); appendText(detail, e.placement); }
      if (e.originalNote) { appendBreak(detail); appendText(detail, `Synopsis: ${e.originalNote}`); }
      const safeUrl = safeSourceUrl(e.sourceUrl);
      if (safeUrl) {
        appendBreak(detail, 2);
        const source = document.createElement("a");
        source.className = "source";
        source.href = safeUrl;
        source.rel = "noopener noreferrer";
        source.textContent = e.ratingSource;
        detail.appendChild(source);
      }
      tooltip.append(title, detail);
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
    }
    function hideTip() { tooltip.classList.remove("visible"); }

    function renderJumpList() {
      jumpList.textContent = "";
      for (const saga of sagas) {
        const sagaEpisodes = episodes.filter(e => e.saga === saga.key);
        const selectedSagaEpisodes = sagaEpisodes.filter(matchesFilters);
        const average = selectedSagaEpisodes.length ? avg(selectedSagaEpisodes) : null;
        const link = document.createElement("a");
        link.className = "jump-link"; link.href = `#saga-${saga.key}`; link.style.setProperty("--jump-color", average === null ? emptyRatingColor : ratingColor(average));
        link.innerHTML = `<span><i></i><b>${jumpLabel(saga)}</b></span><small>${average === null ? "--" : average.toFixed(1)} avg | ${selectedSagaEpisodes.length}/${sagaEpisodes.length}</small>`;
        jumpList.appendChild(link);
      }
    }

    function render() {
      const shown = activeEpisodes();
      output.textContent = "";
      renderJumpList();
      if (!shown.length && !dimMode) {
        document.querySelector("#count").textContent = "0"; document.querySelector("#average").textContent = "--"; document.querySelector("#best").textContent = "--";
        status.textContent = "";
      } else {
        const matched = dimMode ? episodes.filter(matchesFilters) : shown;
        const best = matched.length ? matched.reduce((top, e) => e.rating > top.rating ? e : top, matched[0]) : null;
        document.querySelector("#count").textContent = matched.length;
        document.querySelector("#average").textContent = matched.length ? avg(matched).toFixed(2) : "--";
        document.querySelector("#best").textContent = best ? `${best.displayCode} (${best.rating.toFixed(1)})` : "--";
        status.textContent = "";
      }

      for (const saga of sagas) {
        const sagaEpisodes = episodes.filter(e => e.saga === saga.key).sort((a, b) => a.sortKey - b.sortKey);
        const selectedSagaEpisodes = sagaEpisodes.filter(matchesFilters);
        // In dim mode show saga even if 0 selected; in normal mode skip if nothing selected
        if (!dimMode && selectedSagaEpisodes.length === 0) continue;
        const section = document.createElement("section"); section.className = "saga"; section.id = `saga-${saga.key}`; section.style.setProperty("--saga-color", selectedSagaEpisodes.length ? ratingColor(avg(selectedSagaEpisodes)) : emptyRatingColor);
        section.innerHTML = `<header class="saga-header"><div class="saga-title"><i></i>${saga.label} (avg ${avgText(selectedSagaEpisodes, 1)})</div><div class="saga-meta">${selectedSagaEpisodes.length}/${sagaEpisodes.length} selected | ${dominantKind(selectedSagaEpisodes)}</div></header>`;
        const runs = [];
        for (const episode of sagaEpisodes) {
          const last = runs[runs.length - 1];
          if (last && last.sub.key === episode.subSaga) last.episodes.push(episode);
          else runs.push({ sub: subSagaMeta[episode.subSaga], episodes: [episode] });
        }
        for (const run of runs) {
          const sub = run.sub;
          const subEpisodes = dimMode ? run.episodes : sortEpisodes(run.episodes);
          if (!subEpisodes.length) continue;
          const selectedSubEpisodes = subEpisodes.filter(matchesFilters);
          // In normal mode, hide sub-sagas with no matching episodes
          if (!dimMode && selectedSubEpisodes.length === 0) continue;
          // In normal mode, render only matching tiles; in dim mode render all
          const renderEpisodes = dimMode ? subEpisodes : selectedSubEpisodes;
          if (!renderEpisodes.length) continue;
          const group = document.createElement("div"); group.className = "sub-saga"; group.style.setProperty("--sub-saga-color", selectedSubEpisodes.length ? ratingColor(avg(selectedSubEpisodes)) : emptyRatingColor);
          group.innerHTML = `<div class="sub-head"><div class="sub-title"><i></i><h3>${sub.label} (avg ${avgText(selectedSubEpisodes, 1)})</h3></div><span>${selectedSubEpisodes.length}/${subEpisodes.length} selected | ${sub.kind}</span></div><div class="episode-grid"></div>`;
          const grid = group.querySelector(".episode-grid");
          for (const episode of renderEpisodes) {
            const tile = document.createElement("button"); tile.className = "tile"; tile.type = "button";
            tile.style.setProperty("--rating-color", ratingColor(episode.rating)); tile.style.setProperty("--text-color", ratingTextColor(episode.rating)); tile.style.setProperty("--episode-text-color", episodeTextColor(episode.rating)); tile.style.setProperty("--text-stroke-color", textStrokeColor(episode.rating)); tile.style.setProperty("--type-color", CATEGORY_META[episode.category].color);
            if (!matchesFilters(episode)) tile.classList.add("dimmed");
            tile.innerHTML = `<svg class="tile-svg" viewBox="0 0 58 34" aria-hidden="true"><rect class="tile-rect" x="0" y="0" width="58" height="34" rx="3" ry="3"></rect><text class="epno" x="4" y="10">${episode.displayCode}</text><text class="score" x="27" y="24">${episode.rating.toFixed(1)}</text></svg>`;
            tile.setAttribute("aria-label", `${episode.displayCode}, ${episode.title}, rating ${episode.rating.toFixed(1)}. Open ${episode.ratingSource} source`);
            tile.addEventListener("mousemove", event => showTip(event, episode)); tile.addEventListener("focus", event => showTip(event, episode)); tile.addEventListener("mouseleave", hideTip); tile.addEventListener("blur", hideTip); tile.addEventListener("click", () => openSource(episode));
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
      sortOrder = "watch"; sortLabelEl.textContent = "Watch order";
      sortMenuEl.querySelectorAll(".sort-option").forEach(el => el.classList.toggle("selected", el.textContent === "Watch order"));
      document.querySelector("#dim-toggle").checked = false; dimMode = false;
      searchEl.value = ""; searchQuery = "";
      render();
    });
    document.querySelector("#filler-only").addEventListener("click", () => { typeFilter.setSelected(["filler"]); sagaFilter.selectAll(); subSagaFilter.selectAll(); render(); });
    document.querySelector("#canon-only").addEventListener("click", () => { typeFilter.setSelected(["manga", "mixed", "anime"]); sagaFilter.selectAll(); subSagaFilter.selectAll(); render(); });
    document.querySelector("#episodes-only").addEventListener("click", () => { typeFilter.setSelected(["manga", "mixed", "filler", "anime"]); sagaFilter.selectAll(); subSagaFilter.selectAll(); render(); });
    document.querySelector("#media-only").addEventListener("click", () => { typeFilter.setSelected(["movie", "special", "recap", "ova", "short"]); sagaFilter.selectAll(); subSagaFilter.selectAll(); render(); });
    render();
  </script>
</body>
</html>
'@

$html = $html.Replace('__EPISODES_JSON__', $episodesJson).Replace('__CATEGORY_SUMMARY_JSON__', $categorySummaryJson).Replace('__SAGAS_JSON__', $sagasJson).Replace('__SUB_SAGAS_JSON__', $subSagasJson).Replace('__SAGA_SUMMARY_JSON__', $sagaSummaryJson).Replace('__SUB_SAGA_SUMMARY_JSON__', $subSagaSummaryJson)
[System.IO.File]::WriteAllText($outputPath, $html, [System.Text.UTF8Encoding]::new($false))

[pscustomobject]@{ Output = $outputPath; Mode = 'compact-saga-grid' } | ConvertTo-Json

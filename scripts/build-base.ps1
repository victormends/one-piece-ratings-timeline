param(
  [switch]$RefreshRatings
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $repoRoot 'data'
$outputPath = Join-Path $dataDir 'base-episodes.html'
$sourcePath = Join-Path $dataDir 'seriesgraph-season-ratings.json'
$sourceUrl = 'https://seriesgraph.com/api/shows/37854/season-ratings'

function Expand-Ranges([string]$rangeText) {
  $set = [ordered]@{}
  foreach ($part in ($rangeText -split ',')) {
    $value = $part.Trim()
    if (-not $value) { continue }
    if ($value -match '^(\d+)\s*-\s*(\d+)$') {
      for ($episode = [int]$Matches[1]; $episode -le [int]$Matches[2]; $episode++) { $set[[string]$episode] = $true }
    } elseif ($value -match '^\d+$') {
      $set[[string][int]$value] = $true
    } else {
      throw "Invalid range token: $value"
    }
  }
  return [int[]]($set.Keys | ForEach-Object { [int]$_ } | Sort-Object)
}

function New-SubSaga($key, $saga, $label, $ranges, $kind) {
  [pscustomobject]@{ key = $key; saga = $saga; label = $label; ranges = $ranges; kind = $kind }
}

if ($RefreshRatings -or -not (Test-Path -LiteralPath $sourcePath)) {
  $sourceContent = Invoke-WebRequest -Uri $sourceUrl -UseBasicParsing | Select-Object -ExpandProperty Content
  Set-Content -LiteralPath $sourcePath -Value $sourceContent -Encoding UTF8
  $json = $sourceContent | ConvertFrom-Json
} else {
  $json = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
}

$episodeMap = @{}
foreach ($season in $json) {
  foreach ($episode in $season.episodes) {
    if ($null -eq $episode.vote_average -or $null -eq $episode.num_votes) { continue }
    $episodeMap[[int]$episode.episode_number] = $episode
  }
}
$maxEpisode = ($episodeMap.Keys | Measure-Object -Maximum).Maximum

$mangaRanges = '1-44, 48-49, 52-53, 62-67, 70-92, 94-97, 100, 103-130, 144-195, 207-212, 217-219, 227-278, 284-290, 293-302, 304-316, 320-325, 337-353, 355-381, 385-405, 408-417, 422-425, 430-452, 459-488, 490-491, 493-496, 500-505, 507-519, 521-541, 543-573, 579-589, 591-624, 629-632, 634-652, 654-656, 658-678, 680-689, 691-730, 732-736, 739-746, 752-774, 776, 779, 783-788, 790-802, 804-806, 808-877, 880, 886, 891-894, 897-906, 908-923, 925-987, 990, 992-1028, 1031-1083, 1085-1156'
if ($maxEpisode -gt 1156) { $mangaRanges = "$mangaRanges, 1157-$maxEpisode" }

$categoryText = [ordered]@{
  manga = $mangaRanges
  mixed = '45-47, 61, 68-69, 101, 226, 354, 421, 489, 520, 574, 625, 628, 633, 653, 657, 679, 690, 731, 738, 751, 777-778, 789, 803, 807, 878-879, 881-885, 887-890, 924, 988-989, 991'
  filler = '54-60, 98-99, 102, 131-143, 196-206, 220-225, 279-283, 291-292, 303, 317-319, 326-336, 382-384, 406-407, 426-429, 457-458, 492, 542, 575-578, 590, 626-627, 747-750, 780-782, 895-896, 907, 1029-1030'
  anime = '50-51, 93, 213-216, 418-420, 453-456, 497-499, 506, 737, 775, 1084'
}

$sagas = @(
  [pscustomobject]@{ key='east-blue'; label='East Blue Saga'; color='#38bdf8' },
  [pscustomobject]@{ key='arabasta'; label='Arabasta Saga'; color='#22c55e' },
  [pscustomobject]@{ key='sky-island'; label='Sky Island Saga'; color='#60a5fa' },
  [pscustomobject]@{ key='water-7'; label='Water 7 Saga'; color='#fb923c' },
  [pscustomobject]@{ key='thriller-bark'; label='Thriller Bark Saga'; color='#ef4444' },
  [pscustomobject]@{ key='summit-war'; label='Summit War Saga'; color='#e5e7eb' },
  [pscustomobject]@{ key='fish-man-island'; label='Fish-Man Island Saga'; color='#4ade80' },
  [pscustomobject]@{ key='dressrosa'; label='Dressrosa Saga'; color='#a78bfa' },
  [pscustomobject]@{ key='whole-cake'; label='Whole Cake Island Saga'; color='#f9a8d4' },
  [pscustomobject]@{ key='wano'; label='Wano Country Saga'; color='#fde047' },
  [pscustomobject]@{ key='final'; label='Final Saga'; color='#facc15' }
)

$subSagas = @(
  New-SubSaga 'romance-dawn' 'east-blue' 'Romance Dawn' '1-3' 'Canon'
  New-SubSaga 'orange-town' 'east-blue' 'Orange Town' '4-8' 'Canon'
  New-SubSaga 'syrup-village' 'east-blue' 'Syrup Village' '9-18' 'Canon'
  New-SubSaga 'baratie' 'east-blue' 'Baratie' '19-30' 'Canon'
  New-SubSaga 'arlong-park' 'east-blue' 'Arlong Park' '31-44' 'Canon'
  New-SubSaga 'loguetown' 'east-blue' 'Loguetown' '45, 48-53' 'Canon'
  New-SubSaga 'buggys-adventure' 'east-blue' "Buggy's Adventure Chronicles" '46-47' 'Anime Canon'
  New-SubSaga 'warship-island' 'east-blue' 'Warship Island' '54-61' 'Filler'
  New-SubSaga 'reverse-mountain' 'arabasta' 'Reverse Mountain' '62-63' 'Canon'
  New-SubSaga 'whiskey-peak' 'arabasta' 'Whiskey Peak' '64-67' 'Canon'
  New-SubSaga 'koby-helmeppo' 'arabasta' 'Diary of Koby & Helmeppo' '68-69' 'Anime Canon'
  New-SubSaga 'little-garden' 'arabasta' 'Little Garden' '70-77' 'Canon'
  New-SubSaga 'drum-island' 'arabasta' 'Drum Island' '78-91' 'Canon'
  New-SubSaga 'arabasta-arc' 'arabasta' 'Arabasta' '92-130' 'Mixed'
  New-SubSaga 'post-arabasta' 'arabasta' 'Post-Arabasta' '131-135' 'Filler'
  New-SubSaga 'goat-island' 'sky-island' 'Goat Island' '136-138' 'Filler'
  New-SubSaga 'ruluka-island' 'sky-island' 'Ruluka Island' '139-143' 'Filler'
  New-SubSaga 'jaya' 'sky-island' 'Jaya' '144-152' 'Canon'
  New-SubSaga 'skypiea' 'sky-island' 'Skypiea' '153-195' 'Canon'
  New-SubSaga 'g8' 'sky-island' 'G-8' '196-206' 'Filler'
  New-SubSaga 'long-ring-long-land' 'water-7' 'Long Ring Long Land' '207-219' 'Canon'
  New-SubSaga 'oceans-dream' 'water-7' "Ocean's Dream" '220-224' 'Filler'
  New-SubSaga 'foxys-return' 'water-7' "Foxy's Return" '225-226' 'Filler'
  New-SubSaga 'water-7-arc' 'water-7' 'Water 7' '227-263' 'Canon'
  New-SubSaga 'enies-lobby' 'water-7' 'Enies Lobby' '264-312' 'Mixed'
  New-SubSaga 'post-enies-lobby' 'water-7' 'Post-Enies Lobby' '313-325' 'Mixed'
  New-SubSaga 'ice-hunter' 'thriller-bark' 'Ice Hunter' '326-336' 'Filler'
  New-SubSaga 'thriller-bark-arc' 'thriller-bark' 'Thriller Bark' '337-381' 'Canon'
  New-SubSaga 'spa-island' 'thriller-bark' 'Spa Island' '382-384' 'Filler'
  New-SubSaga 'sabaody' 'summit-war' 'Sabaody Archipelago' '385-405' 'Canon'
  New-SubSaga 'boss-luffy-special' 'summit-war' 'Boss Luffy Historical Special' '406-407' 'Filler'
  New-SubSaga 'amazon-lily' 'summit-war' 'Amazon Lily' '408-421' 'Canon'
  New-SubSaga 'little-east-blue' 'summit-war' 'Little East Blue' '426-429' 'Filler'
  New-SubSaga 'impel-down' 'summit-war' 'Impel Down' '422-425, 430-452' 'Canon'
  New-SubSaga 'straw-hats-separation' 'summit-war' 'Straw Hats Separation Serial' '453-456' 'Anime Canon'
  New-SubSaga 'marineford' 'summit-war' 'Marineford' '457-489' 'Canon'
  New-SubSaga 'post-war' 'summit-war' 'Post-War' '490-516' 'Canon'
  New-SubSaga 'return-to-sabaody' 'fish-man-island' 'Return to Sabaody' '517-522' 'Canon'
  New-SubSaga 'fish-man-island-arc' 'fish-man-island' 'Fish-Man Island' '523-574' 'Canon'
  New-SubSaga 'zs-ambition' 'dressrosa' "Z's Ambition" '575-578' 'Filler'
  New-SubSaga 'punk-hazard' 'dressrosa' 'Punk Hazard' '579-625' 'Canon'
  New-SubSaga 'caesar-retrieval' 'dressrosa' 'Caesar Retrieval' '626-628' 'Filler'
  New-SubSaga 'dressrosa-arc' 'dressrosa' 'Dressrosa' '629-746' 'Canon'
  New-SubSaga 'silver-mine' 'whole-cake' 'Silver Mine' '747-750' 'Filler'
  New-SubSaga 'zou' 'whole-cake' 'Zou' '751-779' 'Canon'
  New-SubSaga 'marine-rookie' 'whole-cake' 'Marine Rookie' '780-782' 'Filler'
  New-SubSaga 'whole-cake-island' 'whole-cake' 'Whole Cake Island' '783-877' 'Canon'
  New-SubSaga 'levely' 'whole-cake' 'Levely / Reverie' '878-889' 'Canon'
  New-SubSaga 'cidre-guild' 'wano' 'Cidre Guild' '895-896' 'Filler'
  New-SubSaga 'wano-country' 'wano' 'Wano Country' '890-894, 897-1028, 1031-1088' 'Canon'
  New-SubSaga 'utas-past' 'wano' "Uta's Past" '1029-1030' 'Filler'
  New-SubSaga 'egghead' 'final' 'Egghead' '1089-1155' 'Canon'
  New-SubSaga 'elbaf' 'final' 'Elbaf' "1156-$maxEpisode" 'Canon'
)

$categories = [ordered]@{}
foreach ($key in $categoryText.Keys) { $categories[$key] = Expand-Ranges $categoryText[$key] }

$episodeCategory = @{}
foreach ($key in $categories.Keys) {
  foreach ($episodeNumber in $categories[$key]) {
    if ($episodeCategory.ContainsKey($episodeNumber)) { throw "Episode $episodeNumber appears in two categories" }
    $episodeCategory[$episodeNumber] = $key
  }
}

$episodeSubSaga = @{}
foreach ($subSaga in $subSagas) {
  foreach ($episodeNumber in (Expand-Ranges $subSaga.ranges)) {
    if ($episodeMap.ContainsKey($episodeNumber)) {
      if ($episodeSubSaga.ContainsKey($episodeNumber)) { throw "Episode $episodeNumber appears in two sub-sagas" }
      $episodeSubSaga[$episodeNumber] = $subSaga
    }
  }
}

$episodes = foreach ($episodeNumber in ($episodeSubSaga.Keys | Sort-Object)) {
  $episode = $episodeMap[$episodeNumber]
  $subSaga = $episodeSubSaga[$episodeNumber]
  $category = if ($episodeCategory.ContainsKey($episodeNumber)) { [string]$episodeCategory[$episodeNumber] } else { 'manga' }
  [pscustomobject]@{
    episode = [int]$episodeNumber
    title = [string]$episode.name
    rating = [double]$episode.vote_average
    tconst = [string]$episode.tconst
    category = $category
    saga = [string]$subSaga.saga
    subSaga = [string]$subSaga.key
  }
}

$categorySummary = [ordered]@{}
foreach ($key in $categories.Keys) { $categorySummary[$key] = ($episodes | Where-Object { $_.category -eq $key }).Count }

$sagaSummary = [ordered]@{}
foreach ($saga in $sagas) { $sagaSummary[$saga.key] = ($episodes | Where-Object { $_.saga -eq $saga.key }).Count }

$subSagaSummary = [ordered]@{}
foreach ($subSaga in $subSagas) { $subSagaSummary[$subSaga.key] = ($episodes | Where-Object { $_.subSaga -eq $subSaga.key }).Count }

$episodesJson = ($episodes | ConvertTo-Json -Depth 4 -Compress).Replace('</', '<\/')
$categorySummaryJson = ($categorySummary | ConvertTo-Json -Compress)
$sagasJson = ($sagas | ConvertTo-Json -Depth 4 -Compress)
$subSagasJson = ($subSagas | ConvertTo-Json -Depth 4 -Compress)
$sagaSummaryJson = ($sagaSummary | ConvertTo-Json -Compress)
$subSagaSummaryJson = ($subSagaSummary | ConvertTo-Json -Compress)

$template = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>One Piece Episode Ratings Explorer</title>
  <style>
    :root { color-scheme: dark; --bg:#111319; --panel:#191d27; --panel-2:#202634; --text:#f4f7fb; --muted:#9ca7b8; --grid:#303747; --accent:#7dd3fc; }
    * { box-sizing:border-box; } body { margin:0; min-height:100vh; background:radial-gradient(circle at top left,rgba(125,211,252,.16),transparent 34rem),linear-gradient(135deg,#0d1017 0%,var(--bg) 48%,#151827 100%); color:var(--text); font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
    main { width:min(1320px,calc(100% - 32px)); margin:0 auto; padding:34px 0 48px; } header { display:grid; gap:18px; grid-template-columns:1fr auto; align-items:end; margin-bottom:22px; }
    h1 { margin:0 0 8px; font-size:clamp(2rem,5vw,4.25rem); line-height:.96; letter-spacing:-.07em; } .subtitle { margin:0; color:var(--muted); max-width:880px; line-height:1.55; } .source { color:var(--accent); text-decoration:none; } .source:hover { text-decoration:underline; }
    .stats { display:grid; grid-template-columns:repeat(3,minmax(90px,1fr)); gap:10px; min-width:320px; } .stat { border:1px solid rgba(255,255,255,.08); border-radius:16px; background:rgba(25,29,39,.82); padding:14px; box-shadow:0 16px 40px rgba(0,0,0,.22); } .stat strong { display:block; font-size:1.55rem; letter-spacing:-.04em; } .stat span { color:var(--muted); font-size:.82rem; }
    .panel { border:1px solid rgba(255,255,255,.08); border-radius:24px; background:rgba(25,29,39,.86); box-shadow:0 24px 70px rgba(0,0,0,.3); overflow:hidden; backdrop-filter:blur(14px); } .toolbar { display:grid; gap:16px; padding:16px 18px; border-bottom:1px solid rgba(255,255,255,.08); background:rgba(32,38,52,.64); }
    .filter-section { display:grid; gap:8px; } .filter-title { color:var(--muted); font-size:.76rem; letter-spacing:.1em; text-transform:uppercase; } .filters,.actions { display:flex; flex-wrap:wrap; gap:9px; align-items:center; }
    .filter { display:inline-flex; align-items:center; gap:8px; border:1px solid rgba(255,255,255,.1); border-radius:999px; background:rgba(255,255,255,.045); color:var(--text); padding:8px 11px; cursor:pointer; user-select:none; } .filter input { accent-color:var(--filter-color); } .filter small { color:var(--muted); }
    .saga-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(250px,1fr)); gap:10px; } details { border:1px solid rgba(255,255,255,.09); border-radius:16px; background:rgba(255,255,255,.035); overflow:hidden; } summary { display:flex; align-items:center; justify-content:space-between; gap:8px; cursor:pointer; padding:10px 12px; color:var(--text); } summary span { display:inline-flex; gap:8px; align-items:center; } .dot { width:11px; height:11px; border-radius:999px; background:var(--filter-color); box-shadow:0 0 14px var(--filter-color); }
    .subfilters { display:flex; flex-wrap:wrap; gap:7px; padding:0 10px 10px; } .subfilters .filter { font-size:.84rem; padding:7px 9px; }
    .action { border:1px solid rgba(255,255,255,.12); border-radius:999px; background:rgba(125,211,252,.08); color:var(--text); padding:8px 11px; cursor:pointer; } .action:hover { background:rgba(125,211,252,.16); }
    .meta-row { display:flex; flex-wrap:wrap; justify-content:space-between; gap:12px; color:var(--muted); font-size:.88rem; } .legend { display:flex; flex-wrap:wrap; gap:10px 16px; color:var(--muted); font-size:.88rem; } .legend-item { display:inline-flex; gap:7px; align-items:center; } .swatch { width:12px; height:12px; border-radius:999px; background:var(--color); box-shadow:0 0 16px var(--color); }
    .graph-wrap { overflow-x:auto; padding:22px 18px 18px; } .graph { position:relative; display:flex; align-items:end; gap:3px; min-width:1120px; height:420px; padding:12px 0 42px 42px; background:repeating-linear-gradient(to top,transparent 0 39px,var(--grid) 40px),linear-gradient(to right,rgba(255,255,255,.018),rgba(255,255,255,0)); border-radius:16px; } .axis-label { position:absolute; left:0; width:34px; color:var(--muted); font-size:.72rem; text-align:right; transform:translateY(50%); }
    .bar { position:relative; flex:1 0 4px; min-width:4px; height:calc(var(--rating) * 10%); border:0; border-radius:6px 6px 2px 2px; background:linear-gradient(to top,color-mix(in srgb,var(--rating-color) 62%,#111319),var(--rating-color)); box-shadow:0 0 12px color-mix(in srgb,var(--saga-color) 38%,transparent); cursor:pointer; transition:transform 150ms ease,filter 150ms ease; border-bottom:3px solid var(--saga-color); } .bar:hover,.bar:focus-visible { transform:translateY(-5px) scaleY(1.02); filter:saturate(1.35) brightness(1.14); outline:none; z-index:3; } .bar::after { content:attr(data-episode); position:absolute; left:50%; bottom:-24px; transform:translateX(-50%) rotate(-70deg); transform-origin:center; color:var(--muted); font-size:.58rem; opacity:.7; } .bar[data-dense="true"]::after { content:""; }
    .tooltip { position:fixed; max-width:380px; pointer-events:none; border:1px solid rgba(255,255,255,.12); border-radius:14px; background:rgba(11,14,20,.94); padding:12px 13px; box-shadow:0 18px 50px rgba(0,0,0,.45); opacity:0; transform:translate(-50%,-110%); transition:opacity 120ms ease; z-index:20; } .tooltip.visible { opacity:1; } .tooltip strong { display:block; margin-bottom:5px; font-size:.96rem; } .tooltip span { color:var(--muted); font-size:.84rem; line-height:1.42; }
    .table-wrap { padding:0 18px 18px; overflow-x:auto; } table { width:100%; min-width:1040px; border-collapse:collapse; overflow:hidden; border-radius:16px; background:rgba(32,38,52,.56); } th,td { padding:11px 13px; border-bottom:1px solid rgba(255,255,255,.07); text-align:left; font-size:.9rem; } th { color:var(--muted); font-size:.76rem; text-transform:uppercase; letter-spacing:.09em; background:rgba(255,255,255,.03); } tr:last-child td { border-bottom:0; }
    .pill { display:inline-flex; align-items:center; justify-content:center; border-radius:999px; color:#071016; background:var(--pill-color); font-weight:800; padding:4px 8px; font-size:.78rem; white-space:nowrap; } .rating-pill { min-width:44px; } .empty { padding:24px; color:#fecaca; }
    @media (max-width:760px) { main{width:min(100% - 20px,1320px); padding-top:22px;} header{grid-template-columns:1fr;} .stats{min-width:0; grid-template-columns:repeat(3,1fr);} .stat{padding:11px;} .stat strong{font-size:1.2rem;} .graph{min-width:860px; height:360px;} .meta-row{display:grid;} }
  </style>
</head>
<body>
  <main>
    <header><div><h1>One Piece Ratings Explorer</h1><p class="subtitle">Series Graph-style rating view with separate filters for episode type, saga, and sub-saga. The graph bars are colored by rating and underlined by saga.</p></div><section class="stats" aria-label="Rating summary"><div class="stat"><strong id="count">--</strong><span>shown episodes</span></div><div class="stat"><strong id="average">--</strong><span>average rating</span></div><div class="stat"><strong id="best">--</strong><span>highest rated</span></div></section></header>
    <section class="panel"><div class="toolbar"><section class="filter-section"><div class="filter-title">Episode Type</div><div id="category-filters" class="filters"></div></section><section class="filter-section"><div class="filter-title">Saga</div><div id="saga-filters" class="filters"></div></section><section class="filter-section"><div class="filter-title">Sub-Sagas</div><div id="sub-saga-filters" class="saga-grid"></div></section><div class="actions"><button class="action" data-preset="all" type="button">All</button><button class="action" data-preset="canon" type="button">Non-filler TV</button><button class="action" data-preset="filler" type="button">Filler only</button><button class="action" data-preset="clear" type="button">Clear</button></div><div class="meta-row"><div class="legend"><span class="legend-item"><i class="swatch" style="--color:#ef4444"></i>Under 6.0</span><span class="legend-item"><i class="swatch" style="--color:#f97316"></i>6.0-6.9</span><span class="legend-item"><i class="swatch" style="--color:#facc15"></i>7.0-7.4</span><span class="legend-item"><i class="swatch" style="--color:#22c55e"></i>7.5+</span></div><div id="status">Using embedded Series Graph ratings snapshot.</div></div></div><div class="graph-wrap"><div id="graph" class="graph" aria-label="Episode ratings bar graph"><span class="axis-label" style="bottom:42px">0</span><span class="axis-label" style="bottom:122px">2</span><span class="axis-label" style="bottom:202px">4</span><span class="axis-label" style="bottom:282px">6</span><span class="axis-label" style="bottom:362px">8</span><span class="axis-label" style="bottom:402px">10</span></div></div><div class="table-wrap"><table><thead><tr><th>Episode</th><th>Type</th><th>Saga</th><th>Sub-Saga</th><th>Title</th><th>Rating</th><th>Votes</th><th>IMDb</th></tr></thead><tbody id="rows"></tbody></table></div></section>
  </main>
  <div id="tooltip" class="tooltip" role="status" aria-live="polite"></div>
  <script id="episode-data" type="application/json">__EPISODES_JSON__</script><script id="category-summary" type="application/json">__CATEGORY_SUMMARY_JSON__</script><script id="saga-data" type="application/json">__SAGAS_JSON__</script><script id="sub-saga-data" type="application/json">__SUB_SAGAS_JSON__</script><script id="saga-summary" type="application/json">__SAGA_SUMMARY_JSON__</script><script id="sub-saga-summary" type="application/json">__SUB_SAGA_SUMMARY_JSON__</script>
  <script>
    const CATEGORY_META={manga:{label:"Manga Canon",color:"#22c55e"},mixed:{label:"Mixed Canon/Filler",color:"#f59e0b"},filler:{label:"Filler",color:"#ef4444"},anime:{label:"Anime Canon",color:"#38bdf8"}};
    const CATEGORY_ORDER=["manga","mixed","filler","anime"],episodes=JSON.parse(document.querySelector("#episode-data").textContent),categorySummary=JSON.parse(document.querySelector("#category-summary").textContent),sagas=JSON.parse(document.querySelector("#saga-data").textContent),subSagas=JSON.parse(document.querySelector("#sub-saga-data").textContent),sagaSummary=JSON.parse(document.querySelector("#saga-summary").textContent),subSagaSummary=JSON.parse(document.querySelector("#sub-saga-summary").textContent);
    const sagaMeta=Object.fromEntries(sagas.map(s=>[s.key,s])),subSagaMeta=Object.fromEntries(subSagas.map(s=>[s.key,s])),selectedCategories=new Set(CATEGORY_ORDER),selectedSagas=new Set(sagas.map(s=>s.key)),selectedSubSagas=new Set(subSagas.map(s=>s.key));
    const graph=document.querySelector("#graph"),rows=document.querySelector("#rows"),tooltip=document.querySelector("#tooltip"),status=document.querySelector("#status");
    function ratingColor(r){return r>=7.5?"#22c55e":r>=7?"#facc15":r>=6?"#f97316":"#ef4444"} function formatVotes(v){return new Intl.NumberFormat("en-US").format(v)} function clearRendered(){graph.querySelectorAll(".bar").forEach(b=>b.remove());rows.textContent=""}
    function shownEpisodes(){return episodes.filter(e=>selectedCategories.has(e.category)&&selectedSagas.has(e.saga)&&selectedSubSagas.has(e.subSaga)).sort((a,b)=>a.episode-b.episode)}
    function showTooltip(event,e){const c=CATEGORY_META[e.category],s=sagaMeta[e.saga],ss=subSagaMeta[e.subSaga];tooltip.textContent=\"\";const title=document.createElement(\"strong\"),detail=document.createElement(\"span\");title.textContent=`Episode ${e.episode}: ${e.title}`;detail.append(document.createTextNode(`${c.label} / ${s.label} / ${ss.label}`),document.createElement(\"br\"),document.createTextNode(`Rating ${e.rating.toFixed(1)} \u00b7 IMDb`));tooltip.append(title,detail);tooltip.style.left=`${event.clientX}px`;tooltip.style.top=`${event.clientY-12}px`;tooltip.classList.add(\"visible\")} function hideTooltip(){tooltip.classList.remove(\"visible\")}
    function render(){const shown=shownEpisodes();clearRendered();if(!shown.length){document.querySelector("#count").textContent="0";document.querySelector("#average").textContent="--";document.querySelector("#best").textContent="--";status.textContent="No episodes match the selected filters.";rows.innerHTML=`<tr><td colspan="8" class="empty">Select at least one type, saga, and sub-saga.</td></tr>`;return} const avg=shown.reduce((s,e)=>s+e.rating,0)/shown.length,best=shown.reduce((t,e)=>e.rating>t.rating?e:t,shown[0]),worst=shown.reduce((l,e)=>e.rating<l.rating?e:l,shown[0]);document.querySelector("#count").textContent=shown.length;document.querySelector("#average").textContent=avg.toFixed(2);document.querySelector("#best").textContent=`${best.episode} (${best.rating.toFixed(1)})`;status.textContent=`Showing ${shown.length} episodes. Highest: ${best.episode}. Lowest: ${worst.episode} (${worst.rating.toFixed(1)}).`;for(const e of shown){const c=CATEGORY_META[e.category],s=sagaMeta[e.saga],ss=subSagaMeta[e.subSaga],rating=ratingColor(e.rating);const bar=document.createElement("button");bar.className="bar";bar.type="button";bar.dataset.episode=e.episode;bar.dataset.dense=shown.length>180;bar.style.setProperty("--rating",e.rating);bar.style.setProperty("--rating-color",rating);bar.style.setProperty("--saga-color",s.color);bar.setAttribute("aria-label",`Episode ${e.episode}, ${c.label}, ${s.label}, ${ss.label}, rating ${e.rating.toFixed(1)}`);bar.addEventListener("mousemove",ev=>showTooltip(ev,e));bar.addEventListener("focus",ev=>showTooltip(ev,e));bar.addEventListener("mouseleave",hideTooltip);bar.addEventListener("blur",hideTooltip);graph.appendChild(bar);const row=document.createElement("tr");row.innerHTML=`<td>${e.episode}</td><td><span class="pill" style="--pill-color:${c.color}">${c.label}</span></td><td><span class="pill" style="--pill-color:${s.color}">${s.label}</span></td><td>${ss.label}</td><td>${e.title}</td><td><span class="pill rating-pill" style="--pill-color:${rating}">${e.rating.toFixed(1)}</span></td><td>${formatVotes(e.votes)}</td><td><a class="source" href="https://www.imdb.com/title/${e.tconst}/">${e.tconst}</a></td>`;rows.appendChild(row)}}
    function makeFilter(container,key,label,color,count,set){const el=document.createElement("label");el.className="filter";el.style.setProperty("--filter-color",color);el.innerHTML=`<input type="checkbox" value="${key}" checked> <span>${label}</span> <small>${count}</small>`;el.querySelector("input").addEventListener("change",ev=>{ev.target.checked?set.add(key):set.delete(key);render()});container.appendChild(el)}
    function renderFilters(){const c=document.querySelector("#category-filters"),sg=document.querySelector("#saga-filters"),sub=document.querySelector("#sub-saga-filters");CATEGORY_ORDER.forEach(k=>makeFilter(c,k,CATEGORY_META[k].label,CATEGORY_META[k].color,categorySummary[k],selectedCategories));sagas.forEach(s=>makeFilter(sg,s.key,s.label,s.color,sagaSummary[s.key],selectedSagas));sagas.forEach(s=>{const details=document.createElement("details");details.open=true;details.style.setProperty("--filter-color",s.color);details.innerHTML=`<summary><span><i class="dot"></i>${s.label}</span><small>${sagaSummary[s.key]}</small></summary><div class="subfilters"></div>`;const box=details.querySelector(".subfilters");subSagas.filter(ss=>ss.saga===s.key).forEach(ss=>makeFilter(box,ss.key,ss.label,s.color,subSagaSummary[ss.key],selectedSubSagas));sub.appendChild(details)})}
    function syncChecks(){document.querySelectorAll("#category-filters input").forEach(i=>i.checked=selectedCategories.has(i.value));document.querySelectorAll("#saga-filters input").forEach(i=>i.checked=selectedSagas.has(i.value));document.querySelectorAll("#sub-saga-filters input").forEach(i=>i.checked=selectedSubSagas.has(i.value))}
    function applyPreset(p){selectedCategories.clear();selectedSagas.clear();selectedSubSagas.clear();if(p==="all"){CATEGORY_ORDER.forEach(k=>selectedCategories.add(k));sagas.forEach(s=>selectedSagas.add(s.key));subSagas.forEach(s=>selectedSubSagas.add(s.key))} if(p==="canon"){["manga","anime"].forEach(k=>selectedCategories.add(k));sagas.forEach(s=>selectedSagas.add(s.key));subSagas.forEach(s=>selectedSubSagas.add(s.key))} if(p==="filler"){["mixed","filler"].forEach(k=>selectedCategories.add(k));sagas.forEach(s=>selectedSagas.add(s.key));subSagas.forEach(s=>selectedSubSagas.add(s.key))} syncChecks();render()}
    document.querySelectorAll(".action").forEach(b=>b.addEventListener("click",()=>applyPreset(b.dataset.preset)));renderFilters();render();
  </script>
</body>
</html>
'@

$html = $template.Replace('__EPISODES_JSON__', $episodesJson).Replace('__CATEGORY_SUMMARY_JSON__', $categorySummaryJson).Replace('__SAGAS_JSON__', $sagasJson).Replace('__SUB_SAGAS_JSON__', $subSagasJson).Replace('__SAGA_SUMMARY_JSON__', $sagaSummaryJson).Replace('__SUB_SAGA_SUMMARY_JSON__', $subSagaSummaryJson)
Set-Content -LiteralPath $outputPath -Value $html -Encoding UTF8

[pscustomobject]@{
  Output = $outputPath
  Episodes = $episodes.Count
  MaxEpisode = $maxEpisode
  Manga = $categorySummary.manga
  Mixed = $categorySummary.mixed
  Filler = $categorySummary.filler
  Anime = $categorySummary.anime
  Sagas = $sagas.Count
  SubSagas = $subSagas.Count
} | ConvertTo-Json

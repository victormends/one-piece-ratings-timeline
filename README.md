# One Piece Ratings Timeline

A standalone fan-made One Piece ratings and watch-order timeline.

The page groups TV episodes, movies, TV specials, recap/remake specials, OVAs, and shorts by saga and sub-saga. Filters fade non-selected entries instead of removing them, so skipped material stays visible in timeline context.

This is a fan research project, not an official One Piece, Toei Animation, IMDb, Series Graph, MyAnimeList, or Jikan project.

## View Locally

Open:

```text
docs/index.html
```

## Rebuild

Run from this repository:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\generate.ps1
```

The generator writes the final static page to `docs/index.html`.

To force a fresh Series Graph ratings download instead of using the local snapshot:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\generate.ps1 -RefreshRatings
```

Requirements:

- Windows PowerShell 5.1 or PowerShell 7+.
- Internet access when rebuilding source caches.
- Local source/cache files under `data/`; these are intentionally not for version control.

## Project Structure

```text
docs/index.html                 Static page for local viewing or GitHub Pages
.github/workflows/refresh-ratings.yml Scheduled GitHub Pages data refresh
scripts/build-base.ps1          Builds the base TV episode dataset and arc metadata
scripts/generate.ps1            Builds the final page with media entries and UI
data/cache/                     Local-only downloaded/source cache, ignored by git
data/generated/                 Local research output, ignored by git
data/original-entry-notes.json  Reviewed project-owned viewing notes
data/one-piece-*.json           Local Jikan cache files, ignored by git
data/seriesgraph-*.json         Local Series Graph snapshot, ignored by git
notes/provider-mapping-report.md Research notes, optional/non-production
sources.md                      Data sources and classification notes
DATA_LICENSE.md                 Third-party data licensing and redistribution notes
```

`docs/index.html` is generated. Edit `scripts/generate.ps1`, `scripts/build-base.ps1`, or source data files, then rebuild instead of hand-editing the generated page.

## Data Sources

TV episode ratings come from the Series Graph One Piece endpoint, which reflects IMDb rating data. English TV titles, release dates, and recall synopsis source text are cached locally from Jikan/MyAnimeList endpoints for rebuilds. Movies, specials, OVAs, shorts, and recap/remake entries use MyAnimeList scores via Jikan.

Optional `originalNote` text is used as the page's short recall synopsis field. TV episode recall synopses are source-derived from the local Jikan/MyAnimeList episode metadata cache; non-TV media synopses use title and placement metadata. These notes are not covered by the MIT License as original project prose. See `SUMMARY_POLICY.md` and `DATA_LICENSE.md` for the workflow and publishing caveats.

Series Graph can lag live IMDb or round scores differently. Upstream TV episode rows without a rating or vote count are skipped until they become rated, so a newly listed but unrated episode may not appear immediately.

See `sources.md` for source details and `DATA_LICENSE.md` before publishing, redistributing, or reusing generated data.

## Filter Semantics

The `Non-filler TV` preset selects manga-canon, mixed canon/filler, and anime-original TV episodes. It excludes pure filler episodes and all non-TV media. The `Episodes only` preset selects all TV episode categories, including filler.

Clicking a tile opens that entry's rating source in a new tab. TV episodes link to IMDb pages; movies, specials, recaps, OVAs, and shorts link to MyAnimeList pages.

## Search Guide

The search box supports plain words, explicit operators, episode ranges, exclusions, saga/category aliases, story tags, and faction tags. Typing filters immediately using prefix matching. Pressing `Enter` switches the current search to exact whole-word matching.

### Basic Text Search

`ace` finds words that start with `ace`, such as `Ace` or `Ace's`. While typing, this is intentionally loose so partial terms are useful.

`ace` followed by `Enter` becomes stricter: it matches `Ace` and `Ace's`, but not longer unrelated words like `access`.

Search checks the episode title, recall synopsis, and episode code, so `e400` or `400` can also find episode-number references when they are present.

### Combining Terms

Use `+` when every term must match:

```text
chopper + nami
```

Use `or` or `|` when any term can match:

```text
die or death
die | death
```

Plain spaces inside a phrase are kept as part of the term, which is useful for multi-word aliases:

```text
whitebeard pirates
heart pirates
celestial dragons
```

For organized multi-part searches, prefer `+` between search blocks instead of writing everything as one long phrase.

### Exclusions

Put `-` before a term to exclude it:

```text
-nami
```

Use grouped exclusions for several terms:

```text
-(nami,usopp)
```

Faction-plus-exclusion examples:

```text
whitebeard pirates + -luffy
whitebeard pirates + -(luffy,ace)
whitebeard pirates + marineford + -luffy
```

Exclusions use the same resolver as normal search, so `-wano`, `-filler`, `-cp9`, or `-whitebeard pirates` work as category, saga, or tag exclusions instead of only plain text.

### Episode Ranges

Use numeric ranges to filter a section of the anime:

```text
400-500
e400-e500
e400-500
```

Ranges can be combined with tags:

```text
400-500 + marines
900-1085 + kaido
```

### Saga And Category Aliases

Saga names are indexed, including common spelling variants:

```text
alabasta
arabasta
skypiea
marineford
whole cake
wano
```

Category aliases include:

```text
canon
filler
non-canon
recap
ova
special
movie
short
```

Examples:

```text
canon + wano
non-canon + movie
filler + -recap
```

### Story Tags

These invisible tags point to curated episode sets:

```text
flashback
backstory
first appearance
debut
recap
```

Examples:

```text
flashback + wano
backstory + law
debut + straw hat
```

`death` expands into related terms such as `die`, `died`, `dead`, `killed`, `sacrifice`, and `execution`.

### Faction Tags

Faction terms search curated episode sets where that group or character is a real focus, not just a tiny mention.

Yonko / Emperor searches:

```text
whitebeard
shanks
blackbeard
big mom
kaido
```

Pirate crews and organizations:

```text
whitebeard pirates
red hair pirates
blackbeard pirates
big mom pirates
beast pirates
heart pirates
kid pirates
buggy pirates
baroque works
donquixote pirates
sun pirates
roger pirates
revolutionary army
```

Marines and World Government:

```text
marines
cp9
cp0
cipher pol
akainu
aokiji
kizaru
fujitora
ryokugyu
celestial dragons
five elders
imu
```

Warlords / Shichibukai:

```text
shichibukai
warlords
crocodile
doflamingo
jinbe
hancock
moriah
mihawk
kuma
law
```

Other useful faction/group tags:

```text
supernovas
worst generation
impel down
minks
wano samurai
scabbards
```

Useful combinations:

```text
shichibukai + marineford
cp9 + robin
big mom + flashback
kaido + 1000-1085
supernovas + -luffy
celestial dragons or five elders
```

## Notes

Timeline placement for non-episode media is a practical release/watch-order placement, not a claim of strict canon continuity. TV episode ratings and media ratings come from different upstream sources, so cross-type comparisons should be treated as approximate.

Before making the repository public, verify that no local cache, snapshot, or research output files from `data/` are staged.

## Keeping Ratings Fresh

The repository includes a scheduled GitHub Actions workflow that rebuilds `docs/index.html` every six hours with `scripts/generate.ps1 -RefreshRatings`. If the generated page changes, the workflow commits the updated page back to the branch.

You can also run the refresh manually from the Actions tab with `workflow_dispatch`, or locally with the `-RefreshRatings` command shown above.

## Recall Synopsis Workflow

The page currently uses source-derived recall synopses for hover text. These are compressed from local episode metadata for TV entries and title/placement metadata for movies, specials, OVAs, shorts, and recaps:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\generate-recall-synopses.ps1
```

Because the TV recall synopses are source-derived, they are documented as third-party/upstream-derived data in `DATA_LICENSE.md` and are not covered by the MIT License.

Then validate, promote, and rebuild:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\validate-original-notes.ps1 -Path data\generated\original-entry-notes-draft.json
powershell -ExecutionPolicy Bypass -File scripts\promote-original-notes.ps1 -Overwrite
powershell -ExecutionPolicy Bypass -File scripts\generate.ps1
```

Only entries with `reviewStatus: "reviewed"` are embedded in the public page as `originalNote` and shown as `Synopsis:` in tooltips.

## Validation

After rebuilding, run these checks before publishing:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\generate.ps1
powershell -ExecutionPolicy Bypass -File scripts\generate.ps1 -RefreshRatings
powershell -ExecutionPolicy Bypass -File scripts\validate-original-notes.ps1 -PublicFile
git status --short --ignored
```

Confirm `data/cache/`, `data/generated/`, `data/one-piece-*.json`, and `data/seriesgraph-*.json` are ignored unless you have explicitly decided to publish those third-party snapshots.

## License

Code in this repository is licensed under the MIT License. Third-party ratings, titles, URLs, vote counts, dates, and metadata belong to their respective sources and are not covered by the MIT License.

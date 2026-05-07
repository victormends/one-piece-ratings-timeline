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

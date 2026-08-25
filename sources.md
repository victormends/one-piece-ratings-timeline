# Sources And Classification Notes

## TV Episodes

TV episode ratings are generated from the Series Graph One Piece season-ratings endpoint:

```text
https://seriesgraph.com/api/shows/37854/season-ratings
```

The endpoint provides global episode numbers, titles, IMDb title IDs, vote averages, vote counts, air dates, and short overview text. The generator validates a continuous episode sequence and required fields before replacing its last known-good snapshot. The generated page labels this source as `Series Graph / IMDb`.

English episode titles and dates are also cached from Jikan endpoints for MyAnimeList anime ID `21`. They are fallbacks when Series Graph metadata is absent and remain the metadata/rating source for non-TV entries:

```text
https://api.jikan.moe/v4/anime/21/episodes
https://api.jikan.moe/v4/anime/21/episodes/{episodeNumber}
```

## One Piece Wiki Coverage Research

Two local Fandom exports were inspected:

- `OnePieceWiki_Pages.zip` — SHA-256 `7875D2BBA4F5BADF5439074308DDCC3E5F9F4A1D19CC612100372560B2197719`
- `One+Piece+Wiki-20260609203511 (1).xml` — SHA-256 `54E51494C2C208EF09F5196ACF29C37A3BDB954BEEB2EAC5A8EB90AAD275D292`

They contain the same 1,592 page titles and page texts. The ZIP is used by `scripts/import-one-piece-wiki.ps1` because its page-per-JSON layout is substantially easier to stream and parse; the XML is therefore retained only as a provenance/export-format cross-check. Neither downloaded source file is committed.

The importer stores only derived research metadata: section presence and length, page IDs, normalized linked character IDs, appearance context, and technique-debut counts. It does not store the wiki short-summary text. `scripts/update-one-piece-wiki-audit.ps1` uses the MediaWiki API to extend the local export through newer published episodes while recording revision timestamps.

The current compact audit covers episodes 1–1175 without number gaps. It found short-summary sections in 1,173 episodes and character-list sections in 1,171. Missing source sections are recorded explicitly in `data/wiki-audit-summary.json`. These values describe source completeness, not whether the project's synopsis or appearance audit is editorially complete.

## Manga Chapter Adaptations

Episode-to-chapter links are derived from the One Piece Wiki [`Template:WC`](https://onepiece.fandom.com/wiki/Template:WC), whose rows map each manga chapter to one or more anime works and source page ranges. `scripts/update-chapter-adaptations.ps1` reads the template through the MediaWiki API, keeps exact `Episode N` mappings, inverts them by episode number, and records the upstream revision in `data/chapter-adaptations.json`.

The generated tooltip links each mapped chapter to its One Piece Wiki chapter page and displays the page range reported by the template. Episodes absent from the table are left without a chapter claim; the generator does not infer manga material from titles, synopses, or category labels.

## Movies, Specials, Recaps, OVAs, And Shorts

Non-episode media ratings use MyAnimeList scores via Jikan. The generated page labels those entries as `MyAnimeList via Jikan` and links each item to its MyAnimeList page.

The current media categories are:

- `Movie`: original theatrical films and 3D theatrical film entries.
- `TV Special`: mostly original or side-story TV specials, including `One Piece Fan Letter`.
- `Recap / Remake`: long-form recap or remake specials/movies such as `Episode of Nami`, `Episode of Merry`, and `Episode of Skypiea`.
- `OVA`: direct special OVA material such as `Strong World Episode 0`.
- `Short`: theatrical short films bundled with early movies.

## Saga And Arc Boundaries

Saga and sub-saga ranges are maintained manually in `scripts/build-base.ps1`.

Recent corrected boundaries:

- Wano Country continues through episode `1088`.
- Egghead is mapped to episodes `1089-1155`.
- Elbaf starts at episode `1156`.

These boundaries were cross-checked against current Wikipedia episode season pages for One Piece seasons 20, 21, and 22.

## Limitations

Ratings from TV episodes and non-episode media are not from the same source. The page intentionally shows source labels in hover tooltips so the values are not treated as one uniform measurement.

Non-episode media placement is based on release-era or practical watch-order context. Some specials are alternate-setting, recap, remake, or non-canon works, so their placement should be read as timeline guidance rather than strict story continuity.

The `Non-filler TV` preset means manga, mixed, and anime-original TV episodes. It does not include pure filler episodes, movies, specials, recaps, OVAs, or shorts.

Chapter adaptation mappings describe which manga pages were used, not whether every scene in an episode is manga-canon. Mixed episodes may also contain anime-original material.

Local files under `data/cache/`, `data/generated/`, and local provider snapshots such as `data/one-piece-*.json` or `data/seriesgraph-*.json` are rebuild/research caches and should not be committed by default. `data/wiki-audit-summary.json` is the deliberate exception: it contains only compact derived counts, provenance, and missing-section lists. Provider mapping notes in `notes/` are research artifacts, not a production source of truth.

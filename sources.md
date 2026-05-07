# Sources And Classification Notes

## TV Episodes

TV episode ratings are generated from the Series Graph One Piece season-ratings endpoint:

```text
https://seriesgraph.com/api/shows/37854/season-ratings
```

The endpoint provides global episode numbers, titles, IMDb title IDs, vote averages, and vote counts. The generated page labels this source as `Series Graph / IMDb`.

English episode titles, release dates, and local rebuild metadata are cached from Jikan endpoints for MyAnimeList anime ID `21`:

```text
https://api.jikan.moe/v4/anime/21/episodes
https://api.jikan.moe/v4/anime/21/episodes/{episodeNumber}
```

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

Local files under `data/cache/`, `data/generated/`, and local source snapshots such as `data/one-piece-*.json` or `data/seriesgraph-*.json` are rebuild/research caches and should not be committed by default. Provider mapping notes in `notes/` are research artifacts, not a production source of truth.

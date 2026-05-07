# Provider Mapping Feasibility Report

Generated: 2026-05-07 10:33:13

## Scope

This report tests whether IMDb non-commercial datasets can replace the current Series Graph ratings source without changing the production page yet. TMDb API mapping is not tested here because `TMDB_API_KEY` is not configured in this repo; it remains the next feasibility step.

## IMDb Dataset Findings

- IMDb parent tconst tested: tt0388629
- Current TV episodes in generated page: 1160
- Current non-TV media entries in generated page: 33
- IMDb episode rows found for parent: 1182
- IMDb episode numbers with one candidate: 1161
- IMDb episode numbers with duplicate candidates: 0
- IMDb episode rows with ratings: 1181
- Current episode numbers missing from IMDb: none
- Extra IMDb episode numbers not in current page: 1161
- Current TV episodes with IMDb ratings: 1160 / 1160

## Checkpoint Episode Results

| Global Ep | Current Title | IMDb Ep | IMDb Title | Current Rating | IMDb Rating | IMDb Votes | Confidence |
|---:|---|---:|---|---:|---:|---:|---|
| 1 | I'm Luffy! The Man Who's Gonna Be King of the Pirates! | 1 | I'm Luffy! The Man Who Will Become the Pirate King! | 8.4 | 8.4 | 42308 | number-match-title-differs |
| 44 | Setting Out with a Smile! Farewell, Hometown Cocoyashi Village! | 44 | Egao no Tabidachi! Saraba Furusato Cocoyashi Mura | 7.9 | 7.9 | 3050 | number-match-title-differs |
| 130 | Scent of Danger! The Seventh Member is Nico Robin! | 130 | Kiken na Kaori! Shichininme wa Nico Robin! | 8.6 | 8.6 | 2722 | number-match-title-differs |
| 516 | Luffy's Training Begins! To the Place We Promised in 2 Years! | 516 | Luffy Shugyou Kaishi: 2-nengo ni Yakusoku no Basho de | 9.2 | 9.2 | 3347 | number-match-title-differs |
| 600 | Save the Children! The Master's Evil Hands Close in! | 600 | Kodomo-tachi o Mamore! Semaru Master no Ma no Te | 7.2 | 7.2 | 911 | number-match-title-differs |
| 889 | Finally, It Starts! The Conspiracy-filled Reverie! | 889 | Finally, It Starts! The Conspiracy-filled Reverie! | 7.6 | 7.6 | 1114 | verified-title |
| 1088 | Luffy's Dream | 1088 | Luffy's Dream | 9.2 | 9.2 | 6123 | verified-title |
| 1089 | Entering a New Chapter! Luffy and Sabo's Paths! | 1089 | Entering a New Chapter! Luffy and Sabo's Paths! | 9.7 | 9.7 | 36030 | verified-title |
| 1122 | The Last Lesson! Impact Inherited | 1122 | The Last Lesson! Impact Inherited | 9.7 | 9.7 | 17779 | verified-title |
| 1155 | The Promised Horizon - Off to the Long-Awaited Elbaph! | 1155 | The Promised Horizon -Off to the Long-Awaited Elbaph | 9.4 | 9.4 | 3861 | verified-title |
| 1156 | The Long-sought Elbaph! The Big Reunion Banquet | 1156 | The Long-sought Elbaph! The Big Reunion Banquet | 9 | 9 | 4280 | verified-title |
| 1160 | An Encounter on a Snowfield - Loki, the Accursed Prince | 1160 | An Encounter on a Snowfield - Loki, the Accursed Prince | 8.9 | 9 | 2060 | verified-title |

## Checkpoint Summary

- Verified by title: 7
- Number match but title differs: 5
- Missing: 0
- Ambiguous: 0

## Media Checkpoints

| Code | Title | Category | Current Rating | IMDb Title | IMDb Rating | IMDb Votes | Candidates | Mapping Status |
|---|---|---|---:|---|---:|---:|---:|---|
| M10 | One Piece Film: Strong World | movie | 8.04 | One Piece: Strong World | 7.4 | 8524 | 1 | manual-id-validated |
| M15 | One Piece Film: Red | movie | 7.82 | One Piece Film: Red | 6.7 | 26581 | 1 | manual-id-validated |
| SP14 | One Piece Fan Letter | special | 9.02 |  |  |  | 0 | manual-imdb-id-needed |
| R4 | One Piece: Episode of Merry - The Tale of One More Friend | recap | 8.19 |  |  |  | 0 | manual-imdb-id-needed |
| R7 | One Piece: Episode of Skypiea | recap | 7.21 | One Piece: Episode of Skypiea | 6.7 | 797 | 1 | manual-id-validated |

## Preliminary Decision

IMDb mapping is not yet proven safe. Do not replace the production data source until mismatches, missing rows, and media mappings are resolved.

## Next Tests

- Add TMDb feasibility once `TMDB_API_KEY` is available.
- Add IMDb media search/mapping for movies, specials, recaps, OVAs, and shorts.
- Build an authoritative `provider-map.json` only after sampled mappings are manually reviewed.

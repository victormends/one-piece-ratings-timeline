# Third-Party Data Notice

This repository's code is licensed under the MIT License. The generated dataset and generated page may include third-party data that is not owned by this repository.

## Included Data Types

The generated page may contain:

- One Piece episode and media titles.
- Ratings, vote counts, and source URLs.
- Air or release dates.
- Saga, sub-saga, category, and watch-order placement labels maintained by this project.
- Short recall synopsis text when `originalNote` entries are embedded in the generated page.

## Upstream Sources

TV episode ratings are sourced through Series Graph and labeled as `Series Graph / IMDb` in the page. Episode titles and dates are cached locally from Jikan/MyAnimeList for rebuilds. Movies, specials, recaps, OVAs, and shorts use MyAnimeList scores through Jikan.

If `originalNote` entries are present, TV episode recall synopses are source-derived from local Jikan/MyAnimeList episode metadata and compressed for hover display. Non-TV media recall synopses are generated from title, type, sub-saga, and placement metadata. The MIT License does not grant rights to upstream-derived synopsis text.

The upstream sources have their own terms, licenses, and usage limits. The MIT License in this repository applies only to original project code and documentation, not to third-party ratings, titles, vote counts, dates, URLs, or other source metadata.

## Publishing Guidance

Before publishing or redistributing a generated build, review whether the embedded data is allowed under the upstream source terms. If in doubt, remove or regenerate sensitive fields such as vote counts, cached provider data, or source-derived recall synopses.

Do not commit local downloaded cache files, source snapshots, or research outputs under `data/`. They are ignored by git and should remain local rebuild artifacts unless you have explicitly reviewed the upstream terms and decided to publish them.

## Fan Project Disclaimer

This is an unofficial fan research project. It is not affiliated with, endorsed by, or sponsored by Eiichiro Oda, Shueisha, Toei Animation, IMDb, Series Graph, MyAnimeList, Jikan, or any related rights holder.

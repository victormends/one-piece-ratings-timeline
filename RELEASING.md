# Release Checklist

Before tagging a public release, verify:

- The GitHub Pages demo opens and matches the current repository state closely enough for the README screenshot to remain representative.
- `scripts/validate-original-notes.ps1 -PublicFile` reports no errors.
- `scripts/validate-generated-data.ps1` reports no errors, 100% date/synopsis coverage, and chapter-adaptation coverage above the configured baseline.
- `scripts/verify-appearance-tags.ps1` reports no errors; warnings should be reviewed as metadata-quality prompts.
- The scheduled refresh workflow is healthy or any temporary upstream/source issue is documented in the release notes.
- `DATA_LICENSE.md`, `SUMMARY_POLICY.md`, and `sources.md` still describe the current data-source boundaries.
- Release notes avoid implying official affiliation or ownership of upstream ratings, titles, metadata, or source-derived synopsis text.

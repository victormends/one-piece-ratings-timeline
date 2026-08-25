# Recall Synopsis Policy

The page can show short recall synopses meant to help someone who already watched identify the entry quickly.

The public field name remains `originalNote` for compatibility, but the UI label is `Synopsis:`.

TV episode recall synopses prefer entries in the reviewed local notes file. When a reviewed value is empty, template-only, title-only, contains likely encoding damage, or appears truncated after an abbreviation such as `Dr.`, `Mr.`, or `St.`, the generator uses a short Series Graph overview instead. Non-TV media synopses use title, type, sub-saga, and placement metadata.

Generated episode records distinguish `synopsisStatus: reviewed` from `synopsisStatus: source-derived` and retain `synopsisSource`. A source-derived fallback is not silently promoted into the reviewed notes file.

These recall synopses are not treated as original project prose. They are upstream-derived data, so publishing them requires accepting the data/licensing risk described in `DATA_LICENSE.md`.

## Implementation Workflow

The notes workflow is intentionally separated from the page generator:

1. Export safe metadata with `scripts/export-entry-metadata.ps1`.
2. Generate candidate recall synopses with `scripts/generate-recall-synopses.ps1`; candidates are marked `reviewStatus: generated`.
3. Validate drafts with `scripts/validate-original-notes.ps1`.
4. Promote reviewed entries with `scripts/promote-original-notes.ps1 -Overwrite`.
5. Rebuild the page with `scripts/generate.ps1`.
6. Validate the final merged output with `scripts/validate-generated-data.ps1`.

`scripts/generate-recall-synopses.ps1` writes `data/generated/original-entry-notes-draft.json` from local episode metadata and media placement data. It targets short hover text with a default cap of 185 characters.

Reviewed notes live in `data/original-entry-notes.json` using schema version `1`. Draft files stay under `data/generated/` and are ignored by git.

## Validation Rules

Validation fails when a note is empty, longer than the validator maximum, duplicated, mapped to an unknown `displayCode`, contains a URL, mentions provider names such as IMDb/MAL/Jikan/Wikipedia, starts with banned openings such as `In this episode`, or appears in the public notes file without `reviewStatus: "reviewed"`.

Validation warns on repeated openings and high title-token overlap. Warnings should be reviewed before promotion.

Final-output validation separately blocks episode-number gaps, a catalog maximum below the baseline, missing dates or synopses, invalid editorial statuses, likely encoding artifacts, low-quality/template synopsis values, and notes above the display limit.

## Review Checklist

Before publishing generated notes:

- Decide whether the public build should include source-derived recall synopses at all.
- Spot-check for phrasing overlap with IMDb, MAL, Jikan, and wiki pages.
- Keep notes optional and stored in a project-owned file, for example `data/original-entry-notes.json`.
- Document the generation date and review method.

If quality or overlap is questionable, keep notes out of the public build and rely on source links instead.

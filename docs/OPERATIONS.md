# Pipeline Operations & Recovery Runbook

This note documents how the automated data pipeline in `one-piece-ratings-timeline` preserves artifact availability, enforces schema/regression gates, and exports diagnostic outputs during GitHub Actions runs.

---

## 1. Freshness SLO & Snapshot Caching

The scheduled refresh workflow ([`.github/workflows/refresh-ratings.yml`](../.github/workflows/refresh-ratings.yml)) runs every 6 hours (`17 */6 * * *`).

- **Upstream resilience:** HTTP fetches in `scripts/provider-utils.ps1` honor `Retry-After` headers and apply exponential backoff across transient `408`/`425`/`429`/`5xx` failures.
- **Last known-good fallback:** GitHub Actions cache restores `data/seriesgraph-season-ratings.json`, `data/one-piece-english-titles.json`, and `data/one-piece-episode-meta.json` prior to refresh. Running `./scripts/generate.ps1 -RefreshRatings -AllowStaleOnProviderFailure` lets a healthy cached provider keep the timeline publishable if an upstream source has a temporary outage.
- **Freshness thresholds (`scripts/export-pipeline-slo.ps1`):**
  - **Warning:** cached snapshot older than `24` hours.
  - **Breach:** cached snapshot older than `72` hours (logged in `data/generated/ops-slo-report.json` and workflow step summary).

---

## 2. Quality & Relational Integrity Gates

Before committing any update or marking CI green, two independent gates verify the generated artifact:

1. **Regression & encoding gate (`scripts/validate-generated-data.ps1`):**
   - Verifies zero episode sequence gaps (`1..max`) against [`data/quality-baseline.json`](../data/quality-baseline.json).
   - Verifies date coverage, synopsis quality (no empty, title-only, template-only, or encoding-corrupted strings), and chapter adaptation mapping invariants.
2. **Normalized SQLite + FTS5 integrity gate (`scripts/build_catalog_db.py`):**
   - Atomically compiles the generated `docs/index.html` catalog, `data/chapter-adaptations.json`, and `data/appearance-audits.json` into `data/generated/one-piece-catalog.sqlite` via temp file + `os.replace()`.
   - Enforces `PRAGMA foreign_keys = ON`, `PRAGMA integrity_check`, `PRAGMA foreign_key_check`, checks for chapter-adaptation drift between `chapter-adaptations.json` and embedded HTML, rebuilds `entries_fts`, and benchmarks FTS5 P95 query latency.

---

## 3. Triage Steps When Scheduled Refresh Fails

1. Download the `generated-data-quality-<run_id>` artifact from the failed GitHub Actions run and inspect `quality-report.json`, `catalog-db-report.json`, and `ops-slo-report.json`.
2. Distinguish **upstream outage** (look for HTTP retry warnings in logs and stale cache age in `ops-slo-report.json`) from **baseline/schema drift**:
   - If upstream Series Graph / Jikan omitted recent episodes, inspect whether stale snapshot cache was corrupted or partially overwritten; invalidate cache key if needed after local verification.
   - If the failure came from a deliberate chapter-adaptation or baseline expectation change, verify locally with:
     ```powershell
     powershell -ExecutionPolicy Bypass -File scripts\generate.ps1 -UseCachedRatings
     powershell -ExecutionPolicy Bypass -File scripts\validate-generated-data.ps1
     python scripts/test_catalog_db.py
     python scripts/build_catalog_db.py
     ```
3. Only update [`data/quality-baseline.json`](../data/quality-baseline.json) upward after confirming episode sequence continuity (`gaps == 0`) and valid synopsis/adaptation coverage in `quality-report.json`.

---

## 4. Querying the Generated SQLite Artifact

The `.sqlite` catalog file stays gitignored (`data/generated/`) and is uploaded as a GitHub Actions workflow artifact on CI and scheduled refreshes. To build and query it locally:

```powershell
python scripts/build_catalog_db.py
python -c "import sqlite3; c=sqlite3.connect('data/generated/one-piece-catalog.sqlite'); print(c.execute('SELECT saga, COUNT(*), ROUND(AVG(rating),2) FROM entries WHERE media_kind=\"episode\" GROUP BY saga ORDER BY MIN(episode_number)').fetchall())"
```

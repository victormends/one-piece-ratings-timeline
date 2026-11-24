"""Build normalized SQLite + FTS5 catalog database and verify relational integrity."""

from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import sys
import time
from typing import Any, Dict, List, Optional, Sequence, Tuple

EPISODE_DATA_RE = re.compile(
    r'<script\s+id="episode-data"\s+type="application/json">([\s\S]*?)</script>'
)

SCHEMA_SQL = """
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = DELETE;

CREATE TABLE entries (
    entry_id TEXT PRIMARY KEY,
    media_kind TEXT NOT NULL,
    episode_number INTEGER,
    title TEXT NOT NULL,
    saga TEXT,
    sub_saga TEXT,
    entry_type TEXT,
    aired TEXT,
    rating REAL CHECK(rating IS NULL OR (rating >= 0.0 AND rating <= 10.0)),
    synopsis TEXT,
    synopsis_status TEXT
);

CREATE UNIQUE INDEX idx_entries_episode
    ON entries(episode_number)
    WHERE media_kind = 'episode' AND episode_number IS NOT NULL;

CREATE INDEX idx_entries_saga_kind ON entries(saga, media_kind);
CREATE INDEX idx_entries_rating ON entries(rating);

CREATE TABLE chapter_adaptations (
    entry_id TEXT NOT NULL REFERENCES entries(entry_id) ON DELETE CASCADE,
    chapter INTEGER NOT NULL CHECK(chapter >= 1),
    pages TEXT NOT NULL,
    url TEXT NOT NULL,
    PRIMARY KEY (entry_id, chapter)
);

CREATE TABLE appearance_tags (
    tag_key TEXT PRIMARY KEY,
    label TEXT NOT NULL,
    first_appearance INTEGER
);

CREATE TABLE entry_appearances (
    tag_key TEXT NOT NULL REFERENCES appearance_tags(tag_key) ON DELETE CASCADE,
    episode_number INTEGER NOT NULL CHECK(episode_number >= 0),
    role TEXT NOT NULL CHECK(role IN ('appears', 'focused', 'flashback', 'remote')),
    PRIMARY KEY (tag_key, episode_number, role)
);

CREATE INDEX idx_entry_appearances_ep ON entry_appearances(episode_number);

CREATE VIRTUAL TABLE entries_fts USING fts5(
    title,
    saga,
    synopsis,
    content='entries',
    content_rowid='rowid'
);
"""


def _read_json_bom_safe(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def _extract_entries(html_path: Path) -> List[Dict[str, Any]]:
    html_text = html_path.read_text(encoding="utf-8-sig")
    match = EPISODE_DATA_RE.search(html_text)
    if not match:
        raise ValueError(f"Generated HTML missing episode-data JSON block: {html_path}")
    entries = json.loads(match.group(1))
    if not isinstance(entries, list) or not entries:
        raise ValueError("episode-data block is empty or not a JSON array")
    return entries


def _expand_appearance_items(items: Sequence[Any]) -> List[int]:
    expanded: List[int] = []
    for item in items:
        if isinstance(item, (list, tuple)) and len(item) == 2:
            start, end = int(item[0]), int(item[1])
            if end < start:
                raise ValueError(f"Inverted appearance episode range: {start}..{end}")
            expanded.extend(range(start, end + 1))
        else:
            expanded.append(int(item))
    return expanded


def _p95_ms(samples: Sequence[float]) -> float:
    if not samples:
        return 0.0
    ordered = sorted(samples)
    idx = min(len(ordered) - 1, max(0, math.ceil(0.95 * len(ordered)) - 1))
    return round(ordered[idx], 3)


def build_catalog_db(
    html_path: Path,
    adaptations_path: Path,
    appearances_path: Path,
    output_db: Path,
    report_path: Path,
    probe_term: str = "Luffy",
) -> Dict[str, Any]:
    started = time.perf_counter()
    entries = _extract_entries(html_path)
    adaptations_doc = _read_json_bom_safe(adaptations_path) if adaptations_path.exists() else {}
    appearances_doc = _read_json_bom_safe(appearances_path) if appearances_path.exists() else {}

    output_db.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_db = output_db.with_name(f".{output_db.name}.{os.getpid()}.tmp")
    if tmp_db.exists():
        tmp_db.unlink()

    conn: Optional[sqlite3.Connection] = None
    try:
        conn = sqlite3.connect(str(tmp_db))
        conn.executescript(SCHEMA_SQL)

        entry_rows: List[Tuple[Any, ...]] = []
        adaptation_rows: List[Tuple[str, int, str, str]] = []
        tv_episode_numbers: List[int] = []
        embedded_adapt_counts: Dict[str, int] = {}

        for item in entries:
            entry_id = str(item.get("displayCode") or "").strip()
            if not entry_id:
                raise ValueError(f"Entry missing non-empty displayCode: {item}")
            media_kind = str(item.get("mediaKind") or "").strip()
            ep_raw = item.get("episode")
            ep_num = int(ep_raw) if ep_raw is not None else None
            if media_kind == "episode":
                if ep_num is None or ep_num < 1:
                    raise ValueError(f"Invalid TV episode number on {entry_id}: {ep_raw}")
                tv_episode_numbers.append(ep_num)

            entry_rows.append(
                (
                    entry_id,
                    media_kind,
                    ep_num,
                    str(item.get("title") or ""),
                    item.get("saga"),
                    item.get("subSaga"),
                    item.get("category"),
                    item.get("aired"),
                    float(item["rating"]) if item.get("rating") is not None else None,
                    item.get("originalNote"),
                    item.get("synopsisStatus"),
                )
            )

            seen_chapters = set()
            raw_adaptations = item.get("adaptations") or []
            for ad in raw_adaptations:
                ch = int(ad["chapter"])
                if ch in seen_chapters:
                    continue
                seen_chapters.add(ch)
                adaptation_rows.append(
                    (
                        entry_id,
                        ch,
                        str(ad["pages"]),
                        str(ad["url"]),
                    )
                )
            if ep_num is not None and raw_adaptations:
                embedded_adapt_counts[str(ep_num)] = len(seen_chapters)

        # Cross-check embedded adaptations vs chapter-adaptations.json when present.
        ca_episodes = adaptations_doc.get("episodes", {})
        if ca_episodes:
            for ep_key, ad_list in ca_episodes.items():
                expected_count = len({int(a["chapter"]) for a in ad_list})
                actual_count = embedded_adapt_counts.get(str(ep_key), 0)
                if expected_count != actual_count:
                    raise ValueError(
                        f"Chapter adaptation drift for episode {ep_key}: "
                        f"JSON has {expected_count}, HTML embeds {actual_count}"
                    )

        tag_rows: List[Tuple[str, str, Optional[int]]] = []
        app_rows_set = set()
        raw_tags = appearances_doc.get("tags", {})
        for tag_key, tag_obj in raw_tags.items():
            label = str(tag_obj.get("label") or tag_key)
            first_app_raw = tag_obj.get("firstAppearance")
            first_app = int(first_app_raw) if first_app_raw is not None else None
            tag_rows.append((str(tag_key), label, first_app))
            for role in ("appears", "focused", "flashback", "remote"):
                for ep in _expand_appearance_items(tag_obj.get(role, [])):
                    app_rows_set.add((str(tag_key), ep, role))

        with conn:
            conn.executemany(
                """
                INSERT INTO entries (
                    entry_id, media_kind, episode_number, title, saga,
                    sub_saga, entry_type, aired, rating, synopsis, synopsis_status
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                entry_rows,
            )
            conn.executemany(
                """
                INSERT INTO chapter_adaptations (entry_id, chapter, pages, url)
                VALUES (?, ?, ?, ?)
                """,
                adaptation_rows,
            )
            conn.executemany(
                """
                INSERT INTO appearance_tags (tag_key, label, first_appearance)
                VALUES (?, ?, ?)
                """,
                tag_rows,
            )
            conn.executemany(
                """
                INSERT INTO entry_appearances (tag_key, episode_number, role)
                VALUES (?, ?, ?)
                """,
                sorted(app_rows_set),
            )
            conn.execute("INSERT INTO entries_fts(entries_fts) VALUES ('rebuild')")

        # Database reliability assertions before atomic swap.
        integrity_row = conn.execute("PRAGMA integrity_check").fetchone()
        integrity_ok = bool(integrity_row and integrity_row[0] == "ok")
        if not integrity_ok:
            raise RuntimeError(f"SQLite integrity_check failed: {integrity_row}")

        fk_violations = conn.execute("PRAGMA foreign_key_check").fetchall()
        if fk_violations:
            raise RuntimeError(f"SQLite foreign_key_check failed: {len(fk_violations)} violation(s)")

        if not tv_episode_numbers:
            raise ValueError("No TV episodes found in entries table")
        max_ep = max(tv_episode_numbers)
        unique_tv = set(tv_episode_numbers)
        if len(unique_tv) != max_ep:
            missing = sorted(set(range(1, max_ep + 1)) - unique_tv)
            raise ValueError(f"TV episode sequence gaps detected: {missing[:10]}")

        probe_hits = conn.execute(
            "SELECT count(*) FROM entries_fts WHERE entries_fts MATCH ?",
            (probe_term,),
        ).fetchone()[0]
        if probe_hits < 1:
            raise RuntimeError(f"FTS5 index sanity probe for '{probe_term}' returned 0 hits")

        # Measure 20-query FTS5 latency profile.
        probe_terms = [probe_term, "saga", "pirate", "episode", "crew"]
        latencies_ms: List[float] = []
        for idx in range(20):
            term = probe_terms[idx % len(probe_terms)]
            t0 = time.perf_counter()
            conn.execute(
                """
                SELECT e.entry_id, e.title
                FROM entries_fts f
                JOIN entries e ON e.rowid = f.rowid
                WHERE entries_fts MATCH ?
                LIMIT 15
                """,
                (term,),
            ).fetchall()
            latencies_ms.append((time.perf_counter() - t0) * 1000.0)

        conn.close()
        conn = None

        os.replace(str(tmp_db), str(output_db))
        build_ms = round((time.perf_counter() - started) * 1000.0, 2)
        db_size_bytes = output_db.stat().st_size

        report: Dict[str, Any] = {
            "version": 1,
            "entries_total": len(entry_rows),
            "tv_episodes": len(tv_episode_numbers),
            "tv_episode_max": max_ep,
            "chapter_mappings": len(adaptation_rows),
            "appearance_tags": len(tag_rows),
            "appearance_links": len(app_rows_set),
            "fts_probe_term": probe_term,
            "fts_probe_hits": int(probe_hits),
            "fts_p95_ms": _p95_ms(latencies_ms),
            "build_ms": build_ms,
            "db_size_bytes": db_size_bytes,
            "integrity_ok": integrity_ok,
            "foreign_key_violations": len(fk_violations),
        }
        report_path.write_text(
            json.dumps(report, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        return report
    finally:
        if conn is not None:
            conn.close()
        if tmp_db.exists():
            tmp_db.unlink()


def main(argv: Optional[Sequence[str]] = None) -> int:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--html", type=Path, default=repo_root / "docs" / "index.html")
    parser.add_argument(
        "--adaptations",
        type=Path,
        default=repo_root / "data" / "chapter-adaptations.json",
    )
    parser.add_argument(
        "--appearances",
        type=Path,
        default=repo_root / "data" / "appearance-audits.json",
    )
    parser.add_argument(
        "--output-db",
        type=Path,
        default=repo_root / "data" / "generated" / "one-piece-catalog.sqlite",
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=repo_root / "data" / "generated" / "catalog-db-report.json",
    )
    parser.add_argument("--probe-term", default="Luffy")
    args = parser.parse_args(argv)

    report = build_catalog_db(
        html_path=args.html,
        adaptations_path=args.adaptations,
        appearances_path=args.appearances,
        output_db=args.output_db,
        report_path=args.report,
        probe_term=args.probe_term,
    )
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

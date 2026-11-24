"""Unit tests for normalized SQLite + FTS5 catalog builder."""

from __future__ import annotations

import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_catalog_db import build_catalog_db


class TestCatalogDb(unittest.TestCase):
    def _write_fixture(self, root: Path, entries: list) -> tuple:
        html_path = root / "index.html"
        adapt_path = root / "chapter-adaptations.json"
        appear_path = root / "appearance-audits.json"
        db_path = root / "out" / "catalog.sqlite"
        report_path = root / "out" / "report.json"

        html_path.write_text(
            f'<html><body><script id="episode-data" type="application/json">{json.dumps(entries)}</script></body></html>',
            encoding="utf-8",
        )
        adapt_path.write_text(
            json.dumps(
                {
                    "version": 1,
                    "episodes": {
                        "1": [
                            {
                                "chapter": 2,
                                "pages": "4-23",
                                "url": "https://onepiece.fandom.com/wiki/Chapter_2",
                            }
                        ]
                    },
                }
            ),
            encoding="utf-8",
        )
        appear_path.write_text(
            json.dumps(
                {
                    "version": 1,
                    "tags": {
                        "luffy": {
                            "label": "Monkey D. Luffy",
                            "firstAppearance": 1,
                            "appears": [[1, 2]],
                            "focused": [1],
                            "flashback": [],
                            "remote": [],
                        }
                    },
                }
            ),
            encoding="utf-8-sig",
        )
        return html_path, adapt_path, appear_path, db_path, report_path

    def test_atomic_build_fts_and_integrity(self) -> None:
        entries = [
            {
                "displayCode": "E1",
                "mediaKind": "episode",
                "episode": 1,
                "title": "I'm Luffy!",
                "saga": "east-blue",
                "subSaga": "romance-dawn",
                "category": "manga",
                "aired": "1999-10-20",
                "rating": 8.4,
                "adaptations": [
                    {
                        "chapter": 2,
                        "pages": "4-23",
                        "url": "https://onepiece.fandom.com/wiki/Chapter_2",
                    }
                ],
                "originalNote": "Luffy meets Coby aboard Alvida's ship.",
                "synopsisStatus": "reviewed",
            },
            {
                "displayCode": "E2",
                "mediaKind": "episode",
                "episode": 2,
                "title": "Enter the Great Swordsman! Zoro",
                "saga": "east-blue",
                "subSaga": "romance-dawn",
                "category": "manga",
                "aired": "1999-11-17",
                "rating": 8.2,
                "adaptations": [],
                "originalNote": "Luffy frees Zoro from Shells Town.",
                "synopsisStatus": "reviewed",
            },
            {
                "displayCode": "M1",
                "mediaKind": "movie",
                "episode": None,
                "title": "One Piece: The Movie",
                "saga": "east-blue",
                "subSaga": "syrup-village",
                "category": "movie",
                "aired": "2000-03-04",
                "rating": 7.1,
                "originalNote": "Side adventure before Sanji.",
                "synopsisStatus": "reviewed",
            },
        ]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            html_path, adapt_path, appear_path, db_path, report_path = self._write_fixture(root, entries)
            report = build_catalog_db(html_path, adapt_path, appear_path, db_path, report_path)

            self.assertEqual(report["entries_total"], 3)
            self.assertEqual(report["tv_episodes"], 2)
            self.assertEqual(report["chapter_mappings"], 1)
            self.assertEqual(report["appearance_tags"], 1)
            self.assertEqual(report["appearance_links"], 3)
            self.assertTrue(report["integrity_ok"])
            self.assertEqual(report["foreign_key_violations"], 0)
            self.assertTrue(db_path.exists())
            self.assertTrue(report_path.exists())

            conn = sqlite3.connect(str(db_path))
            try:
                hits = conn.execute(
                    "SELECT count(*) FROM entries_fts WHERE entries_fts MATCH 'Zoro'"
                ).fetchone()[0]
                self.assertEqual(hits, 1)
            finally:
                conn.close()

    def test_detects_episode_sequence_gap(self) -> None:
        entries = [
            {
                "displayCode": "E1",
                "mediaKind": "episode",
                "episode": 1,
                "title": "Luffy Episode 1",
                "saga": "east-blue",
                "rating": 8.0,
                "adaptations": [
                    {
                        "chapter": 2,
                        "pages": "4-23",
                        "url": "https://onepiece.fandom.com/wiki/Chapter_2",
                    }
                ],
                "originalNote": "Start.",
                "synopsisStatus": "reviewed",
            },
            {
                "displayCode": "E3",
                "mediaKind": "episode",
                "episode": 3,
                "title": "Gap Episode 3",
                "saga": "east-blue",
                "rating": 7.5,
                "originalNote": "Missing E2.",
                "synopsisStatus": "reviewed",
            },
        ]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            html_path, adapt_path, appear_path, db_path, report_path = self._write_fixture(root, entries)
            with self.assertRaises(ValueError):
                build_catalog_db(html_path, adapt_path, appear_path, db_path, report_path)


if __name__ == "__main__":
    unittest.main(verbosity=2)

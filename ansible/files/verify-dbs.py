#!/usr/bin/env python3
"""Run SQLite integrity checks on every SQLite database under a directory."""
import sqlite3
import sys
from pathlib import Path
from urllib.parse import quote

SQLITE_MAGIC = b"SQLite format 3\x00"
root = Path(sys.argv[1])
bad = 0
for p in sorted(root.rglob("*")):
    if not p.is_file() or p.is_symlink():
        continue
    try:
        with p.open("rb") as f:
            head = f.read(16)
    except OSError:
        continue
    if head != SQLITE_MAGIC:
        continue
    try:
        con = sqlite3.connect(f"file:{quote(str(p))}?mode=ro", uri=True)
        res = con.execute("PRAGMA integrity_check").fetchone()[0]
        con.close()
    except sqlite3.Error as e:
        res = f"ERROR: {e}"
    print(f"{res:<8} {p}")
    if res != "ok":
        bad += 1
print(f"{bad} database(s) failed")
sys.exit(1 if bad else 0)

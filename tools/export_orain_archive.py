#!/usr/bin/env python3
"""Export an Òrain per-user library to the iOS archive format.

WHAT IT DOES
    Reads a per-user SQLite library (``data/users/{id}/orain.db``) and writes a
    single JSON file that the iOS app can import. Read-only: it opens the
    database in immutable mode and never writes to it.

WHY IT EXISTS
    The iOS app keeps its library on the phone (see ORAIN-IOS-SCOPE.md for
    why it cannot depend on the Pi). Callum's songs already live on the Pi, so
    they need one clean way across. This is it.

USAGE
    Dry run first — prints what it found, writes nothing:
        python3 export_orain_archive.py ~/orain/data/users/1/orain.db --inspect

    Then the real export:
        python3 export_orain_archive.py ~/orain/data/users/1/orain.db \
            -o ~/Desktop/orain-library.json

DEFENSIVE BY DESIGN
    The script introspects the schema rather than assuming it. Columns added
    after this was written (or absent because a migration has not run) are
    handled without a crash, and anything unexpected is reported rather than
    silently dropped. This matters because the project-knowledge snapshots of
    the schema have drifted from the live Pi before.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import sqlite3
import sys
from pathlib import Path

SCHEMA_VERSION = 1


# ---------------------------------------------------------------------------
# Schema introspection
# ---------------------------------------------------------------------------

def table_exists(conn: sqlite3.Connection, name: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)
    ).fetchone()
    return row is not None


def columns(conn: sqlite3.Connection, table: str) -> list[str]:
    return [r["name"] for r in conn.execute(f"PRAGMA table_info({table})")]


def pick(row: sqlite3.Row, available: set[str], name: str, default=None):
    """Read a column if this database actually has it."""
    return row[name] if name in available else default


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def export(db_path: Path, source_label: str) -> dict:
    uri = f"file:{db_path}?mode=ro&immutable=1"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row

    try:
        try:
            is_library = table_exists(conn, "songs") and table_exists(conn, "song_versions")
        except sqlite3.DatabaseError:
            raise SystemExit(
                f"{db_path} is not a SQLite database. Point this at a per-user "
                "library file, e.g. ~/orain/data/users/1/orain.db"
            ) from None

        if not is_library:
            raise SystemExit(
                f"{db_path} does not look like an Òrain library "
                "(no songs / song_versions tables)."
            )

        song_cols = set(columns(conn, "songs"))
        version_cols = set(columns(conn, "song_versions"))
        has_media = table_exists(conn, "song_media")
        media_cols = set(columns(conn, "song_media")) if has_media else set()

        # Media, grouped by version, in one pass.
        media_by_version: dict[int, list[dict]] = {}
        if has_media:
            for row in conn.execute("SELECT * FROM song_media ORDER BY id"):
                entry = {"kind": pick(row, media_cols, "kind", "audio")}
                for key in ("url", "filename", "label"):
                    value = pick(row, media_cols, key)
                    if value is not None:
                        entry[key] = value
                media_by_version.setdefault(row["version_id"], []).append(entry)

        # Versions, grouped by song, in one pass.
        versions_by_song: dict[int, list[dict]] = {}
        for row in conn.execute("SELECT * FROM song_versions ORDER BY song_id, id"):
            version = {
                "id": row["id"],
                "song_id": row["song_id"],
                "version_label": pick(row, version_cols, "version_label"),
                "version_title": pick(row, version_cols, "version_title"),
                "language": pick(row, version_cols, "language", "gd"),
                "lyrics": pick(row, version_cols, "lyrics"),
                "melody": pick(row, version_cols, "melody"),
                "source": pick(row, version_cols, "source"),
                "transpose": pick(row, version_cols, "transpose", 0) or 0,
                "is_canonical": bool(pick(row, version_cols, "is_canonical", 0)),
                "created_at": pick(row, version_cols, "created_at"),
                "media": media_by_version.get(row["id"], []),
            }
            versions_by_song.setdefault(row["song_id"], []).append(version)

        songs = []
        for row in conn.execute("SELECT * FROM songs ORDER BY id"):
            songs.append(
                {
                    "slug": row["slug"],
                    "title": row["title"],
                    "composer": pick(row, song_cols, "composer"),
                    "rating": pick(row, song_cols, "rating"),
                    "is_favourite": bool(pick(row, song_cols, "is_favourite", 0)),
                    "on_hitlist": bool(pick(row, song_cols, "on_hitlist", 0)),
                    "notes": pick(row, song_cols, "notes"),
                    "tradition": pick(row, song_cols, "tradition"),
                    "created_at": pick(row, song_cols, "created_at"),
                    "versions": versions_by_song.get(row["id"], []),
                }
            )
    finally:
        conn.close()

    return {
        "schema_version": SCHEMA_VERSION,
        "exported_at": _dt.datetime.now(_dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "source": source_label,
        "songs": songs,
    }


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

def report(archive: dict) -> None:
    songs = archive["songs"]
    versions = [v for s in songs for v in s["versions"]]
    media = [m for v in versions for m in v["media"]]

    no_versions = [s["title"] for s in songs if not s["versions"]]
    no_lyrics = [
        s["title"]
        for s in songs
        if s["versions"] and not any((v["lyrics"] or "").strip() for v in s["versions"])
    ]
    no_canonical = [s["title"] for s in songs if s["versions"] and not any(v["is_canonical"] for v in s["versions"])]
    multi_canonical = [
        s["title"] for s in songs if sum(1 for v in s["versions"] if v["is_canonical"]) > 1
    ]
    audio = [m for m in media if m.get("kind") == "audio"]
    video = [m for m in media if m.get("kind") == "video"]

    print(f"Songs          : {len(songs)}")
    print(f"Versions       : {len(versions)}")
    print(f"Video links    : {len(video)}")
    print(f"Audio files    : {len(audio)}  (NOT carried in the JSON — see below)")
    print()
    print(f"Gàidhlig       : {sum(1 for v in versions if v['language'] == 'gd')} versions")
    print(f"Beurla         : {sum(1 for v in versions if v['language'] == 'en')} versions")
    print(f"With chords    : {sum(1 for v in versions if '[' in (v['lyrics'] or ''))} versions")
    print(f"Favourites     : {sum(1 for s in songs if s['is_favourite'])}")
    print(f"On hitlist     : {sum(1 for s in songs if s['on_hitlist'])}")
    print(f"Rated          : {sum(1 for s in songs if s['rating'])}")

    def warn(label: str, items: list[str]) -> None:
        if items:
            print(f"\n{label} ({len(items)}):")
            for t in items[:20]:
                print(f"  - {t}")
            if len(items) > 20:
                print(f"  … and {len(items) - 20} more")

    warn("Songs with NO versions", no_versions)
    warn("Songs with no lyrics in any version", no_lyrics)
    warn("Songs with no canonical version", no_canonical)
    warn("Songs with MORE THAN ONE canonical version", multi_canonical)

    if audio:
        print(
            "\nNote: audio recordings are referenced by filename only. The "
            "\naudio itself stays on the Pi; the import will tell you how many "
            "\nwere left behind rather than pretending they came across."
        )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Export an Òrain library to the iOS archive JSON format."
    )
    parser.add_argument("database", type=Path, help="path to a per-user orain.db")
    parser.add_argument(
        "-o", "--output", type=Path, help="where to write the JSON (default: stdout)"
    )
    parser.add_argument(
        "--inspect",
        action="store_true",
        help="report what was found and write nothing",
    )
    parser.add_argument(
        "--label",
        default=None,
        help="text recorded in the file's 'source' field (default: the db path)",
    )
    args = parser.parse_args(argv)

    if not args.database.exists():
        print(f"No such file: {args.database}", file=sys.stderr)
        return 1

    archive = export(args.database, args.label or str(args.database))

    if args.inspect:
        report(archive)
        print("\n--inspect: nothing written.")
        return 0

    payload = json.dumps(archive, ensure_ascii=False, indent=2) + "\n"

    if args.output:
        args.output.write_text(payload, encoding="utf-8")
        report(archive)
        size_kb = args.output.stat().st_size / 1024
        print(f"\nWrote {args.output} ({size_kb:.1f} KB)")
    else:
        sys.stdout.write(payload)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

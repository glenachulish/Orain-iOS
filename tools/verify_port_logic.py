#!/usr/bin/env python3
"""Check the *logic* of the Swift ChordPro port without a Swift compiler.

WHY THIS EXISTS
    ChordPro.swift was written in an environment with no Swift toolchain, so
    it could not be compiled or run. That leaves two separate risks:

        1. Swift syntax errors      — caught the moment `swift test` runs.
        2. Wrong algorithm          — NOT caught by compiling, and much worse,
                                      because it fails quietly on odd inputs.

    This script attacks risk 2. It is a deliberate line-for-line
    transliteration of ChordPro.swift into Python — same variable names, same
    branch order, same off-by-one decisions — run against the same golden
    fixtures the Swift tests use. If this passes, the algorithm the Swift
    expresses is right, and `swift test` is left to catch only syntax.

    It is NOT a substitute for `swift test`. It is a way of being wrong about
    fewer things at once.

USAGE
    python3 tools/verify_port_logic.py
"""

from __future__ import annotations

import json
import sys
import unicodedata
from pathlib import Path

FIXTURES = (
    Path(__file__).resolve().parent.parent
    / "OrainCore/Tests/OrainCoreTests/Fixtures/chordpro-goldens.json"
)

WHITESPACE = " \t\n\r\v\f   "

DIRECTIVE_MAP = {
    "start_of_chorus": ("chorus", "start"),
    "end_of_chorus": ("chorus", "end"),
    "start_of_verse": ("verse", "start"),
    "end_of_verse": ("verse", "end"),
    "start_of_bridge": ("bridge", "start"),
    "end_of_bridge": ("bridge", "end"),
    "soc": ("chorus", "start"),
    "eoc": ("chorus", "end"),
    "sov": ("verse", "start"),
    "eov": ("verse", "end"),
    "sob": ("bridge", "start"),
    "eob": ("bridge", "end"),
}


# --- transliteration of ChordPro.swift -------------------------------------


def parse_chordpro_line(line: str):
    """Mirror of ChordPro.parseChordProLine."""
    chars = list(line)
    segments = []
    last_end = 0
    current_chord = None
    i = 0

    while i < len(chars):
        if chars[i] != "[":
            i += 1
            continue

        j = i + 1
        while j < len(chars) and chars[j] != "]":
            j += 1

        if not (j < len(chars) and j > i + 1):
            i += 1
            continue

        match_index = i
        chord = "".join(chars[i + 1 : j])

        if match_index > last_end or current_chord is not None:
            segments.append(
                {"chord": current_chord, "text": "".join(chars[last_end:match_index])}
            )

        current_chord = chord
        last_end = j + 1
        i = j + 1

    if last_end < len(chars) or current_chord is not None:
        segments.append({"chord": current_chord, "text": "".join(chars[last_end:])})

    return segments


def parse_directive_line(line: str):
    """Mirror of ChordPro.parseDirectiveLine."""
    trimmed = line.strip(WHITESPACE)
    if not (len(trimmed) >= 2 and trimmed.startswith("{") and trimmed.endswith("}")):
        return None

    inner = trimmed[1:-1]

    if ":" in inner:
        colon = inner.index(":")
        key = inner[:colon]
        raw_value = inner[colon + 1 :]
    else:
        key = inner
        raw_value = None

    if not key or "}" in key:
        return None
    if raw_value is not None and "}" in raw_value:
        return None

    entry = DIRECTIVE_MAP.get(key.strip(" \t").lower())
    if entry is None:
        return None

    if raw_value is not None and raw_value != "":
        label = raw_value.strip(" \t")
    else:
        label = None

    return {"kind": entry[0], "boundary": entry[1], "label": label}


def build_directive_line(kind: str, boundary: str, label):
    """Mirror of ChordPro.buildDirectiveLine."""
    name = f"{boundary}_of_{kind}"
    if label is not None and label.strip(" \t") != "":
        return "{" + name + ": " + label.strip(" \t") + "}"
    return "{" + name + "}"


def get_sections(lyrics):
    """Mirror of ChordPro.getSections."""
    if not lyrics:
        return []

    sections = []
    current_kind = "plain"
    current_label = None
    current_lines = []

    for line in lyrics.split("\n"):
        d = parse_directive_line(line)
        if d is None:
            current_lines.append(line)
            continue

        if d["boundary"] == "start":
            if current_lines:
                sections.append(
                    {"kind": current_kind, "label": current_label, "lines": current_lines}
                )
            current_kind = d["kind"]
            current_label = d["label"]
            current_lines = []
        else:
            sections.append(
                {"kind": current_kind, "label": current_label, "lines": current_lines}
            )
            current_kind = "plain"
            current_label = None
            current_lines = []

    if current_lines:
        sections.append(
            {"kind": current_kind, "label": current_label, "lines": current_lines}
        )

    return sections


def has_chorus(lyrics):
    return any(s["kind"] == "chorus" for s in get_sections(lyrics))


def repeat_chorus(lyrics):
    """Mirror of ChordPro.repeatChorus."""
    if not lyrics:
        return ""

    sections = get_sections(lyrics)
    chorus = next((s for s in sections if s["kind"] == "chorus"), None)
    if chorus is None:
        return lyrics

    def section_to_lines(s):
        if s["kind"] == "plain":
            return list(s["lines"])
        return (
            [build_directive_line(s["kind"], "start", s["label"])]
            + list(s["lines"])
            + [build_directive_line(s["kind"], "end", None)]
        )

    chorus_lines = section_to_lines(chorus)

    out = []
    for i, s in enumerate(sections):
        out.extend(section_to_lines(s))
        if s["kind"] == "verse":
            nxt = sections[i + 1] if i + 1 < len(sections) else None
            already_followed = nxt is not None and nxt["kind"] == "chorus"
            if not already_followed:
                out.extend(chorus_lines)

    return "\n".join(out)


def lyrics_to_editor(lyrics):
    """Mirror of ChordPro.lyricsToEditor."""
    if not lyrics:
        return [{"chords": "", "lyric": ""}]

    rows = []
    for line in lyrics.split("\n"):
        if parse_directive_line(line) is not None:
            rows.append({"chords": "", "lyric": line})
            continue

        segs = parse_chordpro_line(line)
        chord_chars = []
        lyric_chars = []

        for i, seg in enumerate(segs):
            pos = len(lyric_chars)
            if seg["chord"] is not None:
                if len(chord_chars) < pos:
                    chord_chars.extend(" " * (pos - len(chord_chars)))
                chord_chars.extend(seg["chord"])

            text = seg["text"]
            prev = segs[i - 1] if i > 0 else None
            safe = (i == 0) or (
                prev is not None
                and len(prev["text"]) > 0
                and prev["text"][-1] in WHITESPACE
            )
            if safe:
                while text.startswith(" "):
                    text = text[1:]
            lyric_chars.extend(text)

        while chord_chars and chord_chars[-1] in WHITESPACE:
            chord_chars.pop()

        rows.append({"chords": "".join(chord_chars), "lyric": "".join(lyric_chars)})

    return rows


def editor_to_lyrics(rows):
    """Mirror of ChordPro.editorToLyrics."""
    lines = []

    for row in rows:
        if parse_directive_line(row["lyric"]) is not None:
            lines.append(row["lyric"])
            continue

        if row["chords"].strip(WHITESPACE) == "":
            lines.append(row["lyric"])
            continue

        chords = list(row["chords"])
        lyric = list(row["lyric"])

        result = ""
        i = 0
        j = 0

        while i < len(chords) or j < len(lyric):
            if i < len(chords) and chords[i] != " ":
                chord = ""
                while i < len(chords) and chords[i] != " ":
                    chord += chords[i]
                    i += 1
                result += "[" + chord + "]"

            if j < len(lyric):
                result += lyric[j]
                j += 1
                i = max(i, j)
            else:
                i += 1

        lines.append(result)

    return "\n".join(lines)


# --- transliteration of Library.swift --------------------------------------


def folded_title(title: str) -> str:
    """Mirror of SongSorting.foldedTitle."""
    return "".join(
        ch
        for ch in unicodedata.normalize("NFD", title)
        if unicodedata.category(ch) not in ("Mn", "Mc", "Me")
    ).lower()


# --- the check --------------------------------------------------------------


class Checker:
    def __init__(self) -> None:
        self.passed = 0
        self.failures: list[str] = []

    def check(self, group: str, actual, expected, context: str) -> None:
        if actual == expected:
            self.passed += 1
        else:
            self.failures.append(
                f"{group}: {context}\n    expected: {expected!r}\n    actual:   {actual!r}"
            )


def main() -> int:
    if not FIXTURES.exists():
        print(f"Fixtures not found at {FIXTURES}", file=sys.stderr)
        print("Run: node tools/generate_goldens.mjs", file=sys.stderr)
        return 1

    g = json.loads(FIXTURES.read_text(encoding="utf-8"))
    c = Checker()

    for case in g["parseChordProLine"]:
        c.check(
            "parseChordProLine",
            parse_chordpro_line(case["input"]),
            case["expected"],
            repr(case["input"]),
        )

    for case in g["parseDirectiveLine"]:
        c.check(
            "parseDirectiveLine",
            parse_directive_line(case["input"]),
            case["expected"],
            repr(case["input"]),
        )

    for case in g["buildDirectiveLine"]:
        c.check(
            "buildDirectiveLine",
            build_directive_line(case["kind"], case["boundary"], case["label"]),
            case["expected"],
            f"{case['kind']}/{case['boundary']}/{case['label']!r}",
        )

    for case in g["getSections"]:
        c.check(
            "getSections",
            get_sections(case["input"]),
            case["expected"],
            repr(case["input"]),
        )

    for case in g["hasChorus"]:
        c.check("hasChorus", has_chorus(case["input"]), case["expected"], repr(case["input"]))

    for case in g["repeatChorus"]:
        c.check(
            "repeatChorus", repeat_chorus(case["input"]), case["expected"], repr(case["input"])
        )

    for case in g["lyricsToEditor"]:
        c.check(
            "lyricsToEditor",
            lyrics_to_editor(case["input"]),
            case["expected"],
            repr(case["input"]),
        )

    for case in g["editorToLyrics"]:
        c.check(
            "editorToLyrics",
            editor_to_lyrics(case["input"]),
            case["expected"],
            repr(case["input"]),
        )

    for case in g["roundTrip"]:
        c.check(
            "roundTrip",
            editor_to_lyrics(lyrics_to_editor(case["input"])),
            case["expected"],
            repr(case["input"]),
        )

    # Sorting expectations asserted by the Swift test suite.
    c.check(
        "sorting",
        sorted(
            ["Wild Mountain Thyme", "Òrain Eirisgeidh", "Oran Mòr", "Ailein Duinn"],
            key=lambda t: (folded_title(t), t),
        ),
        ["Ailein Duinn", "Òrain Eirisgeidh", "Oran Mòr", "Wild Mountain Thyme"],
        "accented initial files with its plain letter",
    )
    c.check("sorting", folded_title("Òrain"), "orain", "fold Òrain")
    c.check("sorting", folded_title("ÉISLEAN"), "eislean", "fold ÉISLEAN")
    c.check("sorting", folded_title("Fear a' Bhàta"), "fear a' bhata", "fold Fear a' Bhàta")
    c.check(
        "sorting", folded_title("Òran") == folded_title("Oran"), True, "Òran and Oran tie"
    )
    c.check("sorting", "Oran" < "Òran", True, "raw title breaks the tie")

    print(f"Checked {c.passed + len(c.failures)} assertions against the golden fixtures.")
    if c.failures:
        print(f"\n{len(c.failures)} FAILED:\n")
        for f in c.failures:
            print(f"  {f}\n")
        return 1

    print("All passed — the ported algorithm agrees with the shipped chord.js.")
    print("\nThis does NOT prove the Swift compiles. Run `swift test` on the Mac for that.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

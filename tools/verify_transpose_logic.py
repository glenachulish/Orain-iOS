#!/usr/bin/env python3
"""Check the transposition logic before it ever reaches a compiler.

Same approach as verify_port_logic.py: a line-for-line transliteration of
Transpose.swift into Python, run against a table of cases worked out by hand
from what a musician would actually write. If this passes, the algorithm is
right and `swift test` only has Swift syntax left to catch.

Run:  python3 tools/verify_transpose_logic.py
"""

from __future__ import annotations

import sys

SHARP_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
FLAT_NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
FLAT_KEYS = {1, 3, 5, 8, 10}
LETTER_OFFSETS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
ALLOWED_QUALITY = set(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-#b()°ø∆Δ,"
)


def parse_note(chars):
    if not chars or chars[0] not in LETTER_OFFSETS:
        return None
    pitch = LETTER_OFFSETS[chars[0]]
    index = 1
    if index < len(chars):
        if chars[index] in ("#", "♯"):
            pitch += 1
            index += 1
        elif chars[index] in ("b", "♭"):
            pitch -= 1
            index += 1
    return (pitch % 12, index)


def plausible_quality(quality: str) -> bool:
    if quality == "":
        return True
    if "." in quality or " " in quality:
        return False
    return all(c in ALLOWED_QUALITY for c in quality)


def parse_chord(symbol: str):
    chars = list(symbol)
    if not chars:
        return None

    bass_part = None
    if "/" in chars:
        slash = chars.index("/")
        bass_part = "".join(chars[slash + 1 :])
        chars = chars[:slash]

    parsed = parse_note(chars)
    if parsed is None:
        return None
    root, after_root = parsed

    quality = "".join(chars[after_root:])
    if not plausible_quality(quality):
        return None

    bass = None
    if bass_part is not None:
        bass_chars = list(bass_part)
        parsed_bass = parse_note(bass_chars)
        if parsed_bass is None or parsed_bass[1] != len(bass_chars):
            return None
        bass = parsed_bass[0]

    return {"root": root, "quality": quality, "bass": bass}


def note_name(pitch: int, prefer_flats: bool) -> str:
    index = pitch % 12
    return FLAT_NAMES[index] if prefer_flats else SHARP_NAMES[index]


def prefers_flats(key: int) -> bool:
    return (key % 12) in FLAT_KEYS


def chord_symbols(lyrics):
    if lyrics is None:
        return []
    seen = set()
    out = []
    chars = list(lyrics)
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
        symbol = "".join(chars[i + 1 : j])
        if symbol not in seen:
            seen.add(symbol)
            out.append(symbol)
        i = j + 1
    return out


def detect_key(lyrics):
    if lyrics is None:
        return None
    for symbol in chord_symbols(lyrics):
        chord = parse_chord(symbol)
        if chord is not None:
            return chord["root"]
    return None


def transpose_chord_symbol(symbol: str, semitones: int, prefer_flats: bool) -> str:
    chord = parse_chord(symbol)
    if chord is None:
        return symbol
    out = note_name(chord["root"] + semitones, prefer_flats) + chord["quality"]
    if chord["bass"] is not None:
        out += "/" + note_name(chord["bass"] + semitones, prefer_flats)
    return out


def transpose_lyrics(lyrics, semitones: int, prefer_flats=None) -> str:
    if not lyrics:
        return lyrics or ""

    normalised = semitones % 12
    if normalised == 0:
        return lyrics

    if prefer_flats is not None:
        flats = prefer_flats
    else:
        key = detect_key(lyrics)
        flats = prefers_flats(key + normalised) if key is not None else False

    out = ""
    chars = list(lyrics)
    i = 0
    while i < len(chars):
        if chars[i] != "[":
            out += chars[i]
            i += 1
            continue
        j = i + 1
        while j < len(chars) and chars[j] != "]":
            j += 1
        if not (j < len(chars) and j > i + 1):
            out += chars[i]
            i += 1
            continue
        symbol = "".join(chars[i + 1 : j])
        out += "[" + transpose_chord_symbol(symbol, normalised, flats) + "]"
        i = j + 1
    return out


def targets(symbol: str, lyrics):
    chord = parse_chord(symbol)
    if chord is None:
        return []
    key = detect_key(lyrics)
    if key is None:
        key = chord["root"]
    out = []
    for semitones in range(12):
        flats = prefers_flats(key + semitones)
        out.append(
            {
                "semitones": semitones,
                "label": transpose_chord_symbol(symbol, semitones, flats),
                "resultingKey": note_name(key + semitones, flats),
            }
        )
    return out


# --- the checks -------------------------------------------------------------


class Checker:
    def __init__(self):
        self.passed = 0
        self.failures = []

    def check(self, label, actual, expected):
        if actual == expected:
            self.passed += 1
        else:
            self.failures.append(
                f"{label}\n    expected: {expected!r}\n    actual:   {actual!r}"
            )


def main() -> int:
    c = Checker()

    # --- Chord parsing ------------------------------------------------------
    for symbol, expected in [
        ("G", {"root": 7, "quality": "", "bass": None}),
        ("Am", {"root": 9, "quality": "m", "bass": None}),
        ("Am7", {"root": 9, "quality": "m7", "bass": None}),
        ("C#sus4", {"root": 1, "quality": "sus4", "bass": None}),
        ("Bb", {"root": 10, "quality": "", "bass": None}),
        ("Bbmaj7", {"root": 10, "quality": "maj7", "bass": None}),
        ("D/F#", {"root": 2, "quality": "", "bass": 6}),
        ("Cmaj7/E", {"root": 0, "quality": "maj7", "bass": 4}),
        ("F#m7b5", {"root": 6, "quality": "m7b5", "bass": None}),
        ("Cb", {"root": 11, "quality": "", "bass": None}),
    ]:
        c.check(f"parseChord({symbol!r})", parse_chord(symbol), expected)

    # Things that must NOT be treated as chords.
    for symbol in ["N.C.", "riff", "D.S.", "x", "", "Instrumental break", "C/x", "H"]:
        c.check(f"parseChord({symbol!r}) is None", parse_chord(symbol), None)

    # --- Key spelling -------------------------------------------------------
    for key, expected in [
        (0, False),   # C  → sharps
        (7, False),   # G  → sharps
        (2, False),   # D  → sharps
        (5, True),    # F  → flats
        (10, True),   # Bb → flats
        (3, True),    # Eb → flats
        (8, True),    # Ab → flats
        (1, True),    # Db → flats
        (6, False),   # F# → sharps
    ]:
        c.check(f"prefersFlats(key={key})", prefers_flats(key), expected)

    # --- The headline case: G → C -------------------------------------------
    g_song = "[G]Ailein [C]duinn, [D]hiù o-[G]hoe"
    c.check(
        "G song transposed to C",
        transpose_lyrics(g_song, 5),
        "[C]Ailein [F]duinn, [G]hiù o-[C]hoe",
    )

    # G up a tone → A, a sharp key.
    c.check(
        "G song up a tone lands in A with sharps",
        transpose_lyrics("[G]one [C]two [D]three", 2),
        "[A]one [D]two [E]three",
    )

    # G down a tone → F, a flat key: the B natural becomes Bb, not A#.
    c.check(
        "G song down a tone lands in F with flats",
        transpose_lyrics("[G]one [C]two [D]three [Em]four", 10),
        "[F]one [Bb]two [C]three [Dm]four",
    )

    # C up three semitones → Eb, flats throughout.
    c.check(
        "C to Eb spells flats",
        transpose_lyrics("[C]one [F]two [G]three [Am]four", 3),
        "[Eb]one [Ab]two [Bb]three [Cm]four",
    )

    # A up a semitone → Bb: the E becomes F, the D becomes Eb.
    c.check(
        "A to Bb",
        transpose_lyrics("[A]one [D]two [E]three", 1),
        "[Bb]one [Eb]two [F]three",
    )

    # --- Qualities and slash chords survive ---------------------------------
    c.check(
        "qualities carried across untouched",
        transpose_lyrics("[Am7]a [Csus4]b [F#m7b5]c [Gmaj7]d", 2),
        "[Bm7]a [Dsus4]b [G#m7b5]c [Amaj7]d",
    )
    c.check(
        "slash chords move both notes",
        transpose_lyrics("[D/F#]a [C/E]b", 2),
        "[E/G#]a [D/F#]b",
    )

    # --- Things that must be left alone -------------------------------------
    c.check(
        "non-chords pass through untouched",
        transpose_lyrics("[G]sing [N.C.]nothing [riff]here [D.S.]end", 5),
        "[C]sing [N.C.]nothing [riff]here [D.S.]end",
    )
    c.check(
        "lyrics and directives untouched",
        transpose_lyrics(
            "{start_of_chorus: Sèist}\n[G]Ailein duinn\n{end_of_chorus}", 5
        ),
        "{start_of_chorus: Sèist}\n[C]Ailein duinn\n{end_of_chorus}",
    )
    c.check("zero semitones is identity", transpose_lyrics(g_song, 0), g_song)
    c.check("twelve semitones is identity", transpose_lyrics(g_song, 12), g_song)
    c.check("empty lyrics", transpose_lyrics("", 5), "")
    c.check("none lyrics", transpose_lyrics(None, 5), "")
    c.check(
        "song with no chords is unchanged",
        transpose_lyrics("just words\nno chords here", 5),
        "just words\nno chords here",
    )
    c.check(
        "unclosed bracket left alone",
        transpose_lyrics("[G]a [b c", 5),
        "[C]a [b c",
    )

    # --- Negative and wrapping offsets --------------------------------------
    c.check(
        "negative offset wraps",
        transpose_lyrics("[C]x", -1),
        transpose_lyrics("[C]x", 11),
    )

    # --- Chord list and picker ---------------------------------------------
    c.check(
        "chordSymbols in order, no duplicates",
        chord_symbols("[G]a [C]b [G]c [D]d"),
        ["G", "C", "D"],
    )
    c.check("detectKey uses the first chord", detect_key("[G]a [C]b"), 7)
    c.check("detectKey skips non-chords", detect_key("[N.C.]a [F]b"), 5)
    c.check("detectKey of a chordless song", detect_key("words only"), None)

    t = targets("G", g_song)
    c.check("twelve targets offered", len(t), 12)
    c.check("first target is no change", t[0], {"semitones": 0, "label": "G", "resultingKey": "G"})
    c.check(
        "the G→C option",
        [x for x in t if x["label"] == "C"],
        [{"semitones": 5, "label": "C", "resultingKey": "C"}],
    )
    # Every option must be spelled consistently with the key it lands in.
    for option in t:
        key_flat = "b" in option["resultingKey"]
        label_sharp = "#" in option["label"]
        c.check(
            f"option {option['semitones']} spelling is self-consistent",
            key_flat and label_sharp,
            False,
        )

    # A tapped chord that isn't the key still computes the right shift.
    t2 = targets("C", g_song)
    match = [x for x in t2 if x["label"] == "F"]
    c.check("tapping the C and asking for F shifts by 5", match[0]["semitones"], 5)
    c.check("…and the song lands in C", match[0]["resultingKey"], "C")

    print(f"Checked {c.passed + len(c.failures)} assertions.")
    if c.failures:
        print(f"\n{len(c.failures)} FAILED:\n")
        for f in c.failures:
            print(f"  {f}\n")
        return 1

    print("All passed — the transposition logic is sound.")
    print("\nThis does NOT prove the Swift compiles. Run `swift test` for that.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

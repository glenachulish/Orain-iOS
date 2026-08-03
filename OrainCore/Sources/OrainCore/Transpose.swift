//  Transpose.swift
//  OrainCore
//
//  Moving a song into a different key.
//
//  THE SHAPE OF THE FEATURE
//  ------------------------
//  You are looking at a song in G and cannot reach the top note. You tap the
//  G, say "make that a C", and every other chord follows — C F G. The result
//  is saved as a new version alongside the original, so you keep both.
//
//  WHAT IS STORED
//  --------------
//  Nothing here rewrites the stored lyrics. A transposed version holds the
//  *same* ChordPro text with a `transpose` offset in semitones, and the chord
//  names are shifted on the way to the screen. That keeps the round-trip
//  guarantee intact, keeps the original spelling recoverable, and means a
//  lyric typo fixed once is fixed in every key.
//
//  SPELLING IS DERIVED, NOT STORED
//  -------------------------------
//  Whether a black note is written F# or Gb depends on the key you land in,
//  not on the key you left. Transposing G→A gives a sharp key, so the chords
//  are spelled with sharps; landing in Eb gives flats throughout. That is
//  computed from the resulting key every time rather than stored, so there is
//  exactly one integer to keep — matching the `transpose` column the Pi app
//  has always had.
//
//  The rule is a convention, not a law. A musician who wants Gb where this
//  writes F# can edit the chord text by hand; the point is that the automatic
//  answer is never absurd, not that it is the only defensible one.

import Foundation

public enum Transposer {

    // MARK: - Note names

    /// Chromatic scale spelled with sharps.
    static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Chromatic scale spelled with flats.
    static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    /// Pitch classes of the keys conventionally written with flats:
    /// Db, Eb, F, Ab, Bb. Everything else — including C — takes sharps.
    ///
    /// The two genuinely contested cases are pitch class 1 (Db vs C#) and 6
    /// (F# vs Gb). Db and F# are the choices here: Db because it is the
    /// commoner key signature, F# because guitarists meet it far more often
    /// than Gb.
    static let flatKeys: Set<Int> = [1, 3, 5, 8, 10]

    /// Semitone offset of each natural note from C.
    private static let letterOffsets: [Character: Int] = [
        "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11,
    ]

    // MARK: - A parsed chord symbol

    public struct Chord: Equatable, Sendable {
        /// Pitch class of the root, 0–11 with C = 0.
        public let root: Int
        /// Everything after the root: "m", "7", "sus4", "maj7"… possibly empty.
        public let quality: String
        /// Pitch class of the bass note in a slash chord, if there is one.
        public let bass: Int?

        public init(root: Int, quality: String, bass: Int?) {
            self.root = root
            self.quality = quality
            self.bass = bass
        }
    }

    /// Parse a chord symbol such as `G`, `Am7`, `C#sus4`, `D/F#`.
    ///
    /// Returns `nil` for anything that is not clearly a chord — `N.C.`,
    /// `riff`, `D.S.`, a stray word — so those pass through a transposition
    /// untouched rather than being mangled into nonsense.
    public static func parseChord(_ symbol: String) -> Chord? {
        var chars = Array(symbol)
        guard !chars.isEmpty else { return nil }

        // Split off a slash bass first, so "D/F#" parses as root D, bass F#.
        var bassPart: String?
        if let slash = chars.firstIndex(of: "/") {
            bassPart = String(chars[(slash + 1)...])
            chars = Array(chars[..<slash])
        }

        guard let (root, afterRoot) = parseNote(chars) else { return nil }

        let quality = String(chars[afterRoot...])
        guard isPlausibleQuality(quality) else { return nil }

        var bass: Int?
        if let bassPart {
            let bassChars = Array(bassPart)
            guard let (bassNote, afterBass) = parseNote(bassChars),
                  afterBass == bassChars.count
            else { return nil }  // "C/x" is not a chord we understand
            bass = bassNote
        }

        return Chord(root: root, quality: quality, bass: bass)
    }

    /// Read a note name from the front of `chars`.
    /// Returns its pitch class and the index just past it.
    private static func parseNote(_ chars: [Character]) -> (Int, Int)? {
        guard let first = chars.first, let base = letterOffsets[first] else { return nil }

        var index = 1
        var pitch = base

        if index < chars.count {
            switch chars[index] {
            case "#", "\u{266F}":
                pitch += 1
                index += 1
            case "b", "\u{266D}":
                pitch -= 1
                index += 1
            default:
                break
            }
        }

        return ((pitch % 12 + 12) % 12, index)
    }

    /// A conservative check that what follows the root looks like a chord
    /// quality rather than prose. Rejects anything containing a full stop
    /// (which catches "D.S." and "C.") or a space.
    private static func isPlausibleQuality(_ quality: String) -> Bool {
        if quality.isEmpty { return true }
        if quality.contains(".") || quality.contains(" ") { return false }

        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-#b()°ø∆Δ,")
        return quality.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: - Spelling

    /// The name for a pitch class, spelled for the given key.
    public static func noteName(_ pitch: Int, preferFlats: Bool) -> String {
        let index = (pitch % 12 + 12) % 12
        return preferFlats ? flatNames[index] : sharpNames[index]
    }

    /// Does a key of this pitch class conventionally take flats?
    public static func prefersFlats(key: Int) -> Bool {
        flatKeys.contains((key % 12 + 12) % 12)
    }

    /// The key a version is in — taken as the root of its first chord, which
    /// is right far more often than it is wrong and needs no extra data.
    /// Returns nil for a version with no chords at all.
    public static func detectKey(_ lyrics: String?) -> Int? {
        guard let lyrics else { return nil }
        for symbol in chordSymbols(in: lyrics) {
            if let chord = parseChord(symbol) { return chord.root }
        }
        return nil
    }

    // MARK: - Transposing

    /// Shift one chord symbol by a number of semitones.
    /// Unrecognised symbols are returned exactly as they came in.
    public static func transposeChordSymbol(
        _ symbol: String,
        by semitones: Int,
        preferFlats: Bool
    ) -> String {
        guard let chord = parseChord(symbol) else { return symbol }

        var out = noteName(chord.root + semitones, preferFlats: preferFlats) + chord.quality
        if let bass = chord.bass {
            out += "/" + noteName(bass + semitones, preferFlats: preferFlats)
        }
        return out
    }

    /// Shift every chord in a ChordPro lyric string.
    ///
    /// Only the text inside `[...]` is touched. Lyrics, section directives and
    /// blank lines pass through byte for byte, so the section structure, the
    /// chorus repeat and the reveal counter all behave exactly as before.
    public static func transposeLyrics(
        _ lyrics: String?,
        by semitones: Int,
        preferFlats: Bool? = nil
    ) -> String {
        guard let lyrics, !lyrics.isEmpty else { return lyrics ?? "" }

        let normalised = ((semitones % 12) + 12) % 12
        if normalised == 0 { return lyrics }

        // Work out the spelling once, from the key we are landing in, unless
        // the caller has already decided.
        let flats: Bool
        if let preferFlats {
            flats = preferFlats
        } else if let key = detectKey(lyrics) {
            flats = prefersFlats(key: key + normalised)
        } else {
            flats = false
        }

        var out = ""
        var chars = Array(lyrics)
        var i = 0

        while i < chars.count {
            guard chars[i] == "[" else {
                out.append(chars[i])
                i += 1
                continue
            }

            // Find the closing bracket, matching parseChordProLine's rule:
            // non-empty contents, no nested "]".
            var j = i + 1
            while j < chars.count, chars[j] != "]" { j += 1 }

            guard j < chars.count, j > i + 1 else {
                out.append(chars[i])
                i += 1
                continue
            }

            let symbol = String(chars[(i + 1)..<j])
            out += "[" + transposeChordSymbol(symbol, by: normalised, preferFlats: flats) + "]"
            i = j + 1
        }

        return out
    }

    // MARK: - Support for the picker

    /// Every chord symbol in the lyrics, in the order first met, without
    /// duplicates. This is what the user taps to say "make that one a C".
    public static func chordSymbols(in lyrics: String?) -> [String] {
        guard let lyrics else { return [] }

        var seen: Set<String> = []
        var out: [String] = []
        var chars = Array(lyrics)
        var i = 0

        while i < chars.count {
            guard chars[i] == "[" else {
                i += 1
                continue
            }
            var j = i + 1
            while j < chars.count, chars[j] != "]" { j += 1 }
            guard j < chars.count, j > i + 1 else {
                i += 1
                continue
            }

            let symbol = String(chars[(i + 1)..<j])
            if !seen.contains(symbol) {
                seen.insert(symbol)
                out.append(symbol)
            }
            i = j + 1
        }

        return out
    }

    /// One option in the "make this chord a…" picker.
    public struct Target: Equatable, Sendable, Identifiable {
        /// How far the whole song moves if this option is chosen, 0–11.
        public let semitones: Int
        /// What the tapped chord becomes, spelled for the resulting key.
        public let label: String
        /// The key the song ends up in, spelled the same way.
        public let resultingKey: String

        public var id: Int { semitones }
    }

    /// The twelve things a tapped chord could become, each spelled as it
    /// would actually appear once the change is made.
    ///
    /// The spelling of each option depends on the key that option lands in,
    /// which is why this cannot be a fixed list of note names: choosing "up a
    /// tone" from G gives A and sharps, while "down a tone" gives F and flats.
    public static func targets(forChord symbol: String, in lyrics: String?) -> [Target] {
        guard let chord = parseChord(symbol) else { return [] }
        let key = detectKey(lyrics) ?? chord.root

        return (0..<12).map { semitones in
            let flats = prefersFlats(key: key + semitones)
            return Target(
                semitones: semitones,
                label: transposeChordSymbol(symbol, by: semitones, preferFlats: flats),
                resultingKey: noteName(key + semitones, preferFlats: flats)
            )
        }
    }

    /// A suggested version label for a transposed copy, e.g. "In C".
    /// Deliberately plain: the user can rename it to whatever they call it.
    public static func suggestedLabel(forKey key: Int, semitones: Int) -> String {
        let flats = prefersFlats(key: key + semitones)
        return "In " + noteName(key + semitones, preferFlats: flats)
    }
}

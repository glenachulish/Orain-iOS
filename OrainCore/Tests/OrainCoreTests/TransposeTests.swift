//  TransposeTests.swift
//  OrainCoreTests
//
//  What a musician would actually write, asserted.
//
//  Transposition is easy to get *nearly* right — a version that produces A#
//  where anyone would write Bb is working code and a useless feature. So most
//  of these tests are about spelling rather than arithmetic.

import XCTest
@testable import OrainCore

final class ChordParsingTests: XCTestCase {

    func testParsesOrdinaryChords() {
        XCTAssertEqual(Transposer.parseChord("G"), .init(root: 7, quality: "", bass: nil))
        XCTAssertEqual(Transposer.parseChord("Am"), .init(root: 9, quality: "m", bass: nil))
        XCTAssertEqual(Transposer.parseChord("Am7"), .init(root: 9, quality: "m7", bass: nil))
        XCTAssertEqual(Transposer.parseChord("C#sus4"), .init(root: 1, quality: "sus4", bass: nil))
        XCTAssertEqual(Transposer.parseChord("Bbmaj7"), .init(root: 10, quality: "maj7", bass: nil))
        XCTAssertEqual(Transposer.parseChord("F#m7b5"), .init(root: 6, quality: "m7b5", bass: nil))
    }

    func testParsesSlashChords() {
        XCTAssertEqual(Transposer.parseChord("D/F#"), .init(root: 2, quality: "", bass: 6))
        XCTAssertEqual(Transposer.parseChord("Cmaj7/E"), .init(root: 0, quality: "maj7", bass: 4))
    }

    /// Cb is B. Rare, but it is a real chord and must not be rejected.
    func testWrapsRoundTheOctave() {
        XCTAssertEqual(Transposer.parseChord("Cb"), .init(root: 11, quality: "", bass: nil))
    }

    /// The important half of the job: things in brackets that are NOT chords
    /// must be refused, so a transposition leaves them alone rather than
    /// turning "D.S." into "G.S.".
    func testRefusesThingsThatAreNotChords() {
        for symbol in ["N.C.", "riff", "D.S.", "x", "", "Instrumental break", "C/x", "H"] {
            XCTAssertNil(Transposer.parseChord(symbol), "should not parse: \(symbol)")
        }
    }
}

final class KeySpellingTests: XCTestCase {

    func testFlatKeysTakeFlatsAndTheRestTakeSharps() {
        for (key, expected) in [(0, false), (7, false), (2, false), (6, false),
                                (5, true), (10, true), (3, true), (8, true), (1, true)] {
            XCTAssertEqual(
                Transposer.prefersFlats(key: key), expected, "key pitch class \(key)"
            )
        }
    }

    func testKeyIsTakenFromTheFirstChord() {
        XCTAssertEqual(Transposer.detectKey("[G]a [C]b"), 7)
    }

    func testKeyDetectionSkipsThingsThatAreNotChords() {
        XCTAssertEqual(Transposer.detectKey("[N.C.]a [F]b"), 5)
    }

    func testASongWithNoChordsHasNoKey() {
        XCTAssertNil(Transposer.detectKey("words only"))
        XCTAssertNil(Transposer.detectKey(nil))
    }
}

final class TransposeLyricsTests: XCTestCase {

    private let gSong = "[G]Ailein [C]duinn, [D]hiù o-[G]hoe"

    /// The case the whole feature exists for.
    func testGToC() {
        XCTAssertEqual(
            Transposer.transposeLyrics(gSong, by: 5),
            "[C]Ailein [F]duinn, [G]hiù o-[C]hoe"
        )
    }

    func testUpAToneFromGLandsInAWithSharps() {
        XCTAssertEqual(
            Transposer.transposeLyrics("[G]one [C]two [D]three", by: 2),
            "[A]one [D]two [E]three"
        )
    }

    /// Down a tone from G is F — a flat key — so the B natural must come out
    /// as Bb, not A#. This is the assertion that catches a naive implementation.
    func testDownAToneFromGLandsInFWithFlats() {
        XCTAssertEqual(
            Transposer.transposeLyrics("[G]one [C]two [D]three [Em]four", by: 10),
            "[F]one [Bb]two [C]three [Dm]four"
        )
    }

    func testCToEbSpellsFlatsThroughout() {
        XCTAssertEqual(
            Transposer.transposeLyrics("[C]one [F]two [G]three [Am]four", by: 3),
            "[Eb]one [Ab]two [Bb]three [Cm]four"
        )
    }

    func testAToBb() {
        XCTAssertEqual(
            Transposer.transposeLyrics("[A]one [D]two [E]three", by: 1),
            "[Bb]one [Eb]two [F]three"
        )
    }

    func testQualitiesAreCarriedAcrossUntouched() {
        XCTAssertEqual(
            Transposer.transposeLyrics("[Am7]a [Csus4]b [F#m7b5]c [Gmaj7]d", by: 2),
            "[Bm7]a [Dsus4]b [G#m7b5]c [Amaj7]d"
        )
    }

    func testSlashChordsMoveBothNotes() {
        XCTAssertEqual(
            Transposer.transposeLyrics("[D/F#]a [C/E]b", by: 2),
            "[E/G#]a [D/F#]b"
        )
    }

    func testNonChordsPassThrough() {
        XCTAssertEqual(
            Transposer.transposeLyrics("[G]sing [N.C.]nothing [riff]here [D.S.]end", by: 5),
            "[C]sing [N.C.]nothing [riff]here [D.S.]end"
        )
    }

    /// Section directives, blank lines and the words themselves must survive
    /// byte for byte, or the chorus repeat and reveal counter break.
    func testStructureIsUntouched() {
        let source = "{start_of_chorus: Sèist}\n[G]Ailein duinn\n\n{end_of_chorus}"
        let moved = Transposer.transposeLyrics(source, by: 5)
        XCTAssertEqual(moved, "{start_of_chorus: Sèist}\n[C]Ailein duinn\n\n{end_of_chorus}")

        // And the section machinery agrees.
        XCTAssertEqual(
            ChordPro.getSections(moved).map(\.kind),
            ChordPro.getSections(source).map(\.kind)
        )
    }

    func testIdentityCases() {
        XCTAssertEqual(Transposer.transposeLyrics(gSong, by: 0), gSong)
        XCTAssertEqual(Transposer.transposeLyrics(gSong, by: 12), gSong)
        XCTAssertEqual(Transposer.transposeLyrics("", by: 5), "")
        XCTAssertEqual(Transposer.transposeLyrics(nil, by: 5), "")
        XCTAssertEqual(
            Transposer.transposeLyrics("just words\nno chords here", by: 5),
            "just words\nno chords here"
        )
    }

    func testNegativeOffsetsWrap() {
        XCTAssertEqual(
            Transposer.transposeLyrics("[C]x", by: -1),
            Transposer.transposeLyrics("[C]x", by: 11)
        )
    }

    func testUnclosedBracketIsLeftAlone() {
        XCTAssertEqual(Transposer.transposeLyrics("[G]a [b c", by: 5), "[C]a [b c")
    }

    /// Transposing and transposing back must return the original text, or
    /// stepping up and down through keys would slowly corrupt a song.
    func testRoundTripThroughEveryInterval() {
        for semitones in 1..<12 {
            let there = Transposer.transposeLyrics("[C]a [F]b [G]c [Am]d", by: semitones)
            let back = Transposer.transposeLyrics(there, by: 12 - semitones)
            XCTAssertEqual(back, "[C]a [F]b [G]c [Am]d", "interval \(semitones)")
        }
    }
}

final class TransposeTargetTests: XCTestCase {

    private let gSong = "[G]Ailein [C]duinn, [D]hiù o-[G]hoe"

    func testChordSymbolsAreListedInOrderWithoutDuplicates() {
        XCTAssertEqual(Transposer.chordSymbols(in: "[G]a [C]b [G]c [D]d"), ["G", "C", "D"])
    }

    func testTwelveTargetsAreOffered() {
        XCTAssertEqual(Transposer.targets(forChord: "G", in: gSong).count, 12)
    }

    func testTheFirstTargetIsNoChange() {
        let first = Transposer.targets(forChord: "G", in: gSong).first
        XCTAssertEqual(first?.semitones, 0)
        XCTAssertEqual(first?.label, "G")
    }

    func testTheGToCOption() {
        let targets = Transposer.targets(forChord: "G", in: gSong)
        let toC = targets.first { $0.label == "C" }
        XCTAssertEqual(toC?.semitones, 5)
        XCTAssertEqual(toC?.resultingKey, "C")
    }

    /// Every option must be spelled consistently with the key it lands in —
    /// no offering "F#" as the way to reach the key of "Gb".
    func testEveryOptionIsSpelledConsistentlyWithItsKey() {
        for option in Transposer.targets(forChord: "G", in: gSong) {
            let keyIsFlat = option.resultingKey.contains("b")
            let labelIsSharp = option.label.contains("#")
            XCTAssertFalse(
                keyIsFlat && labelIsSharp,
                "option \(option.semitones): \(option.label) in key \(option.resultingKey)"
            )
        }
    }

    /// Tapping a chord that is not the key still moves the whole song by the
    /// right interval — asking for the C to become F shifts everything by 5.
    func testTappingAChordThatIsNotTheKey() {
        let targets = Transposer.targets(forChord: "C", in: gSong)
        let toF = targets.first { $0.label == "F" }
        XCTAssertEqual(toF?.semitones, 5)
        XCTAssertEqual(toF?.resultingKey, "C", "the song lands in C, though the tapped chord became F")
    }

    func testNoTargetsForSomethingThatIsNotAChord() {
        XCTAssertTrue(Transposer.targets(forChord: "riff", in: gSong).isEmpty)
    }

    func testSuggestedLabel() {
        XCTAssertEqual(Transposer.suggestedLabel(forKey: 7, semitones: 5), "In C")
        XCTAssertEqual(Transposer.suggestedLabel(forKey: 7, semitones: 10), "In F")
        XCTAssertEqual(Transposer.suggestedLabel(forKey: 0, semitones: 3), "In Eb")
    }
}

//  LibraryAndArchiveTests.swift
//  OrainCoreTests
//
//  Sorting, filtering, and the import/export format.

import XCTest
@testable import OrainCore

// A minimal stand-in for a song row, so the filter logic can be tested
// without SwiftData or a UI.
private struct TestSong: FilterableSong {
    var title: String
    var composer: String? = nil
    var tradition: String? = nil
    var canonicalLanguage: String? = nil
    var isFavourite: Bool = false
    var onHitlist: Bool = false
    var rating: Int? = nil
    var searchableText: String = ""
    var tagNames: [String] = []
}

final class SongSortingTests: XCTestCase {

    /// The exact bug the Pi app hit: SQLite's NOCASE folds only ASCII, so a
    /// Gàidhlig initial sorted by code point and landed after the W's.
    func testAccentedInitialSortsWithItsPlainLetter() {
        let titles = ["Wild Mountain Thyme", "Òrain Eirisgeidh", "Oran Mòr", "Ailein Duinn"]
        let sorted = titles.sorted(by: SongSorting.isOrderedBefore)
        // "Òrain…" files among the O's — by its folded form "orain…", which
        // sorts before "oran mor" on the fourth letter, not after the W's.
        XCTAssertEqual(
            sorted,
            ["Ailein Duinn", "Òrain Eirisgeidh", "Oran Mòr", "Wild Mountain Thyme"]
        )
    }

    func testFoldingIsCaseAndAccentInsensitive() {
        XCTAssertEqual(SongSorting.foldedTitle("Òrain"), "orain")
        XCTAssertEqual(SongSorting.foldedTitle("ÉISLEAN"), "eislean")
        XCTAssertEqual(SongSorting.foldedTitle("Fear a' Bhàta"), "fear a' bhata")
    }

    /// Titles that fold alike must still order predictably rather than
    /// arbitrarily — the raw title is the tiebreaker.
    func testTiebreakerIsStable() {
        // Both fold to "oran", so the raw title decides — and it decides the
        // same way whichever order they arrive in.
        XCTAssertEqual(SongSorting.foldedTitle("Òran"), SongSorting.foldedTitle("Oran"))
        XCTAssertTrue(SongSorting.isOrderedBefore("Oran", "Òran"))
        XCTAssertFalse(SongSorting.isOrderedBefore("Òran", "Oran"))
    }
}

final class LibraryFilteringTests: XCTestCase {

    private let songs: [TestSong] = [
        TestSong(
            title: "Ailein Duinn",
            composer: "Trad",
            tradition: "trad",
            canonicalLanguage: "gd",
            isFavourite: true,
            rating: 4,
            searchableText: "Ailein duinn, hiù o-hoe"
        ),
        TestSong(
            title: "Wild Mountain Thyme",
            composer: "Francis McPeake",
            tradition: "modern",
            canonicalLanguage: "en",
            onHitlist: true,
            rating: 2,
            searchableText: "And the wild mountain thyme"
        ),
        TestSong(
            title: "Òrain Eirisgeidh",
            composer: "Trad",
            canonicalLanguage: "gd",
            rating: nil,
            searchableText: ""
        ),
    ]

    func testEmptyFilterReturnsEverythingSorted() {
        let out = LibraryFiltering.apply(LibraryFilter(), to: songs)
        XCTAssertEqual(out.map(\.title), ["Ailein Duinn", "Òrain Eirisgeidh", "Wild Mountain Thyme"])
    }

    func testFiltersCombineWithAnd() {
        var f = LibraryFilter()
        f.composer = "Trad"
        f.language = "gd"
        XCTAssertEqual(
            LibraryFiltering.apply(f, to: songs).map(\.title),
            ["Ailein Duinn", "Òrain Eirisgeidh"]
        )

        f.favouritesOnly = true
        XCTAssertEqual(LibraryFiltering.apply(f, to: songs).map(\.title), ["Ailein Duinn"])
    }

    /// Rating is a threshold, not an exact match — "3+ = performable".
    func testMinRatingIsAThreshold() {
        var f = LibraryFilter()
        f.minRating = 3
        XCTAssertEqual(LibraryFiltering.apply(f, to: songs).map(\.title), ["Ailein Duinn"])

        f.minRating = 2
        XCTAssertEqual(
            LibraryFiltering.apply(f, to: songs).map(\.title),
            ["Ailein Duinn", "Wild Mountain Thyme"]
        )
    }

    /// An unrated song is never "rated 0" — it is simply excluded by a
    /// rating threshold, the same as a NULL in the Pi app.
    func testUnratedSongsAreExcludedByARatingThreshold() {
        var f = LibraryFilter()
        f.minRating = 1
        XCTAssertFalse(
            LibraryFiltering.apply(f, to: songs).map(\.title).contains("Òrain Eirisgeidh")
        )
    }

    func testSearchIsAccentInsensitiveAcrossTitleAndLyrics() {
        var f = LibraryFilter()
        f.searchText = "orain"
        XCTAssertEqual(LibraryFiltering.apply(f, to: songs).map(\.title), ["Òrain Eirisgeidh"])

        f.searchText = "hiu o-hoe"   // lyric text, accent dropped by the typist
        XCTAssertEqual(LibraryFiltering.apply(f, to: songs).map(\.title), ["Ailein Duinn"])
    }

    func testIsActiveReflectsWhetherAnythingIsSet() {
        var f = LibraryFilter()
        XCTAssertFalse(f.isActive)
        f.hitlistOnly = true
        XCTAssertTrue(f.isActive)
    }

    func testTagsAlsoCountAsAnActiveFilter() {
        var f = LibraryFilter()
        f.tagNames = ["wedding"]
        XCTAssertTrue(f.isActive)
    }
}

final class TagFilteringTests: XCTestCase {

    private let songs: [TestSong] = [
        TestSong(title: "Both", canonicalLanguage: "gd", tagNames: ["wedding", "slow air"]),
        TestSong(title: "Wedding only", canonicalLanguage: "en", tagNames: ["wedding"]),
        TestSong(title: "Slow only", canonicalLanguage: "gd", tagNames: ["Slow Air"]),
        TestSong(title: "Neither", canonicalLanguage: "gd", tagNames: []),
    ]

    func testOneTagMatchesEverySongCarryingIt() {
        var f = LibraryFilter()
        f.tagNames = ["wedding"]
        XCTAssertEqual(
            Set(LibraryFiltering.apply(f, to: songs).map(\.title)),
            ["Both", "Wedding only"]
        )
    }

    /// The decision that matters: two tags narrows to songs carrying BOTH.
    /// If this ever flips to "either", every other filter in the app would be
    /// narrowing while this one widened.
    func testTwoTagsRequireBoth() {
        var f = LibraryFilter()
        f.tagNames = ["wedding", "slow air"]
        XCTAssertEqual(LibraryFiltering.apply(f, to: songs).map(\.title), ["Both"])
    }

    /// "Slow Air" and "slow air" are the same label.
    func testTagMatchingIgnoresCaseAndAccents() {
        var f = LibraryFilter()
        f.tagNames = ["SLOW AIR"]
        XCTAssertEqual(
            Set(LibraryFiltering.apply(f, to: songs).map(\.title)),
            ["Both", "Slow only"]
        )
    }

    /// Tags combine with the built-in axes rather than replacing them —
    /// "Gàidhlig songs tagged wedding" has to be askable.
    func testTagsCombineWithLanguage() {
        var f = LibraryFilter()
        f.tagNames = ["wedding"]
        f.language = "gd"
        XCTAssertEqual(LibraryFiltering.apply(f, to: songs).map(\.title), ["Both"])
    }

    func testAskingForATagNobodyHasReturnsNothing() {
        var f = LibraryFilter()
        f.tagNames = ["nonexistent"]
        XCTAssertTrue(LibraryFiltering.apply(f, to: songs).isEmpty)
    }

    func testSummaryNamesWhatIsBeingAskedFor() {
        var f = LibraryFilter()
        f.language = "gd"
        f.tradition = "modern"
        f.tagNames = ["wedding"]
        XCTAssertEqual(f.summary, "Gàidhlig · Modern · wedding")
    }
}

final class OrainArchiveTests: XCTestCase {

    private func sampleArchive() -> OrainArchive {
        OrainArchive(
            exportedAt: "2026-07-29T23:00:00Z",
            source: "test",
            songs: [
                ArchiveSong(
                    slug: "ailein-duinn",
                    title: "Ailein Duinn",
                    composer: "Trad",
                    rating: 4,
                    isFavourite: true,
                    tradition: "trad",
                    versions: [
                        ArchiveVersion(
                            sourceId: 3,
                            language: "gd",
                            lyrics: "[G]Ailein duinn, [D]hiù o-hoe",
                            isCanonical: true,
                            media: [
                                ArchiveMedia(kind: "video", url: "https://example.com/v"),
                                ArchiveMedia(kind: "audio", filename: "abc123.mp3"),
                            ]
                        )
                    ]
                )
            ]
        )
    }

    func testRoundTripsThroughJSON() throws {
        let original = sampleArchive()
        let data = try original.encoded()
        let decoded = try OrainArchive.decode(from: data)
        XCTAssertEqual(decoded, original)
    }

    /// The Pi's own API payload shape must decode as-is, since that is what
    /// the export script dumps and what a future sync would receive.
    func testDecodesThePiApiFieldNames() throws {
        let json = """
        {
          "schema_version": 1,
          "exported_at": "2026-07-29T23:00:00Z",
          "songs": [
            {
              "slug": "oran-eirisgeidh",
              "title": "Òrain Eirisgeidh",
              "composer": null,
              "rating": null,
              "is_favourite": false,
              "on_hitlist": true,
              "notes": "Source PDF: 20260518_Oran Eirisgeidh.pdf",
              "tradition": null,
              "created_at": "2026-05-27 10:00:00",
              "versions": [
                {
                  "id": 12,
                  "song_id": 4,
                  "version_label": null,
                  "version_title": null,
                  "language": "gd",
                  "lyrics": null,
                  "melody": null,
                  "source": null,
                  "contributor": null,
                  "transpose": 0,
                  "is_canonical": true,
                  "created_at": "2026-05-27 10:00:00"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let archive = try OrainArchive.decode(from: json)
        XCTAssertEqual(archive.songs.count, 1)
        XCTAssertEqual(archive.songs[0].title, "Òrain Eirisgeidh")
        XCTAssertTrue(archive.songs[0].onHitlist)
        XCTAssertEqual(archive.songs[0].versions[0].sourceId, 12)
        XCTAssertTrue(archive.songs[0].versions[0].isCanonical)
        // Missing keys must not throw — `media` is absent here.
        XCTAssertEqual(archive.songs[0].versions[0].media, [])
    }

    func testRefusesAFutureSchemaVersion() throws {
        var archive = sampleArchive()
        archive.schemaVersion = OrainArchive.currentSchemaVersion + 1
        let data = try archive.encoded()

        XCTAssertThrowsError(try OrainArchive.decode(from: data)) { error in
            guard case ArchiveError.unsupportedSchemaVersion = error else {
                return XCTFail("expected unsupportedSchemaVersion, got \(error)")
            }
        }
    }

    func testMalformedJSONGivesAReadableError() {
        let data = Data("not json at all".utf8)
        XCTAssertThrowsError(try OrainArchive.decode(from: data)) { error in
            guard case ArchiveError.malformed = error else {
                return XCTFail("expected malformed, got \(error)")
            }
        }
    }

    /// The import screen needs to be able to say what will and will not
    /// come across — audio bytes do not travel in the JSON.
    func testSummaryCountsAudioThatWillNotTransfer() {
        let s = sampleArchive().summary
        XCTAssertEqual(s.songCount, 1)
        XCTAssertEqual(s.versionCount, 1)
        XCTAssertEqual(s.videoLinkCount, 1)
        XCTAssertEqual(s.audioNotTransferredCount, 1)
    }
}

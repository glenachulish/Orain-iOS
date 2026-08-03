//  Library.swift
//  OrainCore
//
//  Sorting and filtering for the song list — the logic the web app does
//  partly in Python (`songs._sort_key`) and partly in JavaScript
//  (`views/library.js`), gathered here so it is testable without a UI.

import Foundation

// MARK: - Accent-insensitive ordering

public enum SongSorting {

    /// Fold accents and case for sorting, so "Òrain Eirisgeidh" files beside
    /// "Oran Eirisgeidh" rather than after the W's.
    ///
    /// The Pi app hit this because SQLite's `NOCASE` folds only ASCII case, so
    /// a Gàidhlig initial sorted by raw code point. The fix there was to sort
    /// in Python with NFKD-then-drop-marks; this is the same rule, so the two
    /// apps list a library in the same order.
    public static func foldedTitle(_ title: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in title.decomposedStringWithCanonicalMapping.unicodeScalars
        where !isCombiningMark(scalar) {
            scalars.append(scalar)
        }
        return String(scalars).lowercased()
    }

    private static func isCombiningMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }

    /// Order two titles: folded form first, raw title as the tiebreaker so
    /// titles that fold alike still order predictably.
    public static func isOrderedBefore(_ a: String, _ b: String) -> Bool {
        let fa = foldedTitle(a)
        let fb = foldedTitle(b)
        if fa != fb { return fa < fb }
        return a < b
    }
}

// MARK: - Filtering

/// The library filters, all of which AND together — matching the web app,
/// where `?composer=…&tradition=…&lang=…&fav=1&hitlist=1&minRating=3`
/// compose rather than replace one another.
public struct LibraryFilter: Equatable, Sendable {
    public var searchText: String = ""
    public var composer: String? = nil
    /// "trad" | "modern"
    public var tradition: String? = nil
    /// "gd" | "en" — matched against the canonical version's language.
    public var language: String? = nil
    public var favouritesOnly: Bool = false
    public var hitlistOnly: Bool = false
    /// Show songs rated at least this. A threshold, not an exact match:
    /// "3+ = performable" is how the mastery model actually reads.
    public var minRating: Int? = nil

    /// User-created tags, matched by folded name. **All** of them must be
    /// present — asking for "wedding" and "slow air" means songs that are
    /// both, not songs that are either.
    ///
    /// AND rather than OR because that is what narrowing means everywhere
    /// else in this filter, and a set of switches that sometimes widened and
    /// sometimes narrowed would be impossible to predict. If "either" is ever
    /// wanted, it should be an explicit choice, not a silent inconsistency.
    public var tagNames: Set<String> = []

    public init() {}

    public var isActive: Bool {
        !(searchText.isEmpty
          && composer == nil
          && tradition == nil
          && language == nil
          && !favouritesOnly
          && !hitlistOnly
          && minRating == nil
          && tagNames.isEmpty)
    }

    /// A short description of what is currently being asked for, for the
    /// banner at the top of a filtered list.
    public var summary: String {
        var parts: [String] = []
        if let language { parts.append(language == "gd" ? "Gàidhlig" : "Beurla") }
        if let tradition { parts.append(tradition == "trad" ? "Traditional" : "Modern") }
        if favouritesOnly { parts.append("favourites") }
        if hitlistOnly { parts.append("hitlist") }
        if let minRating { parts.append("rated \(minRating)+") }
        if let composer { parts.append(composer) }
        parts.append(contentsOf: tagNames.sorted())
        return parts.joined(separator: " · ")
    }
}

/// The subset of a song the filter needs. Keeping this a protocol lets the
/// same logic run against archive rows in tests and SwiftData objects in the
/// app, without OrainCore having to know about SwiftData.
public protocol FilterableSong {
    var title: String { get }
    var composer: String? { get }
    var tradition: String? { get }
    /// The canonical version's language.
    var canonicalLanguage: String? { get }
    var isFavourite: Bool { get }
    var onHitlist: Bool { get }
    var rating: Int? { get }
    /// Lyrics of all versions, for full-text search.
    var searchableText: String { get }
    /// Names of the user-created tags on this song.
    var tagNames: [String] { get }
}

extension FilterableSong {
    /// Default so existing conformances keep working without tags.
    public var tagNames: [String] { [] }
}

public enum LibraryFiltering {

    public static func matches<S: FilterableSong>(_ song: S, _ filter: LibraryFilter) -> Bool {
        if let composer = filter.composer {
            guard let songComposer = song.composer,
                  songComposer.caseInsensitiveCompare(composer) == .orderedSame
            else { return false }
        }

        if let tradition = filter.tradition {
            guard song.tradition == tradition else { return false }
        }

        if let language = filter.language {
            guard song.canonicalLanguage == language else { return false }
        }

        if filter.favouritesOnly, !song.isFavourite { return false }
        if filter.hitlistOnly, !song.onHitlist { return false }

        if let minRating = filter.minRating {
            guard let rating = song.rating, rating >= minRating else { return false }
        }

        if !filter.tagNames.isEmpty {
            // Folded comparison, so a filter saved as "Wedding" still matches
            // a tag stored as "wedding".
            let songTags = Set(song.tagNames.map(SongSorting.foldedTitle))
            let wanted = Set(filter.tagNames.map(SongSorting.foldedTitle))
            guard wanted.isSubset(of: songTags) else { return false }
        }

        if !filter.searchText.isEmpty {
            // Accent- and case-insensitive, so typing "orain" finds "Òrain"
            // — the same folding used for sorting.
            let needle = SongSorting.foldedTitle(filter.searchText)
            let haystack = SongSorting.foldedTitle(song.title + "\n" + song.searchableText)
            guard haystack.contains(needle) else { return false }
        }

        return true
    }

    public static func apply<S: FilterableSong>(_ filter: LibraryFilter, to songs: [S]) -> [S] {
        songs
            .filter { matches($0, filter) }
            .sorted { SongSorting.isOrderedBefore($0.title, $1.title) }
    }
}

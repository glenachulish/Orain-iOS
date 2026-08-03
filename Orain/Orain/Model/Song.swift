//  Song.swift
//  Òrain
//
//  The on-device library. SwiftData rather than SQLite-by-hand: the Pi app
//  uses raw sqlite3 because it was the smallest thing that worked there, but
//  on iOS the smallest thing that works is SwiftData — it is the persistence
//  the platform gives you, and hand-rolling SQLite would mean writing the
//  migration machinery, the change notifications, and eventually the CloudKit
//  bridge that SwiftData already has.
//
//  The shape of the data is deliberately the same as the Pi's: a `Song` is
//  the thing you rate and title, a `SongVersion` is the thing you actually
//  sing. That split was the biggest lesson carried out of Ceòl and it is not
//  up for renegotiation here.

import Foundation
import SwiftData
import OrainCore

@Model
final class Song {
    /// Stable identity, carried over from the Pi so a re-import updates
    /// rather than duplicates.
    @Attribute(.unique) var slug: String

    var title: String
    var composer: String?

    // The three independent mastery axes, straight from Ceòl. Independent by
    // design: mastery, love, and "currently learning" are different things,
    // and no control should ever write more than its own field.
    var rating: Int?
    var isFavourite: Bool
    var onHitlist: Bool

    var notes: String?
    /// "trad" | "modern" | nil. nil is a normal state, not a missing value.
    var tradition: String?

    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SongVersion.song)
    var versions: [SongVersion] = []

    init(
        slug: String,
        title: String,
        composer: String? = nil,
        rating: Int? = nil,
        isFavourite: Bool = false,
        onHitlist: Bool = false,
        notes: String? = nil,
        tradition: String? = nil,
        createdAt: Date = .now
    ) {
        self.slug = slug
        self.title = title
        self.composer = composer
        self.rating = rating
        self.isFavourite = isFavourite
        self.onHitlist = onHitlist
        self.notes = notes
        self.tradition = tradition
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

extension Song {
    /// The version that auto-loads when the song is opened. Exactly one
    /// version should be canonical; if the data ever says otherwise, fall
    /// back to the first rather than showing nothing.
    var canonicalVersion: SongVersion? {
        versions.first(where: \.isCanonical) ?? sortedVersions.first
    }

    var sortedVersions: [SongVersion] {
        versions.sorted { a, b in
            if a.isCanonical != b.isCanonical { return a.isCanonical }
            return a.createdAt < b.createdAt
        }
    }

    /// Languages present across this song's versions, for the language chip.
    var languages: [String] {
        var seen: [String] = []
        for v in sortedVersions where !seen.contains(v.language) {
            seen.append(v.language)
        }
        return seen
    }

    /// Enforce exactly-one-canonical in code, as the Pi app does. The schema
    /// cannot express it, so something has to, and it may as well be the one
    /// method that sets it.
    func makeCanonical(_ version: SongVersion) {
        for v in versions {
            v.isCanonical = (v.persistentModelID == version.persistentModelID)
        }
        updatedAt = .now
    }
}

// Lets OrainCore's filtering run directly against the stored objects without
// OrainCore having to import SwiftData.
extension Song: FilterableSong {
    var canonicalLanguage: String? { canonicalVersion?.language }

    var searchableText: String {
        versions
            .compactMap { $0.lyrics }
            .joined(separator: "\n")
    }
}

@Model
final class SongVersion {
    var song: Song?

    /// What kind of version this is — "Up a 4th", "English singing translation".
    var versionLabel: String?
    /// The title this rendition is sung under; nil inherits the song's title.
    var versionTitle: String?
    /// "gd" | "en". Language lives on the version — a Beurla translation is a
    /// version of the song, not a separate cross-referenced song.
    var language: String
    /// ChordPro inline source, stored verbatim.
    var lyrics: String?
    var melody: String?
    var source: String?
    var transpose: Int
    var isCanonical: Bool
    var createdAt: Date

    /// The Pi row id this came from, so a re-import can recognise it.
    var sourceId: Int?

    @Relationship(deleteRule: .cascade, inverse: \MediaLink.version)
    var media: [MediaLink] = []

    init(
        versionLabel: String? = nil,
        versionTitle: String? = nil,
        language: String = "gd",
        lyrics: String? = nil,
        melody: String? = nil,
        source: String? = nil,
        transpose: Int = 0,
        isCanonical: Bool = false,
        createdAt: Date = .now,
        sourceId: Int? = nil
    ) {
        self.versionLabel = versionLabel
        self.versionTitle = versionTitle
        self.language = language
        self.lyrics = lyrics
        self.melody = melody
        self.source = source
        self.transpose = transpose
        self.isCanonical = isCanonical
        self.createdAt = createdAt
        self.sourceId = sourceId
    }
}

extension SongVersion {
    /// What to show at the top of the song page for this rendition.
    var displayTitle: String {
        versionTitle ?? song?.title ?? "Untitled"
    }

    var hasChorus: Bool {
        ChordPro.hasChorus(lyrics)
    }

    var hasLyrics: Bool {
        !(lyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var languageName: String {
        switch language {
        case "gd": return "Gàidhlig"
        case "en": return "Beurla"
        default: return language
        }
    }
}

@Model
final class MediaLink {
    var version: SongVersion?
    /// "audio" | "video"
    var kind: String
    var url: String?
    /// For audio recorded or imported on the phone.
    var filename: String?
    var label: String?
    var createdAt: Date

    init(
        kind: String,
        url: String? = nil,
        filename: String? = nil,
        label: String? = nil,
        createdAt: Date = .now
    ) {
        self.kind = kind
        self.url = url
        self.filename = filename
        self.label = label
        self.createdAt = createdAt
    }
}

//  OrainArchive.swift
//  OrainCore
//
//  The interchange format between the Pi app and the iOS app.
//
//  WHAT THIS IS FOR
//  ----------------
//  The iOS app keeps its own library on the phone (see the scope document for
//  why it cannot depend on the Pi). Callum's 48 songs already exist on the Pi,
//  so they need a way across. This is that way: a single JSON file, exported
//  from a per-user `orain.db` by `tools/export_orain_archive.py`, opened by
//  the iOS app through the Files app or AirDrop.
//
//  DESIGN NOTES
//  ------------
//  * Field names match the Pi API's `_song_public` / `_version_public`
//    payloads exactly. That keeps the export script a thin dump, and means a
//    future live-sync feature can reuse these same types against the real
//    endpoints rather than inventing a second vocabulary.
//  * `schemaVersion` is checked on import. Older files are still readable;
//    newer files are refused with a clear message rather than half-decoded.
//  * Audio files are NOT carried in the JSON — only the media rows that
//    describe them. Video links survive (they are just URLs); uploaded audio
//    is listed with `filename` so an import can report "3 recordings were not
//    transferred" instead of losing them silently.

import Foundation

// MARK: - Archive

public struct OrainArchive: Codable, Equatable, Sendable {
    /// Bumped whenever the shape changes incompatibly.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var exportedAt: String
    /// Free text describing where this came from, e.g. "orain Pi, user 1".
    public var source: String?
    public var songs: [ArchiveSong]

    public init(
        schemaVersion: Int = OrainArchive.currentSchemaVersion,
        exportedAt: String,
        source: String? = nil,
        songs: [ArchiveSong]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.source = source
        self.songs = songs
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case exportedAt = "exported_at"
        case source
        case songs
    }
}

// MARK: - Song

public struct ArchiveSong: Codable, Equatable, Sendable {
    public var slug: String
    public var title: String
    public var composer: String?
    /// 0–5, or nil for unrated. The mastery axis inherited from Ceòl.
    public var rating: Int?
    public var isFavourite: Bool
    public var onHitlist: Bool
    public var notes: String?
    /// "trad" | "modern" | nil. nil is a first-class state, not an error.
    public var tradition: String?
    public var createdAt: String?
    public var versions: [ArchiveVersion]

    public init(
        slug: String,
        title: String,
        composer: String? = nil,
        rating: Int? = nil,
        isFavourite: Bool = false,
        onHitlist: Bool = false,
        notes: String? = nil,
        tradition: String? = nil,
        createdAt: String? = nil,
        versions: [ArchiveVersion] = []
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
        self.versions = versions
    }

    enum CodingKeys: String, CodingKey {
        case slug, title, composer, rating, notes, tradition, versions
        case isFavourite = "is_favourite"
        case onHitlist = "on_hitlist"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        title = try c.decode(String.self, forKey: .title)
        composer = try c.decodeIfPresent(String.self, forKey: .composer)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating)
        isFavourite = try c.decodeIfPresent(Bool.self, forKey: .isFavourite) ?? false
        onHitlist = try c.decodeIfPresent(Bool.self, forKey: .onHitlist) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        tradition = try c.decodeIfPresent(String.self, forKey: .tradition)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        versions = try c.decodeIfPresent([ArchiveVersion].self, forKey: .versions) ?? []
    }
}

// MARK: - Version

public struct ArchiveVersion: Codable, Equatable, Sendable {
    /// The Pi's row id. Kept so a re-import can recognise a version it has
    /// seen before instead of duplicating it.
    public var sourceId: Int?
    /// Short descriptor of what kind of version this is ("Up a 4th").
    public var versionLabel: String?
    /// The title this rendition is sung under; nil inherits the song's title.
    public var versionTitle: String?
    /// "gd" | "en".
    public var language: String
    /// ChordPro inline source, verbatim.
    public var lyrics: String?
    public var melody: String?
    public var source: String?
    public var transpose: Int
    public var isCanonical: Bool
    public var createdAt: String?
    public var media: [ArchiveMedia]

    public init(
        sourceId: Int? = nil,
        versionLabel: String? = nil,
        versionTitle: String? = nil,
        language: String,
        lyrics: String? = nil,
        melody: String? = nil,
        source: String? = nil,
        transpose: Int = 0,
        isCanonical: Bool = false,
        createdAt: String? = nil,
        media: [ArchiveMedia] = []
    ) {
        self.sourceId = sourceId
        self.versionLabel = versionLabel
        self.versionTitle = versionTitle
        self.language = language
        self.lyrics = lyrics
        self.melody = melody
        self.source = source
        self.transpose = transpose
        self.isCanonical = isCanonical
        self.createdAt = createdAt
        self.media = media
    }

    enum CodingKeys: String, CodingKey {
        case language, lyrics, melody, source, transpose, media
        case sourceId = "id"
        case versionLabel = "version_label"
        case versionTitle = "version_title"
        case isCanonical = "is_canonical"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceId = try c.decodeIfPresent(Int.self, forKey: .sourceId)
        versionLabel = try c.decodeIfPresent(String.self, forKey: .versionLabel)
        versionTitle = try c.decodeIfPresent(String.self, forKey: .versionTitle)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "gd"
        lyrics = try c.decodeIfPresent(String.self, forKey: .lyrics)
        melody = try c.decodeIfPresent(String.self, forKey: .melody)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        transpose = try c.decodeIfPresent(Int.self, forKey: .transpose) ?? 0
        isCanonical = try c.decodeIfPresent(Bool.self, forKey: .isCanonical) ?? false
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        media = try c.decodeIfPresent([ArchiveMedia].self, forKey: .media) ?? []
    }
}

// MARK: - Media

public struct ArchiveMedia: Codable, Equatable, Sendable {
    /// "audio" | "video".
    public var kind: String
    /// Set for video rows.
    public var url: String?
    /// Set for audio rows — the stored filename on the Pi. The bytes do not
    /// travel in the archive; this is here so an import can tell the user
    /// what was left behind.
    public var filename: String?
    public var label: String?

    public init(kind: String, url: String? = nil, filename: String? = nil, label: String? = nil) {
        self.kind = kind
        self.url = url
        self.filename = filename
        self.label = label
    }
}

// MARK: - Reading and writing

public enum ArchiveError: Error, CustomStringConvertible, Equatable {
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case malformed(String)

    public var description: String {
        switch self {
        case let .unsupportedSchemaVersion(found, supported):
            return """
            This library file was written by a newer version of Òrain \
            (format \(found); this app understands up to \(supported)). \
            Update the app, then try again.
            """
        case let .malformed(detail):
            return "That file is not a readable Òrain library: \(detail)"
        }
    }
}

extension OrainArchive {

    /// Decode an archive, refusing files from a future format version rather
    /// than silently importing half of one.
    public static func decode(from data: Data) throws -> OrainArchive {
        let decoder = JSONDecoder()
        let archive: OrainArchive
        do {
            archive = try decoder.decode(OrainArchive.self, from: data)
        } catch {
            throw ArchiveError.malformed(String(describing: error))
        }
        guard archive.schemaVersion <= OrainArchive.currentSchemaVersion else {
            throw ArchiveError.unsupportedSchemaVersion(
                found: archive.schemaVersion,
                supported: OrainArchive.currentSchemaVersion
            )
        }
        return archive
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// A short human summary for the import confirmation screen.
    public var summary: ImportSummary {
        let versions = songs.reduce(0) { $0 + $1.versions.count }
        let audio = songs.reduce(0) { total, song in
            total + song.versions.reduce(0) { $0 + $1.media.filter { $0.kind == "audio" }.count }
        }
        let videos = songs.reduce(0) { total, song in
            total + song.versions.reduce(0) { $0 + $1.media.filter { $0.kind == "video" }.count }
        }
        return ImportSummary(
            songCount: songs.count,
            versionCount: versions,
            videoLinkCount: videos,
            audioNotTransferredCount: audio
        )
    }
}

public struct ImportSummary: Equatable, Sendable {
    public let songCount: Int
    public let versionCount: Int
    public let videoLinkCount: Int
    /// Audio recordings referenced by the archive whose bytes did not travel.
    public let audioNotTransferredCount: Int
}

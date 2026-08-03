//  LibraryImporter.swift
//  Òrain
//
//  Brings an exported Pi library into the on-device store.
//
//  UPSERT, NOT APPEND. Importing the same file twice must not produce two of
//  every song. Songs match on `slug`, versions on the Pi row id they came
//  from. Anything the phone has that the archive does not is left alone —
//  an import adds and updates, it never deletes. That asymmetry is
//  deliberate: a mistaken import should be annoying, not destructive.

import Foundation
import SwiftData
import OrainCore

struct ImportResult: Equatable {
    var songsAdded = 0
    var songsUpdated = 0
    var versionsAdded = 0
    var versionsUpdated = 0
    var videoLinksAdded = 0
    /// Audio the archive referenced but could not carry.
    var audioNotTransferred = 0

    var isEmpty: Bool {
        songsAdded == 0 && songsUpdated == 0 && versionsAdded == 0 && versionsUpdated == 0
    }

    var summaryLine: String {
        var parts: [String] = []
        if songsAdded > 0 { parts.append("\(songsAdded) song\(songsAdded == 1 ? "" : "s") added") }
        if songsUpdated > 0 { parts.append("\(songsUpdated) updated") }
        if versionsAdded > 0 { parts.append("\(versionsAdded) version\(versionsAdded == 1 ? "" : "s") added") }
        if parts.isEmpty { parts.append("nothing new") }
        return parts.joined(separator: ", ")
    }
}

enum LibraryImporter {

    static func importArchive(
        _ archive: OrainArchive,
        into context: ModelContext
    ) throws -> ImportResult {
        var result = ImportResult()

        let existing = try context.fetch(FetchDescriptor<Song>())
        var bySlug = Dictionary(
            existing.map { ($0.slug, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for incoming in archive.songs {
            let song: Song

            if let found = bySlug[incoming.slug] {
                song = found
                apply(incoming, to: song)
                result.songsUpdated += 1
            } else {
                song = Song(
                    slug: incoming.slug,
                    title: incoming.title,
                    composer: incoming.composer,
                    rating: incoming.rating,
                    isFavourite: incoming.isFavourite,
                    onHitlist: incoming.onHitlist,
                    notes: incoming.notes,
                    tradition: incoming.tradition,
                    createdAt: parseDate(incoming.createdAt) ?? .now
                )
                context.insert(song)
                bySlug[incoming.slug] = song
                result.songsAdded += 1
            }

            for incomingVersion in incoming.versions {
                let match = incomingVersion.sourceId.flatMap { id in
                    song.versions.first { $0.sourceId == id }
                }

                if let version = match {
                    apply(incomingVersion, to: version)
                    result.versionsUpdated += 1
                    result.videoLinksAdded += mergeMedia(incomingVersion, into: version, context: context)
                } else {
                    let version = SongVersion(
                        versionLabel: incomingVersion.versionLabel,
                        versionTitle: incomingVersion.versionTitle,
                        language: incomingVersion.language,
                        lyrics: incomingVersion.lyrics,
                        melody: incomingVersion.melody,
                        source: incomingVersion.source,
                        transpose: incomingVersion.transpose,
                        isCanonical: incomingVersion.isCanonical,
                        createdAt: parseDate(incomingVersion.createdAt) ?? .now,
                        sourceId: incomingVersion.sourceId
                    )
                    context.insert(version)
                    version.song = song
                    song.versions.append(version)
                    result.versionsAdded += 1
                    result.videoLinksAdded += mergeMedia(incomingVersion, into: version, context: context)
                }

                result.audioNotTransferred += incomingVersion.media.filter { $0.kind == "audio" }.count
            }

            // Repair the exactly-one-canonical rule if the archive left the
            // song without one (a Pi library can contain such rows).
            if !song.versions.isEmpty, !song.versions.contains(where: \.isCanonical),
               let first = song.sortedVersions.first {
                song.makeCanonical(first)
            }
        }

        try context.save()
        return result
    }

    // MARK: - Field application

    private static func apply(_ incoming: ArchiveSong, to song: Song) {
        song.title = incoming.title
        song.composer = incoming.composer
        song.rating = incoming.rating
        song.isFavourite = incoming.isFavourite
        song.onHitlist = incoming.onHitlist
        song.notes = incoming.notes
        song.tradition = incoming.tradition
        song.updatedAt = .now
    }

    private static func apply(_ incoming: ArchiveVersion, to version: SongVersion) {
        version.versionLabel = incoming.versionLabel
        version.versionTitle = incoming.versionTitle
        version.language = incoming.language
        version.lyrics = incoming.lyrics
        version.melody = incoming.melody
        version.source = incoming.source
        version.transpose = incoming.transpose
        version.isCanonical = incoming.isCanonical
    }

    /// Adds video links that are not already present. Audio rows are counted
    /// but not created — there is no file behind them on this device.
    private static func mergeMedia(
        _ incoming: ArchiveVersion,
        into version: SongVersion,
        context: ModelContext
    ) -> Int {
        var added = 0
        for media in incoming.media where media.kind == "video" {
            guard let url = media.url else { continue }
            let alreadyThere = version.media.contains { $0.kind == "video" && $0.url == url }
            guard !alreadyThere else { continue }

            let link = MediaLink(kind: "video", url: url, label: media.label)
            context.insert(link)
            link.version = version
            version.media.append(link)
            added += 1
        }
        return added
    }

    // MARK: - Dates

    /// The Pi writes SQLite's `CURRENT_TIMESTAMP` format ("2026-05-27
    /// 10:00:00", UTC) and, in places, ISO-8601. Accept both; fall back to
    /// "now" rather than refusing an import over a timestamp.
    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }

        let sqlite = DateFormatter()
        sqlite.locale = Locale(identifier: "en_US_POSIX")
        sqlite.timeZone = TimeZone(identifier: "UTC")
        sqlite.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return sqlite.date(from: raw)
    }
}

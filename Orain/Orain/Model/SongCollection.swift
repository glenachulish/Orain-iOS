//  SongCollection.swift
//  Òrain
//
//  Collections and tags — the two ways of grouping songs that the app itself
//  doesn't dictate.
//
//  A COLLECTION is a songbook: "Sessions", "Cèilidh set", "Learning". A song
//  can sit in several at once, and a collection is just a list — removing a
//  song from one has nothing to do with the song itself.
//
//  A TAG is a label the user invents: "wedding", "slow air", "needs work".
//  The app already has two built-in axes — language and tradition — which are
//  fixed because they mean something specific. Tags are for everything else,
//  and the app has no opinion about what they say.
//
//  Named `SongCollection` rather than `Collection` because Swift already has
//  a `Collection` protocol, and a model type shadowing it would produce
//  spectacularly confusing errors in every file that touched an array.

import Foundation
import SwiftData

@Model
final class SongCollection {
    @Attribute(.unique) var name: String
    var createdAt: Date

    /// No inverse and no cascade. Deleting a songbook must not delete the
    /// songs in it — that is the whole point of a songbook. SwiftData's
    /// default for a to-many relationship is `.nullify`, which is what is
    /// wanted here, but it is written out because getting it wrong would be
    /// quietly destructive.
    @Relationship(deleteRule: .nullify)
    var songs: [Song] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}

extension SongCollection {
    var songCount: Int { songs.count }

    func contains(_ song: Song) -> Bool {
        songs.contains { $0.persistentModelID == song.persistentModelID }
    }

    /// Add or remove, whichever the song is not already.
    func toggle(_ song: Song) {
        if let index = songs.firstIndex(where: { $0.persistentModelID == song.persistentModelID }) {
            songs.remove(at: index)
        } else {
            songs.append(song)
        }
    }
}

@Model
final class SongTag {
    @Attribute(.unique) var name: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify)
    var songs: [Song] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}

extension SongTag {
    var songCount: Int { songs.count }

    func contains(_ song: Song) -> Bool {
        songs.contains { $0.persistentModelID == song.persistentModelID }
    }

    func toggle(_ song: Song) {
        if let index = songs.firstIndex(where: { $0.persistentModelID == song.persistentModelID }) {
            songs.remove(at: index)
        } else {
            songs.append(song)
        }
    }

    /// Tag names are compared case- and accent-insensitively when deciding
    /// whether one already exists, so "Wedding" and "wedding" don't become
    /// two tags — but the name is stored exactly as it was typed.
    static func normalise(_ name: String) -> String {
        OrainCoreSortingBridge.fold(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Small shim so the model layer can use OrainCore's accent folding without
/// importing it into every file.
enum OrainCoreSortingBridge {
    static func fold(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars).lowercased()
    }
}

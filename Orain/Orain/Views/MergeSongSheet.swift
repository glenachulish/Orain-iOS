//  MergeSongSheet.swift
//  Òrain
//
//  "These two are the same song."
//
//  Pick another entry in the library and its versions move into this one.
//  Direction matters and is stated plainly on screen: the song you started
//  from survives, the one you pick disappears as a separate entry. Getting
//  that backwards would be the easiest possible mistake, so the confirmation
//  names both songs rather than saying "are you sure".

import SwiftUI
import SwiftData
import OrainCore

struct MergeSongSheet: View {
    /// The song that survives.
    let song: Song

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var songs: [Song]

    @State private var search = ""
    @State private var chosen: Song?

    /// Everything except this song, best guesses first.
    private var candidates: [Song] {
        let others = songs.filter { $0.persistentModelID != song.persistentModelID }

        let matching: [Song]
        if search.trimmingCharacters(in: .whitespaces).isEmpty {
            matching = others
        } else {
            let needle = SongSorting.foldedTitle(search)
            matching = others.filter {
                SongSorting.foldedTitle($0.title).contains(needle)
            }
        }

        // Likely duplicates float to the top: titles that are the same once
        // case, accents, trailing numbers and punctuation are set aside. This
        // is what catches "It Ain'T Necessarily So 2".
        let mine = comparisonKey(song.title)
        return matching.sorted { a, b in
            let aLikely = comparisonKey(a.title) == mine
            let bLikely = comparisonKey(b.title) == mine
            if aLikely != bLikely { return aLikely }
            return SongSorting.isOrderedBefore(a.title, b.title)
        }
    }

    /// A title reduced to the bit that identifies the song: folded, stripped
    /// of punctuation, and with a trailing copy-number removed.
    private func comparisonKey(_ title: String) -> String {
        var key = SongSorting.foldedTitle(title)
        key = key.filter { $0.isLetter || $0.isNumber || $0 == " " }
        var words = key.split(separator: " ").map(String.init)
        if let last = words.last, Int(last) != nil, words.count > 1 {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    private func looksLikeDuplicate(_ other: Song) -> Bool {
        comparisonKey(other.title) == comparisonKey(song.title)
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing to merge with", systemImage: "arrow.triangle.merge")
                    } description: {
                        Text("There is no other song in the library to combine this one with.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Merge into \(song.title)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Find the other song")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Merge these songs?",
                isPresented: Binding(
                    get: { chosen != nil },
                    set: { if !$0 { chosen = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Merge", role: .destructive) { merge() }
                Button("Cancel", role: .cancel) { chosen = nil }
            } message: {
                Text(confirmationText)
            }
        }
    }

    private var list: some View {
        List {
            Section {
                Text("The song you pick will be absorbed into **\(song.title)**. Its versions, tags and collections come across; it stops being a separate entry in the library.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Merge which song into this one?") {
                ForEach(candidates) { other in
                    Button {
                        chosen = other
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(other.title)
                                    .foregroundStyle(.primary)
                                Text(detail(other))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if looksLikeDuplicate(other) {
                                Text("likely match")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.chordColour.opacity(0.15), in: Capsule())
                                    .foregroundStyle(Theme.chordColour)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func detail(_ other: Song) -> String {
        var parts: [String] = []
        parts.append(other.versions.count == 1 ? "1 version" : "\(other.versions.count) versions")
        if let composer = other.composer, !composer.isEmpty { parts.append(composer) }
        if let language = other.canonicalLanguage {
            parts.append(language == "gd" ? "Gàidhlig" : "Beurla")
        }
        return parts.joined(separator: " · ")
    }

    private var confirmationText: String {
        guard let chosen else { return "" }
        let count = chosen.versions.count
        return """
        \(chosen.title) will be merged into \(song.title). \
        \(count == 1 ? "Its version" : "All \(count) of its versions") will move across, \
        and \(chosen.title) will no longer appear on its own in the library.
        """
    }

    private func merge() {
        guard let other = chosen else { return }
        song.absorb(other)
        context.delete(other)
        try? context.save()
        chosen = nil
        dismiss()
    }
}

//  BrowseView.swift
//  Òrain
//
//  The Filters tab: a table of contents for the library rather than a control
//  panel. Each row opens the song list already narrowed to that one thing.
//
//  Language and tradition are built in and fixed — they mean something
//  specific and the app relies on them. Tags are whatever the user has made
//  up, and are managed from here because there is nowhere else they'd belong.

import SwiftUI
import SwiftData
import OrainCore

struct BrowseView: View {
    @Environment(\.modelContext) private var context
    @Query private var songs: [Song]
    @Query private var tags: [SongTag]

    @State private var renaming: SongTag?
    @State private var tagName = ""

    private var sortedTags: [SongTag] {
        tags.sorted { SongSorting.isOrderedBefore($0.name, $1.name) }
    }

    private var composers: [String] {
        Array(Set(songs.compactMap(\.composer).filter { !$0.isEmpty }))
            .sorted(by: SongSorting.isOrderedBefore)
    }

    var body: some View {
        List {
            Section("Language") {
                filterLink("Gàidhlig", systemImage: "text.bubble", count: count { $0.canonicalLanguage == "gd" }) {
                    var f = LibraryFilter(); f.language = "gd"; return f
                }
                filterLink("Beurla", systemImage: "text.bubble", count: count { $0.canonicalLanguage == "en" }) {
                    var f = LibraryFilter(); f.language = "en"; return f
                }
            }

            Section("Tradition") {
                filterLink("Traditional", systemImage: "leaf", count: count { $0.tradition == "trad" }) {
                    var f = LibraryFilter(); f.tradition = "trad"; return f
                }
                filterLink("Modern", systemImage: "sparkles", count: count { $0.tradition == "modern" }) {
                    var f = LibraryFilter(); f.tradition = "modern"; return f
                }
            }

            Section("Progress") {
                filterLink("Favourites", systemImage: "hand.thumbsup", count: count(\.isFavourite)) {
                    var f = LibraryFilter(); f.favouritesOnly = true; return f
                }
                filterLink("Hitlist", systemImage: "pin", count: count(\.onHitlist)) {
                    var f = LibraryFilter(); f.hitlistOnly = true; return f
                }
                filterLink("Rated 3 or better", systemImage: "star", count: count { ($0.rating ?? 0) >= 3 }) {
                    var f = LibraryFilter(); f.minRating = 3; return f
                }
            }

            Section {
                if sortedTags.isEmpty {
                    Text("No tags yet. Swipe left on a song to add one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedTags) { tag in
                        NavigationLink {
                            // A preset filter rather than a fixed source, so
                            // the toolbar can add language, tradition or a
                            // second tag on top of it.
                            LibraryView(preset: {
                                var f = LibraryFilter(); f.tagNames = [tag.name]; return f
                            }(), title: tag.name)
                        } label: {
                            HStack {
                                Image(systemName: "tag")
                                    .foregroundStyle(Theme.chordColour)
                                Text(tag.name)
                                Spacer()
                                Text("\(tag.songCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                context.delete(tag)
                                try? context.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                tagName = tag.name
                                renaming = tag
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.gray)
                        }
                    }
                }
            } header: {
                Text("Tags")
            } footer: {
                Text("Deleting a tag removes the label. The songs stay where they are.")
            }

            if !composers.isEmpty {
                Section("Composer") {
                    ForEach(composers, id: \.self) { name in
                        NavigationLink {
                            LibraryView(preset: {
                                var f = LibraryFilter(); f.composer = name; return f
                            }(), title: name)
                        } label: {
                            Text(name)
                        }
                    }
                }
            }
        }
        .navigationTitle("Filters")
        .alert("Rename tag", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $tagName)
            Button("Save") {
                let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let renaming, !trimmed.isEmpty {
                    renaming.name = trimmed
                    try? context.save()
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    // MARK: Pieces

    private func filterLink(
        _ title: String,
        systemImage: String,
        count: Int,
        filter: @escaping () -> LibraryFilter
    ) -> some View {
        NavigationLink {
            LibraryView(preset: filter(), title: title)
        } label: {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.chordColour)
                Text(title)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func count(_ predicate: (Song) -> Bool) -> Int {
        songs.filter(predicate).count
    }

    private func count(_ keyPath: KeyPath<Song, Bool>) -> Int {
        songs.filter { $0[keyPath: keyPath] }.count
    }
}

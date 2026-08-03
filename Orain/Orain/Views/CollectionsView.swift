//  CollectionsView.swift
//  Òrain
//
//  Songbooks. Create with +, open by tapping, delete with a left swipe —
//  and deleting one never touches the songs inside it.

import SwiftUI
import SwiftData
import OrainCore

struct CollectionsView: View {
    @Environment(\.modelContext) private var context
    @Query private var collections: [SongCollection]

    @State private var showingNew = false
    @State private var newName = ""
    @State private var renaming: SongCollection?

    private var sorted: [SongCollection] {
        collections.sorted { SongSorting.isOrderedBefore($0.name, $1.name) }
    }

    var body: some View {
        Group {
            if collections.isEmpty {
                empty
            } else {
                list
            }
        }
        .navigationTitle("Collections")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    showingNew = true
                } label: {
                    Label("New collection", systemImage: "plus")
                }
            }
        }
        .alert("New collection", isPresented: $showingNew) {
            TextField("Name", text: $newName)
            Button("Create") { create() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A songbook — \"Cèilidh set\", \"Learning\", \"Sessions\".")
        }
        .alert("Rename collection", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $newName)
            Button("Save") {
                if let renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    renaming.name = newName.trimmingCharacters(in: .whitespaces)
                    try? context.save()
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var list: some View {
        List {
            ForEach(sorted) { collection in
                NavigationLink {
                    LibraryView(collection: collection)
                } label: {
                    HStack {
                        Image(systemName: "book.closed")
                            .foregroundStyle(Theme.chordColour)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(collection.name)
                            Text(countLabel(collection))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        delete(collection)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        newName = collection.name
                        renaming = collection
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.gray)
                }
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("No collections yet", systemImage: "books.vertical")
        } description: {
            Text("A collection is a songbook — a set you're learning, the ones for a cèilidh, whatever grouping is useful. Songs can be in as many as you like.")
        } actions: {
            Button("New collection") {
                newName = ""
                showingNew = true
            }
        }
    }

    private func countLabel(_ collection: SongCollection) -> String {
        let n = collection.songCount
        return n == 1 ? "1 song" : "\(n) songs"
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !collections.contains(where: {
            OrainCoreSortingBridge.fold($0.name) == OrainCoreSortingBridge.fold(name)
        }) else { return }

        context.insert(SongCollection(name: name))
        try? context.save()
        newName = ""
    }

    /// Deletes the songbook only. The songs it listed are untouched and stay
    /// in the library — SwiftData nullifies the link rather than cascading.
    private func delete(_ collection: SongCollection) {
        context.delete(collection)
        try? context.save()
    }
}

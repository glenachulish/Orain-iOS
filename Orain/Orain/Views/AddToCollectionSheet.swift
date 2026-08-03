//  AddToCollectionSheet.swift
//  Òrain
//
//  Where a song gets filed. Reached by swiping right on it in any list.
//
//  Multi-select rather than pick-one, because a song genuinely does belong in
//  several books at once — a Gàidhlig lament can be in "Learning" and
//  "Cèilidh set" and neither is wrong. Tapping toggles, so the same gesture
//  takes it out again.

import SwiftUI
import SwiftData
import OrainCore

struct AddToCollectionSheet: View {
    let song: Song

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var collections: [SongCollection]

    @State private var newName = ""
    @State private var creating = false

    private var sorted: [SongCollection] {
        collections.sorted { SongSorting.isOrderedBefore($0.name, $1.name) }
    }

    var body: some View {
        NavigationStack {
            List {
                if sorted.isEmpty {
                    Section {
                        Text("No collections yet. Make one below.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(sorted) { collection in
                            Button {
                                collection.toggle(song)
                                song.updatedAt = .now
                                try? context.save()
                            } label: {
                                HStack {
                                    Image(systemName: collection.contains(song)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(collection.contains(song)
                                                         ? Theme.chordColour : Color.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(collection.name)
                                            .foregroundStyle(.primary)
                                        Text(collection.songCount == 1
                                             ? "1 song" : "\(collection.songCount) songs")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Collections")
                    }
                }

                Section {
                    if creating {
                        HStack {
                            TextField("Name", text: $newName)
                                .textInputAutocapitalization(.words)
                                .onSubmit { create() }
                            Button("Add") { create() }
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button {
                            creating = true
                        } label: {
                            Label("New collection", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle(song.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Creates the collection and files the song in it in one go — the reason
    /// anyone is making a collection from this screen is to put this song in it.
    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if let existing = collections.first(where: {
            OrainCoreSortingBridge.fold($0.name) == OrainCoreSortingBridge.fold(name)
        }) {
            if !existing.contains(song) { existing.songs.append(song) }
        } else {
            let collection = SongCollection(name: name)
            context.insert(collection)
            collection.songs.append(song)
        }

        song.updatedAt = .now
        try? context.save()
        newName = ""
        creating = false
    }
}

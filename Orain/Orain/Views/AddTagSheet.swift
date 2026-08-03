//  AddTagSheet.swift
//  Òrain
//
//  Labels the user invents. Reached by swiping left on a song.
//
//  Tags differ from collections in what they're for: a collection is a book
//  you open and work through, a tag is a property you filter on. "Cèilidh
//  set" is a collection; "slow air" is a tag. The app doesn't enforce that —
//  it's just why both exist.

import SwiftUI
import SwiftData
import OrainCore

struct AddTagSheet: View {
    let song: Song

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var tags: [SongTag]

    @State private var newName = ""

    private var sorted: [SongTag] {
        tags.sorted { SongSorting.isOrderedBefore($0.name, $1.name) }
    }

    /// Tags already on this song, so they can be shown first and removed.
    private var onThisSong: [SongTag] {
        sorted.filter { $0.contains(song) }
    }

    private var others: [SongTag] {
        sorted.filter { !$0.contains(song) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New tag", text: $newName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { addNew() }
                        Button("Add") { addNew() }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text("Anything useful — \"wedding\", \"slow air\", \"needs work\".")
                }

                if !onThisSong.isEmpty {
                    Section("On this song") {
                        ForEach(onThisSong) { tag in
                            tagRow(tag, isOn: true)
                        }
                    }
                }

                if !others.isEmpty {
                    Section(onThisSong.isEmpty ? "Tags" : "Other tags") {
                        ForEach(others) { tag in
                            tagRow(tag, isOn: false)
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

    private func tagRow(_ tag: SongTag, isOn: Bool) -> some View {
        Button {
            tag.toggle(song)
            song.updatedAt = .now
            try? context.save()
        } label: {
            HStack {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.indigo : Color.secondary)
                Text(tag.name)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(tag.songCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Reuses an existing tag when the name matches ignoring case and
    /// accents, so "Wedding" and "wedding" don't become two separate labels
    /// that each hold half the songs.
    private func addNew() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if let existing = tags.first(where: {
            OrainCoreSortingBridge.fold($0.name) == OrainCoreSortingBridge.fold(name)
        }) {
            if !existing.contains(song) { existing.songs.append(song) }
        } else {
            let tag = SongTag(name: name)
            context.insert(tag)
            tag.songs.append(song)
        }

        song.updatedAt = .now
        try? context.save()
        newName = ""
    }
}

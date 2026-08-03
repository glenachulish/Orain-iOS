//  VersionManagerView.swift
//  Òrain
//
//  Rename a version, choose which one opens with the song, delete the ones
//  you no longer want.
//
//  Transposition makes versions multiply — try three keys and you have four
//  versions — so this is not a tidy-up feature, it is the other half of the
//  transpose feature.

import SwiftUI
import SwiftData
import OrainCore

struct VersionManagerView: View {
    @Bindable var song: Song

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var renaming: SongVersion?
    @State private var deleting: SongVersion?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(song.sortedVersions) { version in
                        row(version)
                    }
                } footer: {
                    Text("The default version is the one that opens with the song. Every song has exactly one.")
                }
            }
            .navigationTitle("Versions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $renaming) { version in
                RenameVersionSheet(version: version, song: song)
            }
            .confirmationDialog(
                "Delete this version?",
                isPresented: Binding(
                    get: { deleting != nil },
                    set: { if !$0 { deleting = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let deleting { delete(deleting) }
                    deleting = nil
                }
                Button("Keep it", role: .cancel) { deleting = nil }
            } message: {
                Text(deleteWarning)
            }
        }
    }

    // MARK: Row

    private func row(_ version: SongVersion) -> some View {
        HStack(spacing: 12) {
            Button {
                song.makeCanonical(version)
                try? context.save()
            } label: {
                Image(systemName: version.isCanonical ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(version.isCanonical ? Theme.mastery : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(version.isCanonical ? "Default version" : "Make this the default")

            VStack(alignment: .leading, spacing: 2) {
                Text(name(version))
                HStack(spacing: 6) {
                    Text(version.languageName)
                    if version.transpose != 0, let key = keyName(version) {
                        Text("· key of \(key)")
                    }
                    if !version.hasLyrics {
                        Text("· no words yet")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button {
                    renaming = version
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    split(version)
                } label: {
                    Label("Make it its own song", systemImage: "arrow.triangle.branch")
                }
                .disabled(song.versions.count < 2)

                Button(role: .destructive) {
                    deleting = version
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func name(_ version: SongVersion) -> String {
        if let label = version.versionLabel, !label.isEmpty { return label }
        if version.isCanonical { return "Main version" }
        return version.languageName
    }

    /// The key this version sounds in, once its transpose offset is applied.
    private func keyName(_ version: SongVersion) -> String? {
        guard let key = Transposer.detectKey(version.lyrics) else { return nil }
        let moved = key + version.transpose
        return Transposer.noteName(moved, preferFlats: Transposer.prefersFlats(key: moved))
    }

    private var deleteWarning: String {
        guard let deleting else { return "" }
        if song.versions.count == 1 {
            return "This is the only version of \(song.title). Deleting it leaves the song with no words."
        }
        if deleting.isCanonical {
            return "This is the default version. Another one will take its place."
        }
        return "This cannot be undone."
    }

    // MARK: Split

    /// Lift a version out into a song of its own — the inverse of merging.
    ///
    /// For when two things were filed as one song and shouldn't have been: a
    /// bulk import that folded two different songs together, or a version
    /// added to the wrong song by mistake.
    ///
    /// The new song inherits the version's own title if it has one, otherwise
    /// its label, otherwise the parent's title with a note that it was split.
    /// Progress fields are copied rather than moved: the original song has
    /// not become less learned by losing a version.
    private func split(_ version: SongVersion) {
        guard song.versions.count > 1 else { return }  // never leave a song empty

        let title = version.versionTitle
            ?? version.versionLabel
            ?? song.title
        let wasCanonical = version.isCanonical

        let newSong = Song(
            slug: uniqueSlug(from: title),
            title: title,
            composer: song.composer,
            rating: song.rating,
            isFavourite: song.isFavourite,
            onHitlist: song.onHitlist,
            notes: song.notes,
            tradition: song.tradition
        )
        context.insert(newSong)

        // Move the version across.
        song.versions.removeAll { $0.persistentModelID == version.persistentModelID }
        version.song = newSong
        version.isCanonical = true
        version.versionLabel = nil          // it is the whole song now, not a variant
        version.versionTitle = nil
        newSong.versions.append(version)

        // Filing carries over — it was in those books as this material.
        for collection in song.collections { collection.songs.append(newSong) }
        for tag in song.tags { tag.songs.append(newSong) }

        // The original keeps a canonical version.
        if wasCanonical, let replacement = song.sortedVersions.first {
            song.makeCanonical(replacement)
        }
        song.updatedAt = .now

        try? context.save()
    }

    /// Slugs identify songs for re-import, so a split song needs one nothing
    /// else is using.
    private func uniqueSlug(from title: String) -> String {
        let base = OrainCoreSortingBridge.fold(title)
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character == "-", result.last == "-" { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let existing = (try? context.fetch(FetchDescriptor<Song>()))?.map(\.slug) ?? []
        var candidate = base.isEmpty ? "song" : base
        var suffix = 2
        while existing.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    // MARK: Delete

    private func delete(_ version: SongVersion) {
        let wasCanonical = version.isCanonical

        song.versions.removeAll { $0.persistentModelID == version.persistentModelID }
        context.delete(version)

        // Deleting the default must leave another one in its place, or the
        // song opens to nothing.
        if wasCanonical, let replacement = song.sortedVersions.first {
            song.makeCanonical(replacement)
        }

        song.updatedAt = .now
        try? context.save()
    }
}

// MARK: - Rename

struct RenameVersionSheet: View {
    @Bindable var version: SongVersion
    let song: Song

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Version name", text: $label)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Name")
                } footer: {
                    Text("What kind of version this is — \"In C\", \"Up a 4th\", \"English singing translation\".")
                }

                Section {
                    TextField(song.title, text: $title)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Sung under the title")
                } footer: {
                    Text("Only if this version is known by a different name. Leave it empty to use the song's own title.")
                }
            }
            .navigationTitle("Rename version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                label = version.versionLabel ?? ""
                title = version.versionTitle ?? ""
            }
        }
    }

    private func save() {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        version.versionLabel = trimmedLabel.isEmpty ? nil : trimmedLabel
        version.versionTitle = trimmedTitle.isEmpty ? nil : trimmedTitle
        song.updatedAt = .now

        try? context.save()
        dismiss()
    }
}

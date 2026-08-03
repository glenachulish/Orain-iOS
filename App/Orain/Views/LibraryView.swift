//  LibraryView.swift
//  Òrain
//
//  The song list, with the same filters the web library grew: composer,
//  tradition, language, favourite, hitlist, and rating-as-a-threshold. They
//  AND together rather than replacing one another, which is what makes
//  "Gàidhlig songs on the hitlist rated 3 or better" a thing you can ask for.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OrainCore

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query private var songs: [Song]

    @State private var filter = LibraryFilter()
    @State private var showingFilters = false
    @State private var showingImporter = false
    @State private var importMessage: String?

    private var visibleSongs: [Song] {
        LibraryFiltering.apply(filter, to: songs)
    }

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    emptyLibrary
                } else if visibleSongs.isEmpty {
                    ContentUnavailableView.search
                } else {
                    songList
                }
            }
            .navigationTitle("Òrain")
            .searchable(text: $filter.searchText, prompt: "Title or words")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilters = true
                    } label: {
                        Label(
                            "Filters",
                            systemImage: filter.isActive
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterSheet(filter: $filter, songs: songs)
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert(
                "Import",
                isPresented: Binding(
                    get: { importMessage != nil },
                    set: { if !$0 { importMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    // MARK: Pieces

    private var songList: some View {
        List {
            if filter.isActive {
                Section {
                    HStack {
                        Text("\(visibleSongs.count) of \(songs.count) songs")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") { filter = LibraryFilter() }
                            .font(.footnote)
                    }
                }
            }

            ForEach(visibleSongs) { song in
                NavigationLink(value: song.slug) {
                    SongRow(song: song)
                }
            }
        }
        .navigationDestination(for: String.self) { slug in
            if let song = songs.first(where: { $0.slug == slug }) {
                SongView(song: song)
            } else {
                Text("That song is no longer here.")
            }
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No songs yet", systemImage: "music.note.list")
        } description: {
            Text("Import a library exported from Òrain, or add a song by hand.")
        } actions: {
            Button("Import a library…") { showingImporter = true }
        }
    }

    // MARK: Import

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }

            // Files handed over by the system arrive security-scoped.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let archive = try OrainArchive.decode(from: data)
            let outcome = try LibraryImporter.importArchive(archive, into: context)

            var message = outcome.summaryLine
            if outcome.audioNotTransferred > 0 {
                message += """
                    \n\n\(outcome.audioNotTransferred) audio recording\
                    \(outcome.audioNotTransferred == 1 ? "" : "s") could not come \
                    across — the files stay where they were exported from.
                    """
            }
            importMessage = message
        } catch let error as ArchiveError {
            importMessage = error.description
        } catch {
            importMessage = "Could not import that file: \(error.localizedDescription)"
        }
    }
}

// MARK: - Row

struct SongRow: View {
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.title)
                .font(.body)

            HStack(spacing: 6) {
                if let composer = song.composer, !composer.isEmpty {
                    Text(composer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let tradition = song.tradition {
                    Text(tradition == "trad" ? "Trad" : "Modern")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                if let language = song.canonicalLanguage {
                    Text(language == "gd" ? "Gàidhlig" : "Beurla")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                StarRating(rating: song.rating) { new in
                    song.rating = new
                    song.updatedAt = .now
                }
                if song.isFavourite {
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.mastery)
                }
                if song.onHitlist {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.mastery)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Five taps, one field. Tapping the current rating again clears it — the
/// same "click the active one to clear" gesture the language toggle uses.
struct StarRating: View {
    let rating: Int?
    var onChange: (Int?) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: (rating ?? 0) >= star ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle((rating ?? 0) >= star ? Theme.mastery : Color.secondary.opacity(0.4))
                    .onTapGesture {
                        onChange(rating == star ? nil : star)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(rating.map { "\($0) of 5" } ?? "not rated")
    }
}

// MARK: - Filters

struct FilterSheet: View {
    @Binding var filter: LibraryFilter
    let songs: [Song]
    @Environment(\.dismiss) private var dismiss

    private var composers: [String] {
        Array(Set(songs.compactMap(\.composer).filter { !$0.isEmpty }))
            .sorted(by: SongSorting.isOrderedBefore)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Progress") {
                    Toggle("Favourites only", isOn: $filter.favouritesOnly)
                    Toggle("On the hitlist", isOn: $filter.hitlistOnly)

                    Picker("Rated at least", selection: $filter.minRating) {
                        Text("Any").tag(Int?.none)
                        ForEach(1...5, id: \.self) { n in
                            Text("\(n)+").tag(Int?.some(n))
                        }
                    }
                }

                Section("Language") {
                    Picker("Language", selection: $filter.language) {
                        Text("All").tag(String?.none)
                        Text("Gàidhlig").tag(String?.some("gd"))
                        Text("Beurla").tag(String?.some("en"))
                    }
                    .pickerStyle(.segmented)
                }

                Section("Tradition") {
                    Picker("Tradition", selection: $filter.tradition) {
                        Text("All").tag(String?.none)
                        Text("Trad").tag(String?.some("trad"))
                        Text("Modern").tag(String?.some("modern"))
                    }
                    .pickerStyle(.segmented)
                }

                if !composers.isEmpty {
                    Section("Composer") {
                        Picker("Composer", selection: $filter.composer) {
                            Text("Anyone").tag(String?.none)
                            ForEach(composers, id: \.self) { name in
                                Text(name).tag(String?.some(name))
                            }
                        }
                    }
                }

                Section {
                    Button("Clear all filters", role: .destructive) {
                        let text = filter.searchText
                        filter = LibraryFilter()
                        filter.searchText = text
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

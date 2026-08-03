//  LibraryView.swift
//  Òrain
//
//  The song list. Used three ways: as the whole library, as the contents of a
//  collection, and as the result of picking a filter in the Filters tab — the
//  same view each time, because they are all "a list of songs" and giving
//  them separate screens would mean three places to fix any future bug.
//
//  Swipe right to file a song in a collection; swipe left to tag it. Both are
//  additive and reversible: nothing in this list deletes a song.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OrainCore

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query private var songs: [Song]

    /// When set, the list shows only this collection's songs.
    private let collection: SongCollection?
    /// When set, the list shows only songs carrying this tag.
    private let tag: SongTag?
    /// A filter applied on entry, from the Filters tab.
    private let preset: LibraryFilter?
    private let presetTitle: String?

    @State private var filter = LibraryFilter()
    @State private var showingFilters = false
    @State private var showingImporter = false
    @State private var importMessage: String?
    @State private var addingToCollection: Song?
    @State private var taggingSong: Song?
    @State private var deletingSong: Song?

    init(
        collection: SongCollection? = nil,
        tag: SongTag? = nil,
        preset: LibraryFilter? = nil,
        title: String? = nil
    ) {
        self.collection = collection
        self.tag = tag
        self.preset = preset
        self.presetTitle = title
    }

    // MARK: Contents

    /// The songs this list is drawn from, before the search box and switches.
    private var source: [Song] {
        if let collection { return collection.songs }
        if let tag { return tag.songs }
        return songs
    }

    private var visibleSongs: [Song] {
        LibraryFiltering.apply(filter, to: source)
    }

    private var title: String {
        if let collection { return collection.name }
        if let tag { return tag.name }
        if let presetTitle { return presetTitle }
        return "Òrain"
    }

    /// The whole library is the only place that needs the import button and
    /// the empty-library invitation.
    private var isWholeLibrary: Bool {
        collection == nil && tag == nil && preset == nil
    }

    var body: some View {
        Group {
            if source.isEmpty {
                emptySource
            } else if visibleSongs.isEmpty {
                ContentUnavailableView.search
            } else {
                songList
            }
        }
        // On the whole library the wordmark is the title, so the navigation
        // bar carries none — anything there would duplicate it. Filtered and
        // collection lists keep an ordinary inline title, since they need to
        // say which list you are looking at.
        .navigationTitle(isWholeLibrary ? "" : title)
        .navigationBarTitleDisplayMode(.inline)
        // Pinned rather than hidden-until-you-pull-down. With a library this
        // size, finding a song is the commonest thing you do here, and a
        // search box you have to go looking for is one step in the way of it.
        .searchable(
            text: $filter.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Title or words"
        )
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
            if isWholeLibrary {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
        .onAppear {
            if let preset, !filter.isActive { filter = preset }
        }
        .sheet(isPresented: $showingFilters) {
            FilterSheet(filter: $filter, songs: source)
        }
        .sheet(item: $addingToCollection) { song in
            AddToCollectionSheet(song: song)
        }
        .sheet(item: $taggingSong) { song in
            AddTagSheet(song: song)
        }
        .confirmationDialog(
            deletingSong.map { "Delete “\($0.title)”?" } ?? "",
            isPresented: Binding(
                get: { deletingSong != nil },
                set: { if !$0 { deletingSong = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete song", role: .destructive) {
                if let song = deletingSong {
                    context.delete(song)
                    try? context.save()
                }
                deletingSong = nil
            }
            Button("Keep it", role: .cancel) { deletingSong = nil }
        } message: {
            Text(deletingSong.map(deleteWarning) ?? "")
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

    // MARK: List

    private var songList: some View {
        List {
            // The wordmark stands where a large navigation title would, and
            // scrolls away with the content for the same reason one does —
            // it is a greeting, not a control, and it should get out of the
            // way once you are reading the list.
            if isWholeLibrary {
                Wordmark()
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
            }

            if filter.isActive {
                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("\(visibleSongs.count) of \(source.count) songs")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            // Clearing returns to however this list was
                            // entered — from a tag or a filter row, back to
                            // that, not all the way out to the whole library.
                            Button("Clear") { filter = preset ?? LibraryFilter() }
                                .font(.footnote)
                        }
                        if !filter.summary.isEmpty {
                            Text(filter.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            ForEach(visibleSongs) { song in
                NavigationLink {
                    SongView(song: song)
                } label: {
                    SongRow(song: song)
                }
                // Swipe right — adding. Both filing actions live here, with
                // Collection first because it is the commoner one: a full
                // swipe fires the first button, so the quick gesture files a
                // song in a book and the deliberate one reaches the tag.
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        addingToCollection = song
                    } label: {
                        Label("Collection", systemImage: "text.badge.plus")
                    }
                    .tint(Theme.chordColour)

                    Button {
                        taggingSong = song
                    } label: {
                        Label("Tag", systemImage: "tag")
                    }
                    .tint(.indigo)
                }
                // Swipe left — taking away. Full swipe is deliberately OFF on
                // this edge: the first button is destructive, and a gesture
                // that deletes a song by being slightly too enthusiastic is
                // not a gesture worth having.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deletingSong = song
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    if let collection {
                        Button {
                            collection.toggle(song)
                            song.updatedAt = .now
                            try? context.save()
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptySource: some View {
        if isWholeLibrary {
            // The empty screen carries the wordmark too, otherwise the app
            // has no name on it at all before the first import.
            VStack(spacing: 24) {
                Wordmark(size: 34)
                ContentUnavailableView {
                    Label("No songs yet", systemImage: "music.note.list")
                } description: {
                    Text("Import a library exported from Òrain, or add a song by hand.")
                } actions: {
                    Button("Import a library…") { showingImporter = true }
                }
            }
        } else if collection != nil {
            ContentUnavailableView {
                Label("Nothing in here yet", systemImage: "book.closed")
            } description: {
                Text("Swipe right on a song in the Songs tab to file it in this collection.")
            }
        } else {
            ContentUnavailableView {
                Label("Nothing matches", systemImage: "magnifyingglass")
            } description: {
                Text("No songs carry this yet.")
            }
        }
    }

    // MARK: Delete

    /// Names what is actually about to be lost. The same wording as the song
    /// page's warning, because the gesture is easier to trigger from here and
    /// the stakes are identical.
    private func deleteWarning(_ song: Song) -> String {
        var parts: [String] = []

        let versionCount = song.versions.count
        if versionCount > 0 {
            parts.append(versionCount == 1 ? "its words" : "all \(versionCount) versions")
        }
        let mediaCount = song.versions.reduce(0) { $0 + $1.media.count }
        if mediaCount > 0 {
            parts.append(mediaCount == 1 ? "1 recording or link" : "\(mediaCount) recordings and links")
        }
        if !song.collections.isEmpty {
            let names = song.collections.map(\.name).sorted().joined(separator: ", ")
            parts.append("its place in \(names)")
        }

        if parts.isEmpty { return "This cannot be undone." }
        return "This removes " + parts.joined(separator: ", ") + ". It cannot be undone."
    }

    // MARK: Import

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }

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

            if !song.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(song.tags.prefix(4)) { tag in
                        Text(tag.name)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.indigo.opacity(0.12), in: Capsule())
                            .foregroundStyle(.indigo)
                    }
                    if song.tags.count > 4 {
                        Text("+\(song.tags.count - 4)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
                if !song.collections.isEmpty {
                    Image(systemName: "book.closed.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Five taps, one field. Tapping the current rating again clears it — the
/// same "tap the active one to clear" gesture used elsewhere.
struct StarRating: View {
    let rating: Int?
    /// Point size of one star. Small by default: five stars sit alongside the
    /// composer and language on one line, and they are the least important
    /// thing there — if anything has to give way it should be the stars, not
    /// the words.
    var size: CGFloat = 11
    var onChange: (Int?) -> Void

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: (rating ?? 0) >= star ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle((rating ?? 0) >= star ? Theme.mastery : Color.secondary.opacity(0.4))
                    .onTapGesture {
                        onChange(rating == star ? nil : star)
                    }
            }
        }
        .fixedSize()
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

    @Query private var allTags: [SongTag]

    private var composers: [String] {
        Array(Set(songs.compactMap(\.composer).filter { !$0.isEmpty }))
            .sorted(by: SongSorting.isOrderedBefore)
    }

    private var tags: [SongTag] {
        allTags.sorted { SongSorting.isOrderedBefore($0.name, $1.name) }
    }

    /// How many of the songs on screen would survive adding this tag — shown
    /// so you can see a filter is about to empty the list before you tap it.
    private func remaining(withTag tag: SongTag) -> Int {
        var trial = filter
        trial.tagNames.insert(tag.name)
        return songs.filter { LibraryFiltering.matches($0, trial) }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                if !tags.isEmpty {
                    Section {
                        ForEach(tags) { tag in
                            Button {
                                if filter.tagNames.contains(tag.name) {
                                    filter.tagNames.remove(tag.name)
                                } else {
                                    filter.tagNames.insert(tag.name)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: filter.tagNames.contains(tag.name)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(filter.tagNames.contains(tag.name)
                                                         ? Color.indigo : Color.secondary)
                                    Text(tag.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(remaining(withTag: tag))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Tags")
                    } footer: {
                        Text("Choosing more than one narrows: songs must carry all of them.")
                    }
                }

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

//  SongView.swift
//  Òrain
//
//  One song: its versions, its words, and the controls you actually want
//  while singing — chords on or off, repeat the chorus, reveal a line at a
//  time, and keep the screen awake.
//
//  The reveal and repeat-chorus behaviours are ported from the web app rather
//  than reinvented, including their rules: reveal counts only real lyric
//  lines, and reveal and auto-scroll are mutually exclusive.

import SwiftUI
import SwiftData
import UIKit
import OrainCore

struct SongView: View {
    @Bindable var song: Song
    @Environment(\.modelContext) private var context

    @State private var selectedVersionID: PersistentIdentifier?
    @State private var showChords = true
    @State private var repeatChorus = false
    @State private var revealMode = false
    @State private var revealedLines = 0
    @State private var fontSize: CGFloat = 17
    @State private var keepAwake = false
    @State private var showingTranspose = false
    @State private var showingVersions = false

    private var versions: [SongVersion] { song.sortedVersions }

    private var activeVersion: SongVersion? {
        versions.first { $0.persistentModelID == selectedVersionID } ?? song.canonicalVersion
    }

    private var lyricsView: LyricsView {
        LyricsView(
            lyrics: activeVersion?.lyrics,
            options: LyricDisplayOptions(
                showChords: showChords,
                repeatChorus: repeatChorus,
                revealedLines: revealMode ? revealedLines : nil,
                fontSize: fontSize,
                transposeSemitones: activeVersion?.transpose ?? 0
            ),
            onTap: advanceReveal
        )
    }

    /// The key this version actually sounds in, once its transpose offset is
    /// applied. Nil for a version with no chords.
    private var soundingKey: String? {
        guard let version = activeVersion,
              let key = Transposer.detectKey(version.lyrics)
        else { return nil }
        let moved = key + version.transpose
        return Transposer.noteName(moved, preferFlats: Transposer.prefersFlats(key: moved))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if versions.count > 1 { versionPicker }
                controls
                if revealMode { revealBar }
                lyricsView
                    .padding(.top, 4)
                mediaSection
                if let notes = song.notes, !notes.isEmpty {
                    notesSection(notes)
                }
            }
            .padding()
        }
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        song.isFavourite.toggle()
                        song.updatedAt = .now
                    } label: {
                        Label(
                            song.isFavourite ? "Remove from favourites" : "Add to favourites",
                            systemImage: song.isFavourite ? "hand.thumbsdown" : "hand.thumbsup"
                        )
                    }
                    Button {
                        song.onHitlist.toggle()
                        song.updatedAt = .now
                    } label: {
                        Label(
                            song.onHitlist ? "Take off the hitlist" : "Put on the hitlist",
                            systemImage: song.onHitlist ? "pin.slash" : "pin"
                        )
                    }
                    Divider()
                    Button {
                        showingTranspose = true
                    } label: {
                        Label("Change key…", systemImage: "music.quarternote.3")
                    }
                    .disabled(!(activeVersion.map { Transposer.detectKey($0.lyrics) != nil } ?? false))

                    Button {
                        showingVersions = true
                    } label: {
                        Label("Versions…", systemImage: "square.stack")
                    }
                    Divider()
                    Toggle("Keep screen awake", isOn: $keepAwake)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingTranspose) {
            if let version = activeVersion {
                // Switch straight to the new version on save — you asked to see
                // the song in another key, so show it in that key.
                TransposeSheet(song: song, version: version) { created in
                    selectedVersionID = created.persistentModelID
                }
            }
        }
        .sheet(isPresented: $showingVersions) {
            VersionManagerView(song: song)
        }
        .onAppear {
            if selectedVersionID == nil {
                selectedVersionID = song.canonicalVersion?.persistentModelID
            }
        }
        .onChange(of: selectedVersionID) { _, _ in
            // A new version means a new set of lines — start the reveal over
            // rather than leaving a half-revealed page from the last one.
            revealedLines = 0
            if !(activeVersion?.hasChorus ?? false) { repeatChorus = false }
        }
        .onChange(of: keepAwake) { _, awake in
            UIApplication.shared.isIdleTimerDisabled = awake
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let version = activeVersion, version.displayTitle != song.title {
                Text(version.displayTitle)
                    .font(.title3)
            }

            HStack(spacing: 10) {
                StarRating(rating: song.rating) { new in
                    song.rating = new
                    song.updatedAt = .now
                }
                if let composer = song.composer, !composer.isEmpty {
                    Text(composer).font(.caption).foregroundStyle(.secondary)
                }
                if let version = activeVersion {
                    Text(version.languageName).font(.caption).foregroundStyle(.secondary)
                }
                if let soundingKey {
                    Text(soundingKey)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.chordColour.opacity(0.12), in: Capsule())
                        .foregroundStyle(Theme.chordColour)
                        .accessibilityLabel("Key of \(soundingKey)")
                }
            }
        }
    }

    private var versionPicker: some View {
        Picker("Version", selection: $selectedVersionID) {
            ForEach(versions) { version in
                Text(versionName(version))
                    .tag(Optional(version.persistentModelID))
            }
        }
        .pickerStyle(.segmented)
    }

    private func versionName(_ version: SongVersion) -> String {
        if let label = version.versionLabel, !label.isEmpty { return label }
        if version.isCanonical { return "Main" }
        return version.languageName
    }

    // MARK: Controls

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { controlButtons }
            VStack(alignment: .leading, spacing: 8) { controlButtons }
        }
    }

    @ViewBuilder
    private var controlButtons: some View {
        Toggle(isOn: $showChords) {
            Label("Chords", systemImage: "guitars")
        }
        .toggleStyle(.button)
        .disabled(!(activeVersion.map { ($0.lyrics ?? "").contains("[") } ?? false))

        if activeVersion?.hasChorus == true {
            Toggle(isOn: $repeatChorus) {
                Label("Repeat sèist", systemImage: "repeat")
            }
            .toggleStyle(.button)
        }

        Toggle(isOn: $revealMode) {
            Label("Reveal", systemImage: "eye")
        }
        .toggleStyle(.button)
        .onChange(of: revealMode) { _, on in
            if on { revealedLines = 0 }
        }

        Stepper("Size", value: $fontSize, in: 13...30, step: 1)
            .labelsHidden()
            .accessibilityLabel("Text size")
    }

    private var revealBar: some View {
        HStack {
            Text("\(revealedLines) / \(lyricsView.realLineCount)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Button("Restart") { revealedLines = 0 }
                .font(.footnote)
            Button("Show all") { revealedLines = lyricsView.realLineCount }
                .font(.footnote)
        }
        .padding(.horizontal, 4)
    }

    private func advanceReveal() {
        guard revealMode else { return }
        revealedLines = min(revealedLines + 1, lyricsView.realLineCount)
    }

    // MARK: Media and notes

    @ViewBuilder
    private var mediaSection: some View {
        if let version = activeVersion, !version.media.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recordings and links")
                    .font(.footnote.smallCaps())
                    .foregroundStyle(.secondary)

                ForEach(version.media) { item in
                    if item.kind == "video", let urlString = item.url, let url = URL(string: urlString) {
                        Link(destination: url) {
                            Label(item.label ?? urlString, systemImage: "play.rectangle")
                                .font(.callout)
                        }
                    } else if item.kind == "audio" {
                        Label(item.label ?? item.filename ?? "Recording", systemImage: "waveform")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.footnote.smallCaps())
                .foregroundStyle(.secondary)
            Text(notes)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

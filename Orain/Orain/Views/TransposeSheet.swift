//  TransposeSheet.swift
//  Òrain
//
//  "Make that G a C, and move everything else with it."
//
//  Two steps, because that is how the thought actually arrives: pick the
//  chord you're looking at, then say what it should be. The alternative — a
//  "+1 / −1 semitone" stepper — is how a program thinks about transposition,
//  not how a singer does.
//
//  Saving always creates a NEW version rather than overwriting. Losing the
//  original key because you tried a different one would be a poor trade.

import SwiftUI
import SwiftData
import OrainCore

struct TransposeSheet: View {
    let song: Song
    let version: SongVersion
    /// Called with the version that was created, so the song page can switch
    /// straight to it.
    var onCreated: (SongVersion) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selectedChord: String?
    @State private var chosen: Transposer.Target?
    @State private var label: String = ""

    private var chords: [String] {
        Transposer.chordSymbols(in: version.lyrics)
            .filter { Transposer.parseChord($0) != nil }
    }

    private var targets: [Transposer.Target] {
        guard let selectedChord else { return [] }
        return Transposer.targets(forChord: selectedChord, in: version.lyrics)
    }

    /// The interval currently chosen, relative to what is already on screen.
    private var semitones: Int { chosen?.semitones ?? 0 }

    var body: some View {
        NavigationStack {
            Group {
                if chords.isEmpty {
                    ContentUnavailableView {
                        Label("No chords to move", systemImage: "guitars")
                    } description: {
                        Text("This version has no chords in it yet, so there is nothing to transpose.")
                    }
                } else {
                    form
                }
            }
            .navigationTitle("Change key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(semitones == 0)
                }
            }
            .onAppear {
                if selectedChord == nil { selectedChord = chords.first }
            }
        }
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section("Which chord?") {
                chordRow
            }

            if selectedChord != nil {
                Section("Make it…") {
                    targetRow
                }
            }

            if semitones != 0 {
                Section("Name for the new version") {
                    TextField("Version name", text: $label)
                        .textInputAutocapitalization(.words)
                }

                Section("Preview") {
                    previewList
                }

                Section {
                    Text("The original version is kept. This adds a second one in the new key — the words are shared, so a correction to either fixes both.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var chordRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chords, id: \.self) { chord in
                    Button {
                        selectedChord = chord
                        chosen = nil
                        label = ""
                    } label: {
                        Text(chord)
                            .font(.body.monospaced())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedChord == chord
                                    ? Theme.chordColour.opacity(0.15)
                                    : Color.secondary.opacity(0.1),
                                in: Capsule()
                            )
                            .foregroundStyle(
                                selectedChord == chord ? Theme.chordColour : Color.primary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var targetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(targets) { target in
                    Button {
                        chosen = target.semitones == 0 ? nil : target
                        label = target.semitones == 0
                            ? ""
                            : Transposer.suggestedLabel(
                                forKey: Transposer.detectKey(version.lyrics) ?? 0,
                                semitones: target.semitones
                              )
                    } label: {
                        VStack(spacing: 2) {
                            Text(target.label)
                                .font(.body.monospaced())
                            Text(target.semitones == 0 ? "as is" : "key of \(target.resultingKey)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            chosen?.semitones == target.semitones
                                ? Theme.chordColour.opacity(0.15)
                                : Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Shows the first few chords before and after, so the choice is checkable
    /// without leaving the sheet.
    private var previewList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(chords.prefix(6), id: \.self) { chord in
                HStack {
                    Text(chord)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(movedChord(chord))
                        .font(.callout.monospaced())
                        .foregroundStyle(Theme.chordColour)
                }
            }
            if chords.count > 6 {
                Text("…and \(chords.count - 6) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func movedChord(_ chord: String) -> String {
        let key = Transposer.detectKey(version.lyrics) ?? 0
        let flats = Transposer.prefersFlats(key: key + semitones)
        return Transposer.transposeChordSymbol(chord, by: semitones, preferFlats: flats)
    }

    // MARK: Saving

    private func save() {
        guard semitones != 0 else { return }

        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)

        // The new version shares the lyrics verbatim and differs only in its
        // transpose offset. That is the whole design: one text, many keys.
        let copy = SongVersion(
            versionLabel: trimmed.isEmpty ? nil : trimmed,
            versionTitle: version.versionTitle,
            language: version.language,
            lyrics: version.lyrics,
            melody: version.melody,
            source: version.source,
            transpose: normalise(version.transpose + semitones),
            isCanonical: false,
            createdAt: .now,
            sourceId: nil
        )

        context.insert(copy)
        copy.song = song
        song.versions.append(copy)
        song.updatedAt = .now

        try? context.save()
        onCreated(copy)
        dismiss()
    }

    private func normalise(_ semitones: Int) -> Int {
        ((semitones % 12) + 12) % 12
    }
}

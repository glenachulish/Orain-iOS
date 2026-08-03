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

    /// The lyrics **as they appear on screen** — the stored text with this
    /// version's existing offset already applied.
    ///
    /// Everything in this sheet works from these rather than from
    /// `version.lyrics`, and that is not a detail. A version transposed to Am
    /// still stores Em; reading the stored text would offer to change a chord
    /// the singer cannot see, and adding the new interval to the old one gave
    /// a key nobody asked for. The sheet must speak about what is on the page.
    private var soundingLyrics: String {
        Transposer.transposeLyrics(version.lyrics, by: version.transpose)
    }

    private var soundingKey: Int {
        Transposer.detectKey(soundingLyrics) ?? 0
    }

    private var chords: [String] {
        Transposer.chordSymbols(in: soundingLyrics)
            .filter { Transposer.parseChord($0) != nil }
    }

    private var targets: [Transposer.Target] {
        guard let selectedChord else { return [] }
        return Transposer.targets(forChord: selectedChord, in: soundingLyrics)
    }

    /// A version that would end up in the same key as the one being made.
    /// Offering to make a duplicate is worse than saying one already exists.
    private var existingVersionInTargetKey: SongVersion? {
        guard semitones != 0 else { return nil }
        let resulting = normalise(version.transpose + semitones)
        return song.versions.first {
            $0.persistentModelID != version.persistentModelID
                && $0.lyrics == version.lyrics
                && normalise($0.transpose) == resulting
        }
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

            if let selectedChord {
                Section {
                    targetRows
                } header: {
                    Text("Make \(selectedChord) into…")
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

                if let existing = existingVersionInTargetKey {
                    Section {
                        Label(
                            "You already have a version in this key\(existing.versionLabel.map { " — “\($0)”" } ?? ""). Saving will add another.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                }

                Section {
                    Text("The original version is kept. This adds a second one in the new key, which you'll find under ⋯ → Versions. The words are shared, so a correction to either fixes both.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A wrapping row of chips rather than a horizontal scroller: every chord
    /// in the song is visible without anyone having to guess that the row
    /// slides sideways.
    private var chordRow: some View {
        FlowLayout(lineSpacing: 8) {
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
                        .padding(.trailing, 4)
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
                .padding(.trailing, 6)
            }
        }
        .padding(.vertical, 2)
    }

    /// All twelve destinations, listed. The first version of this was a
    /// horizontal scroller and you could only see three of them, which made a
    /// complete list look like a broken one.
    @ViewBuilder
    private var targetRows: some View {
        ForEach(targets) { target in
            Button {
                chosen = target.semitones == 0 ? nil : target
                label = target.semitones == 0
                    ? ""
                    : Transposer.suggestedLabel(
                        forKey: soundingKey,
                        semitones: target.semitones
                      )
            } label: {
                HStack(spacing: 10) {
                    Text(target.label)
                        .font(.body.monospaced())
                        .foregroundStyle(
                            target.semitones == 0 ? Color.secondary : Theme.chordColour
                        )
                        .frame(minWidth: 52, alignment: .leading)

                    Text(target.semitones == 0
                         ? "leave it as it is"
                         : "the song moves to \(target.resultingKey)")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if chosen?.semitones == target.semitones {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Theme.chordColour)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
        let flats = Transposer.prefersFlats(key: soundingKey + semitones)
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

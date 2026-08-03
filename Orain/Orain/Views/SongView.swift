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
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVersionID: PersistentIdentifier?
    @State private var showChords = true
    @State private var repeatChorus = false
    @State private var revealMode = false
    @State private var revealedLines = 0
    @State private var fontSize: CGFloat = 17
    @State private var keepAwake = false
    @State private var showingTranspose = false
    @State private var showingVersions = false
    @State private var showingMerge = false
    @State private var confirmingDelete = false
    @State private var showingSavedNote = false
    @State private var savedVersionName = ""

    // Auto-scroll: for playing along, when your hands are busy.
    @State private var autoScroll = false
    @State private var secondsPerLine: Double = 2.5
    @State private var autoScrollLine = 0
    @State private var autoScrollStartedAt: Date?
    @State private var scrollTimer: Timer?

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
        ScrollViewReader { proxy in
            // The controls sit OUTSIDE the scroll view so they stay put while
            // the words move. They are what you reach for mid-song, and a
            // control that has scrolled off the top is no use when your hands
            // are busy.
            VStack(spacing: 0) {
                controls
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)

                if revealMode || autoScroll {
                    Divider()
                    (revealMode ? AnyView(revealBar) : AnyView(autoScrollBar))
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(.bar)
                }

                Divider()

                if showingSavedNote {
                    savedNote
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if versions.count > 1 { versionPicker }
                        lyricsView
                            .padding(.top, 4)
                        mediaSection
                        if let notes = displayableNotes {
                            notesSection(notes)
                        }
                        // Room at the foot so the last line can still reach
                        // the middle of the screen when auto-scroll ends.
                        Color.clear.frame(height: 260)
                    }
                    .padding()
                }
            }
            .onChange(of: autoScroll) { _, on in
                // Resume from where Stop left it, not from the top. Stopping
                // to work out a chord and losing your place would make the
                // control useless for the thing it exists for.
                if on { startAutoScroll(proxy, from: autoScrollLine) }
                else { stopAutoScroll(proxy) }
            }
            .onChange(of: secondsPerLine) { _, _ in
                // Restart from wherever it has got to, so changing speed
                // mid-song does not send you back to the top.
                if autoScroll {
                    let here = currentAutoScrollLine
                    stopAutoScroll(proxy)
                    startAutoScroll(proxy, from: here)
                }
            }
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

                    Button {
                        showingMerge = true
                    } label: {
                        Label("Same as another song…", systemImage: "arrow.triangle.merge")
                    }

                    Divider()
                    Toggle("Keep screen awake", isOn: $keepAwake)
                    Divider()

                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete song", systemImage: "trash")
                    }
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
                    // Say what just happened. Landing on a page of different
                    // chords with no explanation left it unclear whether
                    // anything had been saved, or where it had gone.
                    savedVersionName = created.versionLabel ?? "the new version"
                    withAnimation { showingSavedNote = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation { showingSavedNote = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showingVersions) {
            VersionManagerView(song: song)
        }
        .sheet(isPresented: $showingMerge) {
            MergeSongSheet(song: song)
        }
        .confirmationDialog(
            "Delete “\(song.title)”?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete song", role: .destructive) { deleteSong() }
            Button("Keep it", role: .cancel) { }
        } message: {
            Text(deleteWarning)
        }
        .onAppear {
            if selectedVersionID == nil {
                selectedVersionID = song.canonicalVersion?.persistentModelID
            }
        }
        .onChange(of: selectedVersionID) { _, _ in
            // A new version is a different page: start the reveal over rather
            // than leaving a half-revealed one from the last version, stop any
            // scroll that was running down a different set of lines, and drop
            // the sèist repeat if this version hasn't got one.
            revealedLines = 0
            autoScroll = false
            if !(activeVersion?.hasChorus ?? false) { repeatChorus = false }
        }
        .onChange(of: keepAwake) { _, awake in
            UIApplication.shared.isIdleTimerDisabled = awake
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            stopAutoScroll()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let version = activeVersion, version.displayTitle != song.title {
                Text(version.displayTitle)
                    .font(.title3)
            }

            HStack(spacing: 8) {
                StarRating(rating: song.rating, size: 11) { new in
                    song.rating = new
                    song.updatedAt = .now
                }
                if let composer = song.composer, !composer.isEmpty {
                    Text(composer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
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
                Spacer(minLength: 0)
            }
            .lineLimit(1)
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

    /// One row, always. Words rather than icons — a guitar next to "Chords"
    /// said nothing the word did not, and cost the width that was making the
    /// row wrap.
    private var controls: some View {
        // One line if it fits; if a version adds the Sèist pill and the row
        // would otherwise run past the margin, it slides instead of spilling.
        ViewThatFits(in: .horizontal) {
            controlRow
            ScrollView(.horizontal, showsIndicators: false) {
                controlRow
            }
        }
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            controlButton("Chords", isOn: showChords, enabled: versionHasChords) {
                showChords.toggle()
            }

            if activeVersion?.hasChorus == true {
                controlButton("Sèist", isOn: repeatChorus) {
                    repeatChorus.toggle()
                }
            }

            controlButton("Scroll", isOn: autoScroll) {
                autoScroll.toggle()
            }

            controlButton("Reveal", isOn: revealMode) {
                revealMode.toggle()
                if revealMode {
                    revealedLines = 0
                    autoScroll = false   // one thing steers the page at a time
                }
            }

            Spacer(minLength: 4)

            // Text size, as two small taps rather than a stepper: a stepper's
            // label and chrome were taking a third of the row.
            Button {
                fontSize = max(13, fontSize - 1)
            } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .disabled(fontSize <= 13)

            Button {
                fontSize = min(30, fontSize + 1)
            } label: {
                Image(systemName: "textformat.size.larger")
            }
            .disabled(fontSize >= 30)
        }
        .font(.footnote)
        .buttonStyle(.plain)
        .foregroundStyle(Theme.chordColour)
        .lineLimit(1)
    }

    private var versionHasChords: Bool {
        activeVersion.map { ($0.lyrics ?? "").contains("[") } ?? false
    }

    private func controlButton(
        _ title: String,
        isOn: Bool,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(isOn ? .semibold : .regular))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    isOn ? Theme.chordColour.opacity(0.16) : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
                .foregroundStyle(
                    enabled ? (isOn ? Theme.chordColour : Color.primary) : Color.secondary
                )
                .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// A short-lived note after a key change, saying what was saved and where
    /// to find it again. It clears itself after a few seconds — it is an
    /// explanation, not a message that needs dismissing.
    private var savedNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.chordColour)
            VStack(alignment: .leading, spacing: 1) {
                Text("Saved as “\(savedVersionName)”")
                    .font(.footnote.weight(.medium))
                Text("You're now looking at it. The original is still there — switch between them under ⋯ → Versions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation { showingSavedNote = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Theme.chordColour.opacity(0.10))
    }

    // MARK: Auto-scroll

    /// Speed and a way out.
    private var autoScrollBar: some View {
        HStack(spacing: 10) {
            Text("Slow")
                .font(.caption)
                .foregroundStyle(.secondary)

            // The slider runs fast-to-slow in seconds, but is presented
            // slow-to-fast, because that is the direction people think in.
            Slider(
                value: Binding(
                    get: { Self.slowest + Self.fastest - secondsPerLine },
                    set: { secondsPerLine = Self.slowest + Self.fastest - $0 }
                ),
                in: Self.fastest...Self.slowest
            )
            .tint(Theme.chordColour)

            Text("Fast")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Stop") { autoScroll = false }
                .font(.footnote)
                .foregroundStyle(Theme.chordColour)
        }
    }

    private static let fastest: Double = 0.8    // seconds per line
    private static let slowest: Double = 6.0

    /// Scroll the whole way down in **one** continuous animation.
    ///
    /// The first version of this advanced a line at a time, animating each
    /// step. It looked jumpy, and the reason is worth recording: every step
    /// started a fresh animation, and SwiftUI hitches where one animation
    /// hands over to the next. A single long linear animation to the last
    /// line has no handovers in it, so the motion is genuinely smooth.
    ///
    /// The cost is that "where are we now" is no longer a stored number — the
    /// animation owns the position. So the current line is worked out from
    /// elapsed time instead, which is what `currentAutoScrollLine` does, and
    /// is what lets Stop halt in place rather than springing back.
    private func startAutoScroll(_ proxy: ScrollViewProxy, from line: Int = 0) {
        revealMode = false          // only one thing steers the page at a time

        let total = lyricsView.totalLineCount
        guard total > 1, line < total - 1 else {
            autoScroll = false
            return
        }

        autoScrollLine = line
        autoScrollStartedAt = Date()

        let remaining = Double(total - 1 - line)
        withAnimation(.linear(duration: remaining * secondsPerLine)) {
            proxy.scrollTo(LyricLineID(index: total - 1), anchor: .center)
        }

        // A timer only to notice the end and switch the control off — it does
        // no scrolling itself.
        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(
            withTimeInterval: remaining * secondsPerLine, repeats: false
        ) { _ in
            autoScroll = false
        }
    }

    /// Where the animation has got to, derived from how long it has been
    /// running. Accurate enough to stop in place, which is all it is for.
    private var currentAutoScrollLine: Int {
        guard let started = autoScrollStartedAt else { return autoScrollLine }
        let elapsed = Date().timeIntervalSince(started)
        let advanced = Int(elapsed / secondsPerLine)
        return min(autoScrollLine + advanced, max(0, lyricsView.totalLineCount - 1))
    }

    /// Halt where it is, rather than letting the animation run on or snapping
    /// back to the top: re-target the scroll to the line it has reached, with
    /// no animation, which cancels the long one in flight.
    private func stopAutoScroll(_ proxy: ScrollViewProxy? = nil) {
        scrollTimer?.invalidate()
        scrollTimer = nil

        if let proxy, autoScrollStartedAt != nil {
            let here = currentAutoScrollLine
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(LyricLineID(index: here), anchor: .center)
            }
            autoScrollLine = here
        }
        autoScrollStartedAt = nil
    }

    // MARK: Delete

    /// Says what will actually be lost, rather than "this cannot be undone".
    /// A song with four versions and a recording is a different loss from a
    /// title with nothing under it, and the warning should reflect that.
    private var deleteWarning: String {
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

    private func deleteSong() {
        stopAutoScroll()
        context.delete(song)
        try? context.save()
        dismiss()
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

    /// Recordings and video links for the version on screen, in a bordered
    /// panel — the same shape the Pi app gives them, so the two read alike.
    @ViewBuilder
    private var mediaSection: some View {
        if let version = activeVersion, !version.media.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recordings and links")
                    .font(.footnote.smallCaps())
                    .foregroundStyle(.secondary)

                ForEach(version.media) { item in
                    mediaRow(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func mediaRow(_ item: MediaLink) -> some View {
        if item.kind == "video", let urlString = item.url {
            VideoRow(label: item.label, urlString: urlString)
        } else if item.kind == "audio" {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.label ?? item.filename ?? "Recording")
                        .font(.callout)
                    // Honest about the gap rather than showing a play button
                    // that would do nothing: the audio itself lives on the Pi.
                    Text("Not on this device")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    /// Notes, minus the "Source PDF: …" markers the Phase-3.5 import left
    /// behind. Those are bookkeeping from the migration, not something worth
    /// reading under the words every time the song is opened.
    private var displayableNotes: String? {
        guard let notes = song.notes else { return nil }

        let kept = notes
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.lowercased().hasPrefix("source pdf:")
                    && !trimmed.lowercased().hasPrefix("source:")
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return kept.isEmpty ? nil : kept
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

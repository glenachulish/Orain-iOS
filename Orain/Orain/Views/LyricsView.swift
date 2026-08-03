//  LyricsView.swift
//  Òrain
//
//  Chord-over-lyric rendering — the heart of the app.
//
//  The web version stacks a chord row above a lyric row inside each segment
//  and lets the browser wrap the line. SwiftUI has no equivalent of inline
//  wrapping for a row of stacked pairs, so this file provides a small `Layout`
//  that flows segments and breaks between them. Chords never separate from
//  their syllable, because the pair is one view.
//
//  Every parsing decision comes from OrainCore.ChordPro, which is the ported
//  and golden-tested chord.js — this file only decides how it looks.

import SwiftUI
import OrainCore

// MARK: - Flow layout

/// Lays subviews out left to right, wrapping to a new line when the next one
/// will not fit. Used for the segments of one lyric line.
struct FlowLayout: Layout {
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)

        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height }
            + CGFloat(max(0, rows.count - 1)) * lineSpacing

        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + row.height - size.height),
                    proposal: ProposedViewSize(size)
                )
                x += size.width
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)

            // Start a new row when this segment would overflow — unless the
            // row is empty, in which case an over-wide segment gets its own
            // row rather than vanishing.
            if !current.indices.isEmpty, current.width + size.width > maxWidth {
                rows.append(current)
                current = Row()
            }

            current.indices.append(index)
            current.width += size.width
            current.height = max(current.height, size.height)
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Line identity

/// Every rendered line carries one of these so the song page can scroll to it.
/// Blank lines get one too, which keeps the indices contiguous — auto-scroll
/// advancing "one line" then moves at a steady rate through the verse gaps
/// rather than skipping them.
struct LyricLineID: Hashable {
    let index: Int
}

// MARK: - Display options

struct LyricDisplayOptions {
    var showChords = true
    var repeatChorus = false
    /// Line-by-line reveal: nil means off, otherwise the number of real lyric
    /// lines revealed so far.
    var revealedLines: Int?
    var fontSize: CGFloat = 17
    /// Semitones to shift the chords by on the way to the screen. The stored
    /// lyrics are never rewritten — see OrainCore's Transpose.swift.
    var transposeSemitones: Int = 0
}

// MARK: - The view

struct LyricsView: View {
    let lyrics: String?
    var options: LyricDisplayOptions
    /// Called when the reader taps the lyrics — used to advance reveal mode.
    var onTap: () -> Void = {}

    /// The text actually rendered: the stored lyrics, transposed if the
    /// version calls for it, with the chorus repeated if the reader asked.
    ///
    /// Transposition happens first. It only ever rewrites what is inside the
    /// square brackets, so the section directives the chorus repeat depends on
    /// survive it untouched.
    private var effectiveLyrics: String {
        var text = lyrics ?? ""
        if options.transposeSemitones != 0 {
            text = Transposer.transposeLyrics(text, by: options.transposeSemitones)
        }
        return options.repeatChorus ? ChordPro.repeatChorus(text) : text
    }

    private var sections: [LyricSection] {
        ChordPro.getSections(effectiveLyrics)
    }

    var body: some View {
        if effectiveLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("No words yet.")
                .foregroundStyle(.secondary)
                .italic()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(placedSections, id: \.offset) { placed in
                    sectionView(placed.section, startingAt: placed.offset)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }
    }

    // MARK: Sections

    /// Each section paired with the index its first line has in the flattened
    /// list of all lines. Computed by walking the list rather than searching
    /// for a section by value — two identical sections must not share an
    /// offset, which is exactly what a value search would do.
    private var placedSections: [PlacedSection] {
        var offset = 0
        var out: [PlacedSection] = []
        for section in sections {
            out.append(PlacedSection(section: section, offset: offset))
            offset += section.lines.count
        }
        return out
    }

    private struct PlacedSection {
        let section: LyricSection
        let offset: Int
    }

    @ViewBuilder
    private func sectionView(_ section: LyricSection, startingAt offset: Int) -> some View {
        switch section.kind {
        case .plain:
            VStack(alignment: .leading, spacing: 2) {
                linesView(section.lines, startingAt: offset)
            }

        case .chorus:
            VStack(alignment: .leading, spacing: 2) {
                sectionLabel(section.label ?? "Sèist")
                linesView(section.lines, startingAt: offset)
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Theme.chorusAccent)
                    .frame(width: 3)
            }

        case .bridge:
            VStack(alignment: .leading, spacing: 2) {
                sectionLabel(section.label ?? "Bridge")
                linesView(section.lines, startingAt: offset)
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 1)
            }

        case .verse:
            // A labelled verse shows its label alone — the kind is already
            // implied by the styling, and "Verse: Verse 1" was a real bug in
            // the web app worth not repeating.
            VStack(alignment: .leading, spacing: 2) {
                if let label = section.label {
                    sectionLabel(label)
                }
                linesView(section.lines, startingAt: offset)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .italic()
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)
    }

    // MARK: Lines

    @ViewBuilder
    private func linesView(_ lines: [String], startingAt offset: Int) -> some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            lineView(line, absoluteIndex: offset + index)
        }
    }

    @ViewBuilder
    private func lineView(_ line: String, absoluteIndex: Int) -> some View {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            Color.clear
                .frame(height: options.fontSize * 0.6)
                .id(LyricLineID(index: absoluteIndex))
        } else {
            FlowLayout(lineSpacing: options.showChords ? 6 : 2) {
                ForEach(Array(cells(for: line).enumerated()), id: \.offset) { _, cell in
                    cellView(cell)
                }
            }
            .opacity(isRevealed(absoluteIndex) ? 1 : 0)
            // `opacity` rather than removing the view, so the page never
            // reflows as lines appear — the same reason the web version uses
            // `visibility` instead of `display`.
            .animation(.easeOut(duration: 0.15), value: options.revealedLines)
            .id(LyricLineID(index: absoluteIndex))
        }
    }

    /// One chord sitting over one run of text, as drawn.
    private struct Cell {
        let chord: String?
        let text: String
    }

    /// Break a line into the smallest pieces that can wrap independently.
    ///
    /// This is the fix for lyrics running off the edge of the screen. A
    /// segment between two chords can be a dozen words long, and drawn as one
    /// view it cannot break — so a line with few chord changes ran straight
    /// past the margin. Splitting at spaces lets the flow layout wrap where a
    /// reader would, while the chord stays welded to the word it belongs to,
    /// because it travels with the first piece of its segment.
    private func cells(for line: String) -> [Cell] {
        var out: [Cell] = []

        for segment in ChordPro.parseChordProLine(line) {
            let words = splitKeepingSpaces(segment.text)

            if words.isEmpty {
                out.append(Cell(chord: segment.chord, text: segment.text))
                continue
            }

            for (index, word) in words.enumerated() {
                // Only the first piece carries the chord; the rest are plain
                // text that may wrap anywhere.
                out.append(Cell(chord: index == 0 ? segment.chord : nil, text: word))
            }
        }

        return out
    }

    /// Split on spaces, keeping each space attached to the word before it so
    /// the spacing between words is preserved when they end up on one row.
    private func splitKeepingSpaces(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var pieces: [String] = []
        var current = ""

        for character in text {
            current.append(character)
            if character == " " {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty { pieces.append(current) }

        return pieces
    }

    private func cellView(_ cell: Cell) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if options.showChords {
                Text(cell.chord ?? " ")
                    .font(.system(size: options.fontSize * 0.8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.chordColour)
            }
            Text(cell.text.isEmpty ? "\u{00a0}" : cell.text)
                .font(.system(size: options.fontSize))
        }
        .fixedSize()
    }

    private func isRevealed(_ index: Int) -> Bool {
        guard let revealed = options.revealedLines else { return true }
        return realLineNumber(for: index).map { $0 <= revealed } ?? true
    }

    /// Map a flattened line index to its position among *real* (non-blank)
    /// lyric lines. Blank lines return nil and are always shown.
    private func realLineNumber(for index: Int) -> Int? {
        var count = 0
        var seen = 0
        for section in sections {
            for line in section.lines {
                let isReal = !line.trimmingCharacters(in: .whitespaces).isEmpty
                if isReal { count += 1 }
                if seen == index { return isReal ? count : nil }
                seen += 1
            }
        }
        return nil
    }

    /// Every line including the blank ones — the range auto-scroll walks.
    var totalLineCount: Int {
        sections.reduce(0) { $0 + $1.lines.count }
    }

    /// Total number of real lyric lines — the denominator of the reveal counter.
    var realLineCount: Int {
        sections
            .flatMap(\.lines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }
}

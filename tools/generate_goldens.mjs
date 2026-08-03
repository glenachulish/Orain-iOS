/* Òrain iOS — golden-fixture generator.
 *
 * Runs the shipped chord.js logic (via ./chordpro-ref.mjs) over a corpus of
 * inputs and writes every expected output to
 *   ../OrainCore/Tests/OrainCoreTests/Fixtures/chordpro-goldens.json
 *
 * The Swift port's test suite loads that same JSON and asserts equality.
 * That is what makes "the Swift port behaves exactly like the app you
 * already use" a checkable claim rather than a hope.
 *
 * Run:  node tools/generate_goldens.mjs
 */

import {
  parseChordProLine,
  parseDirectiveLine,
  buildDirectiveLine,
  getSections,
  hasChorus,
  repeatChorus,
  lyricsToEditor,
  editorToLyrics,
} from "./chordpro-ref.mjs";

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ─── Corpus ────────────────────────────────────────────────────────────────
// Chosen to cover every branch in the seven functions, plus the real-world
// shapes that actually occur in the library (Gàidhlig accents, sèist labels,
// lyric-only imported songs).

const LINES = [
  "",
  " ",
  "Ailein duinn, hiù o-hoe",
  "[G]Ailein duinn, [D]hiù o-hoe, [C]hiù o-ho ro [G]eile",
  "[G]Ailein duinn",
  "Ailein [G]duinn",
  "[G][D]Ailein duinn",
  "[G] [D] Ailein",
  "[Am7]Gura [F#m]mise tha fo [Csus4]éislean",
  "trailing chord at end[G]",
  "[G]",
  "no brackets at all",
  "unclosed [bracket",
  "empty []brackets",
  "[G]a[D]b[C]c",
  "  leading spaces kept",
  "Ò mo dhùthaich, 's tu th'air m'aire",
  "[D]Ò mo [G]dhùthaich, 's tu th'air m'[A7]aire",
  "double  spaces  between  words",
  "[G]word [D]  two spaces after chord",
];

const DIRECTIVE_LINES = [
  "{start_of_chorus}",
  "{end_of_chorus}",
  "{soc}",
  "{eoc}",
  "{sov}",
  "{eov}",
  "{sob}",
  "{eob}",
  "{start_of_verse: Verse 2}",
  "{start_of_chorus: Sèist}",
  "{START_OF_CHORUS}",
  "  {start_of_verse}  ",
  "{start_of_verse:}",
  "{start_of_verse:   }",
  "{title: Ailein Duinn}",
  "{not_a_directive}",
  "{}",
  "not a directive at all",
  "{start_of_chorus} trailing text",
  "[G]{soc}",
];

const BUILD_CASES = [
  ["chorus", "start", null],
  ["chorus", "end", null],
  ["verse", "start", "Verse 2"],
  ["verse", "start", ""],
  ["verse", "start", "   "],
  ["bridge", "start", "  Bridge A  "],
  ["bridge", "end", "ignored?"],
];

const LYRICS = [
  "",
  "single line no chords",
  "line one\nline two",
  "line one\n\nline three",
  "[G]Ailein duinn, [D]hiù o-hoe\n[C]hiù o-ho ro [G]eile",
  // A plain verse then a marked chorus
  "Verse words here\n{start_of_chorus}\nSèist words\n{end_of_chorus}",
  // Marked verse + marked chorus, chorus already follows
  "{start_of_verse: Verse 1}\nFirst verse\n{end_of_verse}\n{start_of_chorus: Sèist}\nChorus words\n{end_of_chorus}",
  // Two verses, one chorus written once — the repeat case
  "{start_of_verse: Verse 1}\nFirst verse\n{end_of_verse}\n{start_of_chorus: Sèist}\nChorus words\n{end_of_chorus}\n{start_of_verse: Verse 2}\nSecond verse\n{end_of_verse}",
  // Verse with no chorus anywhere
  "{start_of_verse}\nOnly a verse\n{end_of_verse}",
  // Chorus first, then verses
  "{start_of_chorus}\nChorus first\n{end_of_chorus}\n{start_of_verse}\nVerse after\n{end_of_verse}\n{start_of_verse}\nAnother verse\n{end_of_verse}",
  // Two different choruses — single-chorus model means the first wins
  "{start_of_chorus: A}\nChorus A\n{end_of_chorus}\n{start_of_verse}\nV\n{end_of_verse}\n{start_of_chorus: B}\nChorus B\n{end_of_chorus}",
  // Unclosed section at the end
  "{start_of_chorus}\nNever closed",
  // Directives with nothing between them
  "{start_of_chorus}\n{end_of_chorus}",
  // Bridge
  "{start_of_verse}\nV\n{end_of_verse}\n{start_of_bridge: Middle}\nBridge line\n{end_of_bridge}\n{start_of_chorus}\nC\n{end_of_chorus}",
  // Chords inside sections
  "{start_of_chorus: Sèist}\n[G]Ailein [D]duinn\n{end_of_chorus}\n{start_of_verse}\n[C]Verse [G]line\n{end_of_verse}",
  // Real-world lyric-only imported song shape
  "Ò mo dhùthaich, 's tu th'air m'aire\nÙidh nan eilean, gorm mo shùilean\n\nCòrdadh rium do bheanntan àrda",
  // Trailing newline
  "line\n",
  // Leading newline
  "\nline",
  // Only blank lines
  "\n\n",
];

const EDITOR_ROW_CASES = [
  [{ chords: "", lyric: "" }],
  [{ chords: "", lyric: "plain lyric" }],
  [{ chords: "G", lyric: "Ailein duinn" }],
  [{ chords: "G    D", lyric: "Ailein duinn" }],
  [{ chords: "G   D", lyric: "Ail" }],
  [{ chords: "  G", lyric: "Ailein" }],
  [{ chords: "G", lyric: "" }],
  [{ chords: "GD", lyric: "Ailein" }],
  [{ chords: "Am7  F#m", lyric: "Gura mise" }],
  [{ chords: "", lyric: "{start_of_chorus}" }],
  [{ chords: "IGNORED", lyric: "{start_of_chorus}" }],
  [
    { chords: "G", lyric: "line one" },
    { chords: "", lyric: "" },
    { chords: "D", lyric: "line two" },
  ],
  [{ chords: "   ", lyric: "whitespace-only chord row" }],
];

// ─── Build the golden set ──────────────────────────────────────────────────

const goldens = {
  _meta: {
    generated_from: "static/chord.js (Òrain Pi app), pure functions only",
    generated_by: "tools/generate_goldens.mjs",
    note:
      "Expected values are whatever the SHIPPED JavaScript does — including " +
      "its quirks. The Swift port must match this, not an idealised spec.",
  },

  parseChordProLine: LINES.map((line) => ({
    input: line,
    expected: parseChordProLine(line),
  })),

  parseDirectiveLine: DIRECTIVE_LINES.map((line) => ({
    input: line,
    expected: parseDirectiveLine(line),
  })),

  buildDirectiveLine: BUILD_CASES.map(([kind, boundary, label]) => ({
    kind,
    boundary,
    label,
    expected: buildDirectiveLine(kind, boundary, label),
  })),

  getSections: LYRICS.map((lyrics) => ({
    input: lyrics,
    expected: getSections(lyrics),
  })),

  hasChorus: LYRICS.map((lyrics) => ({
    input: lyrics,
    expected: hasChorus(lyrics),
  })),

  repeatChorus: LYRICS.map((lyrics) => ({
    input: lyrics,
    expected: repeatChorus(lyrics),
  })),

  lyricsToEditor: LYRICS.map((lyrics) => ({
    input: lyrics,
    expected: lyricsToEditor(lyrics),
  })),

  editorToLyrics: EDITOR_ROW_CASES.map((rows) => ({
    input: rows,
    expected: editorToLyrics(rows),
  })),

  // The round-trip guarantee, recorded as data: for each corpus lyric, what
  // does editorToLyrics(lyricsToEditor(L)) actually produce? Where that is
  // not identical to L, the JS is lossy and the Swift port must be lossy in
  // exactly the same way (so a load-then-save in the app never silently
  // rewrites a song differently on iOS than on the Pi).
  roundTrip: LYRICS.map((lyrics) => {
    const out = editorToLyrics(lyricsToEditor(lyrics));
    return { input: lyrics, expected: out, lossless: out === lyrics };
  }),
};

const outPath = resolve(
  __dirname,
  "../OrainCore/Tests/OrainCoreTests/Fixtures/chordpro-goldens.json"
);
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(goldens, null, 2) + "\n", "utf8");

// ─── Report ────────────────────────────────────────────────────────────────

const counts = Object.entries(goldens)
  .filter(([k]) => !k.startsWith("_"))
  .map(([k, v]) => `${k}: ${v.length}`)
  .join("\n  ");

const lossy = goldens.roundTrip.filter((r) => !r.lossless);

console.log(`Wrote ${outPath}`);
console.log(`\nCases:\n  ${counts}`);
console.log(
  `\nRound-trip: ${goldens.roundTrip.length - lossy.length}/${goldens.roundTrip.length} lossless`
);
if (lossy.length) {
  console.log("\nLossy inputs (recorded as goldens, NOT treated as failures):");
  for (const r of lossy) {
    console.log(`  in : ${JSON.stringify(r.input)}`);
    console.log(`  out: ${JSON.stringify(r.expected)}`);
  }
}

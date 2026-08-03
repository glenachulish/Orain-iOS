/* Òrain iOS — reference extract of the shipped `static/chord.js`.
 *
 * These are the SEVEN PURE functions from the live Pi app's chord.js,
 * copied VERBATIM (bodies unchanged; only the doc-comments trimmed and the
 * DOM renderer omitted, since it cannot run outside a browser).
 *
 * Purpose: this file is the *oracle*. `generate_goldens.mjs` runs it over a
 * corpus of inputs and writes the expected outputs to
 * `OrainCore/Tests/OrainCoreTests/Fixtures/chordpro-goldens.json`. The Swift
 * port is then tested against that same JSON, which proves the two
 * implementations agree without needing both toolchains in one place.
 *
 * If chord.js on the Pi ever changes, re-copy the changed function here and
 * re-run the generator; the Swift tests will fail loudly if the port drifted.
 *
 * Source of truth: ~/orain/static/chord.js (Pi app), as of 2026-07-13.
 */

export function parseChordProLine(line) {
  const segments = [];
  const regex = /\[([^\]]+)\]/g;
  let lastEnd = 0;
  let currentChord = null;
  let match;

  while ((match = regex.exec(line)) !== null) {
    if (match.index > lastEnd || currentChord !== null) {
      segments.push({
        chord: currentChord,
        text: line.slice(lastEnd, match.index),
      });
    }
    currentChord = match[1];
    lastEnd = match.index + match[0].length;
  }

  if (lastEnd < line.length || currentChord !== null) {
    segments.push({
      chord: currentChord,
      text: line.slice(lastEnd),
    });
  }

  return segments;
}

const DIRECTIVE_MAP = {
  start_of_chorus:  { kind: "chorus",  boundary: "start" },
  end_of_chorus:    { kind: "chorus",  boundary: "end"   },
  start_of_verse:   { kind: "verse",   boundary: "start" },
  end_of_verse:     { kind: "verse",   boundary: "end"   },
  start_of_bridge:  { kind: "bridge",  boundary: "start" },
  end_of_bridge:    { kind: "bridge",  boundary: "end"   },
  soc:  { kind: "chorus",  boundary: "start" },
  eoc:  { kind: "chorus",  boundary: "end"   },
  sov:  { kind: "verse",   boundary: "start" },
  eov:  { kind: "verse",   boundary: "end"   },
  sob:  { kind: "bridge",  boundary: "start" },
  eob:  { kind: "bridge",  boundary: "end"   },
};

export function parseDirectiveLine(line) {
  const m = /^\s*\{([^}:]+)(?::([^}]*))?\}\s*$/.exec(line);
  if (!m) return null;
  const key = m[1].trim().toLowerCase();
  const entry = DIRECTIVE_MAP[key];
  if (!entry) return null;
  const label = m[2] ? m[2].trim() : null;
  return { kind: entry.kind, boundary: entry.boundary, label };
}

export function buildDirectiveLine(kind, boundary, label) {
  const name = `${boundary}_of_${kind}`;
  if (label && label.trim()) {
    return `{${name}: ${label.trim()}}`;
  }
  return `{${name}}`;
}

export function getSections(lyrics) {
  if (!lyrics) return [];

  const raw = lyrics.split("\n");
  const sections = [];
  let current = { kind: "plain", label: null, lines: [] };

  for (const line of raw) {
    const d = parseDirectiveLine(line);
    if (!d) {
      current.lines.push(line);
      continue;
    }
    if (d.boundary === "start") {
      if (current.lines.length > 0) {
        sections.push(current);
      }
      current = { kind: d.kind, label: d.label, lines: [] };
    } else {
      sections.push(current);
      current = { kind: "plain", label: null, lines: [] };
    }
  }

  if (current.lines.length > 0) {
    sections.push(current);
  }

  return sections;
}

export function hasChorus(lyrics) {
  return getSections(lyrics).some((s) => s.kind === "chorus");
}

export function repeatChorus(lyrics) {
  if (!lyrics) return lyrics === undefined || lyrics === null ? "" : lyrics;

  const sections = getSections(lyrics);

  const chorus = sections.find((s) => s.kind === "chorus");
  if (!chorus) return lyrics;

  const sectionToLines = (s) => {
    if (s.kind === "plain") return s.lines.slice();
    return [
      buildDirectiveLine(s.kind, "start", s.label),
      ...s.lines,
      buildDirectiveLine(s.kind, "end", null),
    ];
  };

  const chorusLines = sectionToLines(chorus);

  const out = [];
  for (let i = 0; i < sections.length; i++) {
    const s = sections[i];
    out.push(...sectionToLines(s));

    if (s.kind === "verse") {
      const next = sections[i + 1];
      const alreadyFollowed = next && next.kind === "chorus";
      if (!alreadyFollowed) {
        out.push(...chorusLines);
      }
    }
  }

  return out.join("\n");
}

export function lyricsToEditor(lyrics) {
  if (!lyrics) return [{ chords: "", lyric: "" }];

  const rows = [];
  for (const line of lyrics.split("\n")) {
    if (parseDirectiveLine(line) !== null) {
      rows.push({ chords: "", lyric: line });
      continue;
    }

    const segs = parseChordProLine(line);

    let chordStr = "";
    let lyricStr = "";

    for (let _i = 0; _i < segs.length; _i++) {
      const seg = segs[_i];
      const pos = lyricStr.length;
      if (seg.chord !== null) {
        if (chordStr.length < pos) {
          chordStr += " ".repeat(pos - chordStr.length);
        }
        chordStr += seg.chord;
      }
      let _t = seg.text;
      const _prev = _i > 0 ? segs[_i-1] : null;
      const _safe = _i === 0 || (_prev && /\s$/.test(_prev.text));
      if (_safe) _t = _t.replace(/^ +/, "");
      lyricStr += _t;
    }

    rows.push({ chords: chordStr.trimEnd(), lyric: lyricStr });
  }

  return rows;
}

export function editorToLyrics(rows) {
  const lines = [];

  for (const { chords, lyric } of rows) {
    if (parseDirectiveLine(lyric) !== null) {
      lines.push(lyric);
      continue;
    }

    if (!chords || !chords.trim()) {
      lines.push(lyric);
      continue;
    }

    let result = "";
    let i = 0;
    let j = 0;

    while (i < chords.length || j < lyric.length) {
      if (i < chords.length && chords[i] !== " ") {
        let chord = "";
        while (i < chords.length && chords[i] !== " ") {
          chord += chords[i++];
        }
        result += `[${chord}]`;
      }

      if (j < lyric.length) {
        result += lyric[j++];
        i = Math.max(i, j);
      } else {
        i++;
      }
    }

    lines.push(result);
  }

  return lines.join("\n");
}

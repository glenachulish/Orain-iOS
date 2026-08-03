# Òrain for iOS — Project Status

*Status as of 2026-07-29. This is the living document: where the project
stands, the build to-do list, and the session log. The stable design reasoning
lives in `ORAIN-IOS-SCOPE.md`, which barely changes. This file is the part
that moves.*

---

## Current status — one paragraph

**Session 1 (2026-07-29): scoped, and Phase 1 scaffolded.** The project has a
design reference (`ORAIN-IOS-SCOPE.md`), a phase plan, a working export path
off the Pi, and a first cut of the app. The ChordPro engine — the risky part
— has been ported to Swift and comes with 155 golden fixtures generated from
the live `chord.js`, so the port's fidelity is checkable rather than assumed.
**Nothing has been compiled.** The Swift was written without a Swift toolchain
available, so the first job of session 2 is `swift test` on the Mac and fixing
whatever it says. Nothing in the Pi project was touched.

---

## What exists right now

```
orain-ios/
├── ORAIN-IOS-SCOPE.md          design reference (read this first)
├── ORAIN-IOS-STATUS.md         this file
├── SETUP.md                    Terminal-by-Terminal, from files to phone
├── OrainCore/                  Swift package — pure logic, no UI
│   ├── Package.swift
│   ├── Sources/OrainCore/
│   │   ├── ChordPro.swift          ported chord.js (7 functions)
│   │   ├── Library.swift           accent-folding sort + filters
│   │   └── OrainArchive.swift      import/export format
│   └── Tests/OrainCoreTests/
│       ├── ChordProGoldenTests.swift
│       ├── LibraryAndArchiveTests.swift
│       └── Fixtures/chordpro-goldens.json    ← generated, never hand-edit
├── App/Orain/                  the SwiftUI app
│   ├── OrainApp.swift
│   ├── Model/Song.swift            SwiftData models
│   ├── Model/LibraryImporter.swift upsert import
│   └── Views/{LibraryView,SongView,LyricsView,Theme}.swift
└── tools/
    ├── chordpro-ref.mjs            verbatim copy of chord.js's pure functions
    ├── generate_goldens.mjs        regenerates the fixtures
    └── export_orain_archive.py     Pi library → archive JSON
```

Verified so far (what could be run without a Mac):

- `node tools/generate_goldens.mjs` — 155 cases across 9 groups; round-trip
  lossless on 19/19 corpus lyrics.
- `export_orain_archive.py` — run against a synthetic library matching the Pi
  schema (songs / song_versions / song_media): correct counts, correct
  warnings for a song with no versions and a song with no lyrics, sensible
  handling of an older database missing `tradition` and `song_media`, and a
  clean error rather than a traceback when pointed at a non-database.
- Sorting and filtering expectations cross-checked against an independent
  Python implementation of the same accent-folding rule.

Not verified — and this is the honest list:

- **No Swift has been compiled.** Not the package, not the app.
- No Xcode project file exists yet; `SETUP.md` covers creating it.
- The SwiftUI layout has never been seen on a screen.
- The export script has not been run against the real Pi library.

---

## Build to-do list

### Phase 0 — Get it building  ← START HERE

- [ ] `cd OrainCore && swift test` on the Mac; fix compile errors and any
      failing golden assertions
- [ ] Create the Xcode project and add `OrainCore` as a local package
      (`SETUP.md` §2)
- [ ] Run in the simulator with an empty library
- [ ] Export the real Pi library and import it on the simulator
- [ ] Run on the actual phone
- [ ] Create the private GitHub repo (`glenachulish/Orain-iOS`) and push —
      **before** the code sprawls, not after (the Pi project's commit backlog
      is the cautionary tale)

### Phase 1 — Read the library  (scaffolded, unproven)

- [x] SwiftData models: Song, SongVersion, MediaLink
- [x] Archive format + upsert importer
- [x] Library list with search
- [x] Filters: favourite, hitlist, rating threshold, language, tradition, composer
- [x] Song view with version picker
- [x] Chord-over-lyric rendering with a wrapping flow layout
- [x] Chords on/off, repeat-sèist, reveal mode, text size, keep screen awake
- [x] Star rating / favourite / hitlist controls
- [ ] All of the above confirmed working on a real device
- [ ] Reveal mode checked against the web app's behaviour on the same song
- [ ] Long-line wrapping checked on the narrowest phone and in landscape
- [ ] A song with no lyrics, and a song with 3+ versions, both checked

### Phase 2 — Editing

- [ ] Add / edit song details
- [ ] Add / edit versions
- [ ] Two-line chord editor with live preview (the round-trip is already
      ported and tested — this is the UI over it)
- [ ] Section-directive affordance (the `§` popover equivalent)
- [ ] Delete song / delete version behind a confirmation
- [ ] "Save" vs "Keep both versions" as two distinct actions

### Phase 3 — Make it iOS-shaped

- [ ] Share sheet: lyrics as text, song as a file
- [ ] Dynamic Type throughout (the lyric view currently uses its own size control)
- [ ] VoiceOver pass on the mastery controls
- [ ] iPad and landscape layouts
- [ ] App icon
- [ ] Haptic on reveal-advance

### Phase 4 — Recordings

- [ ] Record into a version (AVAudioRecorder)
- [ ] Playback, background audio
- [ ] Include audio in export/import

### Phase 5 — Backup and sync

- [ ] Export the on-device library back to archive JSON
- [ ] CloudKit sync between your own devices

### Phase 6 — Optional Pi sync

- [ ] Settings screen for the Funnel URL + login
- [ ] Pull updates from the Pi library

### Phase 7 — App Store

- [ ] Decide on name + subtitle; check nothing else holds it
- [ ] Apple Developer Program enrolment (99 USD/year)
- [ ] Screenshots, description, privacy declaration (nothing collected)
- [ ] TestFlight round with at least one other person
- [ ] Submit

---

## Open decisions still to settle

- **Native Swift vs Capacitor.** Assumed native; argued in scope §3; not yet
  agreed by Callum. The fixtures and export script survive either way.
- **Whether the iOS app eventually replaces the Pi app for Callum's own use**,
  or lives alongside it permanently. Determines how much Phase 6 matters.
- **Whether anyone else ever uses it.** If yes, Phase 2 is mandatory and the
  empty-library first-run experience needs real thought.
- **Repo name and location.**
- **What to do about `transpose`.** The column is carried across but nothing
  reads it yet; the web app's transposition lives outside `chord.js`. Either
  port it in Phase 2 or drop the field.

---

## Session log

### 2026-07-29 — Session 1: scoped and scaffolded

Read the Òrain project knowledge (`orain-project-notes.md`, `ORAIN_STATUS.md`,
`PI-INFRASTRUCTURE.md`, the 2026-07-13 append, `main.py`'s route list,
`chord.js`) to ground the scope in the real codebase rather than a description
of it.

**Decided:** the iOS app is standalone and local-first. The reasoning is in
scope §2 and comes down to three things — the Pi is unreachable to a reviewer,
singing happens where the signal doesn't, and a wrapper around the web app is
the textbook Guideline 4.2 rejection. The knock-on is that the entire
multi-user layer (users, sessions, invites, bcrypt, per-user database files,
admin) does not cross over, which is most of why the iOS app is small.

**Built:** `OrainCore` (ChordPro port, sorting/filtering, archive format) with
two test suites; the SwiftUI Phase-1 app; the Pi export script; the golden
fixture pipeline.

**On verification.** No Swift toolchain was available in the session, so none
of the Swift compiles yet. Rather than hand over unverifiable code, the risky
logic was made checkable a different way: the seven pure functions of
`chord.js` were copied verbatim into `tools/chordpro-ref.mjs`, run over a
155-case corpus, and their outputs frozen as golden fixtures that the Swift
tests assert against. `swift test` on the Mac is therefore a real check of
fidelity, not a smoke test. Two test expectations were caught and corrected
this way before delivery — the accent-folding sort order and the
folded-title tiebreaker were both written wrong first time and disproved
against an independent Python implementation of the same rule.

**Not done:** nothing compiled, no Xcode project, nothing seen on a screen,
export script never run against the real library.

**Pi project:** untouched, as asked. No files in `~/orain`, on the Pi, or in
the Òrain project knowledge were modified.

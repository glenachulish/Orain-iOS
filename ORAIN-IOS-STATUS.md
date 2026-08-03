# Òrain for iOS — Project Status

*Status as of 2026-08-03. This is the living document: where the project
stands, the build to-do list, and the session log. The stable design reasoning
lives in `ORAIN-IOS-SCOPE.md`, which barely changes. This file is the part
that moves.*

---

## Current status — one paragraph

**Session 2 (2026-08-03): it builds, it runs, and the real library is in it.**
`swift test` passed 25 tests with 0 failures on the first compile; the app
target built clean on the first `xcodebuild`; and Òrain now runs in the iOS 26
simulator showing **120 songs imported from the live Pi library**, with chords
sitting over their syllables, the sèist in its rust rule, reveal mode
advancing a line per tap and repeat-sèist behaving. The code is on GitHub at
`glenachulish/Orain-iOS`. Still to do before this is a real app: run it on the
actual phone, and Phase 2 (editing). The Pi project remains untouched.

---

## What exists right now

```
~/orain-ios/
├── ORAIN-IOS-SCOPE.md          design reference (read this first)
├── ORAIN-IOS-STATUS.md         this file
├── SETUP.md                    Terminal-by-Terminal, from files to phone
├── README.md
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
├── Orain/                      the Xcode project
│   ├── Orain.xcodeproj
│   └── Orain/
│       ├── OrainApp.swift
│       ├── Assets.xcassets
│       ├── Model/{Song,LibraryImporter}.swift
│       └── Views/{LibraryView,SongView,LyricsView,Theme}.swift
└── tools/
    ├── chordpro-ref.mjs            verbatim copy of chord.js's pure functions
    ├── generate_goldens.mjs        regenerates the fixtures
    ├── verify_port_logic.py        checks the port's algorithm without Swift
    └── export_orain_archive.py     Pi library → archive JSON
```

**Environment:** Xcode 26.6 (build 17F113). Deployment target iOS 17.0. Bundle
identifier `com.glenachulish.Orain`. `OrainCore` is wired in as a **local**
package, not a remote dependency. The Xcode project uses **file-system
synchronised groups**, so files added to `Orain/Orain/` on disk are picked up
automatically — no dragging into the navigator needed.

**Repo:** `https://github.com/glenachulish/Orain-iOS` — **public**. Nothing
secret is in it: no credentials, no user data, no lyrics. The Pi's Tailscale
Funnel URL was scrubbed from `ORAIN-IOS-SCOPE.md` and the commit amended
*before* the first push, so it appears nowhere in history. Worth re-checking
that before any future push, especially if Phase 6 (Pi sync) is ever built.

### Verified

- `swift test` — 25 tests, 0 failures, first compile. Covers 155 golden
  ChordPro cases, the sort and filter rules, and the archive format.
- `xcodebuild` — `** BUILD SUCCEEDED **`, first attempt, no errors and no
  warnings beyond a harmless AppIntents note.
- Runs in the iPhone 17 simulator (iOS 26.5). Empty-library screen correct.
- **Import of the real 120-song library works.** Chord-over-lyric rendering,
  sèist rule and label, verse numbering, star rating, composer and language in
  the header all confirmed by eye against a known song.
- Reveal mode, repeat-sèist and long-line wrapping all checked and behaving.
- `export_orain_archive.py` run against the live Pi library.

### Not yet done

- **Never run on the actual phone** — simulator only.
- No side-by-side pixel comparison against the Pi rendering of the same song.
  Spot-checks look right; a formal comparison has not been made.
- No editing of any kind (Phase 2).
- No app icon.

---

## Getting a library onto the simulator — the awkward bit

Dragging a `.json` onto the simulator **fails** with "Simulator device failed
to open file" — the simulator has no app registered to handle that type. Two
things followed from that:

1. The working route is to copy the file straight into the app's container:

   ```
   cp ~/Desktop/orain-library.json "$(xcrun simctl get_app_container booted com.glenachulish.Orain data)/Documents/"
   ```

2. Two Info.plist keys were added so the Files app can see that folder —
   `Application supports iTunes file sharing` and `Supports opening documents
   in place`, both YES. These are not a simulator workaround: they are what
   makes the app a proper Files citizen on a real device too.

**Still missing:** the app does not yet *declare* a document type for its
archive format, so AirDropping a library to the phone won't offer "Open in
Òrain". That's a Phase 1 finishing task, not a Phase 3 nicety — it's the
natural way to get songs onto the phone.

---

## Build to-do list

### Phase 0 — Get it building  ✅ complete (2026-08-03)

- [x] `swift test` on the Mac — 25/25 green
- [x] Xcode project created; `OrainCore` added as a local package
- [x] Runs in the simulator with an empty library
- [x] Real Pi library exported and imported
- [x] Private-then-public GitHub repo created and pushed
- [ ] Run on the actual phone

### Phase 1 — Read the library  (working in the simulator)

- [x] SwiftData models: Song, SongVersion, MediaLink
- [x] Archive format + upsert importer
- [x] Library list with search
- [x] Filters: favourite, hitlist, rating threshold, language, tradition, composer
- [x] Song view with version picker
- [x] Chord-over-lyric rendering with a wrapping flow layout
- [x] Chords on/off, repeat-sèist, reveal mode, text size, keep screen awake
- [x] Star rating / favourite / hitlist controls
- [x] Confirmed working with the real 120-song library in the simulator
- [ ] Declare a document type for `.json` archives, so AirDrop offers "Open in Òrain"
- [ ] Confirm on a real device
- [ ] Side-by-side against the Pi's rendering of the same song
- [ ] Check a song with 3+ versions, and one with no lyrics at all

### Phase 2 — Editing, transposition and version management

Now mandatory rather than optional: if the app ships to anyone else, a
stranger with an empty library must be able to put something in it.

- [ ] Add / edit song details
- [ ] Add / edit versions
- [ ] Two-line chord editor with live preview (the round-trip is already
      ported and tested — this is the UI over it)
- [ ] Section-directive affordance (the `§` popover equivalent)
- [ ] **Chord transposition** — tap a chord, choose its new value, all others
      follow; saved as a new named version (scope §5a)
- [ ] Transposition rules: root and bass note only, suffixes untouched;
      sharps-or-flats chosen by the target key; unrecognised chords left alone
- [ ] Golden fixtures for transposition, generated the same way as the
      ChordPro ones — this is fiddly enough to deserve them
- [ ] Rename a version (label and title)
- [ ] Delete a version behind a confirmation; deleting the last one leaves the
      song rather than an orphan
- [ ] Choose the default (canonical) version
- [ ] Delete a song behind a confirmation
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
- [ ] **Before building this:** revisit whether the repo should stay public

### Phase 7 — App Store

- [ ] Assemble a small **copyright-free** seed library (Gàidhlig trad), bundled
      and imported on first run. **Callum's own library must not ship** — see
      scope §5b
- [ ] Decide on name + subtitle; check nothing else holds it
- [ ] **Make the repo private**
- [ ] Apple Developer Program enrolment (99 USD/year) — deliberately deferred
      until the app is worth putting on a store
- [ ] Screenshots, description, privacy declaration (nothing collected)
- [ ] TestFlight round with at least one other person
- [ ] Submit

---

## Open decisions still to settle

- **Name and icon.** Needed before submission, not before Phase 3. Worth
  checking whether an app called "Òrain" already exists.

*Everything else settled — see scope §10. In short: native Swift (settled by
the compiler); both apps run and the Pi stays the everyday library; the
membership gets paid for when the app deserves it; transposition is in and
specified in scope §5a; the repo stays public until submission approaches.*

---

## Notes for the Pi project (not this one's business, but discovered here)

- **`~/orain/data/users/1/orain.db` on the Mac is badly stale** — 48 songs
  against the Pi's 120, with none of the hitlist entries, ratings or video
  links. Anything that reads the Mac's copy as if it were the library is
  wrong. The live file is `/home/pi/orain/data/users/1/orain.db` (lowercase
  `orain`, as ever).
- `~/orain` has several untracked `.bak2`/`.bak3` files from the guarded-patch
  workflow, plus `orain-status-append-2026-07-13.md`. Left alone.

---

## Session log

### 2026-08-03 — Session 2: builds, runs, real library imported

Moved `orain-ios` out of `~/orain` — it had been created *inside* the Pi
project's working tree, where a `git add .` would have committed the entire
iOS project into the repo the Pi deploys from. Nothing had been committed, so
the move was clean.

`swift test`: 25 tests, 0 failures, first compile. The golden-fixture approach
from session 1 paid off exactly as intended — the ChordPro port matched the
shipped `chord.js` on all 155 cases without a single correction.

Created the repo, scrubbed the Pi's Funnel URL from the scope document, and
amended the initial commit so the address never entered history. Repo made
public on the understanding that nothing sensitive is in it and that it can be
flipped private later.

Xcode 26.6 project created; app sources `git mv`d into it so there is exactly
one copy of each file rather than a set in `App/` and a set in the project —
the same drift trap that bit the Pi project's knowledge snapshots.
`xcodebuild` succeeded first attempt.

**The stale-library catch.** The Mac's copy of the library reported 48 songs, 0
favourites and 1 rating, which did not match a library in daily use. Pulling
the live file off the Pi showed **120 songs, 122 versions, 27 on the hitlist,
48 rated and 42 video links**. Importing the Mac copy would have looked like
success and quietly lost 72 songs. Worth remembering that a plausible number
is not a correct one.

Import route into the simulator turned out to need work: dragging a `.json`
onto the simulator fails outright. Fixed properly rather than worked around,
by adding the two Files-sharing Info.plist keys and copying into the app
container. The remaining gap — declaring a document type so AirDrop offers
"Open in Òrain" — is logged as a Phase 1 task.

**Pi project:** the only Pi interaction was a read-only `scp` of the library
file. Nothing on the Pi, and nothing tracked by the Pi repo, was modified.
Later in the session the Mac's *runtime* library copy
(`~/orain/data/users/1/orain.db`, gitignored and not part of the repo) was
refreshed from the Pi at Callum's request, after a timestamped backup.

**Decisions settled** (all four recorded in scope §10, with transposition
specified in §5a and the seed-content/copyright line in §5b): both apps run
with the Pi staying the everyday library; the Apple membership waits until the
app deserves it; transposition ships with version rename / delete /
choose-default; the repo stays public until submission approaches.

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
of the Swift compiled at the time. Rather than hand over unverifiable code,
the risky logic was made checkable a different way: the seven pure functions of
`chord.js` were copied verbatim into `tools/chordpro-ref.mjs`, run over a
155-case corpus, and their outputs frozen as golden fixtures that the Swift
tests assert against. Two test expectations were caught and corrected this way
before delivery — the accent-folding sort order and the folded-title
tiebreaker were both written wrong first time and disproved against an
independent Python implementation of the same rule.

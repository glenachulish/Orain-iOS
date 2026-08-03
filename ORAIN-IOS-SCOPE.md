# Òrain for iOS — Project Scope

*Version 2 — last updated 2026-08-03. This is the **stable design reference** for
the iOS app: what it is, why it is shaped the way it is, and the decisions
that are now settled. It changes only when a genuine design decision changes
— same convention as `orain-project-notes.md` for the Pi app.*

*Current status, the build to-do list and the session log live separately in
`ORAIN-IOS-STATUS.md`. "Update the project notes" means update that file.*

---

## 1. What this is

A second Òrain: a native iOS app holding a personal library of Gàidhlig and
Beurla songs, with the same song/version model, the same ChordPro
chord-over-lyric display, and the same three mastery axes as the web app
running on the Pi.

**The Pi version is untouched.** It keeps running at
`https://ceol-pi.tail01672f.ts.net/orain/`, keeps its own repo
(`glenachulish/Orain`), keeps its own notes. Nothing in this project modifies
it. The only connection between them is a one-directional export file — songs
travel Pi → phone, and nothing travels back automatically.

The longer aim is the App Store. That aim is what drives the single most
important decision below, so it is worth being clear that it is an aim, not a
commitment: everything here works perfectly well as a private app installed on
your own phone, and the App Store step can be taken or skipped later without
rework.

---

## 2. The decision that shapes everything: it must stand alone

**The iOS app keeps its library on the phone. It does not require the Pi, a
login, or a network connection to work.**

This is not a preference. It follows from three things:

**The Pi is not reachable by a stranger.** The web app lives behind a
Tailscale Funnel on a Raspberry Pi in your house. Any App Store reviewer who
downloads the app has no account, and the moment the Pi is off, rebooting, or
mid-power-cut, the app shows nothing. An app whose core function depends on
one person's home server cannot pass review, and would not deserve to.

**Singing happens where the signal doesn't.** A session in a hall, a car, a
kitchen with thick walls. The web app already leans on a PWA cache for this
and it is the weakest part of the experience. A local library removes the
problem rather than mitigating it.

**A wrapper around the web app would be rejected anyway.** App Store Review
Guideline 4.2 ("Minimum Functionality") exists precisely to reject apps that
are a repackaged website. A WebView pointed at the Funnel URL is the textbook
case. Even a Capacitor build of the existing frontend would need the whole
FastAPI backend rewritten to run on-device — at which point the "reuse" is
mostly the CSS.

**Consequence — the multi-user machinery does not come across.** No users
table, no sessions, no invites, no bcrypt, no per-user database files, no
admin flag. All of that exists on the Pi because the Pi serves several people
over the internet. A phone serves the person holding it. Deleting that whole
layer is not a loss; it is most of why the iOS app can be small.

---

## 3. Architecture — decided

**Native Swift, SwiftUI for the interface, SwiftData for storage, one small
pure-Swift package (`OrainCore`) holding all the logic that can be tested
without a simulator.**

```
Orain.xcodeproj
├── OrainCore/            ← Swift package: no UI, no database, all testable
│   ├── ChordPro.swift        the ported chord.js engine
│   ├── Library.swift         sorting + filtering
│   └── OrainArchive.swift    the import/export format
└── App/Orain/
    ├── Model/            SwiftData models + the importer
    └── Views/            SwiftUI
```

### Why this split matters more than usual

Neither of us can run Xcode inside a working session — Claude has no Swift
toolchain, and you would rather not be the compiler. `OrainCore` is the answer:
it builds and tests from Terminal with `swift test`, no Xcode window, no
simulator. So the parts most likely to be *subtly* wrong (chord placement,
round-tripping, sorting Gàidhlig titles) are the parts you can verify with one
command. What is left for the simulator is what only a simulator can judge:
whether it looks right.

### Rejected alternatives, and why

| Option | Why not |
|---|---|
| **WebView wrapper around the Funnel URL** | Guideline 4.2 rejection; useless offline; useless to anyone but you. |
| **Capacitor / Ionic port of the existing SPA** | The frontend is reusable; the FastAPI backend is not. Every endpoint would need reimplementing in JavaScript against a local database. That is the same amount of work as the Swift port, for a worse result and a harder App Store story. |
| **React Native / Flutter** | No reuse from either existing codebase, plus a second toolchain to keep alive. Nothing here needs Android. |
| **Point a native app at the Pi's API** | Re-creates the availability problem and forces the auth layer back in. Sensible only as an *optional* sync feature later — see Phase 6. |

### The one rule inherited wholesale

Songs and versions stay **two separate things**. A `Song` is what you title,
rate, favourite and pin; a `SongVersion` is what you actually sing, and it
carries the language, the lyrics, the transpose. This was the hardest lesson
out of Ceòl (the empty-parent-row bug and its awkward `OR EXISTS` fix) and it
is not being relitigated on a new platform.

---

## 4. What carries over, and what does not

**Ported, deliberately unchanged in behaviour:**

- The ChordPro engine — inline parsing, section directives, chorus repeat, and
  the two-line editor round-trip. Ported line by line and proved equivalent
  against golden fixtures generated from the live `chord.js` (§6).
- Accent-insensitive title ordering (Ò files with O, not after W).
- The three mastery axes as independent fields, with rating filtered as a
  *threshold* (3+ = performable), never an exact match.
- Filters that AND together rather than replacing one another.
- Reveal mode's rules: only real lyric lines count; blank lines and section
  labels come along with the next real line.
- "Verse: Verse 1" stays fixed — a labelled section shows its label alone.

**Rebuilt natively rather than ported:**

- Navigation, lists, forms — SwiftUI, not a hand-rolled history router.
- Chord-over-lyric layout — the browser wraps a row of stacked pairs for free;
  SwiftUI needs an explicit flow `Layout`. Same appearance, different mechanism.
- Storage — SwiftData rather than raw `sqlite3`. On the Pi, raw SQLite was the
  smallest thing that worked. On iOS the smallest thing that works is
  SwiftData, and hand-rolling would mean writing the migration machinery and
  the change notifications it already has (and the CloudKit bridge, if sync
  ever happens).

**Dropped:**

- Auth, invites, sessions, admin, per-user databases (§2).
- The path-prefix contract from `PI-INFRASTRUCTURE.md` — there is no proxy.
- Print / share-by-URL as the primary sharing route; iOS has a share sheet.

---

## 5. Data model

Straight across from the Pi, minus the multi-user columns.

```
Song            slug (unique), title, composer, rating, isFavourite,
                onHitlist, notes, tradition, createdAt, updatedAt
                → versions

SongVersion     versionLabel, versionTitle, language, lyrics (ChordPro
                inline, verbatim), melody, source, transpose, isCanonical,
                createdAt, sourceId
                → media

MediaLink       kind ("audio" | "video"), url, filename, label
```

Notes on the parts that are easy to get wrong:

- `slug` is kept even though there are no URLs, because it is the identity a
  re-import matches on. Without it, importing twice doubles the library.
- `sourceId` is the Pi's row id for a version, used the same way.
- Exactly-one-canonical-version is enforced in code (`Song.makeCanonical`),
  because the schema cannot express it and something must. The importer
  repairs songs that arrive without one.
- `tradition` is nullable and untagged is a normal state, not a missing value.
- Language lives on the version. A Beurla singing translation is a *version*
  of the song, not a second song.

---

## 5a. Transposition and version management

**Decided 2026-08-03.** A singer who cannot reach the top note of a song in G
wants it in C, and wants to keep both. That is the feature.

### What the user does

Tap a chord — say the `G` — and choose what it should become. Every other
chord in the version moves by the same interval, so `G C D` becomes
`C F G`. The result is saved as a **new version**, named for what it is, and
takes its place alongside the original. Versions can be renamed, deleted, and
one of them chosen as the default that opens with the song.

### How it is stored — an offset, not rewritten text

`song_versions.transpose` already exists on the Pi and has always been an
integer. It stays that way: **the lyrics text is never rewritten.** A
transposed version stores the same ChordPro source with `transpose = 5`, and
the renderer shifts the chord names on the way to the screen.

The alternative — rewriting every `[G]` to `[C]` in the stored text — was
rejected for three reasons. It is lossy: once written, there is no way back to
the original spelling if the transposition rule made a poor enharmonic choice.
It breaks the round-trip guarantee, because a load-then-save would no longer
reproduce what was stored. And it would make a lyric typo fixed in one version
need fixing again in every transposed copy.

The cost is that the two-line editor has to show *something* — either the
stored chords or the transposed ones. It shows the transposed ones, matching
what the song page displays, and converts back on save. That conversion is
exactly the kind of thing the golden-fixture approach exists to check.

### The rules that need deciding, not guessing

- **Only the root and the bass note move.** `Am7` → `Dm7`; `D/F#` → `G/B`.
  The suffix is carried across untouched.
- **Sharps or flats is decided by the target key**, not by the source. Going
  up a tone from `G` gives `A` (a sharp key, so `F#` not `Gb`); going to `Eb`
  gives flats throughout. Following the source spelling mechanically produces
  things like `A#` where any musician would write `Bb`.
- **Anything unrecognised is left alone** rather than mangled. A `[N.C.]` or a
  scribbled `[riff]` passes through untouched.
- **Transposition is not applied to lyrics**, obviously, but also not to
  section labels — a chorus labelled "Sèist in G" keeps its name, and renaming
  it is the user's business.

### Version management, made real

The Pi has the version machinery but the iOS app has only shown it so far.
Phase 2 makes it editable:

- **Rename** a version — its label ("Up a 4th", "English singing translation")
  and its title, if it is sung under a different name.
- **Delete** a version, behind a confirmation. Deleting the last version of a
  song leaves the song, not an orphan.
- **Choose the default** — the canonical version, the one that opens with the
  song. Exactly one per song, enforced in code as it already is.

---

## 5b. Seed content, and a copyright line that matters

**Decided 2026-08-03.** If the app ships, it ships with a handful of songs so
a new user can see what it does with an otherwise empty library.

Those seed songs must be **traditional or otherwise out of copyright** —
Gàidhlig trad is ideal, being both the point of the app and safely public
domain. A seed library is not the same thing as a personal library, and the
distinction is worth stating plainly:

**Callum's own 120-song library must not ship with the app.** It contains
lyrics to U2, Tracy Chapman, The Beatles and others. Keeping those on his own
phone for his own singing is ordinary personal use. Distributing them inside
an App Store binary is publishing someone else's lyrics, which is a different
thing entirely and would be a real problem — not a technicality.

The architecture already keeps these apart, and should stay that way:

- The seed is a small bundled archive file, imported on first run.
- Everything else arrives by the user importing or typing it, and stays on
  their device. The app has no server, sends nothing anywhere, and so never
  becomes a distributor of anything a user enters.

---

## 6. How correctness is checked without a compiler in the room

The ChordPro engine is the risky part of the whole project: it is fiddly, it
is invisible when subtly wrong, and a divergence would mean a song edited on
the phone renders differently on the Pi.

The approach:

1. `tools/chordpro-ref.mjs` holds the seven pure functions of the shipped
   `chord.js`, copied verbatim.
2. `tools/generate_goldens.mjs` runs them over a corpus of 155 cases —
   including every branch, Gàidhlig accents, unclosed brackets, empty
   sections, and the round-trip guarantee — and writes the expected outputs to
   `chordpro-goldens.json`.
3. The Swift test suite loads that same JSON and asserts the port agrees.

So "the Swift version behaves like the app you already use" is a claim you can
check with `swift test`, not a claim you have to take on trust.

**The JavaScript is the specification.** If the two disagree, the JavaScript
wins — it is what has been rendering your songs correctly for months. Even its
quirks are carried across on purpose. When `chord.js` changes on the Pi, the
fix is to re-copy the changed function into the reference file and regenerate;
never to hand-edit a fixture.

---

## 7. Getting your songs across

One JSON file, one direction.

```
python3 tools/export_orain_archive.py ~/orain/data/users/1/orain.db --inspect
python3 tools/export_orain_archive.py ~/orain/data/users/1/orain.db -o ~/Desktop/orain-library.json
```

`--inspect` reports what it found and writes nothing: counts, how many
versions carry chords, and warnings for songs with no versions, no lyrics, or
no canonical version. The script opens the database read-only and immutable —
it cannot damage the Pi library even if pointed at the live file.

The file reaches the phone via AirDrop or the Files app, and the app's Import
button reads it. Import is an **upsert**: songs match on `slug`, versions on
`sourceId`, so importing the same file twice updates rather than doubles.
Import never deletes — anything on the phone that the archive lacks is left
alone. A mistaken import should be annoying, not destructive.

**Audio does not travel.** Uploaded recordings live on the Pi as files; the
archive carries only the rows describing them, and the import tells you how
many were left behind rather than losing them quietly. Video links, being just
URLs, come across intact.

---

## 8. Phase plan

Each phase is a thing that works, not a layer.

**Phase 1 — Read your library on the phone.** *(scaffolded 2026-07-29)*
Import an archive; browse, search and filter the library; open a song; see
chords over lyrics; switch versions; set rating / favourite / hitlist; reveal
mode, repeat-chorus, text size, keep-screen-awake. No editing yet. This alone
replaces most of what the phone is used for.

**Phase 2 — Editing, transposition and version management.** Add and edit songs
and versions; the two-line chord editor with live preview; **transpose a
version into a new key and keep both** (§5a); rename, delete and choose the
default version; "edit in place" vs "keep both versions" as two distinct
actions. This is the phase that turns a reader into an instrument, and it is
also the phase that becomes mandatory the moment anyone but Callum uses the
app — a stranger with an empty library needs to be able to put something in it.

**Phase 3 — Make it feel like an iOS app rather than a port.** Share sheet
(lyrics as text, song as a file), Dynamic Type throughout, VoiceOver on the
mastery controls, haptics on reveal-advance, landscape and iPad layouts, a
proper icon.

**Phase 4 — Recordings.** Record straight into a version with AVAudioRecorder;
play back; background audio; files stored in the app container and included in
export.

**Phase 5 — Backup and multi-device.** Export to a file, and iCloud/CloudKit
sync between your own devices. Deliberately after everything else: sync is the
feature most likely to eat a month.

**Phase 6 — Optional Pi sync.** *If still wanted by then.* A settings screen
where the Funnel URL and a login can be entered to pull updates from the Pi
library. Optional by construction, so review never depends on it.

**Phase 7 — App Store.** See §9.

---

## 9. What the App Store actually requires

Facts worth having before deciding, checked 2026-07-29:

- **Apple Developer Program: 99 USD per year.** Individual enrolment covers
  unlimited apps. Without it you can still build to your own device from Xcode,
  but the build expires after 7 days and must be re-installed.
- **A Mac with Xcode.** You have one; the app targets iOS 17+.
- **Guideline 4.2, Minimum Functionality.** The standalone design already
  clears it — the app works with no server, has native navigation, and does
  something a website does not.
- **Privacy details** must be declared. This app collects nothing, talks to
  no analytics service, and has no accounts, which makes that the easiest
  possible declaration — and is worth *keeping* true.
- **The name.** "Òrain" is the ordinary Gaelic word for songs. Fine to use,
  but a one-word common noun is hard to find in a search and cannot be
  defended. A subtitle ("Òrain — Gaelic Song Library") solves the search
  problem. Worth checking whether an app of that name already exists before
  getting attached.
- **Review takes days, not weeks**, and rejections are usually specific and
  fixable. The first submission is the slow one.

Not required, and worth resisting: accounts, ads, subscriptions, analytics.
Their absence is a feature.

---

## 10. Decisions settled 2026-08-03

1. **Native Swift.** Settled by the compiler: it built and ran the same day it
   was first opened in Xcode. Capacitor is no longer under consideration.
2. **Both apps run.** The App Store is the aim, and the Apple Developer
   membership will be paid for when the app is worth putting on it — **not
   before**. Until then the app installs to Callum's own phone from Xcode,
   re-signed every seven days. **The Pi keeps running throughout**, and stays
   the everyday library. Nothing about the iOS app requires retiring it, and
   deciding that now would be deciding it too early. Phase 6 (Pi sync)
   therefore stays genuinely optional rather than becoming load-bearing.
3. **Other people, eventually.** If it ships, it ships with a few
   copyright-free songs so an empty library isn't a dead end. That makes
   Phase 2 (editing) mandatory rather than a nicety — see §5b for the line
   between seed content and Callum's own library, which matters more than it
   might first appear.
4. **Transposition is in, and specified.** See §5a. Chord transposition,
   saved as a new named version, with rename / delete / choose-default
   alongside it. The `transpose` column stays and finally gets used.
5. **Repo stays public for now.** Nothing sensitive is in it. **Make it
   private before App Store submission** — at that point the repo stops being
   a hobby project in the open and starts being the source of a shipping
   binary, and there is no reason to hand anyone the pre-release. Also revisit
   if Phase 6 is ever built, since that introduces server addresses and
   credentials handling.

Still open, and not urgent:

- **Name and icon.** Both needed before submission, neither before Phase 3.
  Worth checking whether an app called "Òrain" already exists before getting
  attached to it.

---

## 11. File conventions for this project

- **`ORAIN-IOS-STATUS.md`** — the living document: current status, to-do list,
  session log. Updated at the end of every session.
- **`ORAIN-IOS-SCOPE.md`** (this file) — the stable design reference. Changes
  only when a real design decision changes; bump the Version line when it does.
- **`SETUP.md`** — how to get from these files to a running app on your phone.
- Fixtures are generated, never hand-edited.
- The Pi project's own files (`ORAIN_STATUS.md`, `orain-project-notes.md`,
  `PI-INFRASTRUCTURE.md`) are **not** modified by this project.

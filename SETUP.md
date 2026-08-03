# Òrain for iOS — Setup

*From these files to a running app. Written to be followed one command at a
time, checking the output before moving on — the same working style as the Pi
project. Nothing here touches `~/orain` or the Pi.*

**Expect the first step to fail.** None of the Swift has been compiled — there
was no Swift toolchain in the session that wrote it. Compile errors on the
first `swift test` are the expected outcome, not a sign anything is wrong.
Paste them into a session and they get fixed; they are almost always a missing
import or a renamed API.

---

## 1. Put the files somewhere sensible

Everything lives in one folder, separate from the Pi project.

```
mkdir -p ~/orain-ios
```

Then copy the contents of this delivery into `~/orain-ios` so you have:

```
~/orain-ios/ORAIN-IOS-SCOPE.md
~/orain-ios/ORAIN-IOS-STATUS.md
~/orain-ios/SETUP.md
~/orain-ios/OrainCore/
~/orain-ios/App/
~/orain-ios/tools/
```

Check before going further:

```
ls -la ~/orain-ios
```

Watch for macOS's " 2" duplicate-naming habit if anything came through the
Downloads folder.

The delivery may also contain a few stray `.fuse_hidden…` files — artefacts of
the sandbox the files were written in, not part of the project. Clear them:

```
find ~/orain-ios -name '.fuse_hidden*' -delete
```

---

## 2. Run the tests — no Xcode window needed

This is the step that proves the ChordPro port matches the app you already
use. It needs the Xcode command line tools, which you may already have.

```
cd ~/orain-ios/OrainCore && swift test
```

If it reports `xcode-select: error: tool 'xcodebuild' requires Xcode`, install
Xcode from the App Store first, open it once to accept the licence, then:

```
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

**What you want to see:** a list of tests, then `Executed N tests, with 0
failures`. Roughly 15 test methods run, covering 155 golden cases.

**If a golden test fails,** the message names the exact input. That means the
Swift port disagrees with `chord.js` on that input — a real bug in the port,
worth reporting rather than working around. The fixtures are generated from
the live JavaScript and are never the thing to edit.

---

## 3. Regenerating the fixtures (only when `chord.js` changes)

If the Pi app's `static/chord.js` is ever changed, copy the changed function
into `tools/chordpro-ref.mjs`, then:

```
cd ~/orain-ios && node tools/generate_goldens.mjs
```

It prints the case counts and any input where the editor round-trip is lossy.
Re-run `swift test` afterwards — a failure at that point is the port telling
you it needs the same change.

---

## 4. Export your songs off the Pi

Read-only, and safe to run against the live file — it opens the database in
immutable mode. Look first:

```
python3 ~/orain-ios/tools/export_orain_archive.py ~/orain/data/users/1/orain.db --inspect
```

That writes nothing. It prints how many songs and versions it found, how many
carry chords, and warnings for anything odd — songs with no versions, songs
with no lyrics, songs with no canonical version.

If the Mac copy of the library is out of date, take it from the Pi instead:

```
scp pi@ceol-pi.local:/home/pi/orain/data/users/1/orain.db ~/Desktop/orain-live.db
```

Note the **lowercase** `orain` — the Pi has had a stray capital-O clone
before, and that one is not what the service reads.

Then the real export:

```
python3 ~/orain-ios/tools/export_orain_archive.py ~/Desktop/orain-live.db -o ~/Desktop/orain-library.json
```

---

## 5. Create the Xcode project

This part is Xcode's UI, not the Terminal.

1. Open Xcode → **File → New → Project…**
2. Choose **iOS → App**. Next.
3. Product Name: `Orain`. Interface: **SwiftUI**. Language: **Swift**.
   Storage: **None** (SwiftData is wired up in code, not by the template).
   Uncheck tests for now.
4. Save it into `~/orain-ios/` — you will end up with
   `~/orain-ios/Orain/Orain.xcodeproj`.
5. Delete the `ContentView.swift` and `OrainApp.swift` the template made
   (move to Trash), then drag in everything from `~/orain-ios/App/Orain/`,
   choosing **Copy items if needed** and **Create groups**.
6. Add the package: **File → Add Package Dependencies… → Add Local…**, choose
   `~/orain-ios/OrainCore`. Then select the app target → **General → Frameworks,
   Libraries and Embedded Content → +** and add `OrainCore`.
7. Set the minimum deployment target to **iOS 17.0** (app target → General).

Then **Cmd-R** to run in the simulator. An empty library with an Import button
is the correct first screen.

---

## 6. Get the songs onto the simulator, then the phone

**Simulator:** drag `orain-library.json` onto the simulator window — it lands
in Files. In the app, tap **Import**, pick it, and the library fills.

**Phone:** connect it, choose it as the run destination in Xcode, Cmd-R. Get
the JSON onto the phone by AirDrop from the Mac, then Import.

Without an Apple Developer Program membership this works, but the build stops
running after 7 days and needs re-installing from Xcode. That is normal and
is not a reason to pay 99 USD/year until the app is worth keeping on the phone
permanently.

---

## 7. Put it in version control early

The Pi project's long uncommitted backlog became a hard blocker at exactly the
wrong moment. Worth not repeating.

On github.com as `glenachulish`: new **private** repo, `Orain-iOS`, no README,
no `.gitignore`. Then:

```
cd ~/orain-ios && git init -b main
```

```
cd ~/orain-ios && printf '.build/\nDerivedData/\n*.xcuserstate\nxcuserdata/\n.DS_Store\n.fuse_hidden*\n' > .gitignore
```

```
cd ~/orain-ios && git add . && git status
```

Read that status list before committing — no `.db`, no `.build`, no
`DerivedData`. Then:

```
cd ~/orain-ios && git commit -m "Òrain for iOS: scope, OrainCore, Phase 1 scaffold"
```

```
cd ~/orain-ios && git remote add origin https://github.com/glenachulish/Orain-iOS.git && git push -u origin main
```

---

## 8. When something goes wrong

- **`swift test` won't compile** — expected on the first run. The errors name
  a file and line. Nothing is lost.
- **A golden test fails** — report the input it names. Do not edit the fixture.
- **The app builds but the library is empty after import** — check the JSON
  opens (`python3 -m json.tool ~/Desktop/orain-library.json | head`) and that
  the export's `--inspect` found songs at all.
- **Chords sit over the wrong syllable** — that is a rendering question, not a
  parsing one, if `swift test` is green. Worth a screenshot alongside the same
  song on the Pi.

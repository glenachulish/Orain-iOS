# Òrain for iOS

A native iOS version of Òrain — a personal library of Gàidhlig and Beurla
songs with chord-over-lyric display. Sister project to the Raspberry Pi web
app, which is **not modified by anything here**.

## Read these in order

1. **`ORAIN-IOS-SCOPE.md`** — what this is and why it is shaped this way.
   The important part is §2: the iOS app is standalone and holds its library
   on the phone. Everything else follows from that.
2. **`ORAIN-IOS-STATUS.md`** — where it stands, the to-do list, the session log.
3. **`SETUP.md`** — from these files to a running app.

## First command

```
cd OrainCore && swift test
```

Nothing here has been compiled — there was no Swift toolchain available when
it was written. Compile errors on the first run are expected.

## What has been checked, and how

The ChordPro engine is a line-by-line port of the web app's `chord.js`. Since
it could not be compiled, it was verified two other ways:

```
node tools/generate_goldens.mjs      regenerate 155 fixtures from the real chord.js
python3 tools/verify_port_logic.py   check the ported algorithm against them
```

`verify_port_logic.py` is a transliteration of `ChordPro.swift` into Python —
same branches, same off-by-ones — run against the same fixtures the Swift
tests use. It passing means the *algorithm* is right; `swift test` is what
proves the Swift itself is.

## Getting songs across from the Pi

```
python3 tools/export_orain_archive.py ~/orain/data/users/1/orain.db --inspect
```

Read-only and safe against the live library. Drop the resulting JSON on the
phone and use the app's Import button.

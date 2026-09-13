# What this fork changes

The engine here is [P-Slice](https://github.com/Psych-Slice/P-Slice), imported
from upstream `master` at `98e75a5`. Upstream is wired up as the `pslice`
remote, so a sync is:

```sh
git fetch pslice master
git diff HEAD pslice/master -- source Project.xml   # see what moved
```

Keeping this list short is the point: the smaller the divergence, the cheaper
every future sync is. Everything below is a deliberate departure from upstream.

## Gameplay

**Characters no longer jitter while several sustains are held**
(`source/states/PlayState.hx`, in both `opponentNoteHit` and `goodNoteHit`)

Upstream stops a sustain from restarting the sing animation only when the
character *has* a `-hold` animation to sit on. A character without one gets
`playAnim(animToPlay, true)` on every sustain piece, so holding two notes at
once makes the two directions fight each other every frame. The added check
suppresses the replay whenever the character is already mid-`sing` (and not
mid-miss), which is what V-Slice does.

## Mobile main menu

**A grid tile confirms on the second tap, not the first**
(`source/mobile/objects/grid/GridTile.hx`, `source/mobile/objects/GridButtons.hx`)

Upstream selects a tile on press and confirms it on release, so one stray thumb
launches a menu. Now the first tap only moves the selection; tapping the
already-selected tile confirms. Keyboard and gamepad `ACCEPT` are untouched.

`GridButtons.selectionShown` exists because the grid starts parked on tile
(0, 0) internally without highlighting it. Without the flag, that one tile
would still confirm on a first tap while every other tile needed two.

## Crash safety

**A health icon survives a graphic that fails to load**
(`source/objects/HealthIcon.hx`)

Upstream falls back to `icon-face` when the *file* is missing, but still
dereferences the result of `Paths.image`. On Android a path can resolve and
then fail to decode, which crashed freeplay on a null graphic. The icon now
falls back once more and bails out rather than throwing.

## Building

**`NO_FIREBASE`** (`Project.xml`)

`FIREBASE_CRASH_HANDLER` is now `unless="NO_FIREBASE"`. Upstream's CI feeds it
`setup/google-services.json` from a repository secret this fork doesn't have,
and the Firebase gradle plugin fails on an empty one. Every use of the define
in `source/` was already behind `#if`, so turning it off just drops the
crash reporter.

**`templates/android/template/app/build.gradle`**

Turning Firebase off isn't enough on its own: lime's app `build.gradle`
template guards the Crashlytics plugin and its dependencies behind
`PSLICE_FIREBASE_SDK`, but leaves the release buildType's
`firebaseCrashlytics {}` block unconditional. With the plugin gone, gradle has
no such method, and the build dies *after* the whole C++ pass has succeeded:

```
build.gradle line 55: Could not find method firebaseCrashlytics()
```

So `templates/` carries that one file, identical to lime's apart from the same
guard wrapped around that block — two added lines. `<template path="templates"
if="NO_FIREBASE"/>` registers it, and a project's own template paths take
priority over lime's (`HXProject.fromFile` appends them last precisely so they
win, and `hxp`'s `findTemplateRecursive` reverses the list and takes the first
match per file). Only that one file is overridden; every other android
template still comes from lime.

This is the one change here worth sending upstream — the unconditional block
is a latent bug in P-Slice's lime fork for anyone building without Firebase.

**`.github/workflows/android.yml`**

Upstream's `main.yml` builds Windows, Linux, macOS, HTML5, Android and iOS, and
its Android job needs P-Slice's Firebase credentials and release keystore. It
still triggers only on `master-dev`, so it stays dormant here. This workflow
builds the Android APK alone, on `ubuntu-24.04`, with `-DNO_FIREBASE`, and
leaves signing to the `key.keystore` that `Project.xml` already points at for
non-debug Android builds — so the artifact installs on a device as-is.

## What was dropped in the switch

The hand-written mobile port that used to live on this branch (touch controls,
storage resolution, the `Paths.nativePath` fix for Android's Haxe-vs-lime path
split, the story menu layout work) is all superseded by P-Slice's own
`source/mobile/`, `StorageUtil`, `NativeFileSystem` and `MobileScaleMode`. It
remains reachable in this branch's history, and the V-Slice freeplay replica
remains on `claude/vslice-freeplay`.

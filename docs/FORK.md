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

## Strums

**The strumline behaves like V-Slice's**
(`source/objects/StrumNote.hx`, `source/states/PlayState.hx`)

Psych splits a sustain into one piece per step and plays `confirm` again on each of
them, so the bright first frame of the glow re-fires the whole way through a hold.
V-Slice instead lets the glow run once, follows it with `confirm-hold`, and leaves
that frozen on its last frame until the hold is over. `confirm-hold` is registered
from the `confirm` animation's own frames, so a note skin only ever has to define
the one — pixel and sparrow alike.

Three other pieces of that behaviour come with it:

- A tapped note holds its glow for `CONFIRM_HOLD_TIME` (0.15s, V-Slice's number)
  after the animation finishes before dropping back, while a **hold** drops the
  instant it runs out. That difference in timing is the point of it.
- A held key never sits on `static`; it rests on `pressed`, re-checked every frame.
- `keyPressed` treats `confirm-hold` as lit, so tapping another lane mid-hold no
  longer drops this one back to the ghost tap.

`PlayState` feeds that with per-lane bookkeeping in `keysCheck`: which lanes had a
piece land this frame, which still have pieces coming, and when each hold actually
ends per the chart. That last one matters because the pieces sit at 0, step,
2·step … (n−1)·step, so the final piece is a whole step short of
`strumTime + sustainLength` — going by the last piece alone dropped the strum a
tenth of a second early, with the end of the sustain still on screen. Ownership is
checked against the hold's own head note, since the next hold in the same lane is
already spawned a couple of seconds ahead, and counting *its* pieces made the hold
look endless.

`openPauseMenu` already resets the player's strums, so it clears this bookkeeping
too — otherwise resuming mid-hold would light a glow for a hold long gone.

The end of a hold is anchored to the trail rather than to a time.
`Note.clipToStrumNote` eats a sustain from the strum's **centre** — half a note
height below its top — and only upscroll gets the matching `correctionOffset` that
cancels that out (`sustainNote.correctionOffset = swagNote.height / 2`, set to 0 on
downscroll). So on downscroll the trail is gone half a note height *before*
`strumTime + sustainLength`, and pinning the strum to that time left it lit with
nothing left to hold — a delay that grows as scroll speed drops (~90ms at speed 2,
~180ms at speed 1). `holdTailConsumed()` mirrors the condition that empties the clip
rect instead, so the strum drops exactly when the last of the trail does, in either
direction at any speed. The chart-time check stays as an upper bound, so this can
only ever shorten the tail end of a hold, never revive one.

Worth recording what this *wasn't*, since it was the obvious suspect: the sustain
pieces are laid out at `step * i` for `i in 0...round(length / step)`, so a hold
whose length isn't a whole number of steps ends up to half a step off. Measured
across the base-game charts, 3402 of 3493 holds are step-exact — 26 late, 65 early —
so that rounding explains almost nothing.

## Hold covers and splashes

**The hold cover loop no longer changes speed with the song**
(`source/objects/SustainSplash.hx`, `source/states/PlayState.hx`)

`SustainSplash.frameRate` was `Math.floor(24 / 100 * SONG.bpm)`, so the looping cover
played at the sheet's authored 24fps only at exactly 100BPM — 38fps at 160, 18fps at
78. The *end* animation was already pinned to 24, so only the loop wandered. It is a
fixed 24 now, still overridable through the same static.

**Pixel stages get real pixel art rather than a pixelated filter**

Upstream draws the ordinary sheets through `PixelSplashShaderRef` with
`pixelAmount = 6` on a pixel stage, which is an impression of pixel art rather than
the thing itself. Both now prefer a dedicated sheet where one exists:

- **Splashes** — `NoteSplash.pixelVariantOf()` picks a `-pixel` twin of whatever skin
  is in play (cached in a map, so spawning a splash is never a file lookup), and
  `assets/shared/images/noteSplashes/noteSplashes-pixel.*` supplies it. Its json sets
  `allowPixel: false` so the shader leaves it alone and `allowRGB: false` so its own
  colours survive — upstream already honours both, and `RGBPalette.copyValues(null)`
  correctly zeroes `mult` rather than throwing.
- **Hold covers** — `SustainSplash` loads `holdCovers/pixelNoteHoldCover` on a pixel
  stage, whose animations are named `loop` and `explode` rather than `holdCover0` /
  `holdCoverEnd0`, since it is V-Slice's own art and not a recolour of the normal
  sheet. It skips the `-210` clip fudge and the note's colour shader, both of which
  exist only to make the stretched ordinary sheet presentable.

**`blend` in a splash skin's json** (`'add'`, `'screen'`, `'multiply'`, `'subtract'`)

V-Slice's pixel splashes are drawn with `screen`, which is what turns their black
outlines into light instead of leaving them as black blobs on screen. Only the four
modes the hardware renderer implements are honoured; anything else draws normally
rather than quietly falling back to something slower.

### Where the pixel cover's placement comes from

Not guesswork: V-Slice's own `pixel` note style
(`preload/data/notestyles/pixel.json`) gives `scale: 6.0`, `offsets: [29, -4]`,
`isPixel: true`. Its `Strumline` centres the cover on the strum, adds
`offsets × scale`, then two further nudges its own source comments call a "hardcoded
adjustment, because we are evil" (−12 x, −96 y).

Running that back through flixel's `drawn_left = x - offset + origin × (1 - scale)`
cancels the scale out of everything but the offsets themselves, which is why the
code reads

```haxe
offset.x = frameWidth * 0.5 - strum.width * 0.5 - PIXEL_OFFSET_X * scale.x - PIXEL_NUDGE_X
```

Upstream's tuned numbers could not be reused here: the two sheets are authored
completely differently — the vanilla frame is 300×400, the pixel one 200×59 — so
neither the offsets nor the clip fudge transfer. The five constants are named at the
top of the class so a nudge is a one-line change.

## Pause

**The pause button finishes its press while the menu is up**
(`source/substates/PauseSubState.hx`)

`PlayState` stops updating the moment the pause menu opens, so its own pause button
can't animate — it freezes mid-press. V-Slice answers that by hiding the real button
and having the pause menu draw a copy that plays the press through: a disc pops out
to 1.4 and shrinks back past resting size, both fading, and the button follows a
beat later. Those numbers are V-Slice's.

The art is not. Rather than bring V-Slice's own button sheet in to clash with the
touch pad's style, this copies whatever graphic the pad is already showing and reads
the button's live position off it — which also means it lands correctly wherever
`MobileScaleMode` and the `P` action mode have put it on a given device. The real
button is hidden for the duration and handed back in `destroy()`, whether the song
resumes or ends there.

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

## Deliberately *not* carried over from the old port

P-Slice already does these, so the hand-written versions were dropped rather than
ported:

| Old port | P-Slice's own |
| --- | --- |
| `HoldCover.hx` plus per-colour hold cover art | `SustainSplash.hx` with a `holdSkin` pref and skinnable sheets; its end animation is already timed off the chart, not the last piece. The pixel sheet from that work *was* brought across — see above |
| A V-Slice pause button built into `MobileControls` | a round `P` touch pad button, data-positioned per device — only its press animation was missing |
| `CoolUtil.widescreenOffset()` / `fillBanner()` and the story menu offsets | `MobileScaleMode` (notch cutouts, logical size, game cutout), and a different V-Slice-style story menu |
| Android BACK to pause | already wired in `PlayState` |

## What was dropped in the switch

The hand-written mobile port that used to live on this branch (touch controls,
storage resolution, the `Paths.nativePath` fix for Android's Haxe-vs-lime path
split, the story menu layout work) is all superseded by P-Slice's own
`source/mobile/`, `StorageUtil`, `NativeFileSystem` and `MobileScaleMode`. It
remains reachable in this branch's history, and the V-Slice freeplay replica
remains on `claude/vslice-freeplay`.

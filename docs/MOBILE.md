# Psych Engine on Android & iOS

This documents the mobile port: how to build it, how the touch controls are put
together, and what still doesn't work.

* [Building for Android](#building-for-android)
* [Building for iOS](#building-for-ios)
* [Trying the touch controls on desktop](#trying-the-touch-controls-on-desktop)
* [How the touch controls work](#how-the-touch-controls-work)
* [Where files live on a phone](#where-files-live-on-a-phone)
* [What isn't done](#what-isnt-done)

---

## Building for Android

Everything in [BUILDING.md](BUILDING.md) still applies; this is what's needed on
top of it.

### Dependencies

- **JDK 17** — newer JDKs break the Gradle version lime generates.
- **Android SDK** with platform 34, build-tools 34.x and NDK **r21e**
  (`21.4.7075529`). Newer NDKs drop the toolchain layout hxcpp expects, and the
  build fails deep inside a C++ compile where the error tells you nothing useful.
  Android Studio's SDK Manager is the easiest way to get all three.
- The `extension-androidtools` haxelib, which is what gives us
  `Context.getExternalFilesDir()`:

```bash
haxelib git extension-androidtools https://github.com/MAJigsaw77/extension-androidtools.git
```

### One-time lime setup

```bash
haxelib run lime setup android
```

It asks for the paths to the SDK, the NDK and the JDK. Point it at the NDK r21e
folder specifically, not the `ndk` parent directory.

### Building

```bash
# debug APK, installed and launched on the connected device
haxelib run lime test android -debug

# release APK
haxelib run lime build android -release

# 32-bit device (arm-v7a instead of the default arm64-v8a)
haxelib run lime build android -release -DARMV7
```

The APK lands in `export/release/android/bin/app/build/outputs/apk/`.

Google Play requires a 64-bit build, which is the default here. Ship ARMv7 as a
separate ABI only if you need to support phones older than about 2016.

### If Lua won't build

`LUA_ALLOWED` is on for Android because LuaJIT does compile for `arm64-v8a`, but
it's the most fragile part of the build. If linc_luajit fails to compile, drop
`|| android` from the `LUA_ALLOWED` line in `Project.xml`. You lose Lua mods;
HScript mods keep working, since hscript-iris is pure Haxe.

---

## Building for iOS

iOS needs macOS with Xcode, and is the less-tested of the two targets.

```bash
haxelib run lime test ios -debug
```

`LUA_ALLOWED` is deliberately off for iOS: the App Store forbids JIT compilation,
which is the whole point of LuaJIT. Mods still work through HScript.

`VIDEOS_ALLOWED` is also off, because hxvlc has no iOS build.

---

## Trying the touch controls on desktop

You don't need a phone to work on the controls. Add the define by hand and the
on-screen buttons appear on a desktop build, driven by the mouse:

```bash
haxelib run lime test windows -debug -DTOUCH_CONTROLS_ALLOWED
```

`TouchButton.mouseEnabled` is what makes the cursor count as a finger; it's on
for every target except mobile, where a real finger already reports itself as a
touch and would otherwise register twice.

Note this only exercises one pointer at a time. Anything about two thumbs at once
— holding a sustain in one lane while tapping another — has to be tested on a
device.

---

## How the touch controls work

The port adds a `mobile` package and changes one thing about how input is read.

**`Controls` is the whole trick.** Every on-screen button carries the names of the
`Controls` actions it stands in for (`ui_up`, `accept`, `note_left`, …), and
buttons add themselves to `TouchButton.list` when they're created.
`Controls.justPressed`/`pressed`/`justReleased` walk that list after checking the
keyboard. So every menu that already asked `controls.UI_UP_P` or `controls.ACCEPT`
responds to touch without a single line of that menu changing — which is why the
diff across two dozen states is one `addVirtualPad(...)` call each.

Buttons that have stopped updating report `isAwake == false` and are skipped.
Without that, a state that handed over to a substate could leave a button stuck
reporting a press forever.

**The pieces:**

| File | What it does |
| --- | --- |
| `mobile/objects/TouchButton.hx` | A button that tracks every finger on it, not just one. `FlxButton` handles a single pointer, which is useless when four notes can be held at once. |
| `mobile/objects/VirtualPad.hx` | The pad menus use: a D-pad cluster and action buttons, in the combinations `VirtualPadDPad` / `VirtualPadAction` describe. |
| `mobile/objects/Hitbox.hx` | The four columns tapped during gameplay. |
| `mobile/objects/MobileControls.hx` | Picks the gameplay layout the player chose and owns the pause button. |
| `mobile/backend/TouchButtonGraphic.hx` | Draws every button at runtime. |
| `mobile/backend/TouchUtil.hx` | The frame counter behind `isAwake`, and vibration. |
| `mobile/backend/StorageUtil.hx` | Writable paths, and unpacking bundled mods on first launch. |
| `mobile/options/MobileOptionsSubState.hx` | Options → Mobile. |

**No new art.** `TouchButtonGraphic` draws the buttons with the OpenFL drawing
API and caches the results as `FlxGraphic`s, so the port adds nothing to
`assets/`, mods and `Paths` are untouched, and buttons stay sharp at any screen
density.

**Gameplay input** is wired in `PlayState.addMobileControls()`. Presses and
releases are callbacks straight to `keyPressed`/`keyReleased` rather than polled,
because a polled press could land a frame late — 16ms at 60fps, a third of the
sick window, quietly costing the player accuracy. Holds need no wiring at all:
the lanes are tagged with the `note_*` actions, so `keysCheck()` reads them
through `Controls` exactly like a held key.

The controls sit on their own `FlxCamera`. `camHUD` gets zoomed on every beat and
a pad riding along with that is unusable.

---

## Where files live on a phone

Android gives every app a private folder under
`Android/data/com.shadowmario.psychengine/files`, and `Main` makes that the
working directory on startup. Every relative path Psych already used — `mods/`,
`modsList.txt`, `crash/`, the save file — then works untouched.

Using that folder instead of shared storage is what keeps the port off the
`WRITE_EXTERNAL_STORAGE` / `MANAGE_EXTERNAL_STORAGE` treadmill: no runtime
permission prompt, and nothing that breaks on the next Android release. The
trade-off is that the folder is harder for players to find with a file manager.

The mods bundled with the build are sealed inside the APK, so
`StorageUtil.unpackBundledFiles()` writes them out on first launch. It never
overwrites a file that already exists, so an app update can't wipe edits a player
made.

Crash logs go to `crash/` inside that same folder — on a device you can't attach
a debugger to, that file is the only way to find out why a build died.

---

## What isn't done

Worth knowing before you file a bug:

- **The editors** (chart, character, stage, dialogue, week) are built around a
  mouse, a keyboard and PsychUI windows. They open on a phone and are not usable.
  Adapting them is a much larger job than the rest of this port combined.
- **This has been type-checked, not run.** Every configuration compiles clean
  (touch on, touch off, `mobile`, `android`), but no build has been put on a
  device. Expect the first run to turn up layout and sizing problems the compiler
  can't see.
- **The pad is laid out in the game's 1280x720 space**, so on a phone wider than
  16:9 the buttons sit inside the letterbox rather than at the true screen edge.
  Fine, but not ideal on a tall phone.
- **Button positions aren't customisable.** Opacity, style and layout are, but not
  dragging individual buttons around.
- **Nothing is exposed to Lua or HScript.** Mods can't read touch state or place
  their own buttons yet.
- **iOS is untested** beyond compiling.

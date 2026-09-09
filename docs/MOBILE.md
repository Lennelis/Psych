# Psych Engine on Android & iOS

This documents the mobile port: how to build it, how the touch controls are put
together, and what still doesn't work.

* [Building for Android](#building-for-android)
  * [The easy way: let GitHub build it](#the-easy-way-let-github-build-it)
  * [Building locally](#building-locally)
* [Building for iOS](#building-for-ios)
* [Trying the touch controls on desktop](#trying-the-touch-controls-on-desktop)
* [How the touch controls work](#how-the-touch-controls-work)
* [Where files live on a phone](#where-files-live-on-a-phone)
* [What isn't done](#what-isnt-done)

---

## Building for Android

There are two routes. The CI one needs nothing installed.

### The easy way: let GitHub build it

`.github/workflows/android.yml` builds a signed, installable APK on a GitHub
runner. Open the repo's **Actions** tab, pick **Build Android APK**, hit **Run
workflow**, and download the `PsychEngine-android` artifact when it finishes. It
also runs automatically on every push to the mobile port branch.

Two switches on the Run workflow form:

| Switch | Default | What it does |
| --- | --- | --- |
| `videos` | off | Includes hxvlc for video cutscenes. It's the most fragile native dependency here, so it's off by default — turn it on if you want cutscenes and are willing to have the build fail in it. |
| `armv7` | off | Also builds 32-bit `armeabi-v7a`. Each ABI is a separate full hxcpp compile, so this roughly doubles the build time. Only needed for phones older than about 2016. |

The APK is signed with a throwaway key generated fresh each run. That's fine for
sideloading, but it means **each build is signed by a different key** — uninstall
the previous build before installing a new one, or Android refuses it as coming
from a different signer. Use your own keystore (below) if that gets annoying.

Expect the first run to take a while: hxcpp compiles the whole engine from
scratch. Later runs reuse a cache of the Haxe libraries, not the C++ objects, so
they aren't much faster.

### Building locally

Everything in [BUILDING.md](BUILDING.md) still applies; this is what's needed on
top.

#### Dependencies

- **JDK 17.** Not newer. Lime 8.1.2 generates Gradle 7.4.2 with Android Gradle
  Plugin 7.3.1, and neither runs on a JDK past 17.
- **Android SDK** with:
  - platform **android-33**
  - build-tools **33.0.2**
  - NDK **r21e** (`21.4.7075529`)

  NDK r21e specifically. Newer NDKs changed the toolchain layout hxcpp expects,
  and the failure surfaces deep inside a C++ compile where the error tells you
  nothing useful. Android Studio's SDK Manager is the easiest way to get all
  three, or from the command line:

  ```bash
  sdkmanager --install "ndk;21.4.7075529" "platforms;android-33" "build-tools;33.0.2"
  ```

- The Haxe libraries, via the setup script:

  ```bash
  chmod +x ./setup/android.sh && ./setup/android.sh   # Linux, macOS
  setup\android.bat                                   # Windows
  ```

  Same list as the desktop setup, plus `extension-androidtools` (which is what
  gives the port `Context.getExternalFilesDir()`), minus `hxdiscord_rpc` (no
  Android build, and `DISCORD_ALLOWED` is off for mobile anyway).

  `extension-androidtools` needs to be **2.x**, which the script installs. Version
  2 moved these classes from `android.*` to `extension.androidtools.*`; Psych's own
  `Main.hx` was written against the 1.x package and would no longer compile against
  it, which is why the storage code lives in `mobile/backend/StorageUtil.hx` now.

#### Pointing lime at the toolchain

`haxelib run lime setup android` asks for the three paths interactively. Lime also
reads them straight from the environment, which is easier to keep straight:

```bash
export ANDROID_SETUP=true
export ANDROID_SDK=$HOME/Android/Sdk
export ANDROID_NDK_ROOT=$HOME/Android/Sdk/ndk/21.4.7075529
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

Those four are exactly what `lime setup android` writes to `~/.lime/config.xml`.
`ANDROID_SETUP` is the flag it sets when it finishes, and lime checks that one
before it looks at anything else — without it you get *"You need to run lime setup
android before you can use the Android target"* no matter how correct the paths
are.

If your SDK has several build-tools installed, lime picks the newest, which AGP
7.3.1 may be too old to accept. Pin it:

```bash
export ANDROID_BUILD_TOOLS=33.0.2
```

Running `./setup/android.sh` prints which of these are set, so use it to check.

#### Building

```bash
haxelib run lime build android -release -D officialBuild -D NO_VIDEOS
```

The flags matter:

- **`-D officialBuild`** is what includes the weeks and songs. Without it the game
  builds and boots to an empty menu — no use for testing the controls.
- **`-D NO_VIDEOS`** leaves out hxvlc. It does have an Android build, but it's the
  likeliest thing to break; drop the flag once the rest works and you want
  cutscenes.
- **`-D ARMV7`** adds the 32-bit ABI. Off by default because each ABI is a
  separate full compile.
- **`-debug`** instead of `-release` gets you a debug-signed APK with no keystore
  needed, but an unoptimised hxcpp build struggles to hold 60fps on a phone, so
  it's not much use for actually playing.

The APK lands at:

```
export/release/android/bin/app/build/outputs/apk/release/PsychEngine-release.apk
```

#### Signing

Android won't install an unsigned APK, and a `-release` build with no keystore
comes out unsigned. Make a keystore once:

```bash
keytool -genkeypair -keystore ~/psych.keystore -alias psychengine \
  -keyalg RSA -keysize 2048 -validity 10000
```

Then point the build at it. `Project.xml` reads these three from the environment
and passes them to Gradle; nothing secret goes in the repo:

```bash
export ANDROID_KEYSTORE=$HOME/psych.keystore
export ANDROID_KEYSTORE_PASSWORD=whatever-you-chose
export ANDROID_KEYSTORE_ALIAS=psychengine
```

Keep the same keystore and you can install updates over each other. Lose it and
you can't — you'd have to uninstall first.

#### Getting it onto the phone

```bash
adb install -r export/release/android/bin/app/build/outputs/apk/release/PsychEngine-release.apk
```

Or copy the APK across and open it in a file manager, with "install from unknown
sources" allowed for that app. `haxelib run lime test android` builds, installs
and launches in one step if a device is already connected over adb.

`adb logcat` is where `trace()` output and crash messages go.

#### If Lua won't build

`LUA_ALLOWED` is on for Android because LuaJIT does compile for `arm64-v8a`, but
it's the most fragile part of the Haxe side of the build. If linc_luajit fails,
drop `|| android` from the `LUA_ALLOWED` line in `Project.xml`. You lose Lua
mods; HScript mods keep working, since hscript-iris is pure Haxe.

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

**Almost no new art.** `TouchButtonGraphic` draws the pads and lanes with the
OpenFL drawing API and caches the results as `FlxGraphic`s, so they add nothing to
`assets/`, mods and `Paths` are untouched, and buttons stay sharp at any screen
density.

The **pause button** is the exception, and it is the base game's own: `pauseButton`
over a faint `pauseCircle`, top right, tapped to pause. Everything about its
placement is V-Slice's, from `PlayState.initPauseSprites` — the button at 0.8 scale
35px in from the corner, the disc at 0.84 by 0.8 centred behind it at a tenth
opacity, spilling past the screen edge exactly as it does there. It stays at full
opacity whatever Controls Opacity is set to, again as in the base game. A build
without those two files falls back to the drawn button, so there is always a way to
pause.

A tap on it must not also be played as a note, since the button hangs about 25px
into the top of the rightmost lane. `TouchButton.deadZones` is what stops that: a
lane ignores any touch that lands inside a button listed there, which is the same
idea as the `deadZones` V-Slice puts on its hitbox hints.

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

`StorageUtil.unpackBundledFiles()` writes bundled mods out to that folder on first
launch, never overwriting a file that already exists. It does nothing at the
moment, because mods are off for mobile — see below — but it stays wired up ready
for when they are enabled.

Crash logs go to `crash/` inside that same folder — on a device you can't attach
a debugger to, that file is the only way to find out why a build died.

---

## What isn't done

Worth knowing before you file a bug:

- **The editors** (chart, character, stage, dialogue, week) are built around a
  mouse, a keyboard and PsychUI windows. They open on a phone and are not usable.
  Adapting them is a much larger job than the rest of this port combined.
- **This has been type-checked, not run.** Every configuration compiles clean
  (touch on, touch off, `mobile`, `android`), but no APK has been built and put on
  a device. Expect the first run to turn up layout and sizing problems the
  compiler can't see, and the Android build itself to need a nudge.
- **Notched phones will letterbox.** Lime's manifest template doesn't set
  `windowLayoutInDisplayCutoutMode`, so the game keeps clear of the cutout instead
  of drawing under it. Fixing it means overriding the manifest template.
- **The pad is laid out in the game's 1280x720 space**, so on a phone wider than
  16:9 the buttons sit inside the letterbox rather than at the true screen edge.
  Fine, but not ideal on a tall phone.
- **Button positions aren't customisable.** Opacity, style and layout are, but not
  dragging individual buttons around.
- **Nothing is exposed to Lua or HScript.** Mods can't read touch state or place
  their own buttons yet.
- **Mods are off on mobile** (`MODS_ALLOWED` is desktop-only). Worth understanding
  before turning it back on, because it is a one-line edit that quietly guts the
  game.

  Psych reads mod content off the real filesystem, and most of its asset lookups
  are written as an *either/or* rather than a fallback:

  ```haxe
  #if MODS_ALLOWED
  if (FileSystem.exists(path)) rawData = File.getContent(path);
  #else
  rawData = Assets.getText(path);
  #end
  ```

  With the define on, the `Assets` branch isn't compiled at all. That's fine on
  desktop, where `assets` is a loose folder beside the executable and the
  filesystem lookup always succeeds. On Android `assets` lives inside the `.apk`,
  nothing is on disk, and those lookups all come back empty — no weeks, no songs,
  no character or stage data. The game boots to empty menus.

  Enabling mods here means converting those sites (`Character`, `MenuCharacter`,
  `Alphabet`, `DialogueCharacter`, `WeekData`, `CoolUtil.coolTextFile`, the script
  loaders in `PlayState`, and others) from either/or into filesystem-then-`Assets`
  fallbacks — the way `Song.loadFromJson` and `Paths.cacheBitmap` already do it.
  The alternative some ports take is extracting the whole `assets` folder to
  storage on first launch so the filesystem assumption holds, at the cost of
  duplicating a few hundred MB on the device.
- **iOS is untested** beyond compiling.

# Precise input: patching lime

Psych judges a press against the song position at the moment it gets round to looking.
Input arrives once a frame, so the press actually happened somewhere in the interval that
just went by and is read as later than it was - never earlier. Half a frame on average:
about 8ms at 60fps, 4 at 120.

`V-Slice` doesn't have that problem because it asks the operating system when the key
actually went down. Psych can't, and not for want of a binding.

## Why a patch is needed at all

`SDLApplication::ProcessKeyEvent` reads three things off the SDL event:

```cpp
keyEvent.keyCode  = event->key.keysym.sym;
keyEvent.modifier = event->key.keysym.mod;
keyEvent.windowID = event->key.windowID;
```

`event->key.timestamp` is right there and is never read. By the time the event reaches
Haxe as a `KeyEventInfo` - key code, modifier, type, window id - the moment it happened
is gone. No amount of Haxe recovers it.

That is also why V-Slice ship their own lime rather than the released one, and why their
`PreciseInputManager` can call `window.onKeyDownPrecise`, a signal stock lime has no
trace of.

## What the patch does

Carries the event's timestamp through every layer that currently drops it:

- `KeyEvent` and `TouchEvent` gain a `timestamp` field in C++, and `SDLApplication`
  fills it from `event->key.timestamp` / `event->tfinger.timestamp`.
- The CFFI marshalling copies it across, so it reaches Haxe.
- `KeyEventInfo` and `TouchEventInfo` gain the matching field, `lime.ui.Touch` gains
  `timestamp`, and `Window` gains `onKeyDownPrecise` / `onKeyUpPrecise` - the same
  signals V-Slice's `PreciseInputManager` listens to.

Touch as well as keys, because on a phone that is the only input there is.

The number is in whole milliseconds, counted from the same start as `System.getTimer`
(both are `SDL_GetTicks`), so the two subtract directly with nothing to convert. A
millisecond of quantisation is coarse next to a 4ms effect at 120fps and fine next to
an 8ms one at 60; it is the resolution SDL reports and there is no finer one to take
without changing what `getTimer` means to the whole of lime and openfl.

## Applying it

`setup/patch-lime.sh` does the whole thing - finds the installed lime, checks it is
8.1.2, applies the patch once, and rebuilds the native library for whichever
architecture it is handed:

```bash
./setup/patch-lime.sh -Dandroid -DHXCPP_ARM64 -DPLATFORM=android-21
./setup/patch-lime.sh -Dwindows -DHXCPP_M64
```

Those flags are exactly what `lime rebuild` would have passed. Going through hxcpp
directly is what makes one architecture possible: `lime rebuild android` builds four,
three of which nothing here ships.

Then build the game with `-D PATCHED_LIME`, which is what turns `PRECISE_INPUT` on in
`Project.xml`. Both CI workflows do all of this; see `.github/workflows/android.yml`.

## Rebuilding - the expensive part

Patching the source changes nothing on its own. `include.xml` has:

```xml
<ndll name="lime" if="native" unless="lime-console static_link || lime-switch static_link" />
```

so native targets link a **prebuilt** binary, and `haxelib install lime` ships those
already built. The patched C++ has to replace them, per platform, which is a long
build and a fresh failure surface.

So the CI step is allowed to fail. If it does, the build simply goes ahead without
`-D PATCHED_LIME` and the game falls back to the half-frame estimate in
`PlayState.pressLag()`.

A rebuild that fails *after* the patch applied is harmless in its own right: the native
side then never writes `timestamp`, the field stays at zero, `PreciseInput` reads that
as "nothing to say" and returns zero. What would not survive is the patch failing to
apply while the game is still built with `-D PATCHED_LIME` - `onKeyDownPrecise` would
not exist and nothing would compile - which is why the flag is tied to that step
succeeding.

## What it is worth

It removes the jitter that the half-frame correction in `PlayState.pressLag()` cannot:
that correction takes off the average lean, this would take off the spread either side of
it. At 120fps the spread is roughly four milliseconds either way, inside a 45ms Sick
window. At 60fps it is twice that and more worth having.

**It does not touch audio latency.** The delay between the engine playing a sound and a
phone's speaker producing it is a different number and a larger one, and the offset
calibration under Options is what measures it. Precise input is about when a press is
read, not when a sound is heard.

## Status

Applied and wired in. `setup/patch-lime.sh` does the work, both CI workflows call it,
and `source/backend/PreciseInput.hx` is what reads the result.

None of it was testable where it was written - no Haxe toolchain, no NDK - so the first
run of each workflow is the first time any of it has been compiled.

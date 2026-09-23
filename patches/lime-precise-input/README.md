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

Two things, because one is not enough:

1. **Carries the event's timestamp through** - C++ struct, the CFFI marshalling, the Haxe
   `KeyEventInfo`, and two new `onKeyDownPrecise` / `onKeyUpPrecise` signals on `Window`.

2. **Adds a clock worth comparing it to.** `System::GetTimer` returns `SDL_GetTicks`,
   which counts whole milliseconds; so does SDL's event timestamp. Against an effect worth
   about four milliseconds that is too coarse to measure. The patch adds a separate
   nanosecond reading from `SDL_GetPerformanceCounter` rather than changing GetTimer's
   units, which the whole of lime and openfl depend on.

## Applying it

```bash
haxelib install lime 8.1.2          # if it isn't already
cd $(haxelib libpath lime)
git apply /path/to/lime-8.1.2-precise-input.patch
```

The patch is written against 8.1.2, the version `setup/android.sh` pins.

## Rebuilding - the expensive part

Patching the source changes nothing on its own. `include.xml` has:

```xml
<ndll name="lime" if="native" unless="lime-console static_link || lime-switch static_link" />
```

so native targets link a **prebuilt** binary, and `haxelib install lime` ships those
already built. The patched C++ has to replace them, per platform:

```bash
haxelib run lime rebuild windows     # needs MSVC
haxelib run lime rebuild android     # needs the NDK; arm64 and armv7 are separate
```

Both are long. On CI this is a new stage on top of a pipeline that already takes a while,
and it is a fresh failure surface - a broken rebuild takes the Android build with it.

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

Not applied, not wired into the build. The patch is here so the decision can be made
against a real diff rather than a guess, and because none of it is testable from the
container this was written in - no Haxe toolchain, no NDK, no way to know whether the
rebuild even succeeds before CI says so.

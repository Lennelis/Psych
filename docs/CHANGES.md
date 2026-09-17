# What this branch changes

Two additions on top of stock Psych Engine 1.0.4, both borrowed from V-Slice.

## The strumline behaves like V-Slice's

`source/objects/StrumNote.hx`, `source/states/PlayState.hx`

Psych splits a sustain into one piece per step and plays `confirm` again on each of
them, so the bright first frame of the glow re-fires the whole way through a hold.
V-Slice instead lets the glow run once, follows it with `confirm-hold`, and leaves
that frozen on its last frame until the hold is over. `confirm-hold` is registered
from the `confirm` animation's own frames, so a note skin only ever has to define the
one — pixel and sparrow alike, and every existing skin keeps working untouched.

Three other pieces of that behaviour come with it:

- A tapped note holds its glow for `CONFIRM_HOLD_TIME` (0.15s, V-Slice's number)
  after the animation finishes before dropping back, while a **hold** drops the
  instant it runs out. That difference in timing is the point of it.
- A held key never sits on `static`; it rests on `pressed`, re-checked every frame.
- `keyPressed` treats `confirm-hold` as lit, so tapping another lane mid-hold no
  longer drops this one back to the ghost tap.

`PlayState` feeds that with per-lane bookkeeping in `keysCheck`: which lanes had a
piece land this frame, which still have pieces coming, and when each hold ends.

### Where a hold ends, and the delay that came from getting it wrong

The end of a hold is anchored to the trail, not to a time. `Note.clipToStrumNote`
eats a sustain from the strum's **centre** — half a note height below its top — and
only upscroll gets the matching `correctionOffset` that cancels that out
(`sustainNote.correctionOffset = swagNote.height / 2`, set to 0 on downscroll). So on
downscroll the trail is gone half a note height *before* `strumTime + sustainLength`,
and pinning the strum to that time leaves it lit with nothing left to hold — a delay
that grows as scroll speed drops (~90ms at speed 2, ~180ms at speed 1).

`holdTailConsumed()` mirrors the condition that empties the clip rect instead, so the
strum drops exactly when the last of the trail does, in either direction at any
speed. The chart-time check stays as an upper bound, so it can only ever shorten the
tail end of a hold — never drop one early, never revive one, and never misjudge a
hold longer than the note spawn window.

Worth recording what this *wasn't*, since it was the obvious suspect: pieces are laid
out at `step * i` for `i in 0...round(length / step)`, so a hold whose length isn't a
whole number of steps ends up to half a step off. Measured across the base-game
charts, 3402 of 3493 holds are step-exact — 26 late, 65 early — so that rounding
explains almost nothing.

`openPauseMenu` already resets the player's strums, so it clears this bookkeeping too
— otherwise resuming mid-hold would light a glow for a hold long gone.

## Smooth health bar

`source/states/PlayState.hx`, plus the pref and its toggle

The bar slides to its new value instead of snapping. **Options → Visuals → Smooth
Health Bar**, on by default.

Only what the bar *shows* is smoothed. `health` itself is untouched, so dying
(`health <= 0`), scoring and every script that reads it behave exactly as before —
the bar merely catches up. The icons follow, since they already track
`healthBar.barCenter` and `healthBar.percent`; their faces are refreshed from
`updateHealthLerp` as well as `set_health`, because with smoothing the bar's percent
moves on frames where `health` itself didn't change.

V-Slice moves its bar 15% of the remaining distance per frame, which is a half-life
of about 71ms at 60fps. A per-frame lerp smooths faster the higher the framerate,
though, and Psych lets the player pick one — so the same feel is expressed here as a
half-life (`HEALTH_HALF_LIFE`, exponential decay, the shape of V-Slice's
`MathUtil.smoothLerpDecay`), which behaves identically at 60, 144 or uncapped.

## Building

`.github/workflows/windows.yml` builds the Windows zip on this branch. It had to be
`git add -f`'d, because stock Psych's `.gitignore` ignores `.github/` wholesale —
`main.yml` is only in the repo because it predates that line. The repo's own
`main.yml` builds Linux, Windows and macOS but only triggers on `main` and
`experimental`, so it stays dormant here; this is the same Windows job pointed at this
branch.

`-D officialBuild` is load-bearing and is kept: `Project.xml` hangs `BASE_GAME_FILES`
and `VIDEOS_ALLOWED` off it, so a build without it ships with no week 1–7 songs. The
only side effect is that the update check and the crash-report link stay switched on,
both pointing at upstream Psych.

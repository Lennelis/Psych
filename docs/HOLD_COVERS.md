# Hold covers

The glow that sits over a strum while a sustain is being held, ported from V-Slice
(`funkin.play.notes.NoteHoldCover`).

Three animations per colour make one cover:

| Animation | When it plays |
| --- | --- |
| **start** | The hold is taken. Plays once. |
| **hold** | Straight after the start, and loops for as long as the hold runs. |
| **end** | The hold was played all the way to its end. Plays once, then the cover disappears. |

Drop a hold early and the cover vanishes on the spot - no end animation. Only holding
one to the end earns it, which is what makes the end read as a reward rather than as
punctuation.

The opponent gets covers too. Theirs start and loop the same way but vanish at the end
instead of playing it out, matching what V-Slice does with `isPlayer`.

## The art

Four Sparrow sheets, one per note colour, in `assets/shared/images/holdCovers/`:
`holdCoverPurple`, `holdCoverBlue`, `holdCoverGreen`, `holdCoverRed`, each a `.png` and
an `.xml`. The colour names are Psych's own lane names (`Note.colArray`) in title case,
so left is purple, down is blue, up is green and right is red.

The sheets that ship here have one start frame, four loop frames and eight end frames
each, all drawn on a 300x400 canvas.

A missing sheet is not an error: that lane simply gets no cover, and a game with none of
the four behaves exactly as it did before the feature existed.

**Animation prefixes.** These are tried in order, so art named the way V-Slice names it
needs no configuration at all:

- start: `holdCoverStartPurple`, `holdCoverStart`, `hold cover start Purple`, `hold cover start`, `start`
- hold: `holdCoverPurple`, `holdCoverHoldPurple`, `holdCoverHold`, `hold cover hold Purple`, `hold cover Purple`, `hold cover hold`, `hold`, `loop`
- end: `holdCoverEndPurple`, `holdCoverEnd`, `hold cover end Purple`, `hold cover end`, `end`, `explode`

The looping **hold** animation is the only one a cover cannot do without - it is what is
on screen for all but a few frames. Without it the sheet is ignored; without a start or
an end, the cover skips straight to the loop or straight to disappearing.

## Pixel stages

A pixel stage looks for `holdCoverPurple-pixel` and friends first, then falls back to a
single `pixelNoteHoldCover` sheet used by every lane - which is what ships here, since
the pixel cover is a few white sparks with nothing colour about it. It has no start
animation, so those covers open straight into the loop.

Pixel stages also get their own note splashes now. Any splash skin can bring a `-pixel`
sheet along and it will be picked up on a pixel stage automatically:
`noteSplashes-pixel` sits beside `noteSplashes` and is used in its place. Before this,
a pixel stage got the ordinary splash run through the pixelate shader, which is an
impression of pixel art rather than the thing itself.

## Tuning them

`assets/shared/images/holdCovers/holdCover.json`, all of it optional:

```json
{
  "scale": 1,
  "fps": 24,
  "offsets": [-10, 50],
  "pixel": { "scale": 6, "fps": 24, "offsets": [27.5, 0.5], "antialiasing": false },
  "colors": {
    "Purple": {
      "offsets": [0, -4],
      "animations": { "start": "myStartPrefix", "hold": "myHoldPrefix", "end": "myEndPrefix" }
    }
  }
}
```

- Top level applies to every cover. A `pixel` block overrides it when a pixel sheet is
  in use, and a `colors` entry overrides both for that one colour - which can also name
  the animation prefixes outright when a sheet uses something the list above won't guess.
- `offsets` is measured from the strum's centre, in the **sheet's own pixels**: they are
  multiplied by `scale`, the same way V-Slice applies its hold cover offsets. A cover
  follows its strum, so tweens and modcharts move it too.
- The shipped `[-10, 50]` is not decoration. The art is not centred on its own 300x400
  canvas - the loop's glow sits about 10px right of centre and 50px above it - so those
  numbers are what put the glow on the strum rather than up and to the right of it. The
  pixel sheet's `[27.5, 0.5]` is the same correction for its 200x59 canvas.
- `antialiasing` can only ever turn it *off*; the player's own antialiasing setting
  still wins.

On desktop a mod can replace any of these files from its own `images/holdCovers/`
folder, the same as note splashes. Mods are compiled out on mobile (see
[MOBILE.md](MOBILE.md)), so a mobile build uses the bundled sheets.

## Options

Visuals settings:

- **Hold Covers** - on by default. Off skips building the covers entirely, so there is
  nothing loaded and nothing drawn.
- **Hold Cover Opacity** - 100% by default, since the art is drawn at the opacity its
  artist intended. Turn it down to keep the covers without having them shout.

## How it hooks in

Psych splits a sustain into one piece per step and hits each as it arrives, so "the
hold is still going" is not a thing the note objects say directly. `PlayState` already
tracks it per lane for the strum's ghost tap behaviour, and the covers ride on the same
state:

- `startHoldCover()` is called from `goodNoteHit` and `opponentNoteHit`. It ignores
  notes with no sustain, and does nothing if that lane's cover is already up - so a hold
  begun by its head, begun by a piece with Guitar Hero sustains switched off, or played
  by the bot, all start one unbroken loop.
- `updateHoldCovers()` ends it: `playEnd()` once the song reaches the sustain's charted
  end, `stopCover()` the moment `wasHoldingSustain` says the player let go. The bot is
  exempt from the drop check, because it never does.

One cover is built per strum and lives as long as it does, so a hold never waits on a
pool and a lane's sheet is loaded once. They draw above the notes, which is what lets a
cover hide the end of the trail underneath it.

Nothing is exposed to Lua or HScript yet.

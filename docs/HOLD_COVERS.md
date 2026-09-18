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

That sheet is drawn at scale 4 with a framerate of 33, and **blended with `screen`** -
all three taken from V-Slice's own `pixel.json` note style. The blend is not decoration:
about an eighth of the sheet's opaque pixels are near-black outlines, and drawn normally
they sit on the arrow as black blobs. Screen turns them into light instead. Splash
configs therefore take a `blend` field now - `add`, `screen`, `multiply` or `subtract`,
the four the hardware renderer actually implements; anything else draws normally.

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
- The shipped `[-11.6, 45.8]` is not decoration. The art is not centred on its own
  300x400 canvas - the loop's glow sits about 9px right of centre and 51px above it - so
  those numbers are what put the glow on the strum rather than up and to the right of it.
  They are V-Slice's placement, worked back out of it: with the note style's own offsets
  at `[0, 0]`, `Strumline.playNoteHoldCover` and `INITIAL_OFFSET` put the cover 2.3px
  left of the receptor's centre and 5.6px above it, and all four lanes agree on that to
  within a pixel. The pixel sheet's `[27.8, 0.1]` is the same figure for its 200x59
  canvas, and lands on the same answer from completely different numbers.
- `antialiasing` can only ever turn it *off*; the player's own antialiasing setting
  still wins.

A mod can replace any of these files from its own `images/holdCovers/` folder, the
same as note splashes, on desktop and on mobile alike.

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
- `updateStrumHoldState()` ends it, in the same branch that drops the strum to its ghost
  tap: `playEnd()` for a hold carried to its end, `stopCover()` for one let go of early.
  `updateHoldCovers()` only picks up what that never saw - the opponent's covers, and the
  player's under botplay or a cutscene, where there is no key to release and the chart's
  end is the whole story.

**One decision, one frame, both effects.** This is the shape V-Slice uses - glow and
cover come off a single condition in `Strumline.updateNotes` - and it is worth spelling
out why, because the obvious alternative was tried and it is subtly wrong.

Asking the strum and the cover separately means two answers to "is this hold over". The
strum follows the trail; the cover followed the chart. Those are not the same instant,
because Psych's trail runs short: every sustain piece is stretched to cover one step
except the end cap, which `resizeByRatio` deliberately leaves at its art height. The
trail therefore covers `(roundSus - 1)` steps plus whatever that cap is worth, and the
difference is a fixed number of pixels against a length of time - so it moves with the
BPM and the scroll speed. Tens of milliseconds, different in every song, which is exactly
how it read: something slightly off that you could not point at.

The decision also runs *after* the note loop rather than inside `keysCheck`, because it
asks where the last of the trail is and nothing has moved the notes yet at that point in
the frame. `keysCheck` hands its findings on instead of acting on them.

One cover is built per strum and lives as long as it does, so a hold never waits on a
pool and a lane's sheet is loaded once. They draw above the notes, which is what lets a
cover hide the end of the trail underneath it.

Nothing is exposed to Lua or HScript yet.

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

## Adding the art

Four Sparrow sheets, one per note colour, under `assets/shared/images/holdCovers/`:

```
assets/shared/images/holdCovers/holdCoverPurple.png
assets/shared/images/holdCovers/holdCoverPurple.xml
assets/shared/images/holdCovers/holdCoverBlue.png
assets/shared/images/holdCovers/holdCoverBlue.xml
assets/shared/images/holdCovers/holdCoverGreen.png
assets/shared/images/holdCovers/holdCoverGreen.xml
assets/shared/images/holdCovers/holdCoverRed.png
assets/shared/images/holdCovers/holdCoverRed.xml
```

The colour names are Psych's own lane names (`Note.colArray`) in title case, so left is
purple, down is blue, up is green and right is red.

A sheet that is missing is not an error: that lane simply gets no cover, and a game
with none of the four behaves exactly as it did before the feature existed. That is
also why this can be added to the repo before the art is.

**Animation prefixes.** Each sheet needs the three animations above. These prefixes are
tried in order, so art exported from V-Slice or named the obvious way needs no config:

- start: `holdCoverStartPurple`, `holdCoverStart`, `hold cover start Purple`, `hold cover start`, `start`
- hold: `holdCoverPurple`, `holdCoverHoldPurple`, `holdCoverHold`, `hold cover hold Purple`, `hold cover Purple`, `hold cover hold`, `hold`
- end: `holdCoverEndPurple`, `holdCoverEnd`, `hold cover end Purple`, `hold cover end`, `end`

The looping **hold** animation is the only one a cover cannot do without - it is what is
on screen for all but a few frames. Without it the sheet is ignored; without a start or
an end, the cover skips straight to the loop or straight to disappearing.

**Pixel stages** use `holdCoverPurple-pixel` and friends when those exist, and fall back
to the normal sheets otherwise. Antialiasing is off for them either way.

## Tuning them

Everything below is optional. `assets/shared/images/holdCovers/holdCover.json`:

```json
{
  "scale": 1.0,
  "fps": 24,
  "offsets": [0, 0],
  "antialiasing": true,
  "colors": {
    "Purple": {
      "offsets": [0, -4],
      "animations": { "start": "myStartPrefix", "hold": "myHoldPrefix", "end": "myEndPrefix" }
    }
  }
}
```

- `scale`, `fps`, `offsets` and `antialiasing` apply to every colour.
- Anything inside `colors` overrides them for that one colour, and can name the
  animation prefixes outright when the sheet uses something the list above won't guess.
- `offsets` is measured in pixels from the strum's centre, which is where a cover sits
  by default. It follows the strum, so tweens and modcharts move it too.
- `antialiasing` is only ever able to turn it *off* - the player's own antialiasing
  setting still wins.

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

Nothing is exposed to Lua or HScript yet.

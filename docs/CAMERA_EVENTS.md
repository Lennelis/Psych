# Camera events

V-Slice's two camera song events, `ZoomCamera` and `FocusCamera`, ported to Psych as
**Zoom Camera** and **Focus Camera** — with the ease curve drawn in the chart editor so
you can see the move without playing the song.

* [Writing them](#writing-them)
  * [Zoom Camera](#zoom-camera)
  * [Focus Camera](#focus-camera)
  * [Easing](#easing)
* [Seeing them in the chart editor](#seeing-them-in-the-chart-editor)
* [How they drive Psych's camera](#how-they-drive-psychs-camera)

---

## Writing them

V-Slice gives each event a named field per parameter. Psych events carry two free-text
values, so the fields are packed comma-separated — the same shape `Screen Shake` already
uses. The split is consistent across both events:

* **Value 1** — *what* to move to.
* **Value 2** — *how* to get there: `duration, ease`.

Duration is in **steps**, like V-Slice, and defaults to `4`. All of the parsing lives in
`source/backend/CameraEvents.hx`, which is also what the chart editor reads, so the
preview can't drift away from what actually plays.

### Zoom Camera

Value 1 is the zoom, optionally followed by a mode:

| Value 1 | Meaning |
| --- | --- |
| `1.2` | Zoom to 1.2x. Absolute. |
| `1.2, direct` | The same thing said out loud. |
| `1.2, stage` | 1.2x *the stage's own zoom* — a fifth closer than this stage normally sits. |

Stage mode reads off the zoom the stage asked for, not wherever an earlier event left the
camera, so `1, stage` always means "back to normal for this stage" no matter what came
before it.

```
Zoom Camera    1.3           8, quadOut       # swoop in over half a bar
Zoom Camera    1, stage      4, quadIn        # and back out again
Zoom Camera    0.9           0, instant       # snap out, no tween
```

Beat bops still land on top of an authored zoom — it moves the level the bops punch away
from and decay back to, not the camera directly.

### Focus Camera

Value 1 is who to look at, optionally followed by an offset:

| Value 1 | Meaning |
| --- | --- |
| *(blank)* | Give the camera back to the section logic. |
| `bf` | Boyfriend, exactly where a player section would put the camera. |
| `dad` | The opponent. |
| `gf` | Girlfriend. |
| `bf, 0, -60` | Boyfriend, nudged 60px up. |
| `pos, 600, 400` | The point (600, 400), ignoring everyone. |

`boyfriend`/`player`, `opponent`, `girlfriend` and `position` all work too.

**Numbers follow V-Slice's, not Psych's.** `0` is boyfriend, `1` is the opponent, `2` is
girlfriend, `-1` is a position — so a chart converted from V-Slice lands right. Psych's
`Play Animation` numbers them the other way round (0 is dad), which is exactly why the
names are the better thing to write.

```
Focus Camera   dad           4, sineOut
Focus Camera   pos, 640, 360 16, expoInOut    # drift to centre over a bar
Focus Camera                 0, classic       # hand it back
```

Focusing holds the camera until something gives it back — a blank `Focus Camera`, a
`classic` one, or a blank `Camera Follow Pos`. That's the same latch those events already
used (`isCameraOnForcedPos`), so sections won't yank the camera away mid-move.

### Easing

Any name `LuaUtils.getTweenEaseByString` knows: `linear`, `sineIn`, `quadOut`,
`cubeInOut`, `quartOut`, `quintIn`, `expoInOut`, `circOut`, `backIn`, `bounceOut`,
`elasticInOut`, `smoothStepOut`, `smootherStepInOut`, and the rest. An unrecognised name
falls back to `linear` rather than failing.

Two names aren't eases:

* `instant` — snap. Duration is ignored.
* `classic` — Focus Camera only. Snap **and** let go of the camera, the way charts behaved
  before this event existed. This is V-Slice's `CLASSIC`.

---

## Seeing them in the chart editor

Add one of these events and the curve appears under its icon in the event column, running
down the exact number of steps the tween will take.

Time runs down. The curve's horizontal position is how far through the move you are at
that moment — left edge is where it started, right edge is where it ends up. So:

* `linear` is a straight diagonal.
* `quadOut` leans hard to the right early, then creeps.
* `backInOut` and `elastic*` visibly bulge past both edges, which is the overshoot.

Zoom events draw warm, focus events cool, so a chart using both stays readable. The event
text also gains a plain-language line — `zoom 1.3x absolute - 8 steps, quadout`,
`focus opponent (0, -60) - 4 steps, sineout` — which is the parse talking, so if you typo
an ease name you'll see it say `linear` there.

Instant and classic moves draw nothing, because there's no curve to draw.

---

## How they drive Psych's camera

Worth knowing if you're scripting against them, because Psych's camera doesn't work the
way V-Slice's does.

**Zoom** moves `defaultCamZoom`, not `FlxG.camera.zoom`. Psych bops the camera by adding
to `FlxG.camera.zoom` each beat and lerping it back toward `defaultCamZoom` every frame —
setting the zoom directly would just be undone on the next frame. Moving the resting value
is the equivalent of V-Slice tweening its `currentCameraZoom`, and it keeps the bops
working. The one wrinkle: that decay only runs when `camZooming` is on, so while a zoom
tween is live and bops are off, the zoom is applied straight instead.

**Focus** tweens `FlxG.camera.scroll` directly and stops the camera following for the
duration, restoring it on completion. Psych normally chases `camFollow` with a soft lerp,
and chasing an eased point with a lerp gives you neither curve — the ease you asked for
has to be the ease you get. V-Slice nulls its camera target for the same reason.

The helpers are on `PlayState` and are public, so scripts can use them directly:

```haxe
tweenCameraZoom(zoom, durationSeconds, stageRelative, ease);
tweenCameraToPosition(x, y, durationSeconds, ease);
tweenCameraToFollowPoint(durationSeconds, ease);
cancelCameraZoomTween();
cancelCameraFollowTween();
```

Note those take **seconds**, not steps — the events convert. `stageDefaultZoom` holds what
the stage asked for, separately from `defaultCamZoom`.

Both tweens are ordinary `FlxTween`s, so they pause with the game and are cleared on death
along with everything else.

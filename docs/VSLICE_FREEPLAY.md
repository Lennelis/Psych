# The V-Slice freeplay menu

A port of Funkin' V-Slice's freeplay menu, running on Psych's songs. It sits alongside
Psych's own menu rather than replacing it: **Options → Visuals → Freeplay Menu**, set to
`V-Slice`.

The layout, timings and numbers are V-Slice's, kept deliberately — the capsule at
`270 + 60·sin(index)`, the seven frames of squash it jumps in on, the 0.8 everything is
scaled by, the 0.6s the card takes to slide in. What sits behind them is Psych's.

## What it is built out of

V-Slice reads its song list from registries where every song carries an album, a
character, a difficulty rating and per-difficulty scores with note tallies. Psych has
none of that. A song is a line in a week file and `Highscore` remembers a score and an
accuracy, so the port maps what exists and derives the rest:

| Capsule shows | Comes from |
| --- | --- |
| Title | The song's name in the week file |
| Icon | The song's health icon — so a mod's own icons appear here with no work |
| Week label | The week's file name, `week4` printed as `week 4` |
| BPM | Read out of the chart, on demand |
| Rank badge | Derived from the saved accuracy |
| Score | `Highscore.getScore` |
| Difficulty number | The difficulty's place in the list |

Two of those are worth expanding on.

**Ranks.** V-Slice works a rank out from note tallies: a full clear of sicks is gold,
otherwise `(sick + good - miss) / notes` against four thresholds. Psych saves an accuracy
and nothing else, so the accuracy stands in for that ratio and the thresholds are
V-Slice's own — 90% excellent, 80% great, 60% good. 100% is gold, which in Psych means
every note was hit at full rating: the same thing gold is asking for.

**BPM.** Only the selected capsule shows one, and it is read from the chart the first
time it is asked for and then kept. Opening every chart in the game up front to fill in a
number would cost seconds on a phone.

## What Psych has that V-Slice doesn't

Difficulties belong to a **week** in Psych, so the list of them changes as you scroll —
one song offering easy/normal/hard and the next offering four of its own. V-Slice has one
list for the whole game and never has to deal with this, so `applyDifficultyList()` swaps
`Difficulty.list` on every selection change and keeps the chosen difficulty if the new
week also has it. Difficulty sprites are made once per name and kept, since a mod week
with its own names would otherwise reload art on every keypress. A difficulty with no art
of its own — anything that isn't easy, normal, hard, erect or nightmare — is drawn as
text in the same place.

## Shaders

Five of V-Slice's shaders came across. `AngleMask`, `PureColor`, `StrokeShader` and
`BlueFade` needed only their package changed. `HSVShader` and `GaussianBlurShader` are
compiled in with `@:glFragmentSource` rather than loaded from `.frag` at runtime: the
maths is unchanged, but a compile-time shader works whether or not runtime shaders are
switched on, and the capsules need theirs wherever they are drawn.

`Grayscale` came across too and then went away again. V-Slice's capsule builds one and
sets its amount as the selection moves, but never attaches it to anything — the greyed
out look is a second set of frames on the capsule sheet, drawn that way. Porting the
shader would have been porting dead code.

## Not here yet

The DJ, the album roll, the letter sort, the flames and the rank-up animation. The menu
works without them and they hang off the same points V-Slice hangs them off:
`introDone()`, `changeSelection()` and `confirmSelection()`. The art for all of them is
already in `assets/shared/images/freeplay/`, including the DJ, album and sorted letters,
which are Animate atlases — `flxanimate` ships with Psych, so they can be played as they
are.

Also missing: touch swiping (the pad works), per-week backing art, and favourites, which
are stored and drawn but not yet bound to a button.

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

## How closely it follows the original

Closely, and on purpose. `VSliceFreeplayState` keeps V-Slice's order of operations, its
field names and its numbers, because the parts that are easy to paraphrase wrongly turn
out to be exactly the parts that look wrong — which sprite leaves in which direction,
when the capsules learn where they are going, how far the difficulty slides. Three bugs
came out of paraphrasing before this was rewritten as a replica:

- the capsules spent the intro sliding into a heap, because `changeSelection()` — which
  is what sets their targets — was called a second later than V-Slice calls it
- half the menu stayed on screen when leaving, because the list of what moves was four
  hand-picked tweens instead of V-Slice's `exitMovers` map
- the capsules wouldn't leave at all, because `doLerp` kept pulling them back; V-Slice
  switches it off on the line above `doJumpOut`

`exitMovers` is now what it is there: a map from a group of sprites to where they go,
built as the menu is built, so a sprite that is added is a sprite that leaves.

The deliberate departures are marked in the source. There are three. The card's
scrolling text and glows leave with the card, because Psych's state switch is slower
than V-Slice's and the text was left hanging on an empty screen. The RANDOM capsule
arrives visible rather than at alpha zero, since V-Slice has the DJ's hand reveal it and
there is no DJ yet. And the menu's own background is drawn behind the card, because
V-Slice opens freeplay as a substate over the main menu, where Psych switches states and
would otherwise show black.

## What Psych has that V-Slice doesn't

Difficulties belong to a **week** in Psych, so a difficulty *number* means nothing on its
own: `1` is `hard` in one week and something else in the next. V-Slice keys everything by
name, which turns out to be the right shape for this — the menu holds a name, and
anything that needs Psych's number asks `FreeplaySongData.difficultyIndex()`, which
points `Difficulty` at that song's week first so the number and the list agree.

`allDifficulties` — every difficulty any song has, in the order they were first met —
stands in for V-Slice's game-wide list. The arrows cycle through it, and when the song
you are on hasn't got what you landed on, `findClosestDiff` moves to the nearest song
that has, exactly as V-Slice does. A difficulty with no art of its own — anything that
isn't easy, normal, hard, erect or nightmare — is drawn as text in the same place.

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

The rank-up animation that plays when you come back from a song with a better grade,
character select and its cards, and the per-character freeplay styles.

Also missing: swiping and dragging the capsule list (the pad, the arrows and taps on the
letters all work), per-week backing art, and favourites, which are stored, drawn and
filterable but not yet bound to a button.

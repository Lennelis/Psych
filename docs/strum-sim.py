#!/usr/bin/env python3
"""
Where V-Slice's mobile Arrows scheme actually puts the receptors, and what Psych
has to do to land in the same place.

Both engines are walked through with their own arithmetic and their own sheets,
and the only thing compared at the end is where the *visible arrow* lands - which
is the whole difficulty, because the two sheets pad their frames differently and
each engine positions by the frame, not by the art.

V-Slice   funkin/play/notes/Strumline.hx, funkin/play/PlayState.initNoteHitbox,
          funkin/util/Constants.hx, preload/data/notestyles/funkin.json,
          shared/images/noteStrumline.xml
Psych     states/PlayState.generateStaticArrows + placeArrowsStrum,
          objects/StrumNote.reloadNote,
          assets/shared/images/noteSkins/NOTE_assets.xml
"""

# ---------------------------------------------------------------------------
# Sheets
# ---------------------------------------------------------------------------

# noteStrumline.xml, staticLeft0001: the art is 154x157 inside a 232x236 frame,
# sitting 37 in and 38 down. Flixel sizes a sprite by the frame, so every V-Slice
# receptor carries that padding around with it.
VS_ART_W, VS_ART_H = 154.0, 157.0
VS_FRAME_W, VS_FRAME_H = 232.0, 236.0
VS_PAD_X, VS_PAD_Y = 37.0, 38.0

# NOTE_assets.xml, arrowLEFT0000: 154x157 and no frame padding at all, so a Psych
# receptor's x/y IS the top left of the arrow you can see.
PS_ART_W, PS_ART_H = 154.0, 157.0

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

STRUMLINE_SIZE = 104
NOTE_SPACING = STRUMLINE_SIZE + 8          # 112
INITIAL_OFFSET = -0.275 * STRUMLINE_SIZE   # -28.6
STRUMLINE_X_OFFSET = 48.0
STRUMLINE_Y_OFFSET = 24.0
KEY_COUNT = 4

NOTE_STYLE_SCALE = 0.7                     # notestyles/funkin.json -> noteStrumline.scale
PSYCH_SCALE_BASE = 0.7                     # StrumNote.reloadNote: setGraphicSize(width * 0.7)

SPLIT = 35.0                               # Strumline.getXPos, Arrows + isPlayer only
MINI = 0.4                                 # enterMiniMode

INITIAL_W, INITIAL_H = 1280.0, 720.0


def vslice(screen_w, screen_h, android=True, pixel=False):
    """initNoteHitbox, step by step."""
    amp = (screen_w / screen_h) / (INITIAL_W / INITIAL_H)

    strum_scale = (screen_h / screen_w) * 1.95 * amp   # -> 1.95 * 720/1280, aspect cancels
    spacing_scale = (screen_h / screen_w) * 2.8 * amp  # -> 2.8  * 720/1280

    # strumlineScaleCallback: note.scale = styleScale * strumlineScale
    scale = NOTE_STYLE_SCALE * strum_scale

    # get_width() is overridden: four whole cells, never the group's bounds.
    width = KEY_COUNT * NOTE_SPACING * spacing_scale * strum_scale
    group_x = (screen_w - width) / 2 + STRUMLINE_X_OFFSET

    # get_height() is the group's bounds with the background explicitly skipped
    # (findMinYHelper/findMaxYHelper), so it is one receptor's FRAME height.
    frame_h = VS_FRAME_H * scale
    group_y = (screen_h - frame_h) * 0.95 - STRUMLINE_Y_OFFSET
    if pixel:
        group_y -= 10
    elif android:
        group_y += 10

    # getXPos: left and down shoved out by 2*pos, up and right in by pos.
    pos = SPLIT * amp
    cell = NOTE_SPACING * spacing_scale * strum_scale
    lanes = [-pos * 2, -pos * 2 + cell, pos + cell * 2, pos + cell * 3]

    out = []
    for lane in lanes:
        frame_x = group_x + lane + INITIAL_OFFSET
        out.append({
            'art_x': frame_x + VS_PAD_X * scale,
            'art_y': group_y + VS_PAD_Y * scale,
            'art_w': VS_ART_W * scale,
            'art_h': VS_ART_H * scale,
        })
    return out, {'scale': scale, 'cell': cell, 'group_x': group_x, 'group_y': group_y,
                 'frame_h': frame_h, 'amp': amp, 'pos': pos}


def psych(screen_w, screen_h, android=True, pixel=False, y_model='vslice'):
    """placeArrowsStrum, with the correction being tested.

    Psych's receptor is left at its own size; what is matched is where the middle
    of the arrow lands, since the two sheets disagree about how big an arrow is.
    """
    amp = (screen_w / screen_h) / (INITIAL_W / INITIAL_H)
    strum_scale = 1.95 * (INITIAL_H / INITIAL_W)
    spacing_scale = 2.8 * (INITIAL_H / INITIAL_W)

    # StrumNote.reloadNote: setGraphicSize(Std.int(width * 0.7)) - the truncation is real.
    scale = int(PS_ART_W * PSYCH_SCALE_BASE) / PS_ART_W
    w, h = PS_ART_W * scale, PS_ART_H * scale

    # V-Slice's own receptor, as a set of numbers rather than as a sprite.
    vs_scale = NOTE_STYLE_SCALE * strum_scale
    vs_frame_h = VS_FRAME_H * vs_scale
    vs_art_top = VS_PAD_Y * vs_scale
    vs_art_w, vs_art_h = VS_ART_W * vs_scale, VS_ART_H * vs_scale

    cell = NOTE_SPACING * spacing_scale * strum_scale
    group_x = (screen_w - cell * KEY_COUNT) / 2 + STRUMLINE_X_OFFSET

    if y_model == 'sprite':          # what the code did before
        group_y = 0.0
        y = (screen_h - h) * 0.95 - STRUMLINE_Y_OFFSET
        if pixel:
            y -= 10
        elif android:
            y += 10
    else:
        group_y = (screen_h - vs_frame_h) * 0.95 - STRUMLINE_Y_OFFSET
        if pixel:
            group_y -= 10
        elif android:
            group_y += 10
        y = group_y + vs_art_top + (vs_art_h - h) / 2

    pos = SPLIT * amp
    lanes = [-pos * 2, -pos * 2 + cell, pos + cell * 2, pos + cell * 3]
    nudge = 0.0 if y_model == 'sprite' else (vs_art_w - w) / 2

    return [{'art_x': group_x + lane + nudge, 'art_y': y,
             'art_w': w, 'art_h': h} for lane in lanes], {'scale': scale}


def report(title, screen_w, screen_h, **psych_kwargs):
    vs, vm = vslice(screen_w, screen_h)
    ps, pm = psych(screen_w, screen_h, **psych_kwargs)

    print(f'\n{title}  ({screen_w:.0f}x{screen_h:.0f})')
    print(f'  scale      V-Slice {vm["scale"]:.4f}   Psych {pm["scale"]:.4f}')
    print(f'  arrow      V-Slice {vs[0]["art_w"]:.1f}x{vs[0]["art_h"]:.1f}'
          f'   Psych {ps[0]["art_w"]:.1f}x{ps[0]["art_h"]:.1f}')
    print(f'  {"lane":<6}{"V-Slice cx":>12}{"Psych cx":>11}{"dx":>8}'
          f'{"V-Slice cy":>13}{"Psych cy":>11}{"dy":>8}')
    for name, a, b in zip(['left', 'down', 'up', 'right'], vs, ps):
        acx, acy = a['art_x'] + a['art_w'] / 2, a['art_y'] + a['art_h'] / 2
        bcx, bcy = b['art_x'] + b['art_w'] / 2, b['art_y'] + b['art_h'] / 2
        print(f'  {name:<6}{acx:>12.1f}{bcx:>11.1f}{bcx-acx:>8.1f}'
              f'{acy:>13.1f}{bcy:>11.1f}{bcy-acy:>8.1f}')


if __name__ == '__main__':
    print('=' * 78)
    print('AS IT STANDS  - Psych sized 0.7 and positioned by its own sprite height')
    print('=' * 78)
    report('16:9', 1280, 720, y_model='sprite')
    report('20:9 phone', 1600, 720, y_model='sprite')

    print()
    print('=' * 78)
    print("CORRECTED     - Psych's own arrow, centred on where V-Slice's lands")
    print('=' * 78)
    report('16:9', 1280, 720, y_model='vslice')
    report('20:9 phone', 1600, 720, y_model='vslice')

    print()
    vs_scale = NOTE_STYLE_SCALE * 1.95 * (INITIAL_H / INITIAL_W)
    print(f'INITIAL_OFFSET is {INITIAL_OFFSET:.2f} and the sheet pads the art'
          f' {VS_PAD_X * vs_scale:.2f} in from the frame,')
    print('  so the two cancel to within a fifth of a pixel - which is why reading the offset')
    print('  off a screenshot came out at zero, and why leaving both out lands in the same place.')
    print()
    print(f'The arrow itself is still V-Slice {VS_ART_W * vs_scale:.1f}px wide against Psych'
          f' {int(PS_ART_W * PSYCH_SCALE_BASE)}px.')
    print(f'  Constants for the Haxe side: frame {VS_FRAME_H * vs_scale:.4f},'
          f' art top {VS_PAD_Y * vs_scale:.4f},')
    print(f'  art {VS_ART_W * vs_scale:.4f} x {VS_ART_H * vs_scale:.4f}, cell'
          f' {NOTE_SPACING * 2.8 * 1.95 * (INITIAL_H / INITIAL_W) ** 2:.4f}')

#!/usr/bin/env python3
"""
Turns a V-Slice stage into a Psych one.

Psych already builds stages from data - `StageData.addObjectsToState` reads an `objects`
array out of the stage file and PlayState calls it during gameplay - so this is a
translation between two prop formats, not a new loader.

Character positions are NOT converted. The two engines measure them from different
origins and the difference is not constant: comparing the eight stages that exist in
both, the offset between Psych's boyfriend and V-Slice's ranges from (187, 712) to
(250, 785). There is no transform to apply. But an Erect stage is the same stage with
different art, so its characters belong exactly where they stand on the normal one -
Psych's own numbers are carried over untouched and only the scenery is replaced.
"""

import copy, json, os

# LOW_QUALITY | HIGH_QUALITY. `validateVisibility` returns false unless the quality bit
# matching the player's setting is set, so a prop without this is silently never built.
FILTERS = 3


def animation(a):
    """V-Slice names an animation and its frame prefix; Psych calls those `anim` and `name`."""
    return {
        'anim': a.get('name', ''),
        'name': a.get('prefix', ''),
        'fps': a.get('frameRate', 24),
        'loop': a.get('looped', False),
        'indices': a.get('frameIndices', []) or [],
        'offsets': [0, 0],
    }


SKIPPED = []


def prop(p):
    # Psych's stage objects are a flat sprite or a sparrow/packer atlas. An Animate
    # Atlas prop is a folder of spritemaps with its own timeline and there is no data
    # path for one, so it is left out rather than emitted as a reference to nothing.
    # Three props across the nine stages are like this; they are reported, not hidden.
    if p.get('animType') == 'animateatlas':
        SKIPPED.append(p.get('name', '?'))
        return None

    asset = p.get('assetPath') or ''
    anims = p.get('animations') or []
    scale = p.get('scale') or [1, 1]

    # A colour where the art should be is V-Slice's way of writing a solid fill, and its
    # scale is then a size in pixels rather than a multiplier. Psych's `square` is a 1x1
    # white pixel scaled the same way, so the two agree without any arithmetic.
    if asset.startswith('#'):
        return {
            'type': 'square', 'name': p.get('name', 'solid'),
            'x': (p.get('position') or [0, 0])[0], 'y': (p.get('position') or [0, 0])[1],
            'scale': scale, 'scroll': p.get('scroll') or [1, 1],
            'alpha': p.get('alpha', 1), 'angle': p.get('angle', 0),
            'color': asset, 'filters': FILTERS,
        }

    out = {
        'type': 'animatedSprite' if anims else 'sprite',
        'name': p.get('name', asset),
        'x': (p.get('position') or [0, 0])[0], 'y': (p.get('position') or [0, 0])[1],
        'scale': scale, 'scroll': p.get('scroll') or [1, 1],
        'alpha': p.get('alpha', 1), 'angle': p.get('angle', 0),
        # Every sprite is tinted by this, and `colorFromString` throws on null, so white
        # - which tints nothing - has to be spelled out rather than left off.
        'color': '#FFFFFF', 'filters': FILTERS,
        'flipX': p.get('flipX', False), 'flipY': p.get('flipY', False),
        'image': asset,
        'antialiasing': not p.get('isPixel', False),
    }

    if anims:
        out['animations'] = [animation(a) for a in anims]
        out['firstAnimation'] = p.get('startingAnimation') or (anims[0].get('name') if anims else '')

    return out


def convert(vslice, psych_base):
    """Psych's stage, with its characters kept and its scenery replaced."""
    out = copy.deepcopy(psych_base)
    out['directory'] = vslice.get('directory', out.get('directory', ''))
    out['defaultZoom'] = vslice.get('cameraZoom', out.get('defaultZoom', 0.9))

    chars = vslice.get('characters') or {}
    entries = []

    # The characters stand among the scenery rather than in front of all of it, so they
    # go into the same list at the depth V-Slice gave them.
    for key, kind in (('gf', 'gf'), ('dad', 'dad'), ('bf', 'boyfriend')):
        entries.append((chars.get(key, {}).get('zIndex', 0), {'type': kind}))

    for p in (vslice.get('props') or []):
        built = prop(p)
        if built is not None:
            entries.append((p.get('zIndex', 0), built))

    entries.sort(key=lambda e: e[0])
    out['objects'] = [e[1] for e in entries]
    return out

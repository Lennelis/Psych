#!/usr/bin/env python3
"""
Turns a V-Slice chart into a Psych one.

Both engines number notes the same way: data 0-3 is the player, 4-7 the opponent,
whatever section the note lands in. Psych decides it with
`gottaHitNote = (songNotes[1] < totalColumns)` and never consults `mustHitSection`
for it - that field only picks which character the camera watches and feeds
`gfNote`. So note data passes through untouched.

An earlier version of this converter flipped the data against `mustHitSection`,
on the belief that Psych read it the older, section-relative way. It does not, and
the flip mirrored every opponent section - a whole chart wrong with nothing to
error on. The rule is now checked against the engine's own expression and against
the charts Psych ships, where `mustHitSection: true` sections hold data 0-3 and
`false` ones hold 4-7.

Camera events map straight across: Psych's `Focus Camera`, `Zoom Camera` and
`Set Camera Bop` already take V-Slice's own vocabulary, and both engines measure
event durations in steps, so those numbers pass through untouched.

Usage: vslice_to_psych.py <assets-root> <out-root> [song ...]
"""

import json, os, sys

STAGES = {
    'mainStage': 'stage', 'spookyMansion': 'spooky', 'phillyTrain': 'philly',
    'limoRide': 'limo', 'mallXmas': 'mall', 'mallEvil': 'mallEvil',
    'school': 'school', 'schoolEvil': 'schoolEvil',
    'tankmanBattlefield': 'tank', 'phillyStreets': 'phillyStreets',
}

# The Erect stages are their own art and have no Psych equivalent yet, so they fall
# back to the stage they are a version of. Swapped for the real ones once those exist.
STAGES['phillyBlazin'] = 'phillyBlazin'  # Psych calls it the same thing

for base, psych in list(STAGES.items()):
    STAGES[base + 'Erect'] = psych


def carry_over(new_song, old_song):
    """
    Keeps anything the old chart said that this converter has no opinion about.

    A Psych chart carries more than the notes: Stress names a game over character, the
    Weekend 1 songs carry an audio offset, three dozen files carry a `player3`. None of
    that is in a V-Slice chart, and none of it would error on the way out - it would just
    quietly stop happening. So the old values come across untouched.
    """
    if not isinstance(old_song, dict):
        return new_song

    for key, value in old_song.items():
        if key not in new_song:
            new_song[key] = value

    return new_song


# V-Slice ships recoloured characters for some Erect stages that Psych has no copy of.
# They fall back to the character they are a version of - the notes and the voice tracks are
# the same performance, only the art differs, so the song plays correctly and looks plainer.
CHARACTERS = {'bf-dark': 'bf', 'spooky-dark': 'spooky', 'gf-dark': 'gf'}


def character(name, fallback):
    if not name:
        return fallback
    return CHARACTERS.get(name, name)


def beat_ms(bpm):
    return 60000.0 / bpm


def bpm_at(time_changes, t):
    """The tempo in force at a given moment."""
    bpm = time_changes[0]['bpm']
    for tc in time_changes:
        if tc['t'] <= t + 0.001:
            bpm = tc['bpm']
        else:
            break
    return bpm


def build_sections(time_changes, end_ms):
    """
    Lays out four-beat sections across the song, following tempo changes.

    A section carries `changeBPM` only where the tempo actually differs from the one
    before it, which is what Psych's own charts do - marking every section would work
    but makes a diff against a hand-made chart unreadable.
    """
    sections = []
    t = time_changes[0]['t']
    last_bpm = None

    while t < end_ms + 1:
        bpm = bpm_at(time_changes, t)
        length = beat_ms(bpm) * 4
        sections.append({
            'start': t, 'end': t + length, 'bpm': bpm,
            'changed': last_bpm is not None and abs(bpm - last_bpm) > 1e-6,
        })
        last_bpm = bpm
        t += length

    return sections


def note_data(d):
    """Unchanged - both engines read 0-3 as the player and 4-7 as the opponent."""
    return d


def tween_value(v):
    """
    `duration, ease` for Psych.

    CLASSIC and INSTANT are not the same thing and must not collapse together: CLASSIC
    moves the follow point and lets the camera drift after it, INSTANT cuts. Both ignore
    the duration, so the difference is carried entirely by the name.
    """
    ease = v.get('ease', 'CLASSIC')
    if ease == 'CLASSIC':
        return '0, classic'
    if ease == 'INSTANT':
        return '0, instant'
    return '%s, %s%s' % (v.get('duration', 4), ease, v.get('easeDir', ''))


def convert_events(events):
    by_time = {}

    for e in events:
        kind, t, v = e.get('e'), e.get('t', 0), e.get('v')
        if not isinstance(v, dict):
            v = {'char': v} if kind == 'FocusCamera' else {}

        if kind == 'FocusCamera':
            char = v.get('char', 0)
            value1 = 'pos, %s, %s' % (v.get('x', 0), v.get('y', 0)) if char == -1 else str(char)
            row = ['Focus Camera', value1, tween_value(v)]
        elif kind == 'ZoomCamera':
            row = ['Zoom Camera', '%s, %s' % (v.get('zoom', 1.0), v.get('mode', 'stage')), tween_value(v)]
        elif kind == 'SetCameraBop':
            row = ['Set Camera Bop', str(v.get('intensity', 1.0)),
                   '%s, %s' % (v.get('rate', 4), v.get('offset', 0))]
        else:
            continue  # anything else is V-Slice-only and has nowhere to land

        by_time.setdefault(round(t, 4), []).append(row)

    return [[t, rows] for t, rows in sorted(by_time.items())]


def focus_timeline(events):
    """When the camera is on whom, so sections can be marked the way the song plays."""
    out = []
    for e in events:
        if e.get('e') != 'FocusCamera':
            continue
        v = e.get('v')
        char = v.get('char', 0) if isinstance(v, dict) else v
        if char in (0, 1):
            out.append((e.get('t', 0), char))
    out.sort()
    return out


def convert(chart, meta, difficulty, song_id, audio_suffix=''):
    play = meta['playData']
    chars = play.get('characters', {})
    time_changes = meta['timeChanges']

    notes = chart['notes'].get(difficulty) or []
    events = chart.get('events', []) or []

    speeds = chart.get('scrollSpeed', {})
    speed = speeds.get(difficulty, speeds.get('default', 1.0))

    end = max([n['t'] + n.get('l', 0) for n in notes] + [e.get('t', 0) for e in events] + [0])
    sections = build_sections(time_changes, end)
    focus = focus_timeline(events)

    # Whose section it is only picks which character the camera watches when no event
    # is steering it - the notes carry their own side. Taken from the chart's camera
    # events where there are any, and from where the notes actually are where there
    # are not, which is what Psych's own charts do.
    for s in sections:
        if focus:
            char = 0
            for t, c in focus:
                if t <= s['start'] + 1:
                    char = c
                else:
                    break
            s['mustHit'] = (char == 0)
        else:
            mine = sum(1 for n in notes if s['start'] <= n['t'] < s['end'] and n['d'] < 4)
            theirs = sum(1 for n in notes if s['start'] <= n['t'] < s['end'] and n['d'] >= 4)
            s['mustHit'] = mine >= theirs

    out_sections = []
    index, total = 0, len(notes)
    ordered = sorted(notes, key=lambda n: n['t'])

    for s in sections:
        rows = []
        while index < total and ordered[index]['t'] < s['end']:
            n = ordered[index]
            rows.append([n['t'], note_data(n['d']), n.get('l', 0)])
            index += 1

        section = {'sectionNotes': rows, 'sectionBeats': 4, 'mustHitSection': s['mustHit'],
                   'gfSection': False, 'altAnim': False}
        if s['changed']:
            section['changeBPM'] = True
            section['bpm'] = s['bpm']
        out_sections.append(section)

    # Anything past the last section - a stray note after the final bar - still has to
    # go somewhere, or it is silently dropped.
    if index < total:
        out_sections[-1]['sectionNotes'].extend(
            [n['t'], note_data(n['d']), n.get('l', 0)] for n in ordered[index:])

    return {'song': {
        'song': song_id,
        'bpm': time_changes[0]['bpm'],
        'speed': speed,
        'player1': character(chars.get('player'), 'bf'),
        'player2': character(chars.get('opponent'), 'dad'),
        'gfVersion': character(chars.get('girlfriend'), 'gf'),
        'stage': STAGES.get(play.get('stage', ''), play.get('stage', 'stage')),
        'needsVoices': True,
        'audioSuffix': audio_suffix,
        'format': 'psych_v1',
        'notes': out_sections,
        'events': convert_events(events),
    }}

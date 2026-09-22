package states.freeplay;

import states.FreeplayState;

/**
 * Hands out whichever freeplay menu the player picked.
 *
 * There are six places in the engine that go to freeplay - the main menu, the pause
 * menu, the game over screen, the end of a song, a lua call and the `FREEPLAY` compile
 * flag - and every one of them used to name Psych's own state. Routing them all through
 * here is what keeps you in the V-Slice menu after backing out of a song, rather than
 * being handed back to the other one.
 */
class FreeplayHub
{
	public static function menu():MusicBeatState
	{
		if (usingVSlice()) return new VSliceFreeplayState();

		return new FreeplayState();
	}

	/**
	 * Which of the two is going to open.
	 *
	 * Worth asking before switching to it: the V-Slice one brings its own music and its own
	 * arrival, so whatever is sending the player there should not be starting either.
	 */
	public static function usingVSlice():Bool
		return ClientPrefs.data.freeplayStyle == 'V-Slice';
}

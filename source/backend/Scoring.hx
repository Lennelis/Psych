package backend;

/**
 * V-Slice's scoring, as an alternative to Psych's.
 *
 * Psych scores a note by which judgement it landed in - 350 for a sick, 200 for a good, and
 * so on down - so every sick is worth the same whether it was 1ms out or 44. V-Slice's PBOT1
 * ("Points Based On Timing") scores the timing itself, on a curve, so the whole range between
 * a perfect hit and a miss is worth something different.
 *
 * The judgement windows are the same either way - 45, 90 and 135ms - but the hit window is
 * not: V-Slice's is 160ms, where Psych's comes from Safe Frames and is 166.67 by default.
 * Under this system the window is V-Slice's, because the curve is written to reach nothing at
 * the edge of it and a wider one would have notes the game accepted as hits fall outside the
 * only thing that can price them.
 *
 * The two also disagree about what a hold is worth. In Psych a sustain pays nothing at all -
 * `popUpScore` is only called for the note at the head - while V-Slice pays for holds by the
 * second, which on a song full of long notes is a large part of the total.
 *
 * Which one is in use is `ClientPrefs.data.scoringSystem`, and it defaults to Psych's so that
 * scores already in a save go on meaning what they meant.
 *
 * The numbers are V-Slice's own, from its `Scoring` and `Constants`.
 */
class Scoring
{
	/** Whether V-Slice's scoring is the one in use. */
	public static var usingVSlice(get, never):Bool;

	static function get_usingVSlice():Bool
		return ClientPrefs.data.scoringSystem == 'V-Slice';

	// ---------------------------------------------------------------------------------------
	// PBOT1
	// ---------------------------------------------------------------------------------------

	public static final MAX_SCORE:Int = 500;
	public static final MIN_SCORE:Float = 9.0;
	public static final MISS_SCORE:Int = -100;

	/** Tapping a lane with nothing in it. A tenth of a real miss, where Psych charges both 10. */
	public static final GHOST_MISS_SCORE:Int = -10;

	/** Where the curve turns over, and how sharply. */
	public static final SCORING_OFFSET:Float = 54.99;

	public static final SCORING_SLOPE:Float = 0.080;

	/** Inside this, a note is worth the full amount rather than a point off it. */
	public static final PERFECT_THRESHOLD:Float = 5.0;

	/**
	 * Past this, a note is a miss - and under this system it is also where the hit window
	 * ends, which is why `PlayState` sets `safeZoneOffset` from it rather than from Safe
	 * Frames. The two are the same number in V-Slice, and they have to be: the curve is
	 * written to reach nothing at the edge of the window, so a window wider than the curve
	 * would score its last few milliseconds as a miss on a note it had just accepted as a hit.
	 */
	public static final MISS_THRESHOLD:Float = 160.0;

	/**
	 * What a note pays, from how far off it was hit in milliseconds.
	 *
	 * A sigmoid, so it falls away gently around a sick and steeply through the middle of the
	 * window rather than stepping down at each judgement boundary.
	 *
	 * The timing is truncated first, as V-Slice truncates its own before handing it over -
	 * `Std.int(songPosition - time - inputLatency)`. Worth at most a point a note, but it is a
	 * point in the same direction every time.
	 *
	 * Only ever asked about a hit, so there is no miss to return: a note beyond the window is
	 * charged by the miss path instead. V-Slice's version carries that branch and never
	 * reaches it, since nothing outside its window is hittable; here a note type with a
	 * widened `lateHitMult` can be, and the curve has an answer for it - it flattens out at
	 * the minimum rather than falling off a cliff.
	 */
	public static function scoreNote(msTiming:Float):Int
	{
		var absTiming:Float = Math.abs(Std.int(msTiming));

		if (absTiming < PERFECT_THRESHOLD) return MAX_SCORE;

		var factor:Float = 1.0 - (1.0 / (1.0 + Math.exp(-SCORING_SLOPE * (absTiming - SCORING_OFFSET))));
		return Std.int(MAX_SCORE * factor + MIN_SCORE);
	}

	// ---------------------------------------------------------------------------------------
	// Health
	// ---------------------------------------------------------------------------------------

	/**
	 * Psych heals by a flat amount for any hit at all; these are shares of the bar, so a bad
	 * keeps you alive without helping and a shit costs you.
	 *
	 * Written against Psych's `healthBar.bounds.max` of 2, the same maximum V-Slice uses.
	 */
	public static final HEALTH_MAX:Float = 2.0;

	public static final HEALTH_SICK_BONUS:Float = 1.5 / 100.0 * HEALTH_MAX;
	public static final HEALTH_GOOD_BONUS:Float = 0.75 / 100.0 * HEALTH_MAX;
	public static final HEALTH_BAD_BONUS:Float = 0.0;
	public static final HEALTH_SHIT_BONUS:Float = -1.0 / 100.0 * HEALTH_MAX;
	public static final HEALTH_MISS_PENALTY:Float = -4.0 / 100.0 * HEALTH_MAX;

	/** What a hit of this judgement is worth on the health bar. */
	public static function healthForJudgement(judgement:String):Float
	{
		return switch (judgement)
		{
			case 'sick': HEALTH_SICK_BONUS;
			case 'good': HEALTH_GOOD_BONUS;
			case 'bad': HEALTH_BAD_BONUS;
			case 'shit': HEALTH_SHIT_BONUS;
			default: HEALTH_SICK_BONUS;
		};
	}

	// ---------------------------------------------------------------------------------------
	// Holds
	// ---------------------------------------------------------------------------------------

	public static final SCORE_HOLD_BONUS_PER_SECOND:Float = 250.0;
	public static final SCORE_HOLD_DROP_PENALTY_PER_SECOND:Float = -125.0;
	public static final HEALTH_HOLD_BONUS_PER_SECOND:Float = 6.0 / 100.0 * HEALTH_MAX;

	/** V-Slice forgives a hold let go of with less than this left on it. */
	public static final HOLD_DROP_PENALTY_THRESHOLD_MS:Float = 160.0;

	/**
	 * How long a piece of sustain stands for, in song milliseconds.
	 *
	 * V-Slice holds one note object per sustain; Psych chops it into a note every step and
	 * hits them one at a time, which is the only moment it learns a hold is still being held.
	 * A piece therefore stands for the step it covers, and `PlayState` runs the same clock
	 * forward between pieces so the payout arrives per frame as V-Slice's does rather than
	 * four times a second.
	 *
	 * It is also what a dropped piece is charged for, and what a remaining tail is measured in.
	 */
	public static function holdPieceLength():Float
		return Conductor.stepCrochet;

	/**
	 * What letting go of a hold with this much left on it costs.
	 *
	 * The threshold is V-Slice's way of not punishing someone who let go on the last few
	 * milliseconds of a long note, so it only makes sense against a whole remaining hold -
	 * which is what `guitarHeroSustains` hands over, the head note carrying its whole tail.
	 *
	 * Health is deliberately untouched: V-Slice's drop penalty per second is zero, and its
	 * miss penalty is for the note at the head of the hold, not for the sustain behind it.
	 * Psych charges a dropped sustain 12.5% of the bar a piece, which on a long note is a
	 * death sentence the original never hands out.
	 */
	public static function scoreHoldDrop(remainingMs:Float):Int
	{
		if (remainingMs <= HOLD_DROP_PENALTY_THRESHOLD_MS) return 0;

		return Math.round(SCORE_HOLD_DROP_PENALTY_PER_SECOND * remainingMs / 1000);
	}

	/**
	 * What one step of sustain that went by unheld costs.
	 *
	 * Without `guitarHeroSustains` there is no whole hold to charge - the pieces are missed
	 * one at a time as they pass - so this charges each for the step it covers and leaves the
	 * threshold out. Applying it here would waive every drop instead of the last moment of
	 * one: a step is 125ms at 120bpm and the threshold is 160ms, so no single piece ever
	 * reaches it, and holds would be free to let go of.
	 */
	public static function scoreHoldPieceDrop():Int
		return Math.round(SCORE_HOLD_DROP_PENALTY_PER_SECOND * holdPieceLength() / 1000);
}

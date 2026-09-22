package backend;

/**
 * Which parts of V-Slice's gameplay look are switched on.
 *
 * These are presentation only - nothing here changes what a note is worth or when it can be
 * hit. They are grouped rather than offered one at a time because almost none of them is a
 * preference: whether the word COMBO appears, or whether a hold cover draws over the note
 * behind it, is a question of which game you are looking at, not of taste. Four groups is
 * enough to take the layout without the flourishes, or the other way round.
 *
 * `Popups` is the one that stands down on its own. It moves and resizes the judgement and
 * combo art, and a mod that ships its own was drawn and offset against Psych's placement -
 * so applying V-Slice's numbers to it would put someone else's art in the wrong place.
 * Psych says which UI is in use through `PlayState.stageUI`, and the two V-Slice itself has
 * note styles for are the two this leaves alone.
 */
class VSliceVisuals
{
	/** Judgement and combo art: what shows, how big, and where. */
	public static var popups(get, never):Bool;

	static function get_popups():Bool
		return ClientPrefs.data.vslicePopups && usingDefaultUI();

	/** Where the strumlines sit, and what draws over what around them. */
	public static var strumline(get, never):Bool;

	static function get_strumline():Bool
		return ClientPrefs.data.vsliceStrumline;

	/** How the health icons bop. */
	public static var icons(get, never):Bool;

	static function get_icons():Bool
		return ClientPrefs.data.vsliceIcons;

	/** The flourishes either side of a song. */
	public static var transitions(get, never):Bool;

	static function get_transitions():Bool
		return ClientPrefs.data.vsliceTransitions;

	/** V-Slice's fixed red and green, in place of the two characters' icon colours. */
	public static var healthBarColors(get, never):Bool;

	static function get_healthBarColors():Bool
		return ClientPrefs.data.vsliceHealthBar;

	/** The score on its own, in place of Psych's score, misses and rating. */
	public static var scoreCounter(get, never):Bool;

	static function get_scoreCounter():Bool
		return ClientPrefs.data.vsliceScoreCounter;

	/** Holds drawn as one stretched mesh, solid, instead of a sprite per step at 0.6 alpha. */
	public static var sustains(get, never):Bool;

	static function get_sustains():Bool
		return ClientPrefs.data.vsliceSustains;

	/**
	 * True when the song is using art V-Slice has a note style for, rather than a mod's own.
	 *
	 * `stageUI` is `normal`, `pixel`, or whatever a stage named - and a named one carries its
	 * own `<prefix>UI/` folder of judgement and combo art.
	 */
	public static function usingDefaultUI():Bool
	{
		var ui:String = states.PlayState.stageUI;
		return ui == null || ui == 'normal' || ui == 'pixel';
	}

	// -----------------------------------------------------------------------------------------
	// V-Slice's numbers
	// -----------------------------------------------------------------------------------------

	/** `Constants.COLOR_HEALTH_BAR_RED` and `_GREEN`. */
	public static final HEALTH_BAR_RED:FlxColor = 0xFFFF0000;

	public static final HEALTH_BAR_GREEN:FlxColor = 0xFF66FF33;

	/** What the judgement and combo art is drawn at, from the `funkin` note style. */
	public static final JUDGEMENT_SCALE:Float = 0.65;

	public static final COMBO_SCALE:Float = 0.45;

	/** The `pixel` note style draws both at the same size, where Psych scales them apart. */
	public static final PIXEL_POPUP_SCALE:Float = 4.2;

	/** Below this, V-Slice shows no combo at all. */
	public static final COMBO_MIN:Int = 10;

	/** Note splash opacity, which the two note styles disagree about. */
	public static final SPLASH_ALPHA:Float = 0.8;

	public static final PIXEL_SPLASH_ALPHA:Float = 1.0;

	/**
	 * How far left of Psych's the strumlines sit.
	 *
	 * Psych puts a strum at `STRUM_X + 50 + 112 * lane`; V-Slice puts it at `48 + 112 * lane`
	 * less an `INITIAL_OFFSET` of `-0.275 * 104`. The note spacing and the 0.7 both scale by
	 * are the same, and both take `x` as the left edge, so the whole difference is this.
	 */
	public static final STRUM_X_NUDGE:Float = -72.6;

	/** The lift on an arrow as it fades in, and on the way out at the end of a song. */
	public static final ARROW_RISE:Float = 10;

	/** Longest a health icon's bop takes to land, in seconds. */
	public static final ICON_BOP_MAX:Float = 0.175;

	/**
	 * An ease that moves in whole steps instead of smoothly.
	 *
	 * V-Slice fades pixel art with one of these - eight steps on the countdown, two on the
	 * judgement and combo art - so a sprite drawn in hard pixels does not go soft on its way
	 * out. Psych fades everything smoothly, which is the one thing pixel art should not do.
	 */
	public static function stepped(steps:Int):Float->Float
	{
		return function(t:Float):Float
			return (steps <= 0) ? t : Math.floor(t * steps) / steps;
	}

	/** The ease a fade should use for art of this kind. */
	public static function fadeEase(pixel:Bool, steps:Int):Null<Float->Float>
	{
		if (!transitions || !pixel) return null;

		return stepped(steps);
	}
}

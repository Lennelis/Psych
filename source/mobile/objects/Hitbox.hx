package mobile.objects;

import flixel.FlxG;
import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import flixel.util.FlxColor;

/**
 * The four columns the player taps during gameplay.
 *
 * Lanes are tagged with the same `note_left`/`note_down`/`note_up`/`note_right`
 * actions the keyboard uses, which means `PlayState.keysCheck()` picks up held
 * sustains through `Controls` without knowing touch exists. Presses and releases
 * are wired straight to `keyPressed`/`keyReleased` so the hit registers on the
 * same frame the finger lands, instead of a frame later.
 */
class Hitbox extends FlxTypedSpriteGroup<TouchButton>
{
	public static final ACTIONS:Array<String> = ['note_left', 'note_down', 'note_up', 'note_right'];

	/** Fraction of the screen left free at the top, so the pause button stays tappable. */
	public static inline var TOP_RESERVED:Float = 0.14;

	public function new()
	{
		super();

		scrollFactor.set();

		final laneCount:Int = ACTIONS.length;
		final top:Int = Std.int(FlxG.height * TOP_RESERVED);
		final laneWidth:Int = Std.int(FlxG.width / laneCount);
		final laneHeight:Int = FlxG.height - top;
		final hidden:Bool = ClientPrefs.data.hitboxType == 'Hidden';
		final gradient:Bool = ClientPrefs.data.hitboxType != 'Solid';

		for (i in 0...laneCount)
		{
			final button:TouchButton = new TouchButton(i * laneWidth, top, [ACTIONS[i]]);
			button.setLaneGraphic(laneWidth, laneHeight, laneColor(i), gradient);
			button.allowSlideIn = true; // sliding across lanes is how you play rolls with two thumbs
			button.idleAlpha = hidden ? 0 : ClientPrefs.data.controlsAlpha * 0.5;
			button.pressedAlpha = hidden ? 0 : Math.min(1, ClientPrefs.data.controlsAlpha + 0.2);
			button.alpha = button.idleAlpha;
			button.antialiasing = ClientPrefs.data.antialiasing;
			add(button);
		}
	}

	/** The lane for note data `i`, in `left, down, up, right` order. */
	public inline function getLane(i:Int):TouchButton
		return (i >= 0 && i < members.length) ? members[i] : null;

	public function releaseAll():Void
	{
		for (button in members)
			if (button != null) button.release();
	}

	static function laneColor(i:Int):FlxColor
	{
		final colors:Array<Array<FlxColor>> = ClientPrefs.data.arrowRGB;
		if (colors != null && colors[i] != null && colors[i].length > 0) return colors[i][0];

		return FlxColor.WHITE;
	}
}

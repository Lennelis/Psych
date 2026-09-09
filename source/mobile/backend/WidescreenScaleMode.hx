package mobile.backend;

import flixel.FlxG;
import flixel.system.scaleModes.RatioScaleMode;

/**
 * Lets the game fill a screen that's wider than 16:9 instead of sitting in
 * pillarbox bars.
 *
 * Ported down from V-Slice's `funkin.ui.FullScreenScaleMode`. The part worth
 * keeping is that it doesn't stretch or crop anything: it raises `FlxG.width` so
 * the game genuinely renders a wider slice of the world, and the scale stays
 * square. Funkin's version also deals with notch cutouts and desktop window
 * resizing; neither applies here, so this is only the sizing half of it.
 *
 * Turned off it defers entirely to `RatioScaleMode`, which is what Flixel uses by
 * default, so the letterboxed behaviour is untouched.
 */
class WidescreenScaleMode extends RatioScaleMode
{
	/**
	 * Widest the game is allowed to get. Past this a very long phone would be
	 * showing more empty stage than game, so the extra goes back to bars.
	 */
	public static var maxAspectRatio:Float = 20 / 9;

	public static var instance(default, null):WidescreenScaleMode;

	public static var enabled(default, set):Bool = false;

	public function new()
	{
		super();
		instance = this;
	}

	/**
	 * Installs the scale mode if it isn't already, then switches it on or off.
	 *
	 * This has to wait until the game is actually on the stage. Assigning
	 * `FlxG.scaleMode` calls `FlxGame.onResize` straight away, which reads
	 * `FlxG.stage` and the running state - and while `Main`'s constructor is still
	 * going, `FlxGame` has not been added to the stage and no state exists, so both
	 * are null. Calling it from there crashes before the first frame, enabled or not.
	 */
	public static function apply(enable:Bool):Void
	{
		if (!isReady()) return;

		if (instance == null || FlxG.scaleMode != instance) FlxG.scaleMode = new WidescreenScaleMode();

		enabled = enable;
	}

	/**
	 * Everything `FlxGame.onResize` dereferences, checked in order. It reads
	 * `FlxG.stage` and calls `_state.onResize`, so all three have to exist before a
	 * scale mode can be assigned or re-measured.
	 */
	static inline function isReady():Bool
		return FlxG.game != null && FlxG.game.stage != null && FlxG.state != null;

	override function updateGameSize(Width:Int, Height:Int):Void
	{
		// FlxG.width gets widened below, so every measurement has to start again from
		// the size the game was actually built at - otherwise each resize widens the
		// result a bit further than the last.
		untyped FlxG.width = FlxG.initialWidth;
		untyped FlxG.height = FlxG.initialHeight;

		if (FlxG.initialWidth <= 0 || FlxG.initialHeight <= 0 || Height <= 0)
		{
			super.updateGameSize(Width, Height);
			return;
		}

		final gameRatio:Float = FlxG.initialWidth / FlxG.initialHeight;
		final screenRatio:Float = Width / Height;

		// Nothing to gain on a screen that isn't wider than the game; a 4:3 tablet
		// keeps its bars either way.
		if (!enabled || screenRatio <= gameRatio)
		{
			super.updateGameSize(Width, Height);
			return;
		}

		final pixelScale:Float = Height / FlxG.initialHeight;
		final gameWidth:Float = Math.min(Width / pixelScale, FlxG.initialHeight * maxAspectRatio);

		untyped FlxG.width = Math.ceil(gameWidth);

		gameSize.y = Height;
		gameSize.x = Math.floor(gameWidth * pixelScale);
	}

	static function set_enabled(value:Bool):Bool
	{
		enabled = value;

		if (instance != null && isReady())
		{
			instance.onMeasure(FlxG.stage.stageWidth, FlxG.stage.stageHeight);
			FlxG.signals.gameResized.dispatch(FlxG.stage.stageWidth, FlxG.stage.stageHeight);
		}

		return value;
	}
}

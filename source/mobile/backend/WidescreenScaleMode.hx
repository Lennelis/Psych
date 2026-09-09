package mobile.backend;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.system.scaleModes.RatioScaleMode;

/**
 * Lets the game fill a screen that's wider than 16:9 instead of sitting in
 * pillarbox bars.
 *
 * The game keeps its own 1280x720 coordinate space: `FlxG.width` is left alone, so
 * every menu, every stage and every piece of HUD is laid out exactly where it was
 * designed to be, and stays centred. What changes is the cameras - each one is made
 * `cutout` pixels wider and moved half of that to the left, so it renders into the
 * bars either side instead of leaving them black. A camera crops to its own size
 * and `FlxGame` doesn't crop at all, which is what makes that legal.
 *
 * The earlier version of this raised `FlxG.width` instead, the way V-Slice's
 * `FullScreenScaleMode` does. That works there because their states are written
 * against a variable width; Psych's are not, so everything laid out at a fixed
 * coordinate ended up hugging the left edge with the new space piled up on the
 * right. Widening the view rather than the world avoids the whole problem.
 *
 * Turned off, `cutout` is zero and this is just `RatioScaleMode`.
 */
class WidescreenScaleMode extends RatioScaleMode
{
	/**
	 * Widest the game is allowed to get. Past this a very long phone would be
	 * showing more empty stage than game, so the extra goes back to bars.
	 */
	public static var maxAspectRatio:Float = 20 / 9;

	/**
	 * How much wider than `FlxG.width` the screen has room for, in game pixels, with
	 * half of it either side of the game's own band.
	 *
	 * Anything that wants to reach the true edge of the screen - the touch controls -
	 * lays itself out from `-cutout / 2` to `FlxG.width + cutout / 2`.
	 */
	public static var cutout(default, null):Float = 0;

	public static var instance(default, null):WidescreenScaleMode;

	public static var enabled(default, set):Bool = false;

	static var hooked:Bool = false;

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

		// Cameras are made per state, and reset on every switch, so each new one has to
		// be caught as it arrives rather than only the ones standing right now.
		if (!hooked)
		{
			FlxG.cameras.cameraAdded.add(widen);
			hooked = true;
		}

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
		// Letterboxed as usual first: that gives the scale the game is drawn at, which
		// is what turns device pixels into the game pixels `cutout` is measured in.
		super.updateGameSize(Width, Height);

		cutout = 0;

		if (enabled && Height > 0 && FlxG.height > 0 && gameSize.y > 0)
		{
			final scale:Float = gameSize.y / FlxG.height;
			if (scale > 0)
			{
				final widest:Float = Math.min(Width / scale, FlxG.height * maxAspectRatio);
				cutout = Math.max(0, widest - FlxG.width);
			}
		}

		widenAll();
	}

	/**
	 * Gives one camera the extra width and slides it half of that to the left, so the
	 * view grows evenly either side of where it was.
	 *
	 * The scroll goes with it: shifting the left edge out by half the cutout would
	 * otherwise drag everything the camera draws along with it, and menus would come
	 * out further left than they started.
	 */
	static function widen(camera:FlxCamera):Void
	{
		if (camera == null || camera.height != FlxG.height) return; // leave odd little cameras alone

		final extra:Int = Math.round(cutout);
		final target:Int = FlxG.width + extra;
		if (camera.width == target) return;

		camera.scroll.x += (camera.width - target) * 0.5;
		camera.width = target;
		camera.x = -extra * 0.5;
	}

	static function widenAll():Void
	{
		if (FlxG.cameras == null || FlxG.cameras.list == null) return;

		for (camera in FlxG.cameras.list)
			widen(camera);
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

package mobile.backend;

import flixel.FlxG;
import flixel.system.scaleModes.RatioScaleMode;

/**
 * Lets the game fill a screen that's wider than 16:9 instead of sitting in
 * pillarbox bars.
 *
 * Ported down from V-Slice's `funkin.ui.FullScreenScaleMode`: nothing is stretched or
 * cropped, `FlxG.width` is raised so the game genuinely renders a wider slice of the
 * world, and the scale stays square.
 *
 * That leaves the extra width to the right of anything laid out at a fixed
 * coordinate, so whatever should stay centred adds `CoolUtil.widescreenOffset()` to
 * its x, and backgrounds drawn for 1280 grow to cover with `CoolUtil.fillScreen`.
 * Widening the cameras instead of the world was tried and does not work here: Psych's
 * menus set `scrollFactor.set()` on nearly everything, and a screen-fixed sprite
 * doesn't move with its camera - it just ends up sitting half a cutout to the left of
 * where the camera now begins.
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

	/**
	 * How far into the game's own picture the device's cutout reaches, in game pixels.
	 *
	 * `ScreenUtil` answers in device pixels measured from the window's edges, which is not the
	 * same thing: the game is drawn at `scale` into a rectangle that starts `offset` in from
	 * the window, so a notch is only in the way by however much it gets past that. On a
	 * letterboxed screen it usually does not - it eats into the black bar instead, and the
	 * answer here is zero.
	 *
	 * Anything pinned to a screen edge should hold itself this far in. Nothing laid out from
	 * the middle needs to care.
	 */
	public static var notchLeft(default, null):Float = 0;

	public static var notchTop(default, null):Float = 0;
	public static var notchRight(default, null):Float = 0;
	public static var notchBottom(default, null):Float = 0;

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
			resizeCameras();
			return;
		}

		final gameRatio:Float = FlxG.initialWidth / FlxG.initialHeight;
		final screenRatio:Float = Width / Height;

		// Nothing to gain on a screen that isn't wider than the game; a 4:3 tablet
		// keeps its bars either way.
		if (!enabled || screenRatio <= gameRatio)
		{
			super.updateGameSize(Width, Height);
			resizeCameras();
			return;
		}

		final pixelScale:Float = Height / FlxG.initialHeight;
		final gameWidth:Float = Math.min(Width / pixelScale, FlxG.initialHeight * maxAspectRatio);

		untyped FlxG.width = Math.ceil(gameWidth);

		gameSize.y = Height;
		gameSize.x = Math.floor(gameWidth * pixelScale);

		resizeCameras();
	}

	override function updateScaleOffset():Void
	{
		super.updateScaleOffset();

		// Asked again on every measure, because turning the phone round moves the cutout to
		// the other side. `ScreenUtil` is only asked until it answers: the view has no insets
		// to report until it has been attached, so the first read - taken before the game is
		// on screen - is a zero meaning "not yet" rather than "no notch".
		if (!ScreenUtil.measured) ScreenUtil.refresh();

		measureNotch(scale, offset);
	}

	/**
	 * Asks the device again and remeasures, for a layout about to be built.
	 *
	 * The scale mode is only measured when the window changes size, which on a phone may be
	 * once, before the view exists to be asked. Anything laying itself out against the cutout
	 * calls this first rather than trusting that a resize has happened since.
	 */
	public static function refreshNotch():Void
	{
		ScreenUtil.refresh();

		var mode:flixel.system.scaleModes.BaseScaleMode = FlxG.scaleMode;
		if (mode != null) measureNotch(mode.scale, mode.offset);
	}

	/**
	 * Works out how much of the cutout actually lands on the game.
	 *
	 * The numbers are passed in rather than read off `FlxG.scaleMode`, because this also runs
	 * from inside a measure - at which point the mode doing the measuring may not be the one
	 * `FlxG` is pointing at yet.
	 */
	static function measureNotch(scale:flixel.math.FlxPoint, offset:flixel.math.FlxPoint):Void
	{
		if (scale == null || offset == null || scale.x <= 0 || scale.y <= 0)
		{
			notchLeft = notchTop = notchRight = notchBottom = 0;
			return;
		}

		// What is left of each inset once the letterbox has absorbed its share of it. The
		// right and bottom bars are the same width as the left and top ones, Flixel centring
		// the picture in the window.
		notchLeft = Math.max(0, ScreenUtil.left - offset.x) / scale.x;
		notchTop = Math.max(0, ScreenUtil.top - offset.y) / scale.y;
		notchRight = Math.max(0, ScreenUtil.right - offset.x) / scale.x;
		notchBottom = Math.max(0, ScreenUtil.bottom - offset.y) / scale.y;
	}

	/**
	 * Grows the cameras already running to the width the game now renders at.
	 *
	 * Flixel resizes nothing when `FlxG.width` changes: a camera keeps whatever width
	 * it was built at. The first state is created before this gets switched on, so
	 * without this its camera stays 1280 wide and everything past that is a black
	 * band - which is also what kept a camera flash from reaching the screen edges.
	 */
	static function resizeCameras():Void
	{
		if (FlxG.cameras == null || FlxG.cameras.list == null) return;

		for (camera in FlxG.cameras.list)
			if (camera != null && camera.height == FlxG.height && camera.width != FlxG.width)
				camera.width = FlxG.width;
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

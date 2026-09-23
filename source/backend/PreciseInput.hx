package backend;

import flixel.input.keyboard.FlxKey;
import lime.ui.KeyCode;
import lime.ui.KeyModifier;
import lime.ui.Touch;

/**
 * When an input actually happened, rather than when the game noticed it.
 *
 * Input is delivered once a frame. A press lands somewhere in the interval that just
 * elapsed and is judged as though it happened at the end of it, so every hit reads a
 * little late - never early - by up to a frame, half of one on average.
 *
 * SDL stamps every event with the moment it happened and stock lime drops the number
 * before Haxe can see it. The patch under `patches/lime-precise-input/` carries it
 * through, on the same count as `System.getTimer`, so the two can simply be subtracted.
 *
 * This keeps the last press per key and per finger and answers how long ago it was.
 * Without the patched lime the signals are not there, `available` is false, and
 * everything that asks gets zero - which leaves the half frame estimate in PlayState
 * doing the job it was doing before.
 */
class PreciseInput
{
	/** Whether the running build's lime carries event timestamps. */
	public static var available(default, null):Bool = false;

	/**
	 * A press older than this is not believed.
	 *
	 * The timestamp and the clock are whole milliseconds and both wrap after about 49
	 * days of uptime; a wrap would otherwise read as an enormous latency and throw a
	 * judgement wildly out. Half a second is far longer than any real input delay and
	 * far shorter than anything a wrap produces.
	 */
	static inline var SANE_LIMIT:Float = 500;

	static var keyTimes:Map<Int, Float> = new Map<Int, Float>();
	static var touchTimes:Map<Int, Float> = new Map<Int, Float>();
	static var hooked:Bool = false;

	/**
	 * Starts listening. Safe to call on a build whose lime has no timestamps - the
	 * signals simply are not there and nothing is hooked.
	 */
	public static function hook():Void
	{
		if (hooked) return;

		#if PRECISE_INPUT
		var window = flixel.FlxG.stage.application.window;
		window.onKeyDownPrecise.add(onKeyDown);
		Touch.onStart.add(onTouchStart);
		available = true;
		#end

		hooked = true;
	}

	public static function unhook():Void
	{
		if (!hooked) return;

		#if PRECISE_INPUT
		var window = flixel.FlxG.stage.application.window;
		window.onKeyDownPrecise.remove(onKeyDown);
		Touch.onStart.remove(onTouchStart);
		#end

		keyTimes.clear();
		touchTimes.clear();
		hooked = false;
	}

	#if PRECISE_INPUT
	static function onKeyDown(code:KeyCode, _:KeyModifier, timestamp:Float):Void
		keyTimes.set(cast code, timestamp);

	static function onTouchStart(touch:Touch):Void
		touchTimes.set(touch.id, touch.timestamp);
	#end

	/**
	 * How long ago, in milliseconds, the most recent of these keys went down.
	 *
	 * Zero when there is nothing to say: no patched lime, no press recorded, or a figure
	 * that failed the sanity check. Zero is the right answer for "no information" because
	 * it leaves a judgement exactly where it would have been without any of this.
	 */
	public static function sinceKey(keys:Array<FlxKey>):Float
	{
		if (!available || keys == null) return 0;

		var newest:Float = -1;
		for (key in keys)
		{
			var at:Null<Float> = keyTimes.get(cast key);
			if (at != null && at > newest) newest = at;
		}

		return age(newest);
	}

	/** How long ago the most recent touch landed, by the same rules as `sinceKey`. */
	public static function sinceTouch(id:Int):Float
	{
		if (!available) return 0;

		var at:Null<Float> = touchTimes.get(id);
		return (at == null) ? 0 : age(at);
	}

	static function age(stamp:Float):Float
	{
		if (stamp < 0) return 0;

		var elapsed:Float = lime.system.System.getTimer() - stamp;

		// A negative reading means the clock and the stamp disagree, which should not
		// happen and is not worth guessing about.
		if (elapsed < 0 || elapsed > SANE_LIMIT) return 0;

		return elapsed;
	}
}

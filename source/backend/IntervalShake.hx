package backend;

import flixel.FlxObject;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.tweens.FlxEase.EaseFunction;
import flixel.util.FlxTimer;

/**
 * Shakes an object on a fixed interval, with an intensity that eases from one value to
 * another over the shake's lifetime. Ported from V-Slice's `funkin.effects.IntervalShake`,
 * which describes itself as FlxFlicker geared towards shaking.
 *
 * Not a tween and not a camera shake: it writes the object's position directly on each
 * tick and puts it back where it found it at the end, so it composes with whatever else
 * is moving that object between ticks. That is what the freeplay rank animation wants -
 * a capsule that rattles in place while its own tweens carry on.
 *
 * V-Slice pools these. We do not, because the freeplay runs at most a handful at once and
 * a pool that outlives a state is a way to hold a dead sprite alive.
 */
class IntervalShake
{
	static var bound:Map<FlxObject, IntervalShake> = new Map<FlxObject, IntervalShake>();

	/**
	 * @param object          What to shake.
	 * @param duration        How long to shake for, in seconds.
	 * @param interval        How often to move it. Falls back to one tick a frame.
	 * @param startIntensity  Displacement at the start, as a fraction of the object's width.
	 * @param endIntensity    Displacement at the end, same units.
	 * @param ease            Shapes the intensity between the two.
	 * @param onComplete      Called once the object has been put back.
	 */
	public static function shake(object:FlxObject, duration:Float = 1, interval:Float = 0.04, startIntensity:Float = 0, endIntensity:Float = 0,
		?ease:EaseFunction, ?onComplete:IntervalShake->Void):IntervalShake
	{
		// Already shaking - let the one in flight finish rather than fighting it for the
		// position, which would leave the object wherever the loser wrote last.
		if (bound.exists(object)) return bound.get(object);

		if (interval <= 0) interval = FlxG.elapsed;

		var shaker:IntervalShake = new IntervalShake();
		shaker.start(object, duration, interval, startIntensity, endIntensity, ease, onComplete);
		bound.set(object, shaker);
		return shaker;
	}

	public static function isShaking(object:FlxObject):Bool
		return bound.exists(object);

	public static function stopShaking(object:FlxObject):Void
	{
		var shaker:IntervalShake = bound.get(object);
		if (shaker != null) shaker.stop();
	}

	public var object(default, null):FlxObject;
	public var timer(default, null):FlxTimer;

	var duration:Float;
	var interval:Float;
	var startIntensity:Float;
	var endIntensity:Float;
	var ease:EaseFunction;
	var onComplete:IntervalShake->Void;
	var initialOffset:FlxPoint;
	var secondsSinceStart:Float = 0;

	function new() {}

	function start(object:FlxObject, duration:Float, interval:Float, startIntensity:Float, endIntensity:Float, ?ease:EaseFunction,
		?onComplete:IntervalShake->Void):Void
	{
		this.object = object;
		this.duration = duration;
		this.interval = interval;
		this.startIntensity = startIntensity;
		this.endIntensity = endIntensity;
		this.ease = ease;
		this.onComplete = onComplete;

		initialOffset = FlxPoint.get(object.x, object.y);
		secondsSinceStart = 0;

		timer = new FlxTimer().start(interval, tick, Std.int(duration / interval));
	}

	function tick(timer:FlxTimer):Void
	{
		if (object == null) return;

		secondsSinceStart += interval;

		var progress:Float = secondsSinceStart / duration;
		if (ease != null) progress = 1 - ease(progress);

		var intensity:Float = FlxMath.lerp(endIntensity, startIntensity, progress);

		// Both axes off the width, as V-Slice does - a capsule is far wider than it is tall,
		// and matching the shake to each axis separately makes the vertical rattle vanish.
		object.x = initialOffset.x + FlxG.random.float(-intensity * object.width, intensity * object.width);
		object.y = initialOffset.y + FlxG.random.float(-intensity * object.width, intensity * object.width);

		if (timer.loops > 0 && timer.loopsLeft == 0) finish();
	}

	function finish():Void
	{
		if (object != null)
		{
			object.x = initialOffset.x;
			object.y = initialOffset.y;
		}

		var callback:IntervalShake->Void = onComplete;
		release();
		if (callback != null) callback(this);
	}

	public function stop():Void
	{
		if (timer != null) timer.cancel();
		finish();
	}

	function release():Void
	{
		if (object != null) bound.remove(object);
		if (initialOffset != null)
		{
			initialOffset.put();
			initialOffset = null;
		}
		object = null;
		timer = null;
		ease = null;
		onComplete = null;
	}
}

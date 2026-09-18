package backend;

import psychlua.LuaUtils;

/**
 * Parsing for the two V-Slice camera events, `Zoom Camera` and `Focus Camera`.
 *
 * This lives apart from PlayState so the chart editor can read an event exactly the way
 * gameplay will. The editor draws the ease curve it finds here, so if the two parsed
 * differently the preview would be quietly lying about what the song does.
 *
 * Psych events carry two free-text values, where V-Slice's carry a named field per
 * parameter, so the fields are packed comma-separated - the same shape `Screen Shake`
 * already uses. Value 1 is *what* to move to, value 2 is *how* to get there.
 */
class CameraEvents
{
	public static inline var ZOOM:String = 'Zoom Camera';
	public static inline var FOCUS:String = 'Focus Camera';
	public static inline var BOP:String = 'Set Camera Bop';

	/** V-Slice's default, in steps. */
	public static inline var DEFAULT_DURATION:Float = 4;

	public static inline function isCameraEvent(name:String):Bool
		return name == ZOOM || name == FOCUS || name == BOP;

	/** Only the two that move the camera over time have a curve worth drawing. */
	public static inline function hasTweenPreview(name:String):Bool
		return name == ZOOM || name == FOCUS;

	/** Focus targets. The numbers are V-Slice's, so a chart converted from it lands right. */
	public static inline var TARGET_POSITION:Int = -1;
	public static inline var TARGET_BF:Int = 0;
	public static inline var TARGET_DAD:Int = 1;
	public static inline var TARGET_GF:Int = 2;

	static function splitValue(value:String):Array<String>
	{
		if(value == null) return [];
		var parts:Array<String> = value.split(',');
		for (i in 0...parts.length) parts[i] = parts[i].trim();
		while(parts.length > 0 && parts[parts.length - 1].length < 1) parts.pop();
		return parts;
	}

	static function floatAt(parts:Array<String>, index:Int, fallback:Float):Float
	{
		if(index >= parts.length) return fallback;
		var parsed:Float = Std.parseFloat(parts[index]);
		return Math.isNaN(parsed) ? fallback : parsed;
	}

	/**
	 * Value 2 of both events: `duration, ease`.
	 *
	 * `duration` is in steps, like V-Slice. `ease` is any name `LuaUtils.getTweenEaseByString`
	 * knows, plus `instant` (snap, duration ignored) and - for Focus Camera - `classic`, which
	 * snaps *and* hands the camera back to the section logic the way charts behaved before.
	 */
	public static function parseTween(value2:String):CameraTween
	{
		var parts:Array<String> = splitValue(value2);
		var ease:String = (parts.length > 1) ? parts[1].toLowerCase() : 'linear';

		var instant:Bool = (ease == 'instant');
		var classic:Bool = (ease == 'classic');

		var duration:Float = floatAt(parts, 0, DEFAULT_DURATION);
		if(duration < 0) duration = 0;
		if(instant || classic) duration = 0;

		return {
			duration: duration,
			ease: ease,
			easeFunction: LuaUtils.getTweenEaseByString(ease),
			instant: instant,
			classic: classic
		};
	}

	/** Value 1 of `Zoom Camera`: `zoom` or `zoom, mode`. */
	public static function parseZoom(value1:String):CameraZoom
	{
		var parts:Array<String> = splitValue(value1);
		var mode:String = (parts.length > 1) ? parts[1].toLowerCase() : 'direct';
		return {
			zoom: floatAt(parts, 0, 1),
			// Direct is an absolute zoom; stage multiplies the stage's own defaultZoom, so
			// "1.2, stage" reads as "a fifth closer than this stage normally sits".
			stageRelative: (mode == 'stage')
		};
	}

	/** Value 1 of `Focus Camera`: blank, or `target` / `target, x, y`. */
	public static function parseFocus(value1:String):CameraFocus
	{
		var parts:Array<String> = splitValue(value1);
		if(parts.length < 1) return {release: true, target: TARGET_BF, x: 0, y: 0};

		var target:Int = TARGET_BF;
		switch(parts[0].toLowerCase())
		{
			case 'bf' | 'boyfriend' | 'player' | '0': target = TARGET_BF;
			case 'dad' | 'opponent' | '1': target = TARGET_DAD;
			case 'gf' | 'girlfriend' | '2': target = TARGET_GF;
			case 'pos' | 'position' | '-1': target = TARGET_POSITION;
			default:
				var parsed:Float = Std.parseFloat(parts[0]);
				if(!Math.isNaN(parsed)) target = Math.round(parsed);
		}

		return {
			release: false,
			target: target,
			x: floatAt(parts, 1, 0),
			y: floatAt(parts, 2, 0)
		};
	}

	/**
	 * Value 1 of `Set Camera Bop` is the strength, value 2 is `rate, offset` in beats.
	 *
	 * A blank rate hands the bop back to Psych's own schedule - once per section - which is
	 * what the negative stands for. Zero switches bops off, matching V-Slice.
	 */
	public static function parseBop(value1:String, value2:String):CameraBop
	{
		var strength:Array<String> = splitValue(value1);
		var timing:Array<String> = splitValue(value2);

		return {
			intensity: floatAt(strength, 0, 1),
			rate: (timing.length > 0) ? floatAt(timing, 0, -1) : -1,
			offset: floatAt(timing, 1, 0)
		};
	}

	/** A one-line summary for the chart editor to put under the event. */
	public static function describe(eventName:String, value1:String, value2:String):String
	{
		var tween:CameraTween = parseTween(value2);
		var how:String = tween.classic ? 'classic' : (tween.instant ? 'instantly' : '${tween.duration} steps, ${tween.ease}');

		switch(eventName)
		{
			case ZOOM:
				var zoom:CameraZoom = parseZoom(value1);
				return 'zoom ${zoom.zoom}x ${zoom.stageRelative ? "of stage" : "absolute"} - $how';

			case FOCUS:
				var focus:CameraFocus = parseFocus(value1);
				if(focus.release) return 'back to section camera';

				var who:String = 'character ${focus.target}';
				if(focus.target == TARGET_BF) who = 'boyfriend';
				else if(focus.target == TARGET_DAD) who = 'opponent';
				else if(focus.target == TARGET_GF) who = 'girlfriend';
				else if(focus.target == TARGET_POSITION) who = 'position';
				var offset:String = (focus.x != 0 || focus.y != 0) ? ' (${focus.x}, ${focus.y})' : '';
				return 'focus $who$offset - $how';

			case BOP:
				var bop:CameraBop = parseBop(value1, value2);
				var when:String = 'once a section';
				if(bop.rate == 0) when = 'never';
				else if(bop.rate > 0) when = 'every ${bop.rate} beats';

				var phase:String = (bop.rate > 0 && bop.offset != 0) ? ' offset ${bop.offset}' : '';
				return 'bop ${bop.intensity}x, $when$phase';
		}
		return '';
	}
}

typedef CameraTween =
{
	/** In steps, as V-Slice counts it. Zero for instant and classic. */
	var duration:Float;
	var ease:String;
	var easeFunction:Float->Float;
	/** Snap, ignoring duration. */
	var instant:Bool;
	/** Snap and give the camera back to the section logic. Focus Camera only. */
	var classic:Bool;
}

typedef CameraZoom =
{
	var zoom:Float;
	/** Whether `zoom` multiplies the stage's own zoom rather than being absolute. */
	var stageRelative:Bool;
}

typedef CameraBop =
{
	/** Multiplier on Psych's own bop strength. */
	var intensity:Float;
	/** Beats between bops. Negative hands it back to the per-section default, zero is off. */
	var rate:Float;
	/** Phase in beats. */
	var offset:Float;
}

typedef CameraFocus =
{
	/** Value 1 was blank - stop forcing the camera and let sections drive it again. */
	var release:Bool;
	var target:Int;
	var x:Float;
	var y:Float;
}

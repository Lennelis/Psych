package mobile.backend;

import flixel.FlxG;
import mobile.objects.TouchButton;

/**
 * Small shared bits the touch controls need: a frame counter used to spot pads
 * that stopped updating, and haptics.
 */
class TouchUtil
{
	/** Bumped once per frame. `TouchButton` stamps itself with it so `Controls` can tell a live pad from a stale one. */
	public static var frameCount(default, null):Int = 0;

	static var initialized:Bool = false;

	public static function init():Void
	{
		if (initialized) return;
		initialized = true;
		FlxG.signals.preUpdate.add(function() frameCount++);
		FlxG.signals.postUpdate.add(flushNoteVibration);
	}

	/** A short tap of the vibration motor, if the player left it on. */
	public static function vibrate(duration:Int = 15):Void
	{
		#if mobile
		if (!ClientPrefs.data.vibration) return;

		var scaled:Int = Math.round(duration * ClientPrefs.data.vibrationStrength);
		if (scaled < 1) return;

		try
		{
			lime.ui.Haptic.vibrate(0, scaled);
		}
		catch (e:Dynamic) {} // some devices/emulators have no motor to talk to
		#end
	}

	// -------------------------------------------------------------------------------------
	// Note haptics
	// -------------------------------------------------------------------------------------

	/** One note's worth of pulse. V-Slice uses 10ms and stacks amplitude; this stacks length. */
	static inline var NOTE_VIBRATION_MS:Int = 10;

	/** A chord of four should be felt as one firm tap, not as four times a single note. */
	static inline var NOTE_VIBRATION_MAX_STACK:Int = 3;

	static var notesThisFrame:Int = 0;

	/**
	 * Asks for a pulse for a note that was just hit.
	 *
	 * Held until the end of the frame rather than fired here, because a chord arrives as
	 * several notes in the same loop and the motor cannot be told about them one at a time:
	 * each call restarts the pulse, so four notes would feel exactly like one. Counting them
	 * and firing once at the end of the frame is what makes a chord feel heavier.
	 *
	 * The motor lime exposes takes a duration and nothing else, where V-Slice's takes an
	 * amplitude, so a heavier hit is a longer pulse here rather than a stronger one.
	 */
	public static function vibrateNote():Void
	{
		#if mobile
		if (!ClientPrefs.data.vibration || !ClientPrefs.data.noteVibration) return;

		notesThisFrame++;
		#end
	}

	static function flushNoteVibration():Void
	{
		#if mobile
		if (notesThisFrame < 1) return;

		var stack:Int = (notesThisFrame < NOTE_VIBRATION_MAX_STACK) ? notesThisFrame : NOTE_VIBRATION_MAX_STACK;
		notesThisFrame = 0;

		vibrate(NOTE_VIBRATION_MS * stack);
		#end
	}

	/** True if any finger (or the mouse, when testing on desktop) is currently down. */
	public static function anyPressed():Bool
	{
		for (touch in FlxG.touches.list) if (touch.pressed) return true;
		return TouchButton.mouseEnabled && FlxG.mouse.pressed;
	}

	/** True on the frame a finger touches the screen anywhere. */
	public static function anyJustPressed():Bool
	{
		for (touch in FlxG.touches.list) if (touch.justPressed) return true;
		return TouchButton.mouseEnabled && FlxG.mouse.justPressed;
	}

	/**
	 * True if a finger went down anywhere that isn't on a live touch button.
	 * Menus that accept "tap anywhere" use this so the tap doesn't also count as
	 * a press on the virtual pad sitting on top of them.
	 */
	public static function justPressedOutsideButtons():Bool
	{
		if (!anyJustPressed()) return false;

		for (button in TouchButton.list)
			if (button.isAwake && button.justPressed) return false;

		return true;
	}
}

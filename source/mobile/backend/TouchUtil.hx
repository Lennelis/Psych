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
	}

	/** A short tap of the vibration motor, if the player left it on. */
	public static function vibrate(duration:Int = 15):Void
	{
		#if mobile
		if (!ClientPrefs.data.vibration) return;
		try
		{
			lime.ui.Haptic.vibrate(0, duration);
		}
		catch (e:Dynamic) {} // some devices/emulators have no motor to talk to
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

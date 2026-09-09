package mobile.objects;

import flixel.FlxG;
import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import flixel.util.FlxColor;

/**
 * Which directional buttons a pad shows.
 *
 * These are enum abstracts over String rather than plain enums so they can be
 * used as default argument values and written straight into the save file.
 */
enum abstract VirtualPadDPad(String) from String to String
{
	var NONE = 'none';
	var FULL = 'full';
	var UP_DOWN = 'up_down';
	var LEFT_RIGHT = 'left_right';
	var UP_LEFT_RIGHT = 'up_left_right';
}

/** Which action buttons a pad shows. */
enum abstract VirtualPadAction(String) from String to String
{
	var NO_BUTTON = 'none';
	var A = 'a';
	var B = 'b';
	var A_B = 'a_b';
	var A_B_C = 'a_b_c';
}

/**
 * The on-screen pad menus are driven with.
 *
 * Every button here carries the name of a `Controls` action, so `controls.UI_UP_P`,
 * `controls.ACCEPT` and friends light up on their own. That's the whole reason the
 * menu states needed almost no changes: they were already asking `Controls`, and
 * `Controls` now also looks at whatever pad is on screen.
 */
class VirtualPad extends FlxTypedSpriteGroup<TouchButton>
{
	public static var buttonSize:Int = 122;

	static inline var MARGIN:Int = 26;
	static inline var GAP:Int = 12;

	public var dPadMode(default, null):VirtualPadDPad;
	public var actionMode(default, null):VirtualPadAction;

	public function new(dPad:VirtualPadDPad = FULL, action:VirtualPadAction = A_B)
	{
		super();

		dPadMode = dPad;
		actionMode = action;

		scrollFactor.set();
		buildDPad(dPad);
		buildActions(action);
	}

	function buildDPad(mode:VirtualPadDPad):Void
	{
		final size:Int = buttonSize;
		final step:Int = size + GAP;
		final left:Float = MARGIN;
		final bottom:Float = FlxG.height - MARGIN - size;

		switch (mode)
		{
			case NONE:
			case FULL:
				// a cross, so a thumb resting in the middle can reach all four
				addButton('up', left + step, bottom - step * 2, ['ui_up']);
				addButton('left', left, bottom - step, ['ui_left']);
				addButton('right', left + step * 2, bottom - step, ['ui_right']);
				addButton('down', left + step, bottom, ['ui_down']);
			case UP_DOWN:
				addButton('up', left, bottom - step, ['ui_up']);
				addButton('down', left, bottom, ['ui_down']);
			case LEFT_RIGHT:
				addButton('left', left, bottom, ['ui_left']);
				addButton('right', left + step, bottom, ['ui_right']);
			case UP_LEFT_RIGHT:
				addButton('up', left + step, bottom - step, ['ui_up']);
				addButton('left', left, bottom, ['ui_left']);
				addButton('right', left + step * 2, bottom, ['ui_right']);
			default:
		}
	}

	function buildActions(mode:VirtualPadAction):Void
	{
		final size:Int = buttonSize;
		final step:Int = size + GAP;
		final right:Float = FlxG.width - MARGIN - size;
		final bottom:Float = FlxG.height - MARGIN - size;

		switch (mode)
		{
			case NO_BUTTON:
			case A:
				addButton('a', right, bottom, ['accept']);
			case B:
				addButton('b', right, bottom, ['back']);
			case A_B:
				addButton('b', right - step, bottom, ['back']);
				addButton('a', right, bottom, ['accept']);
			case A_B_C:
				addButton('c', right - step * 2, bottom, ['reset']);
				addButton('b', right - step, bottom, ['back']);
				addButton('a', right, bottom, ['accept']);
			default:
		}
	}

	/**
	 * Adds a button outside of the two standard clusters, for the odd state that
	 * needs one more thing to tap.
	 */
	public function addButton(symbol:String, x:Float, y:Float, actions:Array<String>, size:Int = -1):TouchButton
	{
		if (size <= 0) size = buttonSize;

		final button:TouchButton = new TouchButton(x, y, actions);
		button.setGraphic(symbol, size, size);
		button.idleAlpha = ClientPrefs.data.controlsAlpha;
		button.pressedAlpha = Math.min(1, ClientPrefs.data.controlsAlpha + 0.35);
		button.alpha = button.idleAlpha;
		button.antialiasing = ClientPrefs.data.antialiasing;
		add(button);
		return button;
	}

	/** The button standing in for `action`, or null. */
	public function getButton(action:String):TouchButton
	{
		for (button in members)
			if (button != null && button.hasAction(action)) return button;

		return null;
	}

	/** Drops any finger currently held on the pad. See `TouchButton.release`. */
	public function releaseAll():Void
	{
		for (button in members)
			if (button != null) button.release();
	}
}

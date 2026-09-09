package mobile.objects;

import flixel.FlxG;
import flixel.group.FlxSpriteGroup;
import flixel.util.FlxColor;

/**
 * The gameplay control layer: whichever of the touch layouts the player picked,
 * plus the pause button.
 *
 * Whatever the layout, `noteButtons` is always four entries in
 * `left, down, up, right` order, so `PlayState` wires itself up the same way for
 * all of them.
 */
class MobileControls extends FlxSpriteGroup
{
	public static final MODES:Array<String> = ['Hitbox', 'Pad-Right', 'Pad-Left', 'Keyboard'];

	public var noteButtons(default, null):Array<TouchButton> = [];
	public var hitbox(default, null):Hitbox;
	public var pauseButton(default, null):TouchButton;

	public function new()
	{
		super();

		scrollFactor.set();

		switch (ClientPrefs.data.gameplayControls)
		{
			case 'Pad-Right': buildPad(true);
			case 'Pad-Left': buildPad(false);
			case 'Keyboard': // player is on a bluetooth keyboard or a controller, give them a clean screen
			default: buildHitbox();
		}
	}

	function buildHitbox():Void
	{
		hitbox = new Hitbox();
		add(hitbox);

		for (i in 0...Hitbox.ACTIONS.length)
			noteButtons.push(hitbox.getLane(i));
	}

	function buildPad(rightSide:Bool):Void
	{
		final size:Int = VirtualPad.buttonSize;
		final step:Int = size + 12;
		final margin:Int = 26;
		final originX:Float = rightSide ? FlxG.width - margin - size - step * 2 : margin;
		final bottom:Float = FlxG.height - margin - size;

		// left, down, up, right laid out as a cross, in note-data order
		final layout:Array<Array<Float>> = [
			[originX, bottom - step],
			[originX + step, bottom],
			[originX + step, bottom - step * 2],
			[originX + step * 2, bottom - step]
		];
		final symbols:Array<String> = ['left', 'down', 'up', 'right'];

		for (i in 0...4)
		{
			final button:TouchButton = new TouchButton(layout[i][0], layout[i][1], [Hitbox.ACTIONS[i]]);
			button.setGraphic(symbols[i], size, size, noteColor(i));
			button.idleAlpha = ClientPrefs.data.controlsAlpha;
			button.pressedAlpha = Math.min(1, ClientPrefs.data.controlsAlpha + 0.35);
			button.alpha = button.idleAlpha;
			button.antialiasing = ClientPrefs.data.antialiasing;
			add(button);
			noteButtons.push(button);
		}
	}

	/** Adds the small pause button in the top right corner. */
	public function addPauseButton():TouchButton
	{
		if (pauseButton != null) return pauseButton;

		final size:Int = Std.int(VirtualPad.buttonSize * 0.6);
		pauseButton = new TouchButton(FlxG.width - size - 20, 20, ['pause']);
		pauseButton.setGraphic('II', size, size);
		pauseButton.idleAlpha = ClientPrefs.data.controlsAlpha;
		pauseButton.pressedAlpha = 1;
		pauseButton.alpha = pauseButton.idleAlpha;
		pauseButton.antialiasing = ClientPrefs.data.antialiasing;
		add(pauseButton);
		return pauseButton;
	}

	public function releaseAll():Void
	{
		for (button in noteButtons)
			if (button != null) button.release();

		if (pauseButton != null) pauseButton.release();
	}

	static function noteColor(i:Int):FlxColor
	{
		final colors:Array<Array<FlxColor>> = ClientPrefs.data.arrowRGB;
		if (colors != null && colors[i] != null && colors[i].length > 0) return colors[i][0];

		return FlxColor.WHITE;
	}
}

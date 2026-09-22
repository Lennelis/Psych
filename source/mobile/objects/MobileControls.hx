package mobile.objects;

import backend.VSliceVisuals;
import flixel.FlxG;
import flixel.group.FlxSpriteGroup;
import flixel.util.FlxColor;
import objects.Note;

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
	public static final MODES:Array<String> = ['Hitbox', 'Arrows', 'Pad-Right', 'Pad-Left', 'Keyboard'];

	public var noteButtons(default, null):Array<TouchButton> = [];
	public var hitbox(default, null):Hitbox;
	public var pauseButton(default, null):TouchButton;

	/** The faint disc the base game sits behind its pause button. Null without the art. */
	public var pauseCircle(default, null):FlxSprite;

	public function new()
	{
		super();

		scrollFactor.set();

		switch (ClientPrefs.data.gameplayControls)
		{
			case 'Arrows': buildArrows();
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

	/**
	 * Four arrow buttons standing in the player's own note columns, which is what V-Slice's
	 * Arrows scheme is: its hit zones sit on the receptors rather than off to one side, so the
	 * thing being tapped is the thing being aimed at.
	 *
	 * The columns are worked out the way `StrumNote.playerPosition` works them out, so they line
	 * up with the receptors whether middlescroll is on or off, and they are exactly one note wide
	 * so the four tile the lane grid without any two of them sharing a finger.
	 *
	 * The row sits near the bottom rather than on the strumline itself, because upscroll puts the
	 * receptors at the top of the screen where no thumb reaches. On downscroll it lands on them,
	 * which is the V-Slice arrangement.
	 */
	function buildArrows():Void
	{
		final width:Int = Std.int(Note.swagWidth);
		final height:Int = Std.int(Note.swagWidth * 1.25);

		// StrumNote: x = strumLineX + 50 + (FlxG.width / 2) * player, then swagWidth per column.
		var left:Float = (ClientPrefs.data.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X) + 50 + FlxG.width / 2;
		if (VSliceVisuals.strumline && !ClientPrefs.data.middleScroll) left += VSliceVisuals.STRUM_X_NUDGE;

		final top:Float = FlxG.height - height - 26;
		final symbols:Array<String> = ['left', 'down', 'up', 'right'];

		for (i in 0...symbols.length)
		{
			final button:TouchButton = new TouchButton(left + Note.swagWidth * i, top, [Hitbox.ACTIONS[i]]);
			button.setGraphic(symbols[i], width, height, noteColor(i));
			button.allowSlideIn = true; // rolls are played by sliding a thumb across, same as the lanes
			button.idleAlpha = ClientPrefs.data.controlsAlpha;
			button.pressedAlpha = Math.min(1, ClientPrefs.data.controlsAlpha + 0.35);
			button.alpha = button.idleAlpha;
			button.antialiasing = ClientPrefs.data.antialiasing;
			add(button);
			noteButtons.push(button);
		}
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

	/**
	 * Adds the pause button in the top right corner, the way the base game has it: the
	 * button sprite over a faint disc, tapped to pause.
	 *
	 * The numbers are V-Slice's own, from `PlayState.initPauseSprites` - the button at
	 * 0.8 scale, 35px in from the corner, the disc at 0.84 by 0.8 behind it at a tenth
	 * opacity. It sits at full opacity there whatever the other controls are set to, so
	 * it does here too.
	 *
	 * Without the art it falls back to the drawn button the pads use, so a build missing
	 * those files still has a way to pause.
	 */
	public function addPauseButton():TouchButton
	{
		if (pauseButton != null) return pauseButton;

		pauseButton = new TouchButton(0, 0, ['pause']);
		pauseButton.idleAlpha = 1;
		pauseButton.pressedAlpha = 1;
		pauseButton.antialiasing = ClientPrefs.data.antialiasing;

		// Frames 6 to 32 are the squash and bounce V-Slice gives the same sheet on its
		// back button. The game pauses on the press, so what is actually seen is the
		// squash it freezes on while the menu is up, and the bounce back on resume.
		if (pauseButton.setSparrowGraphic('pauseButton', 'pause', 0, 0.8, [for (i in 6...33) i]))
		{
			pauseButton.setPosition(FlxG.width - pauseButton.width - 35, 35);
			addPauseCircle();
		}
		else
		{
			final size:Int = Std.int(VirtualPad.buttonSize * 0.6);
			pauseButton.setGraphic('II', size, size);
			pauseButton.idleAlpha = ClientPrefs.data.controlsAlpha;
			pauseButton.setPosition(FlxG.width - size - 20, 20);
		}

		pauseButton.alpha = pauseButton.idleAlpha;
		add(pauseButton);

		// A tap on the pause button must not be played as a note by the lane underneath
		// it: the button hangs into the top of the rightmost one.
		if (hitbox != null)
			for (i in 0...Hitbox.ACTIONS.length)
			{
				final lane:TouchButton = hitbox.getLane(i);
				if (lane != null) lane.deadZones.push(pauseButton);
			}

		return pauseButton;
	}

	function addPauseCircle():Void
	{
		if (!Paths.fileExists('images/pauseCircle.png', IMAGE)) return;

		pauseCircle = new FlxSprite();
		pauseCircle.loadGraphic(Paths.image('pauseCircle'));
		pauseCircle.scale.set(0.84, 0.8);
		pauseCircle.updateHitbox();
		pauseCircle.setPosition(pauseButton.x + (pauseButton.width - pauseCircle.width) * 0.5,
			pauseButton.y + (pauseButton.height - pauseCircle.height) * 0.5);
		pauseCircle.alpha = 0.1;
		pauseCircle.antialiasing = ClientPrefs.data.antialiasing;
		pauseCircle.scrollFactor.set();
		add(pauseCircle); // before the button, so it sits behind it
	}

	public function releaseAll():Void
	{
		for (button in noteButtons)
			if (button != null) button.release();

		if (pauseButton != null) pauseButton.release();
	}

	/** Hides or shows the note controls, leaving the pause button to the two below. */
	public function setGameplayVisible(value:Bool):Void
	{
		if (hitbox != null) hitbox.visible = value;

		for (button in noteButtons)
			if (button != null) button.visible = value;
	}

	/**
	 * Clears the controls away as the pause menu opens.
	 *
	 * The button and its disc go out instantly rather than fading, because the menu
	 * draws its own copy of them mid-press over the top - the same split V-Slice makes
	 * between `preparePauseUI` here and `transitionIn` there.
	 */
	public function onPause():Void
	{
		releaseAll();
		setGameplayVisible(false);

		if (pauseButton != null)
		{
			pauseButton.playIdleAnim();
			pauseButton.alpha = 0;
		}

		if (pauseCircle != null)
		{
			flixel.tweens.FlxTween.cancelTweensOf(pauseCircle);
			pauseCircle.alpha = 0;
		}
	}

	/** Brings them back as play resumes, over a quarter of a second as V-Slice does. */
	public function onResume():Void
	{
		releaseAll();
		setGameplayVisible(true);

		// The button fades in on its own: TouchButton eases its alpha towards idleAlpha
		// every frame, so leaving it at zero is the fade.
		if (pauseButton != null) pauseButton.alpha = 0;

		if (pauseCircle != null)
		{
			flixel.tweens.FlxTween.cancelTweensOf(pauseCircle);
			pauseCircle.alpha = 0;
			flixel.tweens.FlxTween.tween(pauseCircle, {alpha: 0.1}, 0.25, {ease: flixel.tweens.FlxEase.quartOut});
		}
	}

	static function noteColor(i:Int):FlxColor
	{
		final colors:Array<Array<FlxColor>> = ClientPrefs.data.arrowRGB;
		if (colors != null && colors[i] != null && colors[i].length > 0) return colors[i][0];

		return FlxColor.WHITE;
	}
}

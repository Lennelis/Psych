package mobile.objects;

import flixel.FlxG;
import flixel.group.FlxSpriteGroup;
import flixel.util.FlxColor;
import objects.StrumNote;

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

	/** The receptors the Arrows scheme draws behind its hit zones. Empty for every other layout. */
	public var arrowStrums(default, null):Array<StrumNote> = [];
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
	 * V-Slice's Arrows scheme: four receptors in a row across the lower half of the screen,
	 * each one tapped to play its lane.
	 *
	 * The numbers are `FunkinHitbox`'s own, down to the trailing gap its centring arithmetic
	 * counts in - the row is a spacing's worth left of true centre there, and moving it would
	 * be a different layout rather than the same one.
	 *
	 * What is tapped and what is drawn are two objects, as they are in V-Slice: a hit zone the
	 * full 146 by 149, and a receptor centred inside it. Making the receptor itself the button
	 * would tie the tappable area to the art, which is a good deal smaller than the zone and
	 * would cost the player every near miss the zone is there to catch.
	 *
	 * The receptor is a real `StrumNote`, so the note skin, the pixel stages and the Note
	 * Colors setting all reach it without a word of this knowing about any of them. Holding a
	 * lane shows the press art and keeps it up, which `StrumNote.update` already does off
	 * `keyHeld` for the strumline - it only has to be told what is held.
	 *
	 * V-Slice draws none of this: its hints are left at zero alpha in play and only the
	 * options preview turns them up. Here they follow the Controls Opacity setting instead, so
	 * that arrangement is still a setting away rather than the only one on offer.
	 */
	function buildArrows():Void
	{
		final hintWidth:Int = 146;
		final hintHeight:Int = 149;
		final noteSpacing:Int = 80;

		final xPos:Float = Math.floor((FlxG.width - (hintWidth + noteSpacing) * 4) / 2);
		final yPos:Float = Math.floor(FlxG.height - hintHeight * 2 - 24);

		for (i in 0...4)
		{
			// Transparent rather than hidden: `TouchButton` ignores a button it can't see, so
			// an invisible one would take no taps at all.
			final button:TouchButton = new TouchButton(xPos + i * (hintWidth + noteSpacing), yPos, [Hitbox.ACTIONS[i]]);
			button.makeGraphic(hintWidth, hintHeight, FlxColor.TRANSPARENT);
			button.allowSlideIn = true; // rolls are played by sliding a thumb across, same as the lanes
			button.alphaTweenSpeed = 0;
			button.idleAlpha = 1;
			button.pressedAlpha = 1;
			button.alpha = 1;
			add(button);
			noteButtons.push(button);

			final strum:StrumNote = new StrumNote(0, 0, i, 0);
			strum.setPosition(button.x + (hintWidth - strum.width) * 0.5, button.y + (hintHeight - strum.height) * 0.5);
			strum.alpha = ClientPrefs.data.controlsAlpha;
			add(strum);
			arrowStrums.push(strum);
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

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// A frame behind what the buttons report, the same way the strumline's own is a frame
		// behind the keyboard - `StrumNote` reads this in its update and both orders settle in
		// one frame either way.
		for (i in 0...arrowStrums.length)
			if (arrowStrums[i] != null && i < noteButtons.length && noteButtons[i] != null)
				arrowStrums[i].keyHeld = noteButtons[i].pressed;
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

		for (strum in arrowStrums)
			if (strum != null) strum.visible = value;
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

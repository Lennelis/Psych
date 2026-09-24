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

	/** Whether the Arrows layout is the one in use, so its zones know to chase the receptors. */
	var followingStrums:Bool = false;

	/**
	 * The tap zone, in pixels, as V-Slice ends up sizing it.
	 *
	 * `FunkinHint.update` asks for `followTarget.width * 1.35` by `height * 8`, and what it is
	 * asking is the receptor's *frame* at the note style's 0.7 - 232 by 236 of it - because
	 * `strumlineScaleCallback` sets the scale without calling `updateHitbox`, so `width` and
	 * `height` never hear about the 1.096875. Measuring Psych's receptor instead gave a zone
	 * two thirds the size, since our sheet has no frame padding to measure.
	 *
	 * 219 across against 193 between lanes is the overlap: about 13px of each zone lies under
	 * its neighbour, which is what lets a thumb slide from one note to the next without ever
	 * being over nothing.
	 */
	static inline var ZONE_WIDTH:Float = 219.24; // 232 * 0.7 * 1.35

	static inline var ZONE_HEIGHT:Float = 1321.6; // 236 * 0.7 * 8

	/**
	 * Where its top left sits relative to the middle of the arrow.
	 *
	 * V-Slice measures from the frame's corner and backs off by `width * 0.175` and a flat
	 * 220; both of those are here, plus the padding between that corner and the art, so this
	 * can be taken from the one thing the two engines agree on - where the arrow looks like it
	 * is.
	 */
	static inline var ZONE_LEFT:Float = 115.9507; // 232*0.7*0.175 + 37*0.7678125 + 154*0.7678125/2

	static inline var ZONE_TOP:Float = 309.4502; // 220 + 38*0.7678125 + 157*0.7678125/2

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
	 * V-Slice's Arrows scheme: tap the receptors themselves.
	 *
	 * Its hints draw nothing - `createHintTransparentNote` leaves them at zero alpha - and
	 * `PlayState` then hands each one to `FunkinHint.follow` against the matching receptor, so
	 * what is on screen is the strumline and the zones are only where the taps land. Arrows of
	 * our own underneath it would be a second set of the same four, which is what was here
	 * before and read as ghosts.
	 *
	 * The zone is bigger than the receptor on purpose, and V-Slice's numbers say how much: a
	 * third again as wide as the frame, eight times as tall, starting 220px above. That comes
	 * out as a column down the lane, wide enough to overlap its neighbours by about 13px on
	 * each side - so a thumb sliding from one note to the next is never over nothing, and one
	 * aimed at a note still on its way in plays it anyway.
	 *
	 * These coordinates are V-Slice's starting placement, which is all they are there too:
	 * they hold for the moment before the strumline exists, and `followStrums` has them from
	 * the first frame after.
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
			// A one pixel transparent graphic, sized by hand afterwards: `TouchButton` ignores
			// a button it cannot see, so an invisible one would take no taps at all, and there
			// is no art to load when the receptor is the art.
			final button:TouchButton = new TouchButton(xPos + i * (hintWidth + noteSpacing), yPos, [Hitbox.ACTIONS[i]]);
			button.makeGraphic(1, 1, FlxColor.TRANSPARENT);
			button.setSize(hintWidth, hintHeight);
			button.allowSlideIn = true; // rolls are played by sliding a thumb across, same as the lanes
			button.exclusive = true; // the zones overlap, so a finger in the seam belongs to one of them
			button.alphaTweenSpeed = 0;
			button.idleAlpha = 1;
			button.pressedAlpha = 1;
			button.alpha = 1;
			add(button);
			noteButtons.push(button);
		}

		followingStrums = true;
	}

	/**
	 * Keeps the Arrows zones over the receptors, the way `FunkinHint.follow` does.
	 *
	 * Looked up rather than handed over, because the strums do not exist yet when this is
	 * built - the song generates them later - and a zone that has not found its receptor yet
	 * simply stays where it was placed.
	 */
	function followStrums():Void
	{
		final state:states.PlayState = states.PlayState.instance;
		if (state == null || state.playerStrums == null) return;

		for (i in 0...noteButtons.length)
		{
			final button:TouchButton = noteButtons[i];
			final strum:StrumNote = state.playerStrums.members[i];
			if (button == null || strum == null) continue;

			button.setSize(ZONE_WIDTH, ZONE_HEIGHT);
			button.setPosition(strum.x + strum.width * 0.5 - ZONE_LEFT, strum.y + strum.height * 0.5 - ZONE_TOP);
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

		// A tap on the pause button must not be played as a note by whatever is underneath it.
		// The hitbox's rightmost lane reaches the top of the screen, and so does the Arrows
		// scheme's rightmost column once it has found its receptor - 220px above an upscroll
		// strumline is above the top of the screen.
		for (button in noteButtons)
			if (button != null) button.deadZones.push(pauseButton);

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

		if (followingStrums) followStrums();
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

package objects;

class SustainSplash extends FlxSprite
{
	public static var startCrochet:Float;

	/**
	 * How fast the looping cover plays, in frames per second.
	 *
	 * This used to be derived from the song's BPM (24/100 * bpm), so the loop ran at the
	 * sheet's authored speed only at exactly 100BPM and drifted either side of it - 38fps
	 * at 160. The end animation was already pinned to 24, so only the loop wandered.
	 * V-Slice runs its covers at a fixed rate, and so does this.
	 */
	public static var frameRate:Int = 24;

	public var strumNote:StrumNote;

	/**
	 * The sheet a pixel stage uses instead of pixelating the ordinary one, and how
	 * V-Slice's own `pixel` note style places it: scale 6, offsets [29, -4], no
	 * antialiasing, animations named `loop` and `explode`. The two adjustments below
	 * are V-Slice's as well - its Strumline applies them on top of the offsets, with
	 * the comment "hardcoded adjustment, because we are evil".
	 */
	public static inline var PIXEL_PATH:String = 'holdCovers/pixelNoteHoldCover';

	static inline var PIXEL_SCALE:Float = 6;
	static inline var PIXEL_OFFSET_X:Float = 29;
	static inline var PIXEL_OFFSET_Y:Float = -4;
	static inline var PIXEL_NUDGE_X:Float = -12;
	static inline var PIXEL_NUDGE_Y:Float = -96;

	/** True when this cover is drawing the pixel sheet rather than the ordinary one. */
	public var usingPixel(default, null):Bool = false;

	var timer:FlxTimer;

	public function new():Void
	{
		super();

		x = -50000;

		// A pixel stage gets the pixel sheet where there is one. Its animations are named
		// differently because it is V-Slice's own art, not a recolour of the normal sheet.
		if (PlayState.isPixelStage && Paths.fileExists('images/' + PIXEL_PATH + '.png', IMAGE))
		{
			frames = Paths.getSparrowAtlas(PIXEL_PATH);
			if (frames != null)
			{
				animation.addByPrefix('hold', 'loop', 24, true);
				animation.addByPrefix('end', 'explode', 24, false);
				usingPixel = animation.getNameList().contains("hold");
			}
		}

		if (!usingPixel)
		{
			frames = Paths.getSparrowAtlas('holdCovers/holdCover-' + ClientPrefs.data.holdSkin);

			animation.addByPrefix('hold', 'holdCover0', 24, true);
			animation.addByPrefix('end', 'holdCoverEnd0', 24, false);
			if(!animation.getNameList().contains("hold")) trace("Hold splash is missing 'hold' anim!");
		}
	}

	override function update(elapsed)
	{
		super.update(elapsed);

		if (strumNote != null)
		{
			setPosition(strumNote.x, strumNote.y);
			visible = strumNote.visible;
			alpha = ClientPrefs.data.holdSplashAlpha - (1 - strumNote.alpha);

			if (animation.curAnim?.name == "hold" && strumNote.animation.curAnim?.name == "static")
			{
				x = -50000;
				kill();
			}
		}
	}

	public function setupSusSplash(strum:StrumNote, daNote:Note, ?playbackRate:Float = 1):Void
	{
		final lengthToGet:Int = !daNote.isSustainNote ? daNote.tail.length : daNote.parent.tail.length;
		final timeToGet:Float = !daNote.isSustainNote ? daNote.strumTime : daNote.parent.strumTime;
		final timeThingy:Float = (startCrochet * lengthToGet + (timeToGet - Conductor.songPosition + ClientPrefs.data.ratingOffset)) / playbackRate * .001;

		var tailEnd:Note = !daNote.isSustainNote ? daNote.tail[daNote.tail.length - 1] : daNote.parent.tail[daNote.parent.tail.length - 1];

		animation.play('hold', true, false, 0);
		if (animation.curAnim != null)
		{
			animation.curAnim.frameRate = frameRate;
			animation.curAnim.looped = true;
		}
		// The -210 is a fudge for the ordinary sheet being stretched onto a pixel stage.
		// The pixel sheet is drawn at its own size and wants none of it.
		clipRect = usingPixel ? null : new flixel.math.FlxRect(0, !PlayState.isPixelStage ? 0 : -210, frameWidth, frameHeight);

		if (daNote.shader != null && !usingPixel)
		{
			shader = new objects.NoteSplash.PixelSplashShaderRef().shader;
			shader.data.r.value = daNote.shader.data.r.value;
			shader.data.g.value = daNote.shader.data.g.value;
			shader.data.b.value = daNote.shader.data.b.value;
			shader.data.mult.value = daNote.shader.data.mult.value;
		}

		strumNote = strum;
		alpha = ClientPrefs.data.holdSplashAlpha - (1 - strumNote.alpha);

		if (usingPixel)
		{
			antialiasing = false;
			scale.set(PIXEL_SCALE, PIXEL_SCALE);
			updateHitbox(); // this writes offset, so it has to come before setting it

			// V-Slice centres the cover on the strum, then applies its offsets times the
			// scale and its two nudges. Working that back through flixel's
			// `drawn_left = x - offset + origin * (1 - scale)` cancels the scale out of
			// everything but the offsets themselves.
			offset.set(frameWidth * 0.5 - strum.width * 0.5 - PIXEL_OFFSET_X * scale.x - PIXEL_NUDGE_X,
				frameHeight * 0.5 - strum.height * 0.5 - PIXEL_OFFSET_Y * scale.y - PIXEL_NUDGE_Y);
		}
		else
			offset.set(PlayState.isPixelStage ? 112.5 : 106.25, 100);

		if (timer != null)
			timer.cancel();

		if (!daNote.hitByOpponent && ClientPrefs.data.holdSplashAlpha != 0)
			timer = new FlxTimer().start(timeThingy, (idk:FlxTimer) ->
			{
				if (!(daNote.isSustainNote ? daNote.parent.noteSplashData.disabled : daNote.noteSplashData.disabled) && animation != null)
				{
					alpha = ClientPrefs.data.holdSplashAlpha - (1 - strumNote.alpha);
					animation.play('end', true, false, 0);
					if (animation.curAnim != null)
					{
						animation.curAnim.looped = false;
						animation.curAnim.frameRate = 24;
					}
					clipRect = null;
					animation.finishCallback = (idkEither:Dynamic) ->
					{
						kill();
					}
					return;
				}
				kill();
			});
	}
}

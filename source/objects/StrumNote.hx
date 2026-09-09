package objects;

import backend.animation.PsychAnimationController;

import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;

class StrumNote extends FlxSprite
{
	public var rgbShader:RGBShaderReference;
	public var resetAnim:Float = 0;

	/**
	 * How long the confirm animation stays up after it has finished playing, before
	 * the strum drops back. Ported from V-Slice, where it lives on
	 * `funkin.play.notes.StrumlineNote` as `CONFIRM_HOLD_TIME`.
	 */
	public static var CONFIRM_HOLD_TIME:Float = 0.15;

	/**
	 * Whether this lane's key is being held. `PlayState` keeps it up to date for the
	 * player's strums; it stays false for the opponent, which is what makes them fall
	 * back to 'static' instead of the ghost tap.
	 */
	public var keyHeld:Bool = false;

	/**
	 * Whether a sustain is still being held in this lane. `PlayState` keeps it up to
	 * date.
	 *
	 * Psych splits a sustain into a piece per step and only hits one as each comes
	 * into range, so between pieces the confirm animation finishes and sits on its
	 * last frame. Without knowing a hold is still going, that finish would arm the
	 * fallback below and the strum would flick to the ghost tap over and over for
	 * the length of the hold.
	 */
	public var holdingSustain:Bool = false;

	/** Counts up once the glow has finished playing. -1 when nothing is pending. */
	var confirmHoldTimer:Float = -1;

	/**
	 * Whether the glow belongs to a hold rather than a tap.
	 *
	 * `holdingSustain` covers the player, whose lane PlayState tracks every frame. The
	 * opponent has no such bookkeeping, so this is set by `holdConfirm` instead and
	 * cleared as soon as anything but a glow plays.
	 */
	var sustainConfirm:Bool = false;

	inline function inHold():Bool
		return holdingSustain || sustainConfirm;
	private var noteData:Int = 0;
	public var direction:Float = 90;
	public var downScroll:Bool = false;
	public var sustainReduce:Bool = true;
	private var player:Int;
	
	public var texture(default, set):String = null;
	private function set_texture(value:String):String {
		if(texture != value) {
			texture = value;
			reloadNote();
		}
		return value;
	}

	public var useRGBShader:Bool = true;
	public function new(x:Float, y:Float, leData:Int, player:Int) {
		animation = new PsychAnimationController(this);

		rgbShader = new RGBShaderReference(this, Note.initializeGlobalRGBShader(leData));
		rgbShader.enabled = false;
		if(PlayState.SONG != null && PlayState.SONG.disableNoteRGB) useRGBShader = false;
		
		var arr:Array<FlxColor> = ClientPrefs.data.arrowRGB[leData];
		if(PlayState.isPixelStage) arr = ClientPrefs.data.arrowRGBPixel[leData];
		
		if(leData <= arr.length)
		{
			@:bypassAccessor
			{
				rgbShader.r = arr[0];
				rgbShader.g = arr[1];
				rgbShader.b = arr[2];
			}
		}

		noteData = leData;
		this.player = player;
		this.noteData = leData;
		this.ID = noteData;
		super(x, y);

		var skin:String = null;
		if(PlayState.SONG != null && PlayState.SONG.arrowSkin != null && PlayState.SONG.arrowSkin.length > 1) skin = PlayState.SONG.arrowSkin;
		else skin = Note.defaultNoteSkin;

		var customSkin:String = skin + Note.getNoteSkinPostfix();
		if(Paths.fileExists('images/$customSkin.png', IMAGE)) skin = customSkin;

		texture = skin; //Load texture and anims
		scrollFactor.set();
		animation.finishCallback = onAnimationFinished;
		playAnim('static');
	}

	public function reloadNote()
	{
		var lastAnim:String = null;
		if(animation.curAnim != null) lastAnim = animation.curAnim.name;

		if(PlayState.isPixelStage)
		{
			loadGraphic(Paths.image('pixelUI/' + texture));
			width = width / 4;
			height = height / 5;
			loadGraphic(Paths.image('pixelUI/' + texture), true, Math.floor(width), Math.floor(height));

			antialiasing = false;
			setGraphicSize(Std.int(width * PlayState.daPixelZoom));

			animation.add('green', [6]);
			animation.add('red', [7]);
			animation.add('blue', [5]);
			animation.add('purple', [4]);
			switch (Math.abs(noteData) % 4)
			{
				case 0:
					animation.add('static', [0]);
					animation.add('pressed', [4, 8], 12, false);
					animation.add('confirm', [12, 16], 24, false);
				case 1:
					animation.add('static', [1]);
					animation.add('pressed', [5, 9], 12, false);
					animation.add('confirm', [13, 17], 24, false);
				case 2:
					animation.add('static', [2]);
					animation.add('pressed', [6, 10], 12, false);
					animation.add('confirm', [14, 18], 12, false);
				case 3:
					animation.add('static', [3]);
					animation.add('pressed', [7, 11], 12, false);
					animation.add('confirm', [15, 19], 24, false);
			}
		}
		else
		{
			frames = Paths.getSparrowAtlas(texture);
			animation.addByPrefix('green', 'arrowUP');
			animation.addByPrefix('blue', 'arrowDOWN');
			animation.addByPrefix('purple', 'arrowLEFT');
			animation.addByPrefix('red', 'arrowRIGHT');

			antialiasing = ClientPrefs.data.antialiasing;
			setGraphicSize(Std.int(width * 0.7));

			switch (Math.abs(noteData) % 4)
			{
				case 0:
					animation.addByPrefix('static', 'arrowLEFT');
					animation.addByPrefix('pressed', 'left press', 24, false);
					animation.addByPrefix('confirm', 'left confirm', 24, false);
				case 1:
					animation.addByPrefix('static', 'arrowDOWN');
					animation.addByPrefix('pressed', 'down press', 24, false);
					animation.addByPrefix('confirm', 'down confirm', 24, false);
				case 2:
					animation.addByPrefix('static', 'arrowUP');
					animation.addByPrefix('pressed', 'up press', 24, false);
					animation.addByPrefix('confirm', 'up confirm', 24, false);
				case 3:
					animation.addByPrefix('static', 'arrowRIGHT');
					animation.addByPrefix('pressed', 'right press', 24, false);
					animation.addByPrefix('confirm', 'right confirm', 24, false);
			}
		}
		// The second pass of the glow, which a hold freezes on. Same frames as 'confirm'
		// either way, exactly as V-Slice's note style points 'confirm-hold' back at the
		// confirm frames - taken from the animation itself so a skin only has to define
		// the one, pixel and otherwise.
		var confirmAnim:flixel.animation.FlxAnimation = animation.getByName('confirm');
		if(confirmAnim != null) animation.add('confirm-hold', confirmAnim.frames.copy(), confirmAnim.frameRate, false);

		updateHitbox();

		if(lastAnim != null)
		{
			playAnim(lastAnim, true);
		}
	}

	public function playerPosition()
	{
		x += Note.swagWidth * noteData;
		x += 50;
		x += ((FlxG.width / 2) * player);
	}

	function onAnimationFinished(name:String):Void
	{
		// A hold gets the glow a second time and then freezes on its last frame, which is
		// V-Slice going from 'confirm' to 'confirm-hold' and leaving it there.
		if(name == 'confirm' && inHold() && animation.exists('confirm-hold'))
		{
			playAnim('confirm-hold', true);
			return;
		}

		// resetAnim means something else already owns the revert - the opponent's
		// strums, or the player's under botplay - so don't fight it. A hold that's
		// still running keeps the glow up until PlayState says it ended.
		if((name == 'confirm' || name == 'confirm-hold') && resetAnim <= 0 && !inHold()) confirmHoldTimer = 0;
	}

	/**
	 * Drops the confirm animation right now, skipping the grace period.
	 *
	 * V-Slice ends a hold with no delay at all, unlike a tapped note, so `PlayState`
	 * calls this the moment a sustain runs out.
	 */
	public function finishConfirm():Void
	{
		confirmHoldTimer = -1;
		if(animation.curAnim != null && (animation.curAnim.name == 'confirm' || animation.curAnim.name == 'confirm-hold'))
			playAnim(keyHeld ? 'pressed' : 'static');
	}

	override function update(elapsed:Float) {
		if(resetAnim > 0) {
			resetAnim -= elapsed;
			if(resetAnim <= 0) {
				playAnim('static');
				resetAnim = 0;
			}
		}

		if(confirmHoldTimer >= 0)
		{
			confirmHoldTimer += elapsed;
			if(confirmHoldTimer >= CONFIRM_HOLD_TIME)
			{
				confirmHoldTimer = -1;
				playAnim(keyHeld ? 'pressed' : 'static');
			}
		}
		else if(keyHeld && animation.curAnim != null && animation.curAnim.name == 'static')
		{
			// V-Slice re-checks this every frame: a held key never sits on 'static'.
			playAnim('pressed');
		}

		super.update(elapsed);
	}

	/**
	 * Keeps a hold's glow going without starting it over.
	 *
	 * Psych takes a sustain one piece per step and plays 'confirm' again on each of
	 * them, so the bright first frame re-fired the whole way through a hold. V-Slice's
	 * `StrumlineNote.holdConfirm` instead lets the glow run once, follows it with
	 * 'confirm-hold', and leaves that sitting on its last frame until the hold is over.
	 * A glow already running is left alone here, and `onAnimationFinished` moves it on.
	 */
	/** Lights the strum for a tapped note: a fresh glow, with no hold behind it. */
	public function tapConfirm():Void
	{
		sustainConfirm = false;
		playAnim('confirm', true);
	}

	public function holdConfirm():Void
	{
		sustainConfirm = true;

		if(animation.curAnim == null)
		{
			playAnim('confirm', true);
			return;
		}

		switch(animation.curAnim.name)
		{
			case 'confirm': // still running, or waiting on its finish callback
			case 'confirm-hold': // second pass, or frozen at the end of one
			default: playAnim('confirm', true);
		}
	}

	public function playAnim(anim:String, ?force:Bool = false) {
		// Anything but the glow cancels a pending fallback, so releasing the key mid-wait
		// can't have it fire afterwards, and ends the hold as far as the glow is
		// concerned.
		if(anim != 'confirm' && anim != 'confirm-hold')
		{
			confirmHoldTimer = -1;
			sustainConfirm = false;
		}
		animation.play(anim, force);
		if(animation.curAnim != null)
		{
			centerOffsets();
			centerOrigin();
		}
		if(useRGBShader) rgbShader.enabled = (animation.curAnim != null && animation.curAnim.name != 'static');
	}
}

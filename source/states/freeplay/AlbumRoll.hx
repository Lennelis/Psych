package states.freeplay;

import flixel.group.FlxSpriteGroup;
import flxanimate.PsychFlxAnimate;
import shaders.freeplay.HSVShader;
import states.freeplay.VSliceFreeplayState.ExitMoverData;

/**
 * The album art and its title, bottom right of the freeplay menu.
 *
 * Ported from V-Slice. The art is an Animate atlas that rolls the cover in, and the
 * cover itself is a placeholder symbol inside it that gets swapped for whichever album
 * the song belongs to - which needed a `replaceSymbolGraphic` adding to Psych's
 * flxanimate, since the version it carries had none.
 *
 * Which album a song belongs to is V-Slice metadata that Psych has no equivalent of, so
 * everything is Volume 1 unless something says otherwise. The rest of the covers ship
 * with the art, so a week only needs somewhere to declare one.
 */
class AlbumRoll extends FlxSpriteGroup
{
	/**
	 * The ID of the album to display.
	 * Modify this value to automatically update the album art and title.
	 */
	public var albumId(default, set):String;

	function set_albumId(value:String):String
	{
		if (this.albumId != value || value == null)
		{
			this.albumId = value;
			updateAlbum();
		}

		return value;
	}

	final ALBUM_ART_SYMBOL:String = 'album art placeholder';

	/** Where the cover sits inside its own atlas, read off the symbol's matrix. */
	static inline var ART_OFFSET_X:Float = 692.45;

	static inline var ART_OFFSET_Y:Float = 269;

	var newAlbumArt:PsychFlxAnimate;
	var albumTitle:FlxSprite = null;
	var difficultyStars:DifficultyStars;
	var _exitMovers:ExitMoverData;

	public function new()
	{
		super();

		// V-Slice wants the cover at (width - 360, 220), and the atlas draws it 692 right
		// and 269 down of wherever the sprite is - that is where the artist put it inside
		// the symbol, and it is in the matrices in Animation.json. Taking that back off
		// is what stops the cover being drawn off the right of the screen.
		newAlbumArt = new PsychFlxAnimate(FlxG.width - 360 - ART_OFFSET_X, 220 - ART_OFFSET_Y);
		try
		{
			Paths.loadAnimateAtlas(newAlbumArt, 'freeplay/albumRoll/freeplayAlbum');
			newAlbumArt.anim.addByFrameLabel('intro', 'intro', 24, false);
			newAlbumArt.anim.addByFrameLabel('switch', 'switch', 24, false);
			newAlbumArt.anim.addByFrameLabel('idle', 'idle', 24, true);
		}
		catch (e:Dynamic)
			trace('AlbumRoll: could not load the album atlas ($e)');

		newAlbumArt.antialiasing = ClientPrefs.data.antialiasing;
		newAlbumArt.visible = false;

		difficultyStars = new DifficultyStars(FlxG.width - 330, 209);
		difficultyStars.visible = false;

		add(newAlbumArt);
		add(difficultyStars);

		buildAlbumTitle('freeplay/albumRoll/volume1-text');
		if (albumTitle != null) albumTitle.visible = false;

		newAlbumArt.anim.onComplete.add(onAlbumFinish);
	}

	function onAlbumFinish():Void
	{
		// Play the idle animation for the current album.
		if (playing != 'idle')
		{
			playing = 'idle';
			newAlbumArt.anim.play('idle', true);
		}
	}

	var playing:String = null;

	/**
	 * Load the album data by ID and update the textures.
	 */
	function updateAlbum():Void
	{
		if (albumId == null)
		{
			this.visible = false;
			return;
		}
		else
			this.visible = true;

		// Update the album art.
		var artKey:String = 'freeplay/albumRoll/$albumId';
		if (Paths.fileExists('images/$artKey.png', IMAGE)) newAlbumArt.replaceSymbolGraphic(ALBUM_ART_SYMBOL, Paths.image(artKey));

		buildAlbumTitle('freeplay/albumRoll/$albumId-text');
		applyExitMovers();
	}

	/**
	 * Apply exit movers for the album roll.
	 * @param exitMovers The exit movers to apply.
	 */
	public function applyExitMovers(?exitMovers:ExitMoverData):Void
	{
		if (exitMovers == null) exitMovers = _exitMovers;
		else _exitMovers = exitMovers;

		if (exitMovers == null) return;

		exitMovers.set([newAlbumArt, difficultyStars], {x: FlxG.width, speed: 0.4, wait: 0});

		if (albumTitle != null) exitMovers.set([albumTitle], {x: FlxG.width, speed: 0.4, wait: 0});
	}

	/**
	 * Play the intro animation on the album art.
	 */
	public function playIntro():Void
	{
		this.visible = true;

		if (albumTitle != null) albumTitle.visible = false;
		newAlbumArt.visible = true;
		playing = 'intro';
		newAlbumArt.anim.play('intro', true);

		difficultyStars.visible = false;
		difficultyStars.flameCheck();

		new FlxTimer().start(0.75, function(_)
		{
			showTitle();
			showStars();
			if (albumTitle != null) albumTitle.animation.play('switch');
		});
	}

	public function skipIntro():Void
	{
		this.visible = true;

		// Weird workaround
		playing = 'switch';
		newAlbumArt.anim.play('switch', true);
		if (albumTitle != null) albumTitle.animation.play('switch');
	}

	public function showTitle():Void
	{
		if (albumTitle != null && albumTitle.frames != null) albumTitle.visible = true;
	}

	public function buildAlbumTitle(assetKey:String):Void
	{
		if (albumTitle != null)
		{
			remove(albumTitle);
			albumTitle.destroy();
			albumTitle = null;
		}

		if (!Paths.fileExists('images/$assetKey.png', IMAGE) || !Paths.fileExists('images/$assetKey.xml', TEXT)) return;

		albumTitle = new FlxSprite(FlxG.width - 355, 500);
		albumTitle.frames = Paths.getSparrowAtlas(assetKey);
		albumTitle.antialiasing = ClientPrefs.data.antialiasing;
		albumTitle.visible = this.visible && newAlbumArt.visible && difficultyStars.visible;
		albumTitle.animation.addByPrefix('idle', 'idle0', 24, true);
		albumTitle.animation.addByPrefix('switch', 'switch0', 24, false);
		add(albumTitle);

		albumTitle.animation.finishCallback = function(name:String)
		{
			if (name == 'switch' && albumTitle != null) albumTitle.animation.play('idle');
		};
		albumTitle.animation.play('idle');

		applyExitMovers();
	}

	public function setDifficultyStars(?difficulty:Null<Int>):Void
	{
		if (difficulty == null) return;

		difficultyStars.difficulty = difficulty;
	}

	/**
	 * Make the album stars visible.
	 */
	public function showStars():Void
	{
		difficultyStars.visible = true;
		difficultyStars.flameCheck();
	}

	/**
	 * The name for the OST associated with the album.
	 */
	public function getOSTNameOverride():String
		return "Friday Night Funkin'";
}

/**
 * The little stars under the album, one per point of difficulty.
 *
 * Ported from V-Slice. One long animation holds every count of stars - a hundred frames
 * each, one star to fifteen, and a sixteenth at frame 1500 with none - so showing a
 * number means starting at its hundred and looping back before it reaches the next one.
 */
class DifficultyStars extends FlxSpriteGroup
{
	/**
	 * Internal handler var for difficulty... ranges from 0... to 15
	 * 0 is 1 star... 15 is 0 stars!
	 */
	var curDifficulty(default, set):Int = 0;

	/**
	 * Range between 0 and 15
	 */
	public var difficulty(default, set):Int = 1;

	public var stars:PsychFlxAnimate;
	public var flames:FreeplayFlames;

	var hsvShader:HSVShader;

	public function new(x:Float, y:Float)
	{
		super(x, y);

		hsvShader = new HSVShader();

		flames = new FreeplayFlames(0, 0);

		stars = new PsychFlxAnimate(0, 0);
		try
		{
			Paths.loadAnimateAtlas(stars, 'freeplay/freeplayStars');
			stars.anim.play('diff stars');
		}
		catch (e:Dynamic)
			trace('DifficultyStars: could not load the stars atlas ($e)');

		stars.antialiasing = ClientPrefs.data.antialiasing;

		add(flames);
		add(stars);

		stars.shader = hsvShader;

		for (memb in flames.members)
			if (memb != null) memb.shader = hsvShader;
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// "loops" the current animation
		// for clarity, the animation file looks like
		// frame : stars
		// 0-99: 1 star
		// 100-199: 2 stars
		// ......
		// 1300-1499: 15 stars
		// 1500 : 0 stars
		if (stars.anim == null || stars.anim.curSymbol == null) return;

		if (curDifficulty < 15 && stars.anim.curFrame >= (curDifficulty + 1) * 100) stars.anim.play('diff stars', true, false, curDifficulty * 100);
	}

	function set_difficulty(value:Int):Int
	{
		difficulty = value;

		if (difficulty <= 0)
		{
			difficulty = 0;
			curDifficulty = 15;
		}
		else if (difficulty <= 15)
		{
			difficulty = value;
			curDifficulty = difficulty - 1;
		}
		else
		{
			difficulty = 15;
			curDifficulty = difficulty - 1;
		}

		flameCheck();

		return difficulty;
	}

	public function flameCheck():Void
	{
		if (difficulty > 10) flames.flameCount = difficulty - 10;
		else
			flames.flameCount = 0;
	}

	function set_curDifficulty(value:Int):Int
	{
		curDifficulty = value;

		if (stars == null || stars.anim == null) return curDifficulty;

		if (curDifficulty == 15)
		{
			stars.anim.play('diff stars', true, false, 1500);
			stars.anim.pause();
		}
		else
			stars.anim.play('diff stars', true, false, curDifficulty * 100);

		return curDifficulty;
	}
}

/**
 * The fire behind the stars, for a song hard enough to deserve it.
 *
 * Ported from V-Slice: one flame per point of difficulty past ten, lighting a quarter of
 * a second apart so they catch one after the other rather than all at once.
 */
class FreeplayFlames extends FlxSpriteGroup
{
	var flameX(default, set):Float = FlxG.width - 367;
	var flameY(default, set):Float = 91;
	var flameSpreadX(default, set):Float = 29;
	var flameSpreadY(default, set):Float = 6;

	public var flameCount(default, set):Int = 0;

	var flameTimer:Float = 0.25;

	public function new(x:Float, y:Float)
	{
		super(x, y);

		for (i in 0...5)
		{
			var flame:FlxSprite = new FlxSprite(flameX + (flameSpreadX * i), flameY + (flameSpreadY * i));
			flame.frames = Paths.getSparrowAtlas('freeplay/freeplayFlame');
			flame.animation.addByPrefix('flame', 'fire loop full instance 1', FlxG.random.int(23, 25), false);
			flame.animation.play('flame');
			flame.antialiasing = ClientPrefs.data.antialiasing;
			flame.visible = false;
			flameCount = 0;

			// sets the loop... maybe better way to do this lol!
			flame.animation.finishCallback = function(_) flame.animation.play('flame', true, false, 2);
			add(flame);
		}
	}

	var properPositions:Bool = false;

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// doesn't work in create()/new() for some reason
		// so putting it here bwah!
		if (!properPositions)
		{
			setFlamePositions();
			properPositions = true;
		}
	}

	var timers:Array<FlxTimer> = [];

	function set_flameCount(value:Int):Int
	{
		// Stop all existing timers.
		// This fixes a bug where quickly switching difficulties would show flames.
		for (timer in timers)
		{
			timer.active = false;
			timer.destroy();
		}
		timers = [];

		this.properPositions = false;
		this.flameCount = value;

		var visibleCount:Int = 0;

		for (i in 0...5)
		{
			if (members[i] == null) continue;

			var flame:FlxSprite = members[i];

			if (i < flameCount)
			{
				if (!flame.visible)
				{
					var nextTimer:FlxTimer = new FlxTimer().start(flameTimer * visibleCount, function(currentTimer:FlxTimer)
					{
						if (i >= this.flameCount) return;

						timers.remove(currentTimer);
						flame.animation.play('flame', true);
						flame.visible = true;
					});
					timers.push(nextTimer);

					visibleCount++;
				}
			}
			else
				flame.visible = false;
		}

		return this.flameCount;
	}

	function setFlamePositions():Void
	{
		for (i in 0...5)
		{
			var flame:FlxSprite = members[i];
			if (flame == null) continue;

			flame.x = flameX + (flameSpreadX * i);
			flame.y = flameY + (flameSpreadY * i);
		}
	}

	function set_flameX(value:Float):Float
	{
		this.flameX = value;
		setFlamePositions();
		return this.flameX;
	}

	function set_flameY(value:Float):Float
	{
		this.flameY = value;
		setFlamePositions();
		return this.flameY;
	}

	function set_flameSpreadX(value:Float):Float
	{
		this.flameSpreadX = value;
		setFlamePositions();
		return this.flameSpreadX;
	}

	function set_flameSpreadY(value:Float):Float
	{
		this.flameSpreadY = value;
		setFlamePositions();
		return this.flameSpreadY;
	}
}

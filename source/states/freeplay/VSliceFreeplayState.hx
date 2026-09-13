package states.freeplay;
import backend.Highscore;
import states.freeplay.FreeplaySongData.FreeplayRankTier;

import backend.Song;
import backend.WeekData;
import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import flixel.text.FlxText;
import openfl.display.BlendMode;
import shaders.freeplay.AngleMask;
import shaders.freeplay.HSVShader;
import shaders.freeplay.StrokeShader;
import states.MainMenuState;

/**
 * The freeplay menu from V-Slice, running on Psych's songs.
 *
 * The layout, the timings and the numbers are V-Slice's. What sits behind them is
 * Psych's: the list comes out of the week files, the scores out of `Highscore`, the
 * difficulties out of whichever week a song belongs to - which is why the difficulty
 * list changes as you scroll, something V-Slice never has to deal with.
 *
 * Left out for now, and coming in the next pass: the DJ, the album roll, the letter
 * sort and the rank-up animation. The menu works without them; they hang off the same
 * hooks V-Slice hangs them off.
 */
class VSliceFreeplayState extends MusicBeatState
{
	/**
	 * Shares of the extra width that the songs and the difficulty move right by on a
	 * screen wider than 16:9. V-Slice's `SONGS_POS_MULTI` and `DJ_POS_MULTI`.
	 */
	public static final SONGS_POS_MULTI:Float = 0.75;

	public static final DJ_POS_MULTI:Float = 0.44;

	/** How long the preview takes to fade in, and to fade back out. V-Slice's numbers. */
	public static final FADE_IN_DURATION:Float = 0.5;
	public static final FADE_IN_DELAY:Float = 0.25;
	public static final FADE_IN_START_VOLUME:Float = 0.25;
	public static final FADE_IN_END_VOLUME:Float = 0.7;

	/** Kept between visits, so backing out of a song lands you back on it. */
	static var rememberedSongName:String = null;
	static var rememberedDifficulty:String = null;

	var songs:Array<FreeplaySongData> = [];
	var grpCapsules:FlxTypedGroup<SongMenuItem>;
	var curSelected:Int = 0;
	var curDifficulty:Int = 0;

	var backingCard:BackingCard;
	var backingImage:FlxSprite;
	var blackOverlay:FlxSprite;
	var angleMaskShader:AngleMask = new AngleMask();
	var grpDifficulties:FlxTypedSpriteGroup<DifficultySprite>;
	var difficultySprites:Map<String, DifficultySprite> = [];
	var fpScoreDisplay:FreeplayScore;
	var txtCompletion:FlxText;
	var ostName:FlxText;
	var overhangStuff:FlxSprite;
	var topLeftCornerText:FlxText;
	var fnfHighscoreSpr:FlxSprite;
	var clearBoxSprite:FlxSprite;
	var diffSelLeft:DifficultySelector;
	var diffSelRight:DifficultySelector;

	var intendedScore:Int = 0;
	var intendedCompletion:Float = 0;
	var lerpScore:Float = 0;
	var lerpCompletion:Float = 0;

	/** Blocks input while the menu is arriving or leaving. */
	var busy:Bool = true;

	/**
	 * V-Slice's `CUTOUT_WIDTH`: how much wider than 16:9 the screen is, over 1.5.
	 *
	 * Everything laid out from the left - the card, the songs, the difficulty - moves
	 * right by a share of it, so a wide screen spreads the menu out instead of leaving
	 * it piled against the left edge. Zero at 1280, so nothing moves on a desktop.
	 */
	var cutout:Float = 0;

	var previewTimer:FlxTimer;

	override function create():Void
	{
		super.create();

		PlayState.isStoryMode = false;
		WeekData.reloadWeekFiles(false);

		#if DISCORD_ALLOWED
		DiscordClient.changePresence('In the Menus', null);
		#end

		songs = FreeplaySongData.listAll();

		if (songs.length < 1)
		{
			FlxTransitionableState.skipNextTransIn = true;
			persistentUpdate = false;
			MusicBeatState.switchState(new states.ErrorState("NO SONGS ADDED FOR FREEPLAY\n\nPress ACCEPT to go to the Week Editor Menu.\nPress BACK to return to Main Menu.",
				function() MusicBeatState.switchState(new states.editors.WeekEditorState()), function() MusicBeatState.switchState(new MainMenuState())));
			return;
		}

		persistentUpdate = true;

		cutout = Math.max(0, FlxG.width - FlxG.initialWidth) / 1.5;

		backingCard = new BackingCard(cutout);
		add(backingCard);
		backingCard.build();

		// The art on the right, cut away on a diagonal by the mask shader. The black
		// version of it sits underneath so the diagonal has an edge to reveal from.
		backingImage = new FlxSprite(backingCard.pinkBack.width * 0.74, 0).loadGraphic(Paths.image('freeplay/freeplayBGweek1-bf'));
		backingImage.antialiasing = ClientPrefs.data.antialiasing;
		backingImage.shader = angleMaskShader;
		backingImage.visible = false;

		blackOverlay = new FlxSprite(FlxG.width).makeGraphic(Std.int(backingImage.width), Std.int(backingImage.height), FlxColor.BLACK);
		blackOverlay.shader = angleMaskShader;
		add(blackOverlay);

		// Both are scaled to the same size so the shader's diagonal lines up across them.
		backingImage.setGraphicSize(0, FlxG.height + 1);
		blackOverlay.setGraphicSize(0, FlxG.height + 1);
		backingImage.updateHitbox();
		blackOverlay.updateHitbox();

		grpDifficulties = new FlxTypedSpriteGroup<DifficultySprite>(-300, 80);
		add(grpDifficulties);
		add(backingImage);

		grpCapsules = new FlxTypedGroup<SongMenuItem>();
		add(grpCapsules);

		fnfHighscoreSpr = new FlxSprite(FlxG.width - 420, 70);
		fnfHighscoreSpr.frames = Paths.getSparrowAtlas('freeplay/highscore');
		fnfHighscoreSpr.animation.addByPrefix('highscore', 'highscore small instance 1', 24, false);
		fnfHighscoreSpr.antialiasing = ClientPrefs.data.antialiasing;
		fnfHighscoreSpr.visible = false;
		add(fnfHighscoreSpr);

		// The little "HIGHSCORE" plaque wiggles every now and then, never on a schedule.
		new FlxTimer().start(FlxG.random.float(12, 50), function(tmr)
		{
			fnfHighscoreSpr.animation.play('highscore');
			tmr.time = FlxG.random.float(20, 60);
		}, 0);

		fpScoreDisplay = new FreeplayScore(FlxG.width - 353, 60, 7, 0);
		fpScoreDisplay.visible = false;
		add(fpScoreDisplay);

		clearBoxSprite = new FlxSprite(FlxG.width - 115, 65).loadGraphic(Paths.image('freeplay/clearBox'));
		clearBoxSprite.antialiasing = ClientPrefs.data.antialiasing;
		clearBoxSprite.visible = false;
		add(clearBoxSprite);

		txtCompletion = new FlxText(FlxG.width - 95, 82, 0, '0', 32);
		txtCompletion.setFormat(Paths.font('5by7.ttf'), 32, FlxColor.WHITE, LEFT);
		txtCompletion.visible = false;
		add(txtCompletion);

		diffSelLeft = new DifficultySelector((cutout * DJ_POS_MULTI) + 20, grpDifficulties.y - 10, false);
		diffSelRight = new DifficultySelector((cutout * DJ_POS_MULTI) + 325, grpDifficulties.y - 10, true);
		diffSelLeft.visible = false;
		diffSelRight.visible = false;
		add(diffSelLeft);
		add(diffSelRight);

		// The black bar along the top, and what sits in it.
		overhangStuff = new FlxSprite().makeGraphic(FlxG.width, 164, FlxColor.BLACK);
		overhangStuff.y -= overhangStuff.height;
		add(overhangStuff);

		topLeftCornerText = new FlxText(8, 8, 0, 'FREEPLAY', 48);
		topLeftCornerText.setFormat(Paths.font('vcr.ttf'), 48, FlxColor.WHITE, LEFT);
		topLeftCornerText.shader = new StrokeShader(0xFFFFFFFF, 2, 2);
		topLeftCornerText.visible = false;
		add(topLeftCornerText);

		ostName = new FlxText(8, 8, FlxG.width - 16, "Friday Night Funkin'", 48);
		ostName.setFormat(Paths.font('vcr.ttf'), 48, FlxColor.WHITE, RIGHT);
		ostName.shader = new StrokeShader(0xFFFFFFFF, 2, 2);
		ostName.visible = false;
		add(ostName);

		buildCapsules();
		restoreSelection();

		FlxTween.tween(overhangStuff, {y: -100}, 0.3, {ease: FlxEase.quartOut});
		FlxTween.tween(blackOverlay, {x: backingImage.x}, 0.7, {ease: FlxEase.quintOut});

		// V-Slice waits for the DJ's intro to finish here. Without a DJ yet, the same
		// beat is spent on the card sliding in, so the menu still arrives rather than
		// appearing all at once.
		new FlxTimer().start(0.9, function(_) introDone());

		#if TOUCH_CONTROLS_ALLOWED
		addVirtualPad(FULL, A_B);
		// Its own camera, so the zoom when a song is picked doesn't drag the pad with it.
		addVirtualPadCamera();
		#end
	}

	/** Everything that lands once the card is in and the menu becomes usable. */
	function introDone():Void
	{
		backingImage.visible = true;
		backingCard.introDone();

		FlxTween.color(backingImage, 0.6, 0xFF000000, 0xFFFFFFFF, {
			ease: FlxEase.expoOut,
			onUpdate: function(_) angleMaskShader.extraColor = backingImage.color,
			onComplete: function(_) blackOverlay.visible = false
		});

		FlxTween.tween(grpDifficulties, {x: (cutout * DJ_POS_MULTI) + 90}, 0.6, {ease: FlxEase.quartOut});

		diffSelLeft.visible = true;
		diffSelRight.visible = true;

		new FlxTimer().start(1 / 24, function(_)
		{
			fnfHighscoreSpr.visible = true;
			topLeftCornerText.visible = true;
			ostName.visible = true;
			fpScoreDisplay.visible = true;
			clearBoxSprite.visible = true;
			txtCompletion.visible = true;

			busy = false;
			changeSelection();
		});
	}

	function buildCapsules():Void
	{
		// One shader for the lot, like V-Slice: it is how a character's freeplay gets
		// tinted as a whole, so every capsule has to be looking at the same one.
		var hsvShader:HSVShader = new HSVShader();

		for (i in 0...songs.length)
		{
			var capsule:SongMenuItem = new SongMenuItem(FlxG.width, 0);
			capsule.initData(songs[i], i, curDifficulty);
			capsule.hsvShader = hsvShader;
			capsule.xOffset = cutout * SONGS_POS_MULTI;
			capsule.y = capsule.intendedY(i + 1) + 10;
			capsule.targetPos.x = capsule.x;

			// Faded rather than hidden, and deliberately so: a sprite group passes its
			// own visibility down to every child the moment it changes, so hiding the
			// whole capsule and showing it again would turn the NEW tag, the heart and
			// the title's glow back on regardless of what the song actually wants.
			// V-Slice fades the capsule art and leaves visibility to the contents.
			capsule.capsule.alpha = 0.5;

			// Each capsule's NEW tag starts on a different frame, so a column of them
			// doesn't pulse in lockstep.
			if (capsule.newText.animation.curAnim != null) capsule.newText.animation.curAnim.curFrame = 45 - ((i * 4) % 45);

			capsule.initJumpIn(Math.min(i, 4));
			grpCapsules.add(capsule);
		}
	}

	/** Puts the selection back where it was last time, if that song is still here. */
	function restoreSelection():Void
	{
		if (rememberedSongName == null) return;

		for (i in 0...songs.length)
		{
			if (songs[i].songName != rememberedSongName) continue;

			curSelected = i;
			break;
		}
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		lerpScore = FlxMath.lerp(lerpScore, intendedScore, FlxMath.bound(elapsed * 12, 0, 1));
		lerpCompletion = FlxMath.lerp(lerpCompletion, intendedCompletion, FlxMath.bound(elapsed * 12, 0, 1));

		if (Math.abs(lerpScore - intendedScore) < 10) lerpScore = intendedScore;
		if (Math.abs(lerpCompletion - intendedCompletion) < 0.02) lerpCompletion = intendedCompletion;

		fpScoreDisplay.updateScore(Math.round(lerpScore));
		txtCompletion.text = '${Math.floor(lerpCompletion * 100)}';

		if (busy) return;

		if (controls.UI_UP_P) changeSelection(-1);
		else if (controls.UI_DOWN_P) changeSelection(1);

		if (controls.UI_LEFT_P) changeDiff(-1);
		else if (controls.UI_RIGHT_P) changeDiff(1);

		if (controls.BACK) goBack();
		else if (controls.ACCEPT) confirmSelection();
	}

	function currentCapsule():SongMenuItem
		return grpCapsules.members[curSelected];

	function currentSong():FreeplaySongData
		return songs[curSelected];

	function changeSelection(change:Int = 0):Void
	{
		var previous:Int = curSelected;

		curSelected = FlxMath.wrap(curSelected + change, 0, songs.length - 1);

		if (change != 0 && curSelected != previous) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		// Psych hands out difficulties per week, so the list itself changes with the
		// song. V-Slice has one list for everything and never does this.
		applyDifficultyList();

		rememberedSongName = currentSong().songName;

		for (index => capsule in grpCapsules.members)
		{
			// V-Slice counts the capsules from one, not zero, because its first entry is
			// the RANDOM capsule sitting above the songs. The list has no random entry
			// yet, but the counting is worth keeping: it is what puts the selected song
			// in the second slot with one song visible above it, rather than pinned to
			// the top of the screen with nothing before it.
			var slot:Int = index + 1;

			capsule.selected = index == curSelected;
			capsule.curSelected = curSelected;
			capsule.index = index;

			var offsetIndex:Int = slot - curSelected;
			var yOffset:Float = 0;

			// Nudges the capsules past either end further off screen, so they aren't
			// hanging half-visible at the edges.
			if (offsetIndex < 0) yOffset += 50;
			else if (offsetIndex > 4) yOffset -= 10;

			capsule.targetPos.y = capsule.intendedY(offsetIndex) - yOffset;
			capsule.targetPos.x = capsule.intendedX(offsetIndex) + (cutout * SONGS_POS_MULTI);

			if (slot < curSelected) capsule.targetPos.y -= 100; // another 100 for good measure
		}

		refreshScore();
		currentCapsule().refreshDisplay(curDifficulty);

		queuePreview();
	}

	/** Swaps in the difficulties of whichever week the selected song came from. */
	function applyDifficultyList():Void
	{
		var song:FreeplaySongData = currentSong();
		var wanted:String = (rememberedDifficulty != null) ? rememberedDifficulty : Difficulty.getDefault();

		Difficulty.copyFrom(song.difficulties);

		var index:Int = Difficulty.list.indexOf(wanted);
		curDifficulty = (index > -1) ? index : Math.round(Math.max(0, Difficulty.list.indexOf(Difficulty.getDefault())));

		refreshDifficultySprites();
	}

	function changeDiff(change:Int = 0):Void
	{
		if (Difficulty.list.length < 1) return;

		curDifficulty = FlxMath.wrap(curDifficulty + change, 0, Difficulty.list.length - 1);
		rememberedDifficulty = Difficulty.getString(curDifficulty, false);

		if (change != 0)
		{
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
			if (change < 0) diffSelLeft.press();
			else diffSelRight.press();
		}

		refreshDifficultySprites();
		refreshScore();
		currentCapsule().refreshDisplay(curDifficulty);
	}

	/**
	 * Shows the sprite for the current difficulty and hides the rest.
	 *
	 * Sprites are made once per difficulty name and kept, because the list is rebuilt
	 * every time the selection moves to a song from another week - and a mod week with
	 * its own difficulty names would otherwise reload art on every keypress.
	 */
	function refreshDifficultySprites():Void
	{
		for (diff in Difficulty.list)
		{
			if (difficultySprites.exists(diff)) continue;

			var sprite:DifficultySprite = new DifficultySprite(diff);
			difficultySprites.set(diff, sprite);
			grpDifficulties.add(sprite);
		}

		var current:String = Difficulty.getString(curDifficulty, false);

		for (name => sprite in difficultySprites)
		{
			sprite.visible = (name == current) && Difficulty.list.contains(name);
			sprite.y = 80;
		}
	}

	function refreshScore():Void
	{
		var song:FreeplaySongData = currentSong();

		intendedScore = song.getScore(curDifficulty);

		var accuracy:Float = song.getAccuracy(curDifficulty);
		intendedCompletion = (accuracy > 0) ? accuracy : 0;
	}

	/**
	 * Starts the song's instrumental playing quietly under the menu.
	 *
	 * Held back a moment on purpose: scrolling through ten songs shouldn't open ten
	 * files, so nothing loads until the selection has settled, and even then only if
	 * the capsule that asked for it is still the selected one.
	 */
	function queuePreview():Void
	{
		if (previewTimer != null) previewTimer.cancel();

		var capsule:SongMenuItem = currentCapsule();
		previewTimer = new FlxTimer().start(FADE_IN_DELAY, function(_) playPreview(capsule));
	}

	function playPreview(capsule:SongMenuItem):Void
	{
		if (capsule == null || !capsule.selected || busy) return;

		var song:FreeplaySongData = capsule.freeplayData;
		if (song == null) return;

		var previousMod:String = Mods.currentModDirectory;
		Mods.currentModDirectory = song.folder;

		try
		{
			var inst = Paths.inst(song.songName);
			if (inst != null)
			{
				FlxG.sound.playMusic(inst, 0, false);
				FlxG.sound.music.fadeIn(FADE_IN_DURATION, FADE_IN_START_VOLUME, FADE_IN_END_VOLUME);
			}
		}
		catch (e:Dynamic)
			trace('VSliceFreeplayState: no preview for "${song.songName}" ($e)');

		Mods.currentModDirectory = previousMod;
	}

	function goBack():Void
	{
		busy = true;

		if (previewTimer != null) previewTimer.cancel();

		FlxG.sound.play(Paths.sound('cancelMenu'));
		backingCard.disappear();

		for (capsule in grpCapsules.members)
			capsule.doJumpOut = true;

		FlxTween.tween(backingCard.pinkBack, {x: -backingCard.pinkBack.width}, 0.4, {ease: FlxEase.quartOut});
		FlxTween.tween(overhangStuff, {y: -overhangStuff.height}, 0.2);
		FlxTween.tween(backingImage, {x: FlxG.width * 1.5}, 0.4);
		FlxTween.tween(grpDifficulties, {x: -300}, 0.25);

		new FlxTimer().start(0.45, function(_)
		{
			persistentUpdate = false;
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			MusicBeatState.switchState(new MainMenuState());
		});
	}

	function confirmSelection():Void
	{
		busy = true;

		if (previewTimer != null) previewTimer.cancel();

		FlxG.sound.play(Paths.sound('confirmMenu'));
		currentCapsule().confirm();
		backingCard.confirm();

		FlxTween.tween(FlxG.camera, {zoom: 1.05}, 0.6, {ease: FlxEase.quadOut});
		if (FlxG.sound.music != null) FlxTween.tween(FlxG.sound.music, {volume: 0}, 0.6);

		new FlxTimer().start(1, function(_) loadSong());
	}

	function loadSong():Void
	{
		var song:FreeplaySongData = currentSong();

		persistentUpdate = false;
		Mods.currentModDirectory = song.folder;

		var songLowercase:String = song.formatted();
		var poop:String = Highscore.formatSong(songLowercase, curDifficulty);

		try
		{
			Song.loadFromJson(poop, songLowercase);
			PlayState.isStoryMode = false;
			PlayState.storyDifficulty = curDifficulty;
		}
		catch (e:haxe.Exception)
		{
			trace('ERROR! ${e.message}');

			// Nothing to play, so hand the menu back rather than dying on a black screen.
			busy = false;
			FlxG.sound.play(Paths.sound('cancelMenu'));
			FlxTween.tween(FlxG.camera, {zoom: 1}, 0.3);
			return;
		}

		@:privateAccess
		if (PlayState._lastLoadedModDirectory != Mods.currentModDirectory) Paths.freeGraphicsFromMemory();

		LoadingState.prepareToSong();
		LoadingState.loadAndSwitchState(new PlayState());

		#if !SHOW_LOADING_SCREEN
		if (FlxG.sound.music != null) FlxG.sound.music.stop();
		#end

		#if (MODS_ALLOWED && DISCORD_ALLOWED)
		DiscordClient.loadModRPC();
		#end
	}

	override function destroy():Void
	{
		if (previewTimer != null) previewTimer.cancel();
		super.destroy();
	}
}

/**
 * The word EASY, NORMAL or HARD above the capsules.
 *
 * V-Slice ships art for its five difficulties. Psych lets a week name anything at all,
 * and a mod's `insane` has no picture, so anything without one is drawn as text in the
 * same place at the same size.
 */
class DifficultySprite extends FlxSprite
{
	public var difficultyId(default, null):String;

	var label:FlxText;

	public function new(diffId:String)
	{
		super();

		this.difficultyId = diffId;
		this.antialiasing = ClientPrefs.data.antialiasing;

		var assetDiffId:String = diffId.toLowerCase();

		// Difficulty names can be hyphenated; drop a suffix at a time looking for art.
		while (!Paths.fileExists('images/freeplay/freeplay$assetDiffId.png', IMAGE))
		{
			var parts:Array<String> = assetDiffId.split('-');
			parts.pop();

			if (parts.length == 0)
			{
				assetDiffId = null;
				break;
			}

			assetDiffId = parts.join('-');
		}

		if (assetDiffId == null)
		{
			makeTextGraphic(diffId);
			return;
		}

		if (Paths.fileExists('images/freeplay/freeplay$assetDiffId.xml', TEXT))
		{
			frames = Paths.getSparrowAtlas('freeplay/freeplay$assetDiffId');
			animation.addByPrefix('idle', 'idle0', 24, true);
			if (ClientPrefs.data.flashing) animation.play('idle');
		}
		else
			loadGraphic(Paths.image('freeplay/freeplay$assetDiffId'));
	}

	/** Draws the difficulty's name into a graphic, for difficulties that ship no art. */
	function makeTextGraphic(name:String):Void
	{
		var text:FlxText = new FlxText(0, 0, 0, name.toUpperCase());
		text.setFormat(Paths.font('5by7.ttf'), 48, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		text.borderSize = 2;

		@:privateAccess
		text.regenGraphic();

		loadGraphic(text.pixels.clone());
		text.destroy();
	}
}

/** One of the two arrows either side of the difficulty. */
class DifficultySelector extends FlxSprite
{
	var flipped:Bool;

	public function new(x:Float, y:Float, flipped:Bool)
	{
		super(x, y);

		this.flipped = flipped;

		frames = Paths.getSparrowAtlas('freeplay/freeplaySelector');
		animation.addByPrefix('shine', 'arrow pointer loop', 24);
		animation.play('shine');

		antialiasing = ClientPrefs.data.antialiasing;
		flipX = flipped;
	}

	/** The squash it does when its side is pressed. */
	public function press():Void
	{
		scale.set(0.5, 0.5);
		FlxTween.cancelTweensOf(scale);
		FlxTween.tween(scale, {x: 1, y: 1}, 0.6, {ease: FlxEase.elasticOut});
	}
}

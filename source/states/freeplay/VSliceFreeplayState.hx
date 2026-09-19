package states.freeplay;

import backend.Highscore;
import backend.IntervalShake;
import backend.Song;
import backend.WeekData;
import flixel.FlxCamera;
import flixel.FlxObject;
import openfl.display.BlendMode;
import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import flixel.text.FlxText;
import options.GameplayChangersSubstate;
import shaders.freeplay.AngleMask;
import shaders.freeplay.HSVShader;
import shaders.freeplay.PureColor;
import shaders.freeplay.StrokeShader;
import states.MainMenuState;
import states.freeplay.FreeplaySongData.FreeplayRankTier;
import states.freeplay.SongMenuItem.FreeplayMath;

/**
 * The freeplay menu from V-Slice, running on Psych's songs.
 *
 * This follows V-Slice's own `FreeplayState` closely on purpose - the same order of
 * operations, the same field names, the same numbers - because the parts that are easy
 * to paraphrase wrongly are exactly the parts that look wrong: which sprite leaves in
 * which direction, when the capsules learn where they are going, how far the difficulty
 * slides. Where this departs from it, there is a comment saying why.
 *
 * What is Psych's rather than V-Slice's is everything behind the display. The list
 * comes out of the week files, the scores out of `Highscore`, and a difficulty is a
 * name that belongs to a week rather than a number that belongs to the game.
 *
 * Not here yet, and hanging off the same points V-Slice hangs them off: the DJ, the
 * album roll, the letter sort and the rank animation.
 */
class VSliceFreeplayState extends MusicBeatState
{
	/**
	 * For the audio preview, the duration of the fade-in effect.
	 */
	public static final FADE_IN_DURATION:Float = 0.5;

	/**
	 * For the audio preview, the volume at which the fade-in starts.
	 */
	public static final FADE_IN_START_VOLUME:Float = 0.25;

	/**
	 * For the audio preview, the volume at which the fade-in ends.
	 */
	public static final FADE_IN_END_VOLUME:Float = 0.7;

	/**
	 * For the audio preview, the time to wait before attempting to load a song preview.
	 */
	/**
	 * How long a song has to be the selected one before its preview starts loading.
	 *
	 * V-Slice uses a quarter second, but it can afford to: this reads the inst off disk on the
	 * main thread, so scrolling for the bottom of a long list meant loading every song on the
	 * way past and a stutter for each one. Long enough now that only resting on a song pays
	 * for it.
	 */
	public static final FADE_IN_DELAY:Float = 0.5;

	/**
	 * For positioning the DJ, and what sits with him, on wide displays.
	 */
	public static final DJ_POS_MULTI:Float = 0.44;

	/**
	 * For positioning the songs list on wide displays.
	 */
	public static final SONGS_POS_MULTI:Float = 0.75;

	/**
	 * For scaling some sprites on wide displays. V-Slice's `CUTOUT_WIDTH`, which is the
	 * width the screen has beyond 16:9, over 1.5.
	 */
	public static var CUTOUT_WIDTH:Float = 0;

	/**
	 * The song we were on when this menu was last accessed.
	 * NOTE: `null` if the last song was `Random`.
	 */
	public static var rememberedSongName:Null<String> = null;

	/**
	 * The difficulty we were on when this menu was last accessed.
	 */
	public static var rememberedDifficulty:String = null;

	/**
	 * Set by PlayState when a run earns a better badge than the song had. Consumed once, by
	 * the next freeplay to open - a static rather than a constructor argument because six
	 * different places build this menu, all of them through FreeplayHub.
	 */
	public static var pendingRankAnim:Null<RankAnimParams> = null;

	/** The above, once this state has taken it, waiting for the menu to finish arriving. */
	var queuedRankAnim:Null<RankAnimParams> = null;

	var songs:Array<FreeplaySongData> = [];
	var curSelected:Int = 0;

	/**
	 * Currently selected difficulty, in string form - which is the only form that means
	 * anything across weeks, since a Psych difficulty number is an index into whichever
	 * week's list is loaded.
	 */
	var currentDifficulty:String = null;

	/** Every difficulty any song has, which is what the arrows cycle through. */
	var allDifficulties:Array<String> = [];

	var fpScoreDisplay:FreeplayScore;
	var txtCompletion:FlxText;
	var lerpCompletion:Float = 0;
	var intendedCompletion:Float = 0;
	var lerpScore:Float = 0;
	var intendedScore:Int = 0;
	var grpDifficulties:FlxTypedSpriteGroup<DifficultySprite>;

	var previewTimers:Array<FlxTimer> = [];

	/** Bit of a utility var to get the currently displayed DifficultySprite. */
	var currentDifficultySprite(get, never):DifficultySprite;

	function get_currentDifficultySprite():DifficultySprite
	{
		var found:Array<DifficultySprite> = grpDifficulties.group.members.filter(d -> d != null && d.difficultyId == currentDifficulty);
		return (found.length > 0) ? found[0] : null;
	}

	/** Another utility var, this one gets our current selected capsule easily. */
	var currentCapsule(get, never):SongMenuItem;

	function get_currentCapsule():SongMenuItem
		return grpCapsules.members[curSelected];

	var grpCapsules:FlxTypedGroup<SongMenuItem>;
	var dj:FreeplayDJ = null;
	var ostName:FlxText;
	var albumRoll:AlbumRoll;
	var letterSort:LetterSort;

	var currentFilter:SongFilter = null;
	var currentFilteredSongs:Array<FreeplaySongData> = [];
	var exitMovers:ExitMoverData = new Map();
	var diffSelLeft:DifficultySelector;
	var diffSelRight:DifficultySelector;

	public var funnyCam:FlxCamera;

	/** The card behind where the DJ will go. */
	var backingCard:BackingCard;

	/**
	 * Which backdrop the menu wears. True is the main menu's art with the drifting checker over
	 * it; false hands the whole thing back to V-Slice's pink card and week 1 portrait, with no
	 * other change needed anywhere.
	 */
	static inline var USE_MENU_BACKGROUND:Bool = true;

	var freeplayBackdrop:FreeplayBackdrop;

	/** The backing card that has the toned dots. */
	public var backingImage:FlxSprite;

	public var angleMaskShader:AngleMask = new AngleMask();

	var blackOverlayBullshitLOLXD:FlxSprite;
	var overhangStuff:FlxSprite;
	var topLeftCornerText:FlxText;
	var fnfHighscoreSpr:FlxSprite;
	var clearBoxSprite:FlxSprite;

	/** Blocks input while the menu is arriving or leaving. V-Slice has a state machine. */
	var uiState:FreeplayUIState = EnteringFreeplay;

	inline function canInteract():Bool
		return uiState == Idle;

	override function create():Void
	{
		super.create();

		PlayState.isStoryMode = false;
		WeekData.reloadWeekFiles(false);

		#if DISCORD_ALLOWED
		DiscordClient.changePresence('In the Menus', null);
		#end

		CUTOUT_WIDTH = Math.max(0, FlxG.width - FlxG.initialWidth) / 1.5;

		// Add a null entry that represents the RANDOM option, then the songs themselves.
		songs.push(null);
		for (song in FreeplaySongData.listAll())
			songs.push(song);

		if (songs.length < 2)
		{
			FlxTransitionableState.skipNextTransIn = true;
			persistentUpdate = false;
			MusicBeatState.switchState(new states.ErrorState("NO SONGS ADDED FOR FREEPLAY\n\nPress ACCEPT to go to the Week Editor Menu.\nPress BACK to return to Main Menu.",
				function() MusicBeatState.switchState(new states.editors.WeekEditorState()), function() MusicBeatState.switchState(new MainMenuState())));
			return;
		}

		persistentUpdate = true;

		// Which song it lands on needs no saying: rememberedSongName and rememberedDifficulty
		// were set when the song was picked, and this menu already reopens on them. Carrying a
		// name through PlayState as well would only give the two a way to disagree.
		queuedRankAnim = pendingRankAnim;
		pendingRankAnim = null;

		// Dropped so the capsules read their position file again - editing it and coming back
		// into freeplay is the whole point of it being a file.
		SongMenuItem.reloadNudges();

		allDifficulties = FreeplaySongData.listAllDifficulties(songs);
		if (rememberedDifficulty == null || !allDifficulties.contains(rememberedDifficulty)) rememberedDifficulty = Difficulty.getDefault();
		currentDifficulty = rememberedDifficulty;

		// V-Slice opens freeplay over the main menu, as a substate, so the menu shows
		// through while the card slides in and the art is revealed. Psych switches states
		// instead, and what showed through was black.
		var backdrop:FlxSprite = new FlxSprite(-80).loadGraphic(Paths.image('menuBG'));
		backdrop.antialiasing = ClientPrefs.data.antialiasing;
		add(backdrop);
		CoolUtil.fillScreen(backdrop);

		// Everything below is built in V-Slice's order, because that order is what the
		// menu's layering is: the card, then the art, then the capsules, then the bars.
		albumRoll = new AlbumRoll();
		letterSort = new LetterSort((CUTOUT_WIDTH * SONGS_POS_MULTI) + 400, 75);
		fpScoreDisplay = new FreeplayScore(FlxG.width - 353, 60, 7, 0);
		grpCapsules = new FlxTypedGroup<SongMenuItem>();
		grpDifficulties = new FlxTypedSpriteGroup<DifficultySprite>(-300, 80);
		txtCompletion = new FlxText(FlxG.width - 95, 82, 0, '0', 32);
		ostName = new FlxText(8, 8, FlxG.width - 16, albumRoll.getOSTNameOverride(), 48);

		// Behind everything, and added before the card so it stays there. The V-Slice backdrop
		// this replaces is hidden rather than removed - the card carries the confirm glow and
		// the scrolling text, which are not background and still have to work.
		if (USE_MENU_BACKGROUND)
		{
			freeplayBackdrop = new FreeplayBackdrop();
			add(freeplayBackdrop);
		}

		backingCard = new BackingCard(CUTOUT_WIDTH);
		backingImage = new FlxSprite(backingCard.pinkBack.width * 0.74, 0).loadGraphic(Paths.image('freeplay/freeplayBGweek1-bf'));

		diffSelLeft = new DifficultySelector((CUTOUT_WIDTH * DJ_POS_MULTI) + 20, grpDifficulties.y - 10, false);
		diffSelRight = new DifficultySelector((CUTOUT_WIDTH * DJ_POS_MULTI) + 325, grpDifficulties.y - 10, true);

		add(backingCard);
		backingCard.build();
		backingCard.applyExitMovers(exitMovers);
		if (USE_MENU_BACKGROUND) hideVSliceBackdrop();

		// The DJ is an Adobe Animate atlas authored at the full 1280x720, so he is
		// positioned by moving the whole stage rather than by placing a sprite - which is
		// what V-Slice's `useAnimatePosition` means for boyfriend.
		dj = new FreeplayDJ(CUTOUT_WIDTH * DJ_POS_MULTI, 0);

		if (dj.loaded)
		{
			exitMovers.set([dj], {x: -dj.width * 1.6, speed: 0.5});
			add(dj);
		}

		backingImage.antialiasing = ClientPrefs.data.antialiasing;
		backingImage.shader = angleMaskShader;
		backingImage.visible = false;

		blackOverlayBullshitLOLXD = new FlxSprite(FlxG.width).makeGraphic(Std.int(backingImage.width), Std.int(backingImage.height), FlxColor.BLACK);
		add(blackOverlayBullshitLOLXD); // used to mask the text lol!

		// this makes the texture sizes consistent, for the angle shader
		backingImage.setGraphicSize(0, FlxG.height + 1);
		blackOverlayBullshitLOLXD.setGraphicSize(0, FlxG.height + 1);
		backingImage.updateHitbox();
		blackOverlayBullshitLOLXD.updateHitbox();

		exitMovers.set([blackOverlayBullshitLOLXD, backingImage], {x: FlxG.width * 1.5, speed: 0.4, wait: 0});

		add(grpDifficulties);
		add(backingImage);

		blackOverlayBullshitLOLXD.shader = angleMaskShader;

		add(grpCapsules);

		exitMovers.set([grpDifficulties], {x: -300, speed: 0.25, wait: 0});

		for (diffId in allDifficulties)
		{
			var diffSprite:DifficultySprite = new DifficultySprite(diffId);
			diffSprite.visible = (diffId == currentDifficulty);
			grpDifficulties.add(diffSprite);
		}

		albumRoll.albumId = null;
		albumRoll.visible = false;
		albumRoll.applyExitMovers(exitMovers);
		add(albumRoll);

		overhangStuff = new FlxSprite().makeGraphic(FlxG.width, 164, FlxColor.BLACK);
		overhangStuff.y -= overhangStuff.height;

		FlxTween.tween(overhangStuff, {y: -100}, 0.3, {ease: FlxEase.quartOut});
		FlxTween.tween(blackOverlayBullshitLOLXD, {x: backingImage.x}, 0.7, {ease: FlxEase.quintOut});

		topLeftCornerText = new FlxText(8, 8, 0, 'FREEPLAY', 48);
		topLeftCornerText.setFormat(Paths.font('vcr.ttf'), 48, FlxColor.WHITE, LEFT);
		topLeftCornerText.visible = false;

		ostName.setFormat(Paths.font('vcr.ttf'), 48, FlxColor.WHITE, RIGHT);
		ostName.visible = false;
		ostName.shader = new StrokeShader(0xFFFFFFFF, 2, 2);

		exitMovers.set([overhangStuff, topLeftCornerText, ostName], {y: -overhangStuff.height, x: 0, speed: 0.2, wait: 0});

		var sillyStroke:StrokeShader = new StrokeShader(0xFFFFFFFF, 2, 2);
		topLeftCornerText.shader = sillyStroke;

		fnfHighscoreSpr = new FlxSprite(FlxG.width - 420, 70);
		fnfHighscoreSpr.frames = Paths.getSparrowAtlas('freeplay/highscore');
		fnfHighscoreSpr.animation.addByPrefix('highscore', 'highscore small instance 1', 24, false);
		fnfHighscoreSpr.antialiasing = ClientPrefs.data.antialiasing;
		fnfHighscoreSpr.visible = false;
		fnfHighscoreSpr.setGraphicSize(0, Std.int(fnfHighscoreSpr.height * 1));
		fnfHighscoreSpr.updateHitbox();
		add(fnfHighscoreSpr);

		new FlxTimer().start(FlxG.random.float(12, 50), function(tmr)
		{
			fnfHighscoreSpr.animation.play('highscore');
			tmr.time = FlxG.random.float(20, 60);
		}, 0);

		fpScoreDisplay.visible = false;
		add(fpScoreDisplay);

		clearBoxSprite = new FlxSprite(FlxG.width - 115, 65).loadGraphic(Paths.image('freeplay/clearBox'));
		clearBoxSprite.antialiasing = ClientPrefs.data.antialiasing;
		clearBoxSprite.visible = false;
		add(clearBoxSprite);

		txtCompletion.setFormat(Paths.font('5by7.ttf'), 32, FlxColor.WHITE, LEFT);
		txtCompletion.visible = false;
		add(txtCompletion);

		exitMovers.set([fpScoreDisplay, fnfHighscoreSpr, clearBoxSprite], {x: FlxG.width, speed: 0.3});
		exitMovers.set([txtCompletion], {x: FlxG.width * 1.05, speed: 0.315});

		add(letterSort);
		letterSort.visible = false;

		exitMovers.set([letterSort], {y: -100, speed: 0.3});

		// Reminder, this is a callback function being set, rather than these being called here in create()
		letterSort.changeSelectionCallback = function(str:String)
		{
			var curSong:FreeplaySongData = currentCapsule.freeplayData;
			currentCapsule.selected = false;

			switch (str)
			{
				case 'fav': generateSongList({filterType: FAVORITE}, true, false);
				case 'ALL': generateSongList(null, true, false);
				case '#': generateSongList({filterType: REGEXP, filterData: '0-9'}, true, false);
				default: generateSongList({filterType: REGEXP, filterData: str}, true, false);
			}

			// If the current song is still in the list, or if it was random, we'll land on it
			// Otherwise we want to land on the first song of the group, rather than random song
			// when changing letter sorts - that is, only if there's more than one song in the group!
			if (curSong == null || currentFilteredSongs.contains(curSong)) changeSelection();
			else if (grpCapsules.members.length > 0)
			{
				curSelected = 1;
				changeSelection();
			}
		};

		diffSelLeft.visible = false;
		diffSelRight.visible = false;
		add(diffSelLeft);
		add(diffSelRight);

		// putting these here to fix the layering
		add(overhangStuff);
		add(topLeftCornerText);
		add(ostName);

		// Generates the song list with the capsules jumping in.
		generateSongList(null, true);

		// A camera of its own, so the fade when a song is picked doesn't touch anything
		// the state doesn't own - the touch pad gets its own below.
		funnyCam = new FlxCamera();
		funnyCam.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(funnyCam, false);

		forEach(function(basic) basic.cameras = [funnyCam]);
		letterSort.inputCamera = funnyCam;

		setUpRankAnim();

		#if TOUCH_CONTROLS_ALLOWED
		addVirtualPad(FULL, A_B);
		addVirtualPadCamera();
		#end

		if (dj != null && dj.loaded)
		{
			// The menu opens when the DJ finishes his intro, which is V-Slice's own cue - and
			// anyway if he hasn't managed it in time. V-Slice can take its DJ for granted; this
			// cannot, and one that never finishes used to mean a menu stuck half built.
			dj.onIntroDone.add(function() onDJIntroDone());
			new FlxTimer().start(1.5, function(_) onDJIntroDone());
		}
		else
		{
			// No DJ at all, so there is nothing to wait for and no entrance of his to head.
			// Sitting out his timer just left the menu unusable for a second and a half with
			// nothing happening on screen. It arrives fully built instead, under the same fade
			// the rest of the game comes in on.
			onDJIntroDone(true);
		}
	}

	/** Whether the menu has finished arriving, so the watchdog can't run this twice. */
	var introDone:Bool = false;

	/**
	 * Everything that lands once the intro is over and the menu becomes usable.
	 *
	 * `instant` puts it all in place at once instead of animating it in, for when there is no
	 * DJ and so no entrance to be in step with.
	 */
	function onDJIntroDone(?instant:Bool = false):Void
	{
		if (introDone) return;

		introDone = true;
		uiState = Idle;

		if (instant)
		{
			backingImage.color = 0xFFFFFFFF;
			angleMaskShader.extraColor = backingImage.color;
			blackOverlayBullshitLOLXD.visible = false;
		}
		else
		{
			FlxTween.color(backingImage, 0.6, 0xFF000000, 0xFFFFFFFF, {
				ease: FlxEase.expoOut,
				onUpdate: function(_) angleMaskShader.extraColor = backingImage.color,
				onComplete: function(_) blackOverlayBullshitLOLXD.visible = false
			});
		}

		var restingX:Float = (CUTOUT_WIDTH * DJ_POS_MULTI) + 90;
		FlxTween.cancelTweensOf(grpDifficulties);

		// The group moves before its members, and that order is not cosmetic. A sprite group
		// shifts its children by the delta when its own x changes, so setting a child to an
		// absolute x and then moving the group takes that child twice as far - which put the
		// remembered difficulty off the side of the screen on arrival, until an arrow press
		// reset it to an absolute position and it came back. The tweened path got away with it
		// because both tweens ran together and the child's absolute write landed last.
		if (instant) grpDifficulties.x = restingX;
		else FlxTween.tween(grpDifficulties, {x: restingX}, 0.6, {ease: FlxEase.quartOut});

		for (diff in grpDifficulties.group.members)
		{
			if (diff == null) continue;

			FlxTween.cancelTweensOf(diff);
			if (instant) diff.x = restingX;
			else FlxTween.tween(diff, {x: restingX}, 0.6, {ease: FlxEase.quartOut});
			diff.y = 80;
			diff.visible = (diff == currentDifficultySprite);
		}

		diffSelLeft.visible = true;
		diffSelRight.visible = true;
		letterSort.visible = true;

		exitMovers.set([diffSelLeft, diffSelRight], {x: -diffSelLeft.width * 2, speed: 0.26});

		function showTopRow()
		{
			fnfHighscoreSpr.visible = true;
			topLeftCornerText.visible = true;
			ostName.visible = true;
			fpScoreDisplay.visible = true;
			fpScoreDisplay.updateScore(0);

			clearBoxSprite.visible = true;
			txtCompletion.visible = true;
			intendedCompletion = 0;
		}

		function settle()
		{
			sillyStrokeWidth(0);
			changeSelection();
		}

		if (instant)
		{
			showTopRow();
			settle();
		}
		else
		{
			new FlxTimer().start(1 / 24, function(handShit)
			{
				showTopRow();
				new FlxTimer().start(1.5 / 24, function(bold) settle());
			});
		}

		albumRoll.playIntro();
		albumRoll.albumId = albumIdFor(currentCapsule.freeplayData);

		backingImage.visible = !USE_MENU_BACKGROUND;
		backingCard.introDone();

		// Last, so the menu is fully arrived and the capsules are where they belong before one
		// of them gets picked up. A short beat after, because landing a rank on the same frame
		// the list settles reads as a glitch rather than a flourish.
		if (queuedRankAnim != null)
		{
			var params:RankAnimParams = queuedRankAnim;
			queuedRankAnim = null;
			uiState = RankAnimating;
			new FlxTimer().start(0.3, function(_) rankAnimStart(params));
		}
	}

	/**
	 * Which album cover a song gets.
	 *
	 * V-Slice has an album per song in its metadata and a registry to look it up in.
	 * Psych has neither, and every cover that ships is a base game one, so everything is
	 * Volume 1 until a week has somewhere to say otherwise.
	 */
	function albumIdFor(song:FreeplaySongData):String
	{
		if (song == null) return null;

		return 'volume1';
	}

	function sillyStrokeWidth(value:Float):Void
	{
		var stroke:StrokeShader = cast(topLeftCornerText.shader, StrokeShader);
		if (stroke == null) return;

		stroke.width = value;
		stroke.height = value;
	}

	/**
	 * Builds the capsules for the song list.
	 *
	 * V-Slice rebuilds this whenever the letter sort or the difficulty changes, which is
	 * why it is its own function rather than part of `create`. The filtering it does on
	 * the way is the letter sort's, which is a later stage.
	 *
	 * @param force Whether the capsules should jump back in using their animation.
	 */
	function generateSongList(?filterStuff:SongFilter, force:Bool = false, onlyIfChanged:Bool = true, noJumpIn:Bool = false):Void
	{
		var tempSongs:Array<FreeplaySongData> = songs.copy();

		if (filterStuff != null) tempSongs = sortSongs(tempSongs, filterStuff);

		// Only songs that have the difficulty being asked for, which is what makes the
		// difficulty arrows a filter as well as a setting.
		tempSongs = tempSongs.filter(function(song:FreeplaySongData)
		{
			if (song == null) return true; // Random

			return song.hasDifficulty(currentDifficulty);
		});

		if (onlyIfChanged && sameSongs(tempSongs, currentFilteredSongs))
		{
			// If the song list is the same, we don't need to generate a new list.
			// Instead, we just apply the jump-in animation to the existing capsules.
			for (capsule in grpCapsules.members)
			{
				if (!noJumpIn)
				{
					capsule.initPosition(FlxG.width, 0);
					capsule.initJumpIn(0, force);
				}
			}

			// Stop processing.
			return;
		}

		// Only now do we know that the filter is actually changing.
		currentFilter = filterStuff;
		currentFilteredSongs = tempSongs;
		curSelected = 0;

		// Killed, not destroyed: every capsule is a dozen sprites and half a dozen
		// atlases, and building a fresh set on every difficulty press is what made that
		// press take a visible age. V-Slice recycles them and so does this.
		grpCapsules.killMembers();

		// One shader for the lot, like V-Slice: it is how a character's freeplay gets
		// tinted as a whole, so every capsule has to be looking at the same one.
		var hsvShader:HSVShader = new HSVShader();

		// The RANDOM capsule, which is why everything below counts from one.
		var randomCapsule:SongMenuItem = grpCapsules.recycle(SongMenuItem);
		randomCapsule.initRandom();
		randomCapsule.onConfirm = function() capsuleOnOpenRandom(randomCapsule);
		randomCapsule.hsvShader = hsvShader;
		randomCapsule.xOffset = CUTOUT_WIDTH * SONGS_POS_MULTI;
		if (force) randomCapsule.initJumpIn(0, force);
		else randomCapsule.forcePosition();

		for (i in 1...currentFilteredSongs.length)
		{
			var tempSong:FreeplaySongData = currentFilteredSongs[i];
			if (tempSong == null) continue;

			var funnyMenu:SongMenuItem = grpCapsules.recycle(SongMenuItem);
			funnyMenu.initPosition(FlxG.width, 0);
			funnyMenu.initData(tempSong, i, currentDifficulty);
			funnyMenu.onConfirm = function() capsuleOnConfirmDefault(funnyMenu);
			funnyMenu.y = funnyMenu.intendedY(i + 1) + 10;
			funnyMenu.targetPos.x = funnyMenu.x;
			funnyMenu.capsule.alpha = 0.5;
			funnyMenu.hsvShader = hsvShader;
			funnyMenu.xOffset = CUTOUT_WIDTH * SONGS_POS_MULTI;

			// Each capsule's NEW tag starts on a different frame, so a column of them
			// doesn't pulse in lockstep.
			if (funnyMenu.newText.animation.curAnim != null) funnyMenu.newText.animation.curAnim.curFrame = 45 - (((i - 1) * 4) % 45);

			if (force) funnyMenu.initJumpIn(0, force);
			else funnyMenu.forcePosition();
		}

		if (funnyCam != null) forEach(function(basic) basic.cameras = [funnyCam]);
		restoreRankCameras();

		rememberSelection();
		changeSelection();
		refreshCapsuleDisplays();
	}

	function rememberSelection():Void
	{
		if (rememberedSongName == null) return;

		for (i in 1...currentFilteredSongs.length)
		{
			if (currentFilteredSongs[i] == null || currentFilteredSongs[i].songName != rememberedSongName) continue;

			curSelected = i;
			return;
		}

		curSelected = 0;
	}

	/** Whether two song lists hold the same songs, whatever order they are in. */
	static function sameSongs(a:Array<FreeplaySongData>, b:Array<FreeplaySongData>):Bool
	{
		if (a.length != b.length) return false;

		for (song in a)
			if (!b.contains(song)) return false;

		return true;
	}

	/**
	 * Narrows the song list down to whatever the letter sort is asking for.
	 *
	 * The regex is V-Slice's: a group like `A-C` becomes `^[A-C].*`, which is why the
	 * letters are ranges rather than single letters - `^[OR]` would not match Pico, and
	 * `^[O-R]` does.
	 */
	public function sortSongs(songsToFilter:Array<FreeplaySongData>, songFilter:SongFilter):Array<FreeplaySongData>
	{
		var filterAlphabetically = function(a:FreeplaySongData, b:FreeplaySongData):Int
		{
			var nameA:String = (a != null) ? a.songName.toLowerCase() : '';
			var nameB:String = (b != null) ? b.songName.toLowerCase() : '';

			if (nameA < nameB) return -1;
			if (nameA > nameB) return 1;
			return 0;
		};

		switch (songFilter.filterType)
		{
			case REGEXP:
				// filterStuff.filterData has a string with the first letter of the sorting range, and the second one
				// this creates a filter to return all the songs that start with a letter between those two
				var filterRegexp:EReg = new EReg('^[' + songFilter.filterData + '].*', 'i');
				songsToFilter = songsToFilter.filter(function(filteredSong:FreeplaySongData)
				{
					if (filteredSong == null) return true; // Random

					return filterRegexp.match(filteredSong.songName);
				});

				songsToFilter.sort(filterAlphabetically);

			case STARTSWITH:
				// extra note: this is essentially a "search"
				songsToFilter = songsToFilter.filter(function(filteredSong:FreeplaySongData)
				{
					if (filteredSong == null) return true; // Random

					return filteredSong.songName.toLowerCase().startsWith(songFilter.filterData);
				});

			case FAVORITE:
				// sort favorites by week, not alphabetically
				songsToFilter = songsToFilter.filter(function(filteredSong:FreeplaySongData)
				{
					if (filteredSong == null) return true; // Random

					return filteredSong.isFav;
				});

			case ALL:
				// no filter!
		}

		return songsToFilter;
	}

	function refreshCapsuleDisplays():Void
	{
		for (capsule in grpCapsules.members)
			if (capsule != null && capsule.alive) capsule.refreshDisplay(currentDifficulty);
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		lerpScoreDisplays();
		handleInputs(elapsed);
	}

	function lerpScoreDisplays():Void
	{
		lerpScore = snap(FreeplayMath.smoothLerp(lerpScore, intendedScore, FlxG.elapsed, 0.2), intendedScore, 1);
		lerpCompletion = snap(FreeplayMath.smoothLerp(lerpCompletion, intendedCompletion, FlxG.elapsed, 0.5), intendedCompletion, 1 / 100);

		if (Math.isNaN(lerpScore)) lerpScore = intendedScore;
		if (Math.isNaN(lerpCompletion)) lerpCompletion = intendedCompletion;

		fpScoreDisplay.updateScore(Std.int(lerpScore));

		txtCompletion.text = '${Std.int(Math.min(100, Math.max(0, Math.floor(lerpCompletion * 100))))}';

		// Right align the completion percentage.
		switch (txtCompletion.text.length)
		{
			case 3: txtCompletion.offset.x = 10;
			case 2: txtCompletion.offset.x = 0;
			case 1: txtCompletion.offset.x = -24;
			default: txtCompletion.offset.x = 0;
		}
	}

	static inline function snap(base:Float, target:Float, threshold:Float):Float
		return Math.abs(base - target) <= threshold ? target : base;

	var spamming:Bool = false;
	var spamTimer:Float = 0;

	function handleInputs(elapsed:Float):Void
	{
		if (!canInteract()) return;

		handleDirectionalInput(elapsed);

		if (controls.UI_LEFT_P) changeDiff(-1);
		if (controls.UI_RIGHT_P) changeDiff(1);

		if (controls.BACK) goBack();

		if (controls.ACCEPT && currentCapsule != null && currentCapsule.onConfirm != null) currentCapsule.onConfirm();

		// Psych's modifiers, on the key Psych's own freeplay uses for them. V-Slice has no
		// equivalent menu to copy the binding from, and anyone coming from Psych will already
		// reach for CTRL here. Previews keep playing underneath, since the substate does not
		// touch the music and stopping it would restart the song on the way back.
		if (FlxG.keys.justPressed.CONTROL)
		{
			persistentUpdate = false;
			openSubState(new GameplayChangersSubstate());
		}

		// F5 replays the rank animation on the highlighted song without having to earn one,
		// stepping to the next tier each press so all six can be seen in a row. Nothing is
		// written to the save - the badge goes back to the real one on the next selection
		// change - so this cannot award a rank by accident.
		if (FlxG.keys.justPressed.F5 && currentCapsule != null && currentCapsule.freeplayData != null)
		{
			var previous:FreeplayRankTier = currentCapsule.ranking.rank;
			var oldRank:Null<FreeplayRankTier> = previous.exists() ? previous : null;
			testRankIndex = (testRankIndex + 1) % TEST_RANKS.length;

			rankAnimStart({oldRank: oldRank, newRank: TEST_RANKS[testRankIndex]});
		}
	}

	static final TEST_RANKS:Array<FreeplayRankTier> = [
		FreeplayRankTier.LOSS, FreeplayRankTier.GOOD, FreeplayRankTier.GREAT,
		FreeplayRankTier.EXCELLENT, FreeplayRankTier.PERFECT, FreeplayRankTier.PERFECT_GOLD
	];
	var testRankIndex:Int = -1;

	override function closeSubState():Void
	{
		persistentUpdate = true;
		super.closeSubState();
	}

	/**
	 * Up and down, with V-Slice's hold-to-spam: nothing for most of a second, then a
	 * step every 0.07, so a long list can be crossed without the first press running away.
	 */
	function handleDirectionalInput(elapsed:Float):Void
	{
		final upP:Bool = controls.UI_UP;
		final downP:Bool = controls.UI_DOWN;

		if (upP || downP)
		{
			if (spamming)
			{
				if (spamTimer >= 0.07)
				{
					spamTimer = 0;
					changeSelection(upP ? -1 : 1);
				}
			}
			else if (spamTimer >= 0.9)
				spamming = true;
			else if (spamTimer <= 0)
				changeSelection(upP ? -1 : 1);

			spamTimer += elapsed;
			if (dj != null) dj.onPlayerAction();
		}
		else
		{
			spamming = false;
			spamTimer = 0;
		}
	}

	function changeSelection(change:Int = 0):Void
	{
		var prevSelected:Int = curSelected;

		curSelected += change;

		if (curSelected < 0) curSelected = grpCapsules.countLiving() - 1;
		if (curSelected >= grpCapsules.countLiving()) curSelected = 0;

		if (change != 0 && curSelected != prevSelected) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		var daSong:FreeplaySongData = currentCapsule.freeplayData;
		intendedScore = (daSong != null) ? daSong.getScore(currentDifficulty) : 0;
		intendedCompletion = (daSong != null) ? Math.max(0, daSong.getAccuracy(currentDifficulty)) : 0;
		rememberedSongName = (daSong != null) ? daSong.songName : null;

		changeDiff();
		currentCapsule.refreshDisplay(currentDifficulty);

		for (index => capsule in grpCapsules.members)
		{
			// V-Slice counts its capsules from one: member zero is RANDOM, and what this
			// buys is the selected song sitting in the second slot with one above it,
			// where the arc of x positions bulges furthest right.
			var slot:Int = index + 1;

			capsule.selected = (index == curSelected);
			capsule.curSelected = curSelected;

			var capsuleIndex:Int = slot - curSelected;
			var yOffset:Float = 0;

			// Small offset so edge capsules actually go offscreen enough to not require to be rendered.
			if (capsuleIndex < 0) yOffset += 50;
			else if (capsuleIndex > 4) yOffset -= 10;

			capsule.targetPos.y = capsule.intendedY(capsuleIndex) - yOffset;
			capsule.targetPos.x = capsule.intendedX(capsuleIndex) + (CUTOUT_WIDTH * SONGS_POS_MULTI);

			if (slot < curSelected) capsule.targetPos.y -= 100; // another 100 for good measure
		}

		if (daSong != null)
		{
			albumRoll.albumId = albumIdFor(daSong);
			albumRoll.setDifficultyStars(daSong.getDifficultyRating(currentDifficulty));
		}
		else
			albumRoll.albumId = null;

		if (grpCapsules.countLiving() > 0 && canInteract())
		{
			if (FlxG.sound.music != null) FlxG.sound.music.pause();
			queuePreview();
			currentCapsule.selected = true;
		}
	}

	/**
	 * The root of difficulty changes.
	 *
	 * V-Slice cycles through every difficulty in the game and, when the song it is on
	 * hasn't got the one you landed on, moves to the nearest song that has. Psych's
	 * difficulties belong to a week rather than to the game, so `allDifficulties` stands
	 * in for its global list and the same rule applies on top of it - which is a much
	 * better fit for Psych than swapping the list out underneath you would be.
	 */
	function changeDiff(change:Int = 0, capsuleAnim:Bool = false):Void
	{
		if (capsuleAnim && currentCapsule != null)
		{
			currentCapsule.doLerp = false;

			var movement:Float = (change > 0) ? 15 : -15;
			FlxTween.tween(currentCapsule, {x: currentCapsule.x - movement}, 0.1, {ease: FlxEase.expoOut});
			FlxTween.tween(currentCapsule, {x: currentCapsule.x + movement}, 0.1, {ease: FlxEase.expoIn, startDelay: 0.1});
		}

		// The difficulty that is leaving slides out the way the arrow points.
		for (diff in grpDifficulties.group.members)
		{
			if (diff == null || diff.difficultyId != currentDifficulty) continue;
			if (change == 0) break;

			diff.visible = true;
			final newX:Int = (change > 0) ? -320 : 500;

			FlxTween.tween(diff, {x: newX + (CUTOUT_WIDTH * DJ_POS_MULTI)}, 0.2, {
				ease: FlxEase.circInOut,
				onComplete: function(_)
				{
					diff.x = 90 + (CUTOUT_WIDTH * DJ_POS_MULTI);
					diff.visible = false;
				}
			});
			break;
		}

		if (change != 0) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		var daSong:FreeplaySongData = currentCapsule.freeplayData;

		var currentDifficultyIndex:Int = allDifficulties.indexOf(currentDifficulty);
		if (currentDifficultyIndex == -1) currentDifficultyIndex = allDifficulties.indexOf(Difficulty.getDefault());
		if (currentDifficultyIndex == -1) currentDifficultyIndex = 0;

		currentDifficultyIndex += change;

		if (currentDifficultyIndex < 0) currentDifficultyIndex = allDifficulties.length - 1;
		if (currentDifficultyIndex >= allDifficulties.length) currentDifficultyIndex = 0;

		currentDifficulty = allDifficulties[currentDifficultyIndex];

		// For when we change the difficulty, but the song doesn't have that difficulty!
		if (daSong != null && !daSong.hasDifficulty(currentDifficulty))
		{
			// Switch to the closest song with that difficulty.
			curSelected = findClosestDiff(currentDifficulty);
			daSong = currentCapsule.freeplayData;
			rememberedSongName = (daSong != null) ? daSong.songName : null;
		}

		rememberedDifficulty = currentDifficulty;

		if (daSong != null)
		{
			intendedScore = daSong.getScore(currentDifficulty);
			intendedCompletion = Math.max(0, daSong.getAccuracy(currentDifficulty));
			if (!capsuleAnim) generateSongList(currentFilter, false, true, true);
			if (change != 0) currentCapsule.refreshDisplay(currentDifficulty);
		}
		else
		{
			intendedScore = 0;
			intendedCompletion = 0;
			if (!capsuleAnim) generateSongList(currentFilter, false, true, true);
		}

		if (!Math.isFinite(intendedCompletion) || Math.isNaN(intendedCompletion)) intendedCompletion = 0;

		// The difficulty that is arriving slides in from the other side.
		for (diffSprite in grpDifficulties.group.members)
		{
			if (diffSprite == null) continue;

			final isCurrentDiff:Bool = (diffSprite.difficultyId == currentDifficulty);

			if (change == 0) diffSprite.visible = isCurrentDiff;

			if (!isCurrentDiff || change == 0) continue;

			diffSprite.x = (change > 0) ? 500 : -320;
			diffSprite.x += (CUTOUT_WIDTH * DJ_POS_MULTI);

			FlxTween.tween(diffSprite, {x: 90 + (CUTOUT_WIDTH * DJ_POS_MULTI)}, 0.2, {ease: FlxEase.circInOut});

			diffSprite.offset.y += 5;
			diffSprite.alpha = 0.5;
			new FlxTimer().start(1 / 24, function(swag)
			{
				diffSprite.alpha = 1;
				diffSprite.updateHitbox();
				diffSprite.visible = true;
			});
		}

		if (change != 0)
		{
			if (change < 0) diffSelLeft.press();
			else diffSelRight.press();
		}
	}

	/** The capsule nearest the one selected whose song has this difficulty. */
	function findClosestDiff(diff:String):Int
	{
		var closestIndex:Int = 0;

		for (index in 0...grpCapsules.members.length)
		{
			var song:FreeplaySongData = grpCapsules.members[index].freeplayData;
			if (song == null) continue;

			var c:Int = curSelected - index;
			if (song.hasDifficulty(diff) && (Math.abs(c) < Math.abs(closestIndex - curSelected) || closestIndex == 0)) closestIndex = index;
		}

		return closestIndex;
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
		clearPreviews();

		var capsule:SongMenuItem = currentCapsule;
		previewTimers.push(new FlxTimer().start(FADE_IN_DELAY, function(_) playCurSongPreview(capsule)));
	}

	function clearPreviews():Void
	{
		while (previewTimers.length > 0)
		{
			var timer:FlxTimer = previewTimers.pop();
			if (timer != null) timer.cancel();
		}
	}

	function playCurSongPreview(daSongCapsule:SongMenuItem):Void
	{
		if (daSongCapsule == null || !daSongCapsule.selected || !canInteract()) return;

		var song:FreeplaySongData = daSongCapsule.freeplayData;
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

	/** RANDOM picks a song and opens it, exactly as picking it yourself would. */
	function capsuleOnOpenRandom(randomCapsule:SongMenuItem):Void
	{
		var available:Array<SongMenuItem> = grpCapsules.members.filter(function(cap:SongMenuItem) return cap.alive && cap.freeplayData != null);

		if (available.length == 0)
		{
			trace('No songs available!');
			FlxG.sound.play(Paths.sound('cancelMenu'));
			return;
		}

		var chosen:SongMenuItem = FlxG.random.getObject(available);

		// The difficulty has to be one the chosen song actually has.
		if (chosen.freeplayData != null && !chosen.freeplayData.hasDifficulty(currentDifficulty))
			currentDifficulty = chosen.freeplayData.difficulties[0];

		capsuleOnConfirmDefault(chosen);
	}

	function capsuleOnConfirmDefault(cap:SongMenuItem):Void
	{
		var song:FreeplaySongData = cap.freeplayData;
		if (song == null) return;

		uiState = Exiting;

		clearPreviews();

		FlxG.sound.play(Paths.sound('confirmMenu'));

		if (dj != null) dj.onConfirm();

		currentCapsule.forcePosition();
		currentCapsule.confirm();
		backingCard.confirm();

		if (FlxG.sound.music != null) FlxTween.tween(FlxG.sound.music, {volume: 0}, 0.6);

		new FlxTimer().start(0.9, function(tmr:FlxTimer)
		{
			funnyCam.fade(FlxColor.BLACK, 0.2, false, function() loadSong(song));
		});
	}

	function loadSong(song:FreeplaySongData):Void
	{
		persistentUpdate = false;
		Mods.currentModDirectory = song.folder;

		var songLowercase:String = song.formatted();
		var difficulty:Int = song.difficultyIndex(currentDifficulty);
		var poop:String = Highscore.formatSong(songLowercase, difficulty);

		try
		{
			Song.loadFromJson(poop, songLowercase);
			PlayState.isStoryMode = false;
			PlayState.storyDifficulty = difficulty;
		}
		catch (e:haxe.Exception)
		{
			trace('ERROR! ${e.message}');

			// Nothing to play, so hand the menu back rather than dying on a black screen.
			uiState = Idle;
			funnyCam.fade(FlxColor.BLACK, 0.2, true);
			FlxG.sound.play(Paths.sound('cancelMenu'));
			return;
		}

		@:privateAccess
		if (PlayState._lastLoadedModDirectory != Mods.currentModDirectory)
		{
			// Left for PlayState to do rather than done here. freeGraphicsFromMemory() works out
			// what to keep by walking the live state's sprites, and this menu is still on screen
			// and still drawing for the frames the transition takes - so anything its scan misses
			// gets its texture freed mid-render, and the next draw dies inside FlxDrawQuadsItem.
			// nextReloadAll reaches the same end from PlayState.create(), by which point there is
			// nothing of this menu left to trip over.
			PlayState.nextReloadAll = true;
		}

		LoadingState.prepareToSongEarly();
		LoadingState.loadAndSwitchState(new PlayState());

		#if !SHOW_LOADING_SCREEN
		if (FlxG.sound.music != null) FlxG.sound.music.stop();
		#end

		#if (MODS_ALLOWED && DISCORD_ALLOWED)
		DiscordClient.loadModRPC();
		#end
	}

	/**
	 * Sends every piece of the menu off its own edge.
	 *
	 * The list of what moves is `exitMovers`, built as the menu is - so a sprite that is
	 * added is a sprite that leaves, and there is no second list to forget to update.
	 * That is V-Slice's arrangement and it exists for a reason: the first version of this
	 * moved four things by hand and left the capsules, the score and the top bar sitting
	 * on screen while the rest of the menu walked out.
	 */
	function goBack():Void
	{
		if (!canInteract()) return;

		uiState = Exiting;

		clearPreviews();

		FlxG.sound.play(Paths.sound('cancelMenu'));

		var longestTimer:Float = 0;

		backingCard.disappear();

		for (grpSpr in exitMovers.keys())
		{
			var moveData:MoveData = exitMovers.get(grpSpr);
			if (moveData == null) continue;

			for (spr in grpSpr)
			{
				if (spr == null) continue;

				var moveDataX:Float = (moveData.x != null) ? moveData.x : spr.x;
				var moveDataY:Float = (moveData.y != null) ? moveData.y : spr.y;
				var moveDataSpeed:Float = (moveData.speed != null) ? moveData.speed : 0.2;
				var moveDataWait:Float = (moveData.wait != null) ? moveData.wait : 0.0;

				FlxTween.tween(spr, {x: moveDataX, y: moveDataY}, moveDataSpeed, {ease: FlxEase.expoIn});

				longestTimer = Math.max(longestTimer, moveDataSpeed + moveDataWait);
			}
		}

		for (caps in grpCapsules.members)
		{
			caps.doJumpIn = false;
			caps.doLerp = false;
			caps.doJumpOut = true;
		}

		new FlxTimer().start(longestTimer, function(_)
		{
			persistentUpdate = false;
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			MusicBeatState.switchState(new MainMenuState());
		});
	}

	// ---------------------------------------------------------------------------------------
	// The rank animation. V-Slice's rankAnimStart -> rankDisplayNew -> rankAnimSlam -> finish,
	// with its timings kept. What is missing is the DJ, who in V-Slice fist-pumps through all
	// of it; there is nobody to pump here, so those calls are simply absent rather than faked.
	// ---------------------------------------------------------------------------------------

	var rankCamera:FlxCamera;
	var rankBg:FlxSprite;
	var rankVignette:FlxSprite;
	var sparks:FlxSprite;
	var sparksAdd:FlxSprite;
	var rankOriginalPos:FlxPoint = new FlxPoint();

	function setUpRankAnim():Void
	{
		// The capsule being ranked is moved onto a camera of its own so it can be flung to the
		// middle of the screen and zoomed into without dragging the rest of the menu with it.
		rankCamera = new FlxCamera();
		rankCamera.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(rankCamera, false);

		rankBg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xD3000000);
		rankBg.scrollFactor.set();
		rankBg.alpha = 0;
		rankBg.cameras = [rankCamera];

		// Directly beneath the capsules rather than on the end of the list. A camera does not
		// reorder anything - the state's member order is the draw order - so appending this
		// would black out the very capsule it is meant to be sitting behind.
		var capsuleLayer:Int = members.indexOf(grpCapsules);
		if (capsuleLayer < 0) add(rankBg);
		else insert(capsuleLayer, rankBg);

		rankVignette = new FlxSprite().loadGraphic(Paths.image('freeplay/rankVignette'));
		rankVignette.scrollFactor.set();
		rankVignette.scale.set(2, 2);
		rankVignette.updateHitbox();
		rankVignette.blend = BlendMode.ADD;
		rankVignette.alpha = 0;
		rankVignette.cameras = [funnyCam];
		add(rankVignette);

		sparks = new FlxSprite();
		sparks.frames = Paths.getSparrowAtlas('freeplay/sparks');
		sparks.animation.addByPrefix('sparks', 'sparks', 24, false);
		sparks.setPosition(517, 134);
		sparks.scale.set(0.5, 0.5);
		sparks.blend = BlendMode.ADD;
		sparks.visible = false;
		sparks.cameras = [rankCamera];
		add(sparks);

		sparksAdd = new FlxSprite();
		sparksAdd.frames = Paths.getSparrowAtlas('freeplay/sparksadd');
		sparksAdd.animation.addByPrefix('sparks add', 'sparks add', 24, false);
		sparksAdd.setPosition(498, 116);
		sparksAdd.scale.set(0.5, 0.5);
		sparksAdd.blend = BlendMode.ADD;
		sparksAdd.visible = false;
		sparksAdd.cameras = [rankCamera];
		add(sparksAdd);
	}

	/**
	 * Puts the rank sprites back on their own camera.
	 *
	 * generateSongList ends by sweeping every member onto funnyCam, and it runs again every
	 * time the letter filter changes - so without this the backdrop and the sparks quietly
	 * migrate off the rank camera partway through a session.
	 */
	/**
	 * Takes V-Slice's own backdrop out of the picture: the pink card it all sits on, the orange
	 * strip across it, and the week 1 art on the right with the black panel that masks it in.
	 *
	 * Hidden rather than deleted. The intro still tweens the art's colour and the exit still
	 * flies the panel off screen, and both are harmless against an invisible sprite - whereas
	 * removing them means unpicking the entrance, the exit and the confirm, none of which is
	 * background. Turning any of these back on is one visible = true.
	 */
	function hideVSliceBackdrop():Void
	{
		backingCard.pinkBack.visible = false;
		backingCard.orangeBackShit.visible = false;
		backingCard.alsoOrangeLOL.visible = false;
		backingImage.visible = false;
		blackOverlayBullshitLOLXD.visible = false;
	}

	function restoreRankCameras():Void
	{
		if (rankCamera == null) return;

		rankBg.cameras = [rankCamera];
		sparks.cameras = [rankCamera];
		sparksAdd.cameras = [rankCamera];
		rankVignette.cameras = [funnyCam];
	}

	/**
	 * Everything the running animation owns, so a second run can take it all back.
	 *
	 * The sequence is five timers deep and leaves tweens running on two cameras, the capsule,
	 * its badge and its target position. Left alone, a second run inherits all of it: the first
	 * run's four-second failsafe lands in the middle of the second and yanks the capsule home
	 * before its rank arrives, camera zoom tweens stack into a zoom far past 1.8, and a capsule
	 * whose restore never ran stays frozen out of the list with doLerp off.
	 */
	var rankTimers:Array<FlxTimer> = [];
	var rankingCapsule:SongMenuItem = null;

	function rankTimer(delay:Float, callback:FlxTimer->Void):Void
		rankTimers.push(new FlxTimer().start(delay, callback));

	function releaseRankTimers():Void
	{
		for (timer in rankTimers)
			if (timer != null) timer.cancel();
		rankTimers.resize(0);
	}

	/**
	 * Hands the ranked capsule back to the list: off the rank camera, done being written to by
	 * the animation's tweens, and sitting where the list expects it. Everything here is about
	 * the capsule alone, because this also runs at the natural end of the animation - where the
	 * cameras are still easing back and should be left to.
	 */
	function restoreRankedCapsule():Void
	{
		var capsule:SongMenuItem = rankingCapsule;
		rankingCapsule = null;
		if (capsule == null) return;

		IntervalShake.stopShaking(capsule);
		FlxTween.cancelTweensOf(capsule);
		FlxTween.cancelTweensOf(capsule.targetPos);
		FlxTween.cancelTweensOf(capsule.ranking);
		FlxTween.cancelTweensOf(capsule.blurredRanking);

		capsule.angle = 0;
		capsule.ranking.scale.set(1, 1);
		capsule.blurredRanking.scale.set(1, 1);
		capsule.fakeRanking.visible = false;
		capsule.fakeBlurredRanking.visible = false;
		capsule.targetPos.set(rankOriginalPos.x, rankOriginalPos.y);
		capsule.setPosition(rankOriginalPos.x, rankOriginalPos.y);
		capsule.doLerp = true;
		capsule.cameras = [funnyCam];
	}

	/**
	 * Everything back as it was, including the parts a finished animation is allowed to leave
	 * settling. For starting a run over the top of another, not for ending one cleanly.
	 */
	function cancelRankAnim():Void
	{
		releaseRankTimers();

		FlxTween.cancelTweensOf(rankCamera);
		FlxTween.cancelTweensOf(funnyCam);
		FlxTween.cancelTweensOf(rankBg);
		FlxTween.cancelTweensOf(rankVignette);

		for (capsule in grpCapsules.members)
			if (capsule != null) IntervalShake.stopShaking(capsule);

		restoreRankedCapsule();

		rankCamera.zoom = 1;
		funnyCam.zoom = 1;
		rankBg.alpha = 0;
		rankVignette.alpha = 0;
		sparks.visible = sparksAdd.visible = false;
	}

	function rankAnimStart(params:RankAnimParams):Void
	{
		var capsule:SongMenuItem = currentCapsule;
		if (capsule == null) return;

		// Anything still in flight from a previous run belongs to that run, not this one.
		cancelRankAnim();

		uiState = RankAnimating;
		rankingCapsule = capsule;

		clearPreviews();
		if (FlxG.sound.music != null) FlxG.sound.music.volume = 0;

		capsule.sparkle.alpha = 0;
		capsule.doLerp = false;
		capsule.cameras = [rankCamera];

		// Where it has to come back to. Read off the capsule rather than written down, so the
		// slam lands wherever the list actually puts the selected song.
		rankOriginalPos.set(capsule.targetPos.x, capsule.targetPos.y);

		rankBg.alpha = 1;
		rankCamera.fade(FlxColor.BLACK, 0.5, true, null, true);

		// The badge it is losing, sitting there to be knocked off. With nothing to knock off,
		// the new one simply arrives and there are no sparks.
		capsule.ranking.visible = false;
		capsule.blurredRanking.visible = false;
		capsule.fakeRanking.visible = false;
		capsule.fakeBlurredRanking.visible = false;

		if (params.oldRank != null)
		{
			capsule.fakeRanking.rank = params.oldRank;
			capsule.fakeBlurredRanking.rank = params.oldRank;
			capsule.fakeRanking.visible = true;
			capsule.fakeBlurredRanking.visible = true;
			capsule.fakeRanking.alpha = 1;
			sparksAdd.color = params.oldRank.getColor();
		}

		rankCamera.zoom = 1.85;
		FlxTween.tween(rankCamera, {zoom: 1.8}, 0.6, {ease: FlxEase.sineIn});

		funnyCam.zoom = 1.15;
		FlxTween.tween(funnyCam, {zoom: 1.1}, 0.6, {ease: FlxEase.sineIn});

		capsule.setPosition((FlxG.width / 2) - (capsule.capsule.width / 2), (FlxG.height / 2) - (capsule.capsule.height / 2));

		rankTimer(0.5, function(_) rankDisplayNew(params, capsule));

		// A menu that cannot be left is worse than one that skips its flourish. If any step of
		// the sequence fails to arrive, this puts the capsule back and hands control over. It is
		// tracked like the rest, so it dies with its own run rather than landing in the next.
		rankTimer(4, function(_)
		{
			if (uiState == RankAnimating) rankAnimFinish(capsule);
		});
	}

	function rankDisplayNew(params:RankAnimParams, capsule:SongMenuItem):Void
	{
		// Twenty times its size and shrunk in a tenth of a second, which is what makes it read
		// as a stamp coming down rather than a sprite appearing.
		capsule.ranking.visible = true;
		capsule.blurredRanking.visible = true;
		capsule.ranking.rank = params.newRank;
		capsule.blurredRanking.rank = params.newRank;
		capsule.ranking.scale.set(20, 20);
		capsule.blurredRanking.scale.set(20, 20);

		// Settles at 1, not V-Slice's 0.9. Their badge sits at 0.9 in the capsule's normal
		// layout; ours sits at 1, so landing on 0.9 meant the stamp ended a touch small and
		// then popped to full size the moment the animation let go of it.
		FlxTween.tween(capsule.ranking, {'scale.x': 1, 'scale.y': 1}, 0.1);
		FlxTween.tween(capsule.blurredRanking, {'scale.x': 1, 'scale.y': 1}, 0.1);

		rankTimer(0.1, function(_)
		{
			capsule.fakeRanking.visible = false;
			capsule.fakeBlurredRanking.visible = false;

			if (params.oldRank != null)
			{
				sparks.visible = sparksAdd.visible = true;
				sparks.animation.play('sparks', true);
				sparksAdd.animation.play('sparks add', true);
				sparks.animation.finishCallback = function(_) sparks.visible = sparksAdd.visible = false;
			}

			FlxG.sound.play(Paths.sound(rankImpactSound(params.newRank)));

			rankCamera.zoom = 1.3;
			FlxTween.tween(rankCamera, {zoom: 1.5}, 0.3, {ease: FlxEase.backInOut});
			FlxTween.tween(funnyCam, {zoom: 1.05}, 0.3, {ease: FlxEase.elasticOut});

			capsule.x -= 10;
			capsule.y -= 20;
			capsule.angle = -3;
			FlxTween.tween(capsule, {angle: 0}, 0.5, {ease: FlxEase.backOut});

			IntervalShake.shake(capsule, 0.3, 1 / 30, 0.1, 0, FlxEase.quadOut);
		});

		rankTimer(0.4, function(_)
		{
			FlxTween.tween(funnyCam, {zoom: 1}, 0.8, {ease: FlxEase.sineIn});
			FlxTween.tween(rankCamera, {zoom: 1.2}, 0.8, {ease: FlxEase.backIn});
			FlxTween.tween(capsule, {x: rankOriginalPos.x - 7, y: rankOriginalPos.y - 80}, 1.3, {ease: FlxEase.quartIn});
		});

		rankTimer(0.6, function(_) rankAnimSlam(params, capsule));
	}

	function rankAnimSlam(params:RankAnimParams, capsule:SongMenuItem):Void
	{
		FlxTween.tween(rankBg, {alpha: 0}, 0.5, {ease: FlxEase.expoIn});
		FlxG.sound.play(Paths.sound(rankSlamSound(params.newRank)));

		FlxTween.tween(capsule.targetPos, {x: rankOriginalPos.x, y: rankOriginalPos.y}, 0.5, {ease: FlxEase.expoOut});

		rankTimer(0.5, function(_)
		{
			// The flight tween from rankDisplayNew still has a few tenths left to run, and it
			// writes x/y every frame - so it has to go before anything sets a final position,
			// or the capsule drifts back out of place under the shake. The angle tween is
			// collateral and is started again below.
			FlxTween.cancelTweensOf(capsule);
			IntervalShake.stopShaking(capsule);

			funnyCam.shake(0.0045, 0.35);

			rankCamera.zoom = 0.8;
			funnyCam.zoom = 0.8;
			FlxTween.tween(rankCamera, {zoom: 1}, 1, {ease: FlxEase.elasticOut});
			FlxTween.tween(funnyCam, {zoom: 1}, 0.8, {ease: FlxEase.elasticOut});

			capsule.fadeAnim(params.newRank);
			rankVignette.color = capsule.getTrailColor();
			rankVignette.alpha = 1;
			FlxTween.tween(rankVignette, {alpha: 0}, 0.6, {ease: FlxEase.expoOut});

			capsule.doLerp = false;
			capsule.setPosition(rankOriginalPos.x, rankOriginalPos.y);
			FlxTween.tween(capsule, {angle: 0}, 0.5, {ease: FlxEase.backOut});

			// The rest of the list flinches away from it, furthest first.
			for (index => other in grpCapsules.members)
			{
				if (other == null || index == curSelected) continue;

				var distance:Float = Math.abs(index - curSelected) - 1;
				if (distance >= 5) continue;

				rankTimer(distance / 20, function(_) IntervalShake.shake(other, 0.3, 1 / 30, 0.06, 0, FlxEase.quadOut));
			}

			IntervalShake.shake(capsule, 0.6, 1 / 24, 0.12, 0, FlxEase.quadOut, function(_) rankAnimFinish(capsule));
		});
	}

	function rankAnimFinish(capsule:SongMenuItem):Void
	{
		if (uiState != RankAnimating) return;

		// Before the teardown, because that stops the shake whose completion callback is this
		// function - and the guard above is what keeps that from re-entering and starting the
		// song preview twice.
		uiState = Idle;

		// Only the capsule. The cameras are mid-elastic and the vignette mid-fade, and both are
		// heading exactly where they should - cutting them here is what made the end of the
		// animation snap rather than settle.
		releaseRankTimers();
		restoreRankedCapsule();
		capsule.sparkle.alpha = 0.7;

		playCurSongPreview(capsule);
	}

	/** The thud as the badge lands. V-Slice keys this off the new rank, not the old. */
	function rankImpactSound(rank:FreeplayRankTier):String
	{
		return switch (rank)
		{
			case LOSS: 'ranks/rankinbad';
			case PERFECT, PERFECT_GOLD: 'ranks/rankinperfect';
			default: 'ranks/rankinnormal';
		}
	}

	/** The fanfare as the capsule slams home. */
	function rankSlamSound(rank:FreeplayRankTier):String
	{
		return switch (rank)
		{
			case GOOD: 'ranks/good';
			case GREAT: 'ranks/great';
			case EXCELLENT: 'ranks/excellent';
			case PERFECT, PERFECT_GOLD: 'ranks/perfect';
			default: 'ranks/loss';
		}
	}

	override function destroy():Void
	{
		clearPreviews();
		super.destroy();
	}
}

/** What the letter sort is asking the song list for. V-Slice's `SongFilter`. */
typedef SongFilter =
{
	var filterType:FilterType;
	var ?filterData:String;
}

/** Possible types to use for the song filter. */
enum abstract FilterType(String)
{
	/** Filter to songs which start with a string. */
	var STARTSWITH;

	/** Filter to songs which match a regular expression. */
	var REGEXP;

	/** Filter to songs which the player has starred. */
	var FAVORITE;

	/** Don't filter at all. */
	var ALL;
}

/** Where a sprite goes when the menu is left, and how fast. V-Slice's `MoveData`. */
typedef MoveData =
{
	var ?x:Float;
	var ?y:Float;
	var ?speed:Float;
	var ?wait:Float;
}

typedef ExitMoverData = Map<Array<FlxSprite>, MoveData>;

/**
 * What a just-finished song wants the freeplay to celebrate.
 *
 * `oldRank` is null when the song had never been ranked, which is the difference between
 * a badge appearing out of nothing and one being knocked off by a better one - the sparks
 * only play for the second.
 */
typedef RankAnimParams =
{
	var ?oldRank:FreeplayRankTier;
	var newRank:FreeplayRankTier;
}

/** What the menu is doing, and so what it will listen to. V-Slice's `UIStateMachine`. */
enum abstract FreeplayUIState(String)
{
	var EnteringFreeplay;
	var Idle;
	var Exiting;
	/** A rank is landing on a capsule. Everything is on hold until it has. */
	var RankAnimating;
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
	var whiteShader:PureColor;

	public function new(x:Float, y:Float, flipped:Bool)
	{
		super(x, y);

		whiteShader = new PureColor(FlxColor.WHITE);
		whiteShader.colorSet = true;

		frames = Paths.getSparrowAtlas('freeplay/freeplaySelector');
		animation.addByPrefix('shine', 'arrow pointer loop', 24);
		animation.play('shine');

		antialiasing = ClientPrefs.data.antialiasing;
		flipX = flipped;
	}

	/** Squashes to half size and flashes white for two frames, then springs back. */
	public function press():Void
	{
		offset.y -= 5;
		scale.set(0.5, 0.5);
		shader = whiteShader;

		new FlxTimer().start(2 / 24, function(tmr)
		{
			scale.set(1, 1);
			shader = null;
			updateHitbox();
		});
	}
}

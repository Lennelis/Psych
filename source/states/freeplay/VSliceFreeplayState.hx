package states.freeplay;

import backend.Highscore;
import backend.Song;
import backend.WeekData;
import flixel.FlxCamera;
import flixel.FlxObject;
import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import flixel.text.FlxText;
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
	public static final FADE_IN_DELAY:Float = 0.25;

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
	var ostName:FlxText;
	var exitMovers:ExitMoverData = new Map();
	var diffSelLeft:DifficultySelector;
	var diffSelRight:DifficultySelector;

	public var funnyCam:FlxCamera;

	/** The card behind where the DJ will go. */
	var backingCard:BackingCard;

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
		fpScoreDisplay = new FreeplayScore(FlxG.width - 353, 60, 7, 0);
		grpCapsules = new FlxTypedGroup<SongMenuItem>();
		grpDifficulties = new FlxTypedSpriteGroup<DifficultySprite>(-300, 80);
		txtCompletion = new FlxText(FlxG.width - 95, 82, 0, '0', 32);
		ostName = new FlxText(8, 8, FlxG.width - 16, "Friday Night Funkin'", 48);

		backingCard = new BackingCard(CUTOUT_WIDTH);
		backingImage = new FlxSprite(backingCard.pinkBack.width * 0.74, 0).loadGraphic(Paths.image('freeplay/freeplayBGweek1-bf'));

		diffSelLeft = new DifficultySelector((CUTOUT_WIDTH * DJ_POS_MULTI) + 20, grpDifficulties.y - 10, false);
		diffSelRight = new DifficultySelector((CUTOUT_WIDTH * DJ_POS_MULTI) + 325, grpDifficulties.y - 10, true);

		add(backingCard);
		backingCard.build();
		backingCard.applyExitMovers(exitMovers);

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

		diffSelLeft.visible = false;
		diffSelRight.visible = false;
		add(diffSelLeft);
		add(diffSelRight);

		// putting these here to fix the layering
		add(overhangStuff);
		add(topLeftCornerText);
		add(ostName);

		// Generates the song list with the capsules jumping in.
		generateSongList(true);

		// A camera of its own, so the fade when a song is picked doesn't touch anything
		// the state doesn't own - the touch pad gets its own below.
		funnyCam = new FlxCamera();
		funnyCam.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(funnyCam, false);

		forEach(function(basic) basic.cameras = [funnyCam]);

		#if TOUCH_CONTROLS_ALLOWED
		addVirtualPad(FULL, A_B);
		addVirtualPadCamera();
		#end

		// V-Slice waits on the DJ's intro here. Without a DJ yet, the card sliding in
		// takes the same beat, so the menu still arrives rather than appearing at once.
		new FlxTimer().start(0.9, function(_) onDJIntroDone());
	}

	/** Everything that lands once the intro is over and the menu becomes usable. */
	function onDJIntroDone():Void
	{
		uiState = Idle;

		FlxTween.color(backingImage, 0.6, 0xFF000000, 0xFFFFFFFF, {
			ease: FlxEase.expoOut,
			onUpdate: function(_) angleMaskShader.extraColor = backingImage.color,
			onComplete: function(_) blackOverlayBullshitLOLXD.visible = false
		});

		FlxTween.cancelTweensOf(grpDifficulties);
		for (diff in grpDifficulties.group.members)
		{
			if (diff == null) continue;

			FlxTween.cancelTweensOf(diff);
			FlxTween.tween(diff, {x: (CUTOUT_WIDTH * DJ_POS_MULTI) + 90}, 0.6, {ease: FlxEase.quartOut});
			diff.y = 80;
			diff.visible = (diff == currentDifficultySprite);
		}
		FlxTween.tween(grpDifficulties, {x: (CUTOUT_WIDTH * DJ_POS_MULTI) + 90}, 0.6, {ease: FlxEase.quartOut});

		diffSelLeft.visible = true;
		diffSelRight.visible = true;

		exitMovers.set([diffSelLeft, diffSelRight], {x: -diffSelLeft.width * 2, speed: 0.26});

		new FlxTimer().start(1 / 24, function(handShit)
		{
			fnfHighscoreSpr.visible = true;
			topLeftCornerText.visible = true;
			ostName.visible = true;
			fpScoreDisplay.visible = true;
			fpScoreDisplay.updateScore(0);

			clearBoxSprite.visible = true;
			txtCompletion.visible = true;
			intendedCompletion = 0;

			new FlxTimer().start(1.5 / 24, function(bold)
			{
				sillyStrokeWidth(0);
				changeSelection();
			});
		});

		backingImage.visible = true;
		backingCard.introDone();
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
	function generateSongList(force:Bool = false):Void
	{
		curSelected = 0;

		for (capsule in grpCapsules.members)
			capsule.kill();

		grpCapsules.clear();

		// One shader for the lot, like V-Slice: it is how a character's freeplay gets
		// tinted as a whole, so every capsule has to be looking at the same one.
		var hsvShader:HSVShader = new HSVShader();

		// The RANDOM capsule, which is why everything below counts from one.
		var randomCapsule:SongMenuItem = new SongMenuItem(0, 0);
		randomCapsule.initRandom();
		randomCapsule.onConfirm = function() capsuleOnOpenRandom(randomCapsule);
		randomCapsule.hsvShader = hsvShader;
		randomCapsule.xOffset = CUTOUT_WIDTH * SONGS_POS_MULTI;
		if (force) randomCapsule.initJumpIn(0, force);
		else randomCapsule.forcePosition();
		grpCapsules.add(randomCapsule);

		for (i in 1...songs.length)
		{
			var tempSong:FreeplaySongData = songs[i];
			if (tempSong == null) continue;

			var funnyMenu:SongMenuItem = new SongMenuItem(0, 0);
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

			grpCapsules.add(funnyMenu);
		}

		if (funnyCam != null) forEach(function(basic) basic.cameras = [funnyCam]);

		rememberSelection();
		changeSelection();
		refreshCapsuleDisplays();
	}

	function rememberSelection():Void
	{
		if (rememberedSongName == null) return;

		for (i in 1...songs.length)
		{
			if (songs[i] == null || songs[i].songName != rememberedSongName) continue;

			curSelected = i;
			return;
		}

		curSelected = 0;
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
			if (change != 0) currentCapsule.refreshDisplay(currentDifficulty);
		}
		else
		{
			intendedScore = 0;
			intendedCompletion = 0;
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

	override function destroy():Void
	{
		clearPreviews();
		super.destroy();
	}
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

/** What the menu is doing, and so what it will listen to. V-Slice's `UIStateMachine`. */
enum abstract FreeplayUIState(String)
{
	var EnteringFreeplay;
	var Idle;
	var Exiting;
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

package states.freeplay;
import states.freeplay.FreeplaySongData.FreeplayRankTier;

import flixel.group.FlxGroup;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import openfl.display.BlendMode;
import shaders.freeplay.GaussianBlurShader;
import shaders.freeplay.HSVShader;

/**
 * One song in the freeplay list: the capsule.
 *
 * Ported from V-Slice, with its numbers kept - the positions inside a capsule, the
 * seven frames of squash it jumps in on, the 0.8 everything is scaled by. What changed
 * is where the contents come from, since Psych's songs carry a week, an icon and a
 * colour rather than V-Slice's metadata.
 */
class SongMenuItem extends FlxSpriteGroup
{
	/**
	 * Nudges read from `images/freeplay/freeplayCapsule/position.json`.
	 *
	 * Same idea as the album's: the numbers that decide where a capsule's text sits are
	 * quicker to see than to derive, so they live in a file rather than in constants that
	 * have to be guessed at from a screenshot. All offsets, so all zeroes is what the code
	 * does on its own.
	 *
	 * Held statically because a capsule is built many times over; `reloadNudges()` drops it
	 * so the next menu reads the file again.
	 */
	static var nudges:CapsuleNudges = null;

	public static function reloadNudges():Void
		nudges = null;

	static function nudge():CapsuleNudges
	{
		if (nudges != null) return nudges;

		// These are the numbers Leo measured against the real game, so an untouched build
		// already looks right and position.json only exists for further tuning.
		nudges = {
			antialiasText: true,
			songTextX: 0, songTextY: 0,
			weekTextX: 0, weekTextY: 0, weekTextScale: 1,
			weekTextEngrave: true, weekTextEngraveColor: 'FF6E6A82', weekTextEngraveX: 1, weekTextEngraveY: 1,
			bpmTextX: 3, bpmTextY: 1, bpmTextScale: 1,
			bpmDigitsX: 0, bpmDigitsY: 0, bpmDigitGap: 11,
			difficultyTextX: 5, difficultyTextY: 2, difficultyTextScale: 1,
			difficultyDigitsX: 0, difficultyDigitsY: -1, difficultyDigitGap: 30,
			newTextX: 0, newTextY: 0, newTextScale: 1,
			rankX: 0, rankY: 0,
			iconX: 0, iconY: 0
		};

		try
		{
			var raw:String = Paths.getTextFromFile('images/freeplay/freeplayCapsule/position.json');
			if (raw == null || raw.length < 1) return nudges;

			var parsed:Dynamic = haxe.Json.parse(raw);
			function pick(name:String, fallback:Float):Float
			{
				var value:Dynamic = Reflect.field(parsed, name);
				if (value == null) return fallback;

				var asFloat:Float = cast value;
				return Math.isNaN(asFloat) ? fallback : asFloat;
			}

			var flag:Dynamic = Reflect.field(parsed, 'antialiasText');
			if (flag != null) nudges.antialiasText = (flag == true);

			nudges.songTextX = pick('songTextX', nudges.songTextX);
			nudges.songTextY = pick('songTextY', nudges.songTextY);
			nudges.weekTextX = pick('weekTextX', nudges.weekTextX);
			nudges.weekTextY = pick('weekTextY', nudges.weekTextY);
			nudges.weekTextScale = pick('weekTextScale', nudges.weekTextScale);

			var engrave:Dynamic = Reflect.field(parsed, 'weekTextEngrave');
			if (engrave != null) nudges.weekTextEngrave = (engrave == true);

			var engraveColor:Dynamic = Reflect.field(parsed, 'weekTextEngraveColor');
			if (engraveColor != null) nudges.weekTextEngraveColor = Std.string(engraveColor);

			nudges.weekTextEngraveX = pick('weekTextEngraveX', nudges.weekTextEngraveX);
			nudges.weekTextEngraveY = pick('weekTextEngraveY', nudges.weekTextEngraveY);
			nudges.bpmTextX = pick('bpmTextX', nudges.bpmTextX);
			nudges.bpmTextY = pick('bpmTextY', nudges.bpmTextY);
			nudges.bpmTextScale = pick('bpmTextScale', nudges.bpmTextScale);
			nudges.bpmDigitsX = pick('bpmDigitsX', nudges.bpmDigitsX);
			nudges.bpmDigitsY = pick('bpmDigitsY', nudges.bpmDigitsY);
			nudges.bpmDigitGap = pick('bpmDigitGap', nudges.bpmDigitGap);
			nudges.difficultyTextX = pick('difficultyTextX', nudges.difficultyTextX);
			nudges.difficultyTextY = pick('difficultyTextY', nudges.difficultyTextY);
			nudges.difficultyTextScale = pick('difficultyTextScale', nudges.difficultyTextScale);
			nudges.difficultyDigitsX = pick('difficultyDigitsX', nudges.difficultyDigitsX);
			nudges.difficultyDigitsY = pick('difficultyDigitsY', nudges.difficultyDigitsY);
			nudges.difficultyDigitGap = pick('difficultyDigitGap', nudges.difficultyDigitGap);
			nudges.newTextX = pick('newTextX', nudges.newTextX);
			nudges.newTextY = pick('newTextY', nudges.newTextY);
			nudges.newTextScale = pick('newTextScale', nudges.newTextScale);
			nudges.rankX = pick('rankX', nudges.rankX);
			nudges.rankY = pick('rankY', nudges.rankY);
			nudges.iconX = pick('iconX', nudges.iconX);
			nudges.iconY = pick('iconY', nudges.iconY);
		}
		catch (e:Dynamic)
			trace('SongMenuItem: could not read the capsule position.json ($e)');

		return nudges;
	}

	public var capsule:FlxSprite;

	var pixelIcon:FreeplayIcon;

	public var freeplayData(default, null):FreeplaySongData = null;

	public var selected(default, set):Bool;
	public var forceHighlight(default, set):Bool;

	var songText:CapsuleText;

	public var favIconBlurred:FlxSprite;
	public var favIcon:FlxSprite;
	public var ranking:FreeplayRank;
	public var blurredRanking:FreeplayRank;
	public var targetPos:FlxPoint = new FlxPoint();
	public var doLerp:Bool = false;
	public var doJumpIn:Bool = false;
	public var doJumpOut:Bool = false;
	public var onConfirm:Void->Void;
	public var hsvShader(default, set):HSVShader;

	public var bpmText:FlxSprite;
	public var difficultyText:FlxSprite;
	public var weekText:FlxSprite;
	public var newText:FlxSprite;

	var difficultyNumbers:Array<CapsuleNumber> = []; // "bignumbers" in the .fla
	var bpmNumbers:Array<CapsuleNumber> = []; // "smallnumbers" in the .fla

	public var sparkle:FlxSprite;

	var sparkleTimer:FlxTimer;

	/** Where this capsule sits in the list, so it knows how far it is from the selection. */
	public var index:Int = 0;

	/** How far right the whole column has been pushed, on a screen wider than 16:9. */
	public var xOffset:Float = 0;

	public var curSelected:Int = 0;

	public var realScaled:Float = 0.8;

	var grpHide:FlxGroup;

	// Defaulted because the capsules are recycled, and recycling builds one with no
	// arguments when the pool has nothing dead to hand back.
	public function new(x:Float = 0, y:Float = 0)
	{
		super(x, y);

		capsule = new FlxSprite();
		capsule.frames = Paths.getSparrowAtlas('freeplay/freeplayCapsule/capsule/freeplayCapsule');
		capsule.animation.addByPrefix('selected', 'mp3 capsule w backing0', 24);
		capsule.animation.addByPrefix('unselected', 'mp3 capsule w backing NOT SELECTED', 24);
		capsule.antialiasing = ClientPrefs.data.antialiasing;
		add(capsule);

		var nudged:CapsuleNudges = nudge();

		bpmText = new FlxSprite(144 + nudged.bpmTextX, 87 + nudged.bpmTextY).loadGraphic(Paths.image('freeplay/freeplayCapsule/bpmtext'));
		bpmText.setGraphicSize(Std.int(bpmText.width * 0.9 * nudged.bpmTextScale));
		bpmText.updateHitbox();
		bpmText.antialiasing = nudged.antialiasText;
		add(bpmText);

		difficultyText = new FlxSprite(414 + nudged.difficultyTextX, 87 + nudged.difficultyTextY).loadGraphic(Paths.image('freeplay/freeplayCapsule/difficultytext'));
		difficultyText.setGraphicSize(Std.int(difficultyText.width * 0.9 * nudged.difficultyTextScale));
		difficultyText.updateHitbox();
		difficultyText.antialiasing = nudged.antialiasText;
		add(difficultyText);

		weekText = new FlxSprite(291 + nudged.weekTextX, 88 + nudged.weekTextY);
		weekText.scale.set(0.9 * nudged.weekTextScale, 0.9 * nudged.weekTextScale);
		weekText.visible = false;
		weekText.active = false;
		// The week name is drawn from a font at runtime rather than coming off a sheet like
		// everything else here, so without this it is the one label on the capsule with hard
		// pixel edges - which is what made it look flat next to the art beside it.
		weekText.antialiasing = nudged.antialiasText;
		add(weekText);

		newText = new FlxSprite(454 + nudged.newTextX, 9 + nudged.newTextY);
		newText.frames = Paths.getSparrowAtlas('freeplay/freeplayCapsule/new');
		newText.animation.addByPrefix('newAnim', 'NEW notif', 24, true);
		newText.animation.play('newAnim', true);
		newText.setGraphicSize(Std.int(newText.width * 0.9 * nudged.newTextScale));
		newText.updateHitbox();
		newText.antialiasing = nudged.antialiasText;
		add(newText);

		for (i in 0...2)
		{
			var num:CapsuleNumber = new CapsuleNumber(466 + nudged.difficultyDigitsX + (i * nudged.difficultyDigitGap), 32 + nudged.difficultyDigitsY, true, 0);
			add(num);
			difficultyNumbers.push(num);
		}

		for (i in 0...3)
		{
			var num:CapsuleNumber = new CapsuleNumber(185 + nudged.bpmDigitsX + (i * nudged.bpmDigitGap), 88.5 + nudged.bpmDigitsY, false, 0);
			add(num);
			bpmNumbers.push(num);
		}

		// Never added to the group; it is only a list of what the pop-in hides and shows.
		grpHide = new FlxGroup();

		ranking = new FreeplayRank(420 + nudged.rankX, 41 + nudged.rankY);
		add(ranking);

		blurredRanking = new FreeplayRank(ranking.x, ranking.y);
		blurredRanking.shader = new GaussianBlurShader(1);
		add(blurredRanking);

		sparkle = new FlxSprite(ranking.x, ranking.y);
		sparkle.frames = Paths.getSparrowAtlas('freeplay/sparkle');
		sparkle.animation.addByPrefix('sparkle', 'sparkle Export0', 24, false);
		sparkle.animation.play('sparkle', true);
		sparkle.scale.set(0.8, 0.8);
		sparkle.blend = BlendMode.ADD;
		sparkle.visible = false;
		sparkle.alpha = 0.7;
		add(sparkle);

		songText = new CapsuleText(capsule.width * 0.26 + nudged.songTextX, 45 + nudged.songTextY, 'Random', Std.int(40 * realScaled));
		add(songText);
		grpHide.add(songText);

		// V-Slice's own position for it. Where it actually ends up being drawn is a
		// hundred pixels to the left of that and some way above it - see FreeplayIcon.
		pixelIcon = new FreeplayIcon(160 + nudged.iconX, 35 + nudged.iconY);
		add(pixelIcon);
		grpHide.add(pixelIcon);

		favIconBlurred = makeFavIcon(380, 40);
		favIconBlurred.shader = new GaussianBlurShader(1);
		add(favIconBlurred);

		favIcon = makeFavIcon(favIconBlurred.x, favIconBlurred.y);
		add(favIcon);

		setVisibleGrp(false);
	}

	function makeFavIcon(x:Float, y:Float):FlxSprite
	{
		var icon:FlxSprite = new FlxSprite(x, y);
		icon.frames = Paths.getSparrowAtlas('freeplay/favHeart');
		icon.animation.addByPrefix('fav', 'favorite heart', 24, false);
		icon.animation.play('fav');
		icon.setGraphicSize(50, 50);
		icon.updateHitbox();
		icon.blend = BlendMode.ADD;
		icon.visible = false;
		return icon;
	}

	function sparkleEffect(timer:FlxTimer):Void
	{
		sparkle.setPosition(FlxG.random.float(ranking.x - 20, ranking.x + 3), FlxG.random.float(ranking.y - 29, ranking.y + 4));
		sparkle.animation.play('sparkle', true);
		sparkleTimer = new FlxTimer().start(FlxG.random.float(1.2, 4.5), sparkleEffect);
	}

	/**
	 * Draws the week's name into the little label on the capsule.
	 *
	 * The label is a picture of text rather than text: V-Slice renders it once into a
	 * bitmap and keeps it in Flixel's cache under the string itself, so a week shared by
	 * twenty songs is drawn once. Psych's week names are file names, so `week4` becomes
	 * `week 4` the same way V-Slice unpacks `bonusWeek2`.
	 */
	function checkWeek():Void
	{
		weekText.offset.set(0, 0);

		if (freeplayData == null || freeplayData.levelName == null)
		{
			weekText.visible = false;
			return;
		}

		weekText.visible = true;

		var clean:String = prettifyLevelName(freeplayData.levelName);
		var key:String = weekTextKey(clean);
		createWeekTextGraphic(clean, key);
		weekText.loadGraphic(FlxG.bitmap.get(key));
	}

	static function prettifyLevelName(levelId:String):String
	{
		var out:String = '';

		for (i in 0...levelId.length)
		{
			if (i == 0)
			{
				out += levelId.charAt(i);
				continue;
			}

			var previousChar:String = levelId.charAt(i - 1);
			var currentChar:String = levelId.charAt(i);

			if (previousChar.toLowerCase() == previousChar && currentChar.toLowerCase() != currentChar) out += ' ';
			if (Std.parseInt(previousChar) == null && Std.parseInt(currentChar) != null) out += ' ';
			if (Std.parseInt(previousChar) != null && Std.parseInt(currentChar) == null) out += ' ';

			out += currentChar;
		}

		return out;
	}

	/**
	 * Cache key for a week name's rendered bitmap.
	 *
	 * The style is part of the key, not just the text. Otherwise editing the engraving in
	 * position.json would change nothing until the game was restarted, because the old
	 * bitmap would still be sitting in the cache under the same name.
	 */
	static function weekTextKey(text:String):String
	{
		var n:CapsuleNudges = nudge();
		return 'freeplayWeek:$text:${n.weekTextEngrave}:${n.weekTextEngraveColor}:${n.weekTextEngraveX}:${n.weekTextEngraveY}';
	}

	/**
	 * Renders a week name to a bitmap.
	 *
	 * Every other label on a capsule comes off a sheet, drawn by hand with a groove and a
	 * lit edge so it reads as stamped into the plastic. This one is set from a font at
	 * runtime, and a font gives you a flat fill - which is why it was the one piece of text
	 * that looked painted on rather than cut in.
	 *
	 * A shadow in a colour lighter than the capsule, offset down and right, is what puts the
	 * lit edge back: the letter reads as a groove with light catching its lower lip. The
	 * numbers are in position.json because the right ones depend on the capsule art.
	 */
	static function createWeekTextGraphic(text:String, key:String):Void
	{
		if (FlxG.bitmap.checkCache(key)) return;

		var n:CapsuleNudges = nudge();

		var weekTextBase:FlxText = new FlxText(0, 0, 0, text);
		weekTextBase.setFormat(Paths.font('YoureGone-Regular.otf'), 20, 0xFF21242E);

		if (n.weekTextEngrave)
		{
			// Through FlxColor rather than Std.parseInt: an AARRGGBB value with the alpha set
			// is past what a signed 32-bit Int holds, and parseInt has no obligation to do
			// anything sensible with that.
			var engraveColor:Null<FlxColor> = FlxColor.fromString('0x' + n.weekTextEngraveColor);

			weekTextBase.borderStyle = SHADOW;
			weekTextBase.borderColor = (engraveColor != null) ? engraveColor : 0xFF6E6A82;
			weekTextBase.borderSize = 1;
			weekTextBase.shadowOffset.set(n.weekTextEngraveX, n.weekTextEngraveY);
		}

		@:privateAccess
		weekTextBase.regenGraphic();

		FlxG.bitmap.add(weekTextBase.pixels.clone(), false, key);
		weekTextBase.destroy();
	}

	/**
	 * Narrows the title when a rank badge or a heart is sharing the capsule with it.
	 */
	public function checkClip():Void
	{
		var clipSize:Int = 290;
		var clipType:Int = 0;

		if (ranking.visible)
		{
			favIconBlurred.x = this.x + 370;
			favIcon.x = favIconBlurred.x;
			clipType += 1;
		}
		else
			favIconBlurred.x = favIcon.x = this.x + 405;

		if (favIcon.visible) clipType += 1;

		switch (clipType)
		{
			case 2: clipSize = 210;
			case 1: clipSize = 245;
			default:
		}

		songText.clipWidth = clipSize;
	}

	function updateBPM(newBPM:Int):Void
	{
		var shiftX:Float = 191;
		var tempShift:Float = 0;

		if (Math.floor(newBPM / 100) == 1) shiftX = 186;

		for (i in 0...bpmNumbers.length)
		{
			bpmNumbers[i].x = this.x + (shiftX + nudge().bpmDigitsX + (i * nudge().bpmDigitGap));

			switch (i)
			{
				case 0:
					bpmNumbers[i].digit = (newBPM < 100) ? 0 : Math.floor(newBPM / 100) % 10;

				case 1:
					if (newBPM < 10) bpmNumbers[i].digit = 0;
					else
					{
						bpmNumbers[i].digit = Math.floor(newBPM / 10) % 10;
						if (Math.floor(newBPM / 10) % 10 == 1) tempShift = -4;
					}

				case 2:
					bpmNumbers[i].digit = newBPM % 10;
					if (Math.floor(newBPM) % 10 == 1) tempShift -= 4;

				default:
			}

			bpmNumbers[i].x += tempShift;
		}
	}

	function updateDifficultyRating(newRating:Int):Void
	{
		for (i in 0...difficultyNumbers.length)
		{
			switch (i)
			{
				case 0: difficultyNumbers[i].digit = (newRating < 10) ? 0 : Math.floor(newRating / 10);
				case 1: difficultyNumbers[i].digit = newRating % 10;
				default:
			}
		}
	}

	function updateScoringRank(newRank:FreeplayRankTier):Void
	{
		if (sparkleTimer != null) sparkleTimer.cancel();
		sparkle.visible = false;

		ranking.rank = newRank;
		blurredRanking.rank = newRank;

		if (newRank == PERFECT_GOLD)
		{
			sparkleTimer = new FlxTimer().start(1, sparkleEffect);
			sparkle.visible = true;
		}
	}

	function set_hsvShader(value:HSVShader):HSVShader
	{
		this.hsvShader = value;
		capsule.shader = hsvShader;
		songText.shader = hsvShader;
		return value;
	}

	/** The squash the title does whenever the capsule shows or is picked. */
	function textAppear():Void
	{
		songText.scale.set(1.7, 0.2);

		new FlxTimer().start(1 / 24, function(_)
		{
			songText.scale.set(0.4, 1.4);
			new FlxTimer().start(2 / 24, function(_) songText.scale.set(1, 1));
		});
	}

	function setVisibleGrp(value:Bool):Void
	{
		for (spr in grpHide.members)
			if (spr != null) spr.visible = value;

		textAppear();
		updateSelected();
	}

	public function initPosition(x:Float, y:Float):Void
	{
		this.x = x;
		this.y = y;
	}

	/**
	 * The RANDOM capsule that sits above the songs.
	 *
	 * It carries no song, which `refreshDisplay` already knows how to draw - the title
	 * reads Random and everything a song would have is hidden. Everything counts from
	 * one because this is here.
	 */
	public function initRandom():Void
	{
		initPosition(FlxG.width, 0);
		initData(null, 0);
		y = intendedY(0) + 10;
		targetPos.x = x;

		// V-Slice starts this one invisible and has the DJ's hand reveal it as his intro
		// finishes. There is no DJ here yet, and an alpha of zero with nothing to undo it
		// is just a capsule that never arrives, so it comes in with the rest of them.
		favIcon.visible = false;
		favIconBlurred.visible = false;
		ranking.visible = false;
		blurredRanking.visible = false;
	}

	public function initData(data:FreeplaySongData, ?index:Null<Int>, difficulty:String = null):Void
	{
		this.freeplayData = data;
		if (index != null) this.index = index;

		if (favIcon.animation.curAnim != null) favIcon.animation.curAnim.curFrame = favIcon.animation.curAnim.numFrames - 1;
		if (favIconBlurred.animation.curAnim != null) favIconBlurred.animation.curAnim.curFrame = favIconBlurred.animation.curAnim.numFrames - 1;

		refreshDisplay(difficulty);
		checkWeek();
	}

	/** Re-reads everything the capsule shows for a difficulty: bpm, rating, rank, heart. */
	public function refreshDisplay(difficulty:String = null):Void
	{
		if (freeplayData == null)
		{
			songText.text = 'Random';
			pixelIcon.visible = false;
			ranking.visible = false;
			blurredRanking.visible = false;
			favIcon.visible = false;
			favIconBlurred.visible = false;
			newText.visible = false;
		}
		else
		{
			songText.text = freeplayData.songName;
			pixelIcon.setCharacter(freeplayData.songCharacter);
			// A difficulty the song hasn't got means the selection is passing over it on
			// its way somewhere else, so show it at its own first one rather than blank.
			var shown:String = (difficulty != null && freeplayData.hasDifficulty(difficulty)) ? difficulty : freeplayData.difficulties[0];

			updateBPM(freeplayData.getStartingBpm(shown));
			updateDifficultyRating(freeplayData.getDifficultyRating(shown));
			updateScoringRank(freeplayData.getRank(shown));
			newText.visible = freeplayData.isNew;
			favIcon.visible = freeplayData.isFav;
			favIconBlurred.visible = freeplayData.isFav;
			checkClip();
		}

		updateSelected();
	}

	// The seven frames of squash a capsule jumps in on, and where it sits during them.
	var frameInTicker:Float = 0;
	var frameInTypeBeat:Int = 0;
	var frameOutTicker:Float = 0;
	var frameOutTypeBeat:Int = 0;
	var xFrames:Array<Float> = [1.7, 1.8, 0.85, 0.85, 0.97, 0.97, 1];
	var xPosLerpLol:Array<Float> = [0, 0, 0.16, 0.16, 0.22, 0.22, 0.245];
	var xPosOutLerpLol:Array<Float> = [0.245, 0.75, 0.98, 0.98, 1.2];

	public function initJumpIn(maxTimer:Float, ?force:Bool):Void
	{
		frameInTypeBeat = 0;

		new FlxTimer().start((1 / 24) * maxTimer, function(_)
		{
			doJumpIn = true;
			doLerp = true;
		});

		if (force)
		{
			visible = true;
			capsule.alpha = 1;
			setVisibleGrp(true);
		}
		else
			new FlxTimer().start((xFrames.length / 24) * 2.5, function(_)
			{
				visible = true;
				capsule.alpha = 1;
				setVisibleGrp(true);
			});
	}

	/** Drops the capsule straight onto its resting place, skipping the jump. */
	public function forcePosition():Void
	{
		visible = true;
		capsule.alpha = 1;
		updateSelected();
		doLerp = true;
		doJumpIn = false;
		doJumpOut = false;

		frameInTypeBeat = xFrames.length;
		frameOutTypeBeat = 0;

		capsule.scale.x = xFrames[frameInTypeBeat - 1] * realScaled;
		capsule.scale.y = (1 / xFrames[frameInTypeBeat - 1]) * realScaled;

		x = targetPos.x;
		y = targetPos.y;

		setVisibleGrp(true);
	}

	override function update(elapsed:Float):Void
	{
		if (doJumpIn)
		{
			frameInTicker += elapsed;

			if (frameInTicker >= 1 / 24 && frameInTypeBeat < xFrames.length)
			{
				frameInTicker = 0;

				capsule.scale.x = xFrames[frameInTypeBeat] * realScaled;
				capsule.scale.y = (1 / xFrames[frameInTypeBeat]) * realScaled;
				targetPos.x = FlxG.width * xPosLerpLol[Std.int(Math.min(frameInTypeBeat, xPosLerpLol.length - 1))];

				frameInTypeBeat += 1;

				// Once it has flown far enough in, hand it over to the resting position.
				if (targetPos.x <= 320 + xOffset) targetPos.x = intendedX(index + 1 - curSelected) + xOffset;
			}
			else if (frameInTypeBeat == xFrames.length)
				doJumpIn = false;
		}

		if (doJumpOut)
		{
			frameOutTicker += elapsed;

			if (frameOutTicker >= 1 / 24 && frameOutTypeBeat < xFrames.length)
			{
				frameOutTicker = 0;

				capsule.scale.x = xFrames[frameOutTypeBeat] * realScaled;
				capsule.scale.y = (1 / xFrames[frameOutTypeBeat]) * realScaled;
				this.x = FlxG.width * xPosOutLerpLol[Std.int(Math.min(frameOutTypeBeat, xPosOutLerpLol.length - 1))];

				frameOutTypeBeat += 1;
			}
			else if (frameOutTypeBeat == xFrames.length)
				doJumpOut = false;
		}

		if (doLerp)
		{
			x = FreeplayMath.smoothLerp(x, targetPos.x, elapsed, 0.256);
			y = FreeplayMath.smoothLerp(y, targetPos.y, elapsed, 0.192);
		}

		super.update(elapsed);
	}

	/** Plays whatever this capsule does when its song is picked. */
	public function confirm():Void
	{
		if (songText != null)
		{
			textAppear();
			songText.flickerText();
		}

		if (pixelIcon != null && pixelIcon.hasLosingFace) pixelIcon.animation.play('losing');
	}

	public function intendedX(index:Float):Float
		return 270 + (60 * FlxMath.fastSin(index));

	public function intendedY(index:Float):Float
		return (index * ((capsule.height * realScaled) + 10)) + 120;

	function set_selected(value:Bool):Bool
	{
		final wasSelected:Bool = selected;

		selected = value;
		if (wasSelected != selected) updateSelected();

		return selected;
	}

	function set_forceHighlight(value:Bool):Bool
	{
		forceHighlight = value;
		updateSelected();
		return forceHighlight;
	}

	public function updateSelected():Void
	{
		final isSelected:Bool = (this.selected || this.forceHighlight);

		// The capsule art carries its own greyed-out version - "NOT SELECTED" on the
		// sheet - so nothing here has to drain the colour out of it.
		songText.alpha = isSelected ? 1 : 0.6;
		songText.blurredText.visible = isSelected;
		capsule.offset.x = isSelected ? 0 : -5;
		capsule.animation.play(isSelected ? 'selected' : 'unselected');
		ranking.alpha = isSelected ? 1 : 0.7;
		blurredRanking.alpha = isSelected ? 1 : 0;
		favIcon.alpha = isSelected ? 1 : 0.6;
		favIconBlurred.alpha = isSelected ? 1 : 0;
		ranking.color = isSelected ? 0xFFFFFFFF : 0xFFAAAAAA;

		if (songText.tooLong) songText.resetText();
		if (selected && songText.tooLong) songText.initMove();
	}

	override public function kill():Void
	{
		super.kill();

		visible = true;
		capsule.alpha = 1;
		doLerp = false;
		doJumpIn = false;
		doJumpOut = false;
	}

	override function destroy():Void
	{
		if (sparkleTimer != null) sparkleTimer.cancel();
		super.destroy();
	}
}

/** The rank badge that sits on the right of a capsule. */
class FreeplayRank extends FlxSprite
{
	public var rank(default, set):FreeplayRankTier = NONE;

	public function new(x:Float, y:Float)
	{
		super(x, y);

		frames = Paths.getSparrowAtlas('freeplay/rankbadges');

		animation.addByPrefix('PERFECT', 'PERFECT rank0', 24, false);
		animation.addByPrefix('EXCELLENT', 'EXCELLENT rank0', 24, false);
		animation.addByPrefix('GOOD', 'GOOD rank0', 24, false);
		animation.addByPrefix('PERFECTSICK', 'PERFECT rank GOLD', 24, false);
		animation.addByPrefix('GREAT', 'GREAT rank0', 24, false);
		animation.addByPrefix('LOSS', 'LOSS rank0', 24, false);

		blend = BlendMode.ADD;
		antialiasing = ClientPrefs.data.antialiasing;

		this.rank = NONE;

		scale.set(0.9, 0.9);
		updateHitbox();
	}

	function set_rank(val:FreeplayRankTier):FreeplayRankTier
	{
		rank = val;

		if (val == null || !val.exists())
			this.visible = false;
		else
		{
			this.visible = true;

			// Straight to the end of it. The rank is re-assigned every time the selection
			// moves, so playing from frame zero meant the badge flickering through its
			// flourish on every song you scrolled past. V-Slice's badges sit still too;
			// the animation is for a rank being newly earned, which is not this.
			animation.play(val, true, false);
			if (animation.curAnim != null) animation.curAnim.finish();
			centerOffsets(false);

			// V-Slice nudges two of the badges up; the rest sit centred.
			switch (val)
			{
				case GOOD, GREAT: offset.y -= 8;
				default:
			}

			updateHitbox();
		}

		return rank;
	}
}

/** One digit of the capsule's bpm or difficulty rating. */
class CapsuleNumber extends FlxSprite
{
	public var digit(default, set):Int = 0;

	static final numToString:Array<String> = ['ZERO', 'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT', 'NINE'];

	public function new(x:Float, y:Float, big:Bool = false, ?initDigit:Int = 0)
	{
		super(x, y);

		frames = Paths.getSparrowAtlas(big ? 'freeplay/freeplayCapsule/bignumbers' : 'freeplay/freeplayCapsule/smallnumbers');

		for (i in 0...10)
			animation.addByPrefix(numToString[i], numToString[i], 24, false);

		antialiasing = ClientPrefs.data.antialiasing;

		this.digit = initDigit;
		animation.play(numToString[initDigit], true);

		setGraphicSize(Std.int(width * 0.9));
		updateHitbox();
	}

	function set_digit(val:Int):Int
	{
		if (val < 0 || val > 9) val = 0;

		animation.play(numToString[val], true, false, 0);
		centerOffsets(false);

		switch (val)
		{
			case 1: offset.x -= 4;
			case 3: offset.x -= 1;
			default:
		}

		return digit = val;
	}
}

/**
 * The little character icon on a capsule.
 *
 * V-Slice has a pixel icon per character, and those ship with the rest of this art, so
 * they are used when one matches. Psych songs name a health icon instead, and mods
 * bring their own, so anything without a pixel version falls back to the health icon
 * the song already declares - which is why a mod's songs get their own faces here
 * without the mod doing anything.
 */
class FreeplayIcon extends FlxSprite
{
	public var char(default, null):String = '';

	/** Whether this fell back to a health icon that has a losing face to show on confirm. */
	public var hasLosingFace(default, null):Bool = false;

	/**
	 * How far left of its own position the icon is drawn.
	 *
	 * V-Slice gets this by scaling 2x about an origin 100 pixels off the side of the
	 * sprite. Same number, arrived at by shifting what it draws instead, which is the
	 * one thing a sprite group leaves alone.
	 */
	static inline var LEFT_SHIFT:Float = 100;

	/** The size V-Slice's own pixel icons are drawn at: a 50x50 frame at 2x. */
	static inline var PIXEL_SIZE:Float = 50;

	public function new(x:Float, y:Float)
	{
		super(x, y);

		makeGraphic(Std.int(PIXEL_SIZE), Std.int(PIXEL_SIZE), 0x00000000);
		active = false;
	}

	public function setCharacter(char:String):Void
	{
		if (this.char == char) return;

		this.char = char;
		hasLosingFace = false;

		if (char == null || char.length < 1)
		{
			visible = false;
			return;
		}

		if (loadPixelIcon(char) || loadHealthIcon(char))
		{
			visible = true;
			return;
		}

		visible = false;
	}

	/** V-Slice's own icons. Names can be hyphenated, longest match wins, like V-Slice. */
	function loadPixelIcon(char:String):Bool
	{
		final parts:Array<String> = char.split('-');
		var attempt:String = '';
		var best:String = null;

		for (i in 0...parts.length)
		{
			attempt += parts[i];
			if (Paths.fileExists('images/freeplay/icons/${attempt}pixel.png', IMAGE)) best = attempt;
			if (i < parts.length - 1) attempt += '-';
		}

		if (best == null) return false;

		final key:String = 'freeplay/icons/${best}pixel';

		if (Paths.fileExists('images/$key.xml', TEXT)) frames = Paths.getSparrowAtlas(key);
		else loadGraphic(Paths.image(key));

		antialiasing = false;

		// Twice the size it was drawn at, and no more clever than that. Fitting them to
		// a box instead was the mistake: these frames are 36x32 for pico and 40x28 for
		// tankman against 50x50 for boyfriend, so a box blew the small ones up to sizes
		// their art was never meant to be seen at.
		place(2, frameHeight * 0.5);
		return true;
	}

	/** Psych's health icons, the ones a song already names and a mod already ships. */
	function loadHealthIcon(char:String):Bool
	{
		var key:String = 'icons/$char';
		if (!Paths.fileExists('images/$key.png', IMAGE)) key = 'icons/icon-$char';
		if (!Paths.fileExists('images/$key.png', IMAGE)) return false;

		var graphic = Paths.image(key);
		if (graphic == null) return false;

		// Health icons are a strip of square faces; the first one is the happy face.
		var size:Int = graphic.height;
		var frameCount:Int = Math.round(graphic.width / size);
		loadGraphic(graphic, frameCount > 1, size, size);
		animation.add('icon', [0], 0, false);

		// Psych's second face is the losing one. V-Slice's own pixel icons have a confirm
		// animation to play when a song is picked; a health icon has no such thing, but it
		// does have this, and a character pulling a face as you pick their song is closer to
		// what that moment is for than the icon just sitting there.
		if (frameCount > 1) animation.add('losing', [1], 0, false);
		hasLosingFace = frameCount > 1;

		animation.play('icon');

		antialiasing = ClientPrefs.data.antialiasing;

		// Sized and placed to sit where boyfriend's pixel icon does, since a health icon
		// is a 150px square and has no business being drawn at twice that.
		place((PIXEL_SIZE * 2) / frameHeight, PIXEL_SIZE * 0.5);
		return true;
	}

	/**
	 * Scales the icon and shifts where it draws, without touching where it is.
	 *
	 * Moving the sprite is what must not happen: a sprite group owns its children's
	 * coordinates - it adds its own position to theirs as they go in, and moves them by
	 * deltas afterwards - so an absolute position tears the icon out of the capsule.
	 * The offset is the sprite's own, and the group never touches it.
	 *
	 * `updateHitbox` after the scale is what makes a sprite draw from `x, y` at the size
	 * it now is; the offsets then take it from there to where V-Slice puts it.
	 *
	 * @param up   How much bigger than its frame to draw it.
	 * @param lift How far above its own position the top of it should sit.
	 */
	function place(up:Float, lift:Float):Void
	{
		scale.set(up, up);
		updateHitbox();

		offset.x += LEFT_SHIFT;
		offset.y += lift;
	}
}

/** The one bit of `MathUtil` V-Slice's freeplay leans on. */
class FreeplayMath
{
	/**
	 * V-Slice's `smoothLerpPrecision`: a lerp that lands in the same place whatever the
	 * framerate.
	 *
	 * `duration` is how long it takes to close all but `precision` of the gap - a
	 * hundredth of it, by default - so the same call at 30fps and at 144fps arrives
	 * together. A plain `lerp(a, b, elapsed * k)` does not: it moves further per second
	 * the more frames there are, which is why V-Slice's capsules would scroll at a
	 * different speed on a phone than on a desktop.
	 */
	public static function smoothLerp(base:Float, target:Float, deltaTime:Float, duration:Float, precision:Float = 1 / 100):Float
	{
		if (deltaTime == 0) return base;
		if (base == target) return target;

		return FlxMath.lerp(target, base, Math.pow(precision, deltaTime / duration));
	}
}

/** What `images/freeplay/freeplayCapsule/position.json` is allowed to move. */
typedef CapsuleNudges =
{
	var antialiasText:Bool;
	var songTextX:Float;
	var songTextY:Float;
	var weekTextX:Float;
	var weekTextY:Float;
	var weekTextScale:Float;
	var weekTextEngrave:Bool;
	var weekTextEngraveColor:String;
	var weekTextEngraveX:Float;
	var weekTextEngraveY:Float;
	var bpmTextX:Float;
	var bpmTextY:Float;
	var bpmTextScale:Float;
	var bpmDigitsX:Float;
	var bpmDigitsY:Float;
	var bpmDigitGap:Float;
	var difficultyTextX:Float;
	var difficultyTextY:Float;
	var difficultyTextScale:Float;
	var difficultyDigitsX:Float;
	var difficultyDigitsY:Float;
	var difficultyDigitGap:Float;
	var newTextX:Float;
	var newTextY:Float;
	var newTextScale:Float;
	var rankX:Float;
	var rankY:Float;
	var iconX:Float;
	var iconY:Float;
}

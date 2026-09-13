package states.freeplay;

import flixel.FlxObject;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxPoint;
import flxanimate.PsychFlxAnimate;

using StringTools;

/**
 * The row of letters above the songs, which filters the list.
 *
 * Ported from V-Slice. The letters are one Adobe Animate atlas with a symbol per group,
 * and the whole row shuffles sideways on a handful of one-frame timers rather than a
 * tween - which is why the offsets below look like someone counted them off an
 * animation, because that is exactly what they are.
 *
 * V-Slice drives this with its own Q and E bindings. Psych has no such controls, so it
 * is Q and E on a keyboard and a tap on any letter but the middle one on a phone, which
 * is what V-Slice's touch handling does too.
 */
class LetterSort extends FlxSpriteGroup
{
	public var letters:Array<FreeplayLetter> = [];
	public var letterHitboxes:Array<FlxObject> = [];

	// starts at 2, cuz that's the middle letter on start (accounting for fav and #, it should begin at ALL filter)
	var curSelection:Int = 2;

	public var changeSelectionCallback:String->Void;

	/** The camera the row is drawn on, so a tap can be tested against the same one. */
	public var inputCamera:FlxCamera;

	var leftArrow:FlxSprite;
	var rightArrow:FlxSprite;
	var grpSeperators:FlxSpriteGroup;

	public function new(x:Float, y:Float)
	{
		super(x, y);

		grpSeperators = new FlxSpriteGroup();
		add(grpSeperators);

		leftArrow = new FlxSprite(-20, 15).loadGraphic(Paths.image('freeplay/miniArrow'));
		leftArrow.antialiasing = ClientPrefs.data.antialiasing;
		leftArrow.flipX = true;
		add(leftArrow);

		rightArrow = new FlxSprite(380, 15).loadGraphic(Paths.image('freeplay/miniArrow'));
		rightArrow.antialiasing = ClientPrefs.data.antialiasing;
		add(rightArrow);

		for (i in 0...5)
		{
			var letter:FreeplayLetter = new FreeplayLetter(i * 80, 0, i, curSelection);
			letter.x += 50;
			letter.y += 50;
			add(letter);

			var letterHitbox:FlxObject = new FlxObject(letter.x - 50, letter.y - 50, 50, 50);
			letterHitbox.active = false;
			letterHitboxes.push(letterHitbox);

			letters.push(letter);

			if (i != 2) letter.scale.x = letter.scale.y = 0.8;

			var darkness:Float = Math.max(Math.abs(i - 2) / 6, 0.01);

			letter.color = letter.color.getDarkened(darkness);

			// don't put the last seperator
			if (i == 4) continue;

			var sep:FlxSprite = new FlxSprite((i * 80) + 60, 20).loadGraphic(Paths.image('freeplay/seperator'));
			sep.antialiasing = ClientPrefs.data.antialiasing;
			sep.color = letter.color.getDarkened(darkness);
			grpSeperators.add(sep);
		}

		changeSelection(0);
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (FlxG.keys.justPressed.Q) changeSelection(-1);
		if (FlxG.keys.justPressed.E) changeSelection(1);

		handleTap();
	}

	/**
	 * A tap on a letter either side of the middle moves the row that way.
	 *
	 * The outer two count double, so the letter you tapped is the one you land on -
	 * V-Slice's `selectionChanges`, and the second `changeSelection` it does for them.
	 */
	function handleTap():Void
	{
		if (!tapped()) return;

		final selectionChanges:Array<Int> = [-1, -1, 0, 1, 1];

		for (index => hitbox in letterHitboxes)
		{
			if (!tappedOn(hitbox)) continue;

			var changeValue:Int = selectionChanges[index];
			if (changeValue == 0) break;

			changeSelection(changeValue);
			if (index == 0 || index == 4) changeSelection(changeValue, false);

			break;
		}
	}

	function tapped():Bool
	{
		#if mobile
		for (touch in FlxG.touches.list)
			if (touch.justPressed) return true;

		return false;
		#else
		return FlxG.mouse.justPressed;
		#end
	}

	/** Whether the tap that just happened landed inside one of the row's hitboxes. */
	function tappedOn(hitbox:FlxObject):Bool
	{
		// The hitboxes are laid out in the row's own space, so the row's position has to
		// be added back on before anything is compared against a finger.
		var box:FlxObject = hitbox;
		var point:FlxPoint = FlxPoint.get(box.x + x, box.y + y);

		var hit:Bool = false;

		#if mobile
		for (touch in FlxG.touches.list)
		{
			if (!touch.justPressed) continue;

			var world:FlxPoint = touch.getWorldPosition(inputCamera);
			hit = (world.x >= point.x && world.x < point.x + box.width && world.y >= point.y && world.y < point.y + box.height);
			world.put();

			if (hit) break;
		}
		#else
		var world:FlxPoint = FlxG.mouse.getWorldPosition(inputCamera);
		hit = (world.x >= point.x && world.x < point.x + box.width && world.y >= point.y && world.y < point.y + box.height);
		world.put();
		#end

		point.put();
		return hit;
	}

	public function changeSelection(diff:Int = 0, playSound:Bool = true):Void
	{
		doLetterChangeAnims(diff);

		var multiPosOrNeg:Float = diff > 0 ? 1 : -1;

		// if we're moving left (diff < 0), we want control of the right arrow, and vice versa
		var arrowToMove:FlxSprite = diff < 0 ? leftArrow : rightArrow;
		arrowToMove.offset.x = 3 * multiPosOrNeg;

		new FlxTimer().start(2 / 24, function(_) arrowToMove.offset.x = 0);

		if (playSound && diff != 0) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	/**
	 * Buncho timers and stuff to move the letters and separators
	 * Separated out so we can call it again on letters with songs within them
	 * @param diff
	 */
	function doLetterChangeAnims(diff:Int):Void
	{
		var ezTimer = function(frameNum:Int, spr:FlxSprite, offsetNum:Float)
		{
			new FlxTimer().start(frameNum / 24, function(_) spr.offset.x = offsetNum);
		};

		var positions:Array<Float> = [-10, -22, 2, 0];

		// if we're moving left, we want to move the positions the same amount, but negative direciton
		var multiPosOrNeg:Float = diff > 0 ? 1 : -1;

		for (sep in grpSeperators.members)
		{
			ezTimer(0, sep, positions[0] * multiPosOrNeg);
			ezTimer(1, sep, positions[1] * multiPosOrNeg);
			ezTimer(2, sep, positions[2] * multiPosOrNeg);
			ezTimer(3, sep, positions[3] * multiPosOrNeg);
		}

		for (index => letter in letters)
		{
			letter.offset.x = positions[0] * multiPosOrNeg;

			new FlxTimer().start(1 / 24, function(_)
			{
				letter.offset.x = positions[1] * multiPosOrNeg;
				if (index == 0) letter.visible = false;
			});

			new FlxTimer().start(2 / 24, function(_)
			{
				letter.offset.x = positions[2] * multiPosOrNeg;
				if (index == 0) letter.visible = true;
			});

			if (index == 2)
			{
				ezTimer(3, letter, 0);
				continue;
			}

			ezTimer(3, letter, positions[3] * multiPosOrNeg);
		}

		curSelection += diff;
		if (curSelection < 0) curSelection = letters[0].regexLetters.length - 1;
		if (curSelection >= letters[0].regexLetters.length) curSelection = 0;

		for (letter in letters)
			letter.changeLetter(diff, curSelection);

		if (changeSelectionCallback != null) changeSelectionCallback(letters[2].regexLetters[letters[2].curLetter]); // bullshit and long lol!
	}
}

/**
 * The actual sprite for the letters, with their animation code stuff and regex stuff
 */
class FreeplayLetter extends PsychFlxAnimate
{
	/**
	 * A preformatted array of letter strings, for use when doing regex
	 * ex: ['A-B', 'C-D', 'E-H', 'I-L' ...]
	 */
	public var regexLetters:Array<String> = [];

	/**
	 * A preformatted array of the letters, for use when accessing symbol animation info
	 * ex: ['AB', 'CD', 'EH', 'IL' ...]
	 */
	public var animLetters:Array<String> = [];

	/**
	 * The current letter in the regexLetters array this FreeplayLetter is on
	 */
	public var curLetter:Int = 0;

	public function new(x:Float, y:Float, ?letterInd:Null<Int>, curSelected:Int = 0)
	{
		super(x, y);

		try
		{
			Paths.loadAnimateAtlas(this, 'freeplay/sortedLetters');
		}
		catch (e:Dynamic)
		{
			trace('FreeplayLetter: could not load the letters atlas ($e)');
			return;
		}

		antialiasing = ClientPrefs.data.antialiasing;

		// this is used for the regex
		// /^[OR].*/gi doesn't work for showing the song Pico, so now it's
		// /^[O-R].*/gi ant it works for displaying Pico
		// we split by underscores, simply for nice lil convinience
		var alphabet:String = 'A-B_C-D_E-H_I-L_M-N_O-R_S_T_U-Z';
		regexLetters = alphabet.split('_');
		regexLetters.insert(0, 'ALL');
		regexLetters.insert(0, 'fav');
		regexLetters.insert(0, '#');

		// the symbols from flash don't have dashes, so we clean this up for use with animations
		animLetters = regexLetters.map(animLetter -> animLetter.replace('-', ''));

		if (letterInd != null)
		{
			this.anim.play(animLetters[letterInd] + ' move', true);
			curLetter = letterInd;

			if (curSelected != curLetter) this.anim.pause();

			this.anim.onComplete.add(function() this.anim.play(animLetters[curLetter] + ' move', true));
		}
	}

	/**
	 * Changes the letter graphic/anim, used in the LetterSort class above
	 * @param diff -1 or 1, to go left or right in the animation array
	 * @param curSelection what the current letter selection is, to play the bouncing anim if it matches the current letter
	 */
	public function changeLetter(diff:Int = 0, ?curSelection:Null<Int>):Void
	{
		curLetter += diff;

		if (curLetter < 0) curLetter = regexLetters.length - 1;
		if (curLetter >= regexLetters.length) curLetter = 0;

		if (anim == null) return;

		this.anim.play(animLetters[curLetter] + ' move', true);
		if (curSelection != curLetter) this.anim.pause();
	}

	/**
	 * Offset the letter.
	 */
	override function getScreenPosition(?result:FlxPoint, ?camera:FlxCamera):FlxPoint
	{
		var output:FlxPoint = super.getScreenPosition(result, camera);
		output.x -= 50;
		output.y -= 60;
		return output;
	}
}

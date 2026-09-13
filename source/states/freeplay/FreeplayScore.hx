package states.freeplay;

import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;

/**
 * The seven digit score in the top right of the freeplay menu.
 *
 * Ported from V-Slice. Each digit is its own sprite playing a frame out of the digital
 * numbers sheet, so setting a score is a matter of walking the number backwards and
 * handing each place to the sprite that draws it.
 */
class FreeplayScore extends FlxTypedSpriteGroup<ScoreNum>
{
	public var scoreShit(default, set):Int = 0;

	public function new(x:Float, y:Float, digitCount:Int, scoreShit:Int = 100)
	{
		super(0, y);

		for (i in 0...digitCount)
			add(new ScoreNum(x + (45 * i), y, 0));

		this.scoreShit = scoreShit;
	}

	function set_scoreShit(val:Int):Int
	{
		if (group == null || group.members == null) return val;

		var dumbNumb:Int = val;
		dumbNumb = Std.int(Math.min(dumbNumb, Math.pow(10, group.members.length) - 1));

		var loopNum:Int = group.members.length - 1;

		while (dumbNumb > 0)
		{
			group.members[loopNum].digit = dumbNumb % 10;
			dumbNumb = Math.floor(dumbNumb / 10);
			loopNum--;
		}

		while (loopNum >= 0)
		{
			group.members[loopNum].digit = 0;
			loopNum--;
		}

		return scoreShit = val;
	}

	public function updateScore(scoreNew:Int):Void
		scoreShit = scoreNew;
}

/** One digit of the score. */
class ScoreNum extends FlxSprite
{
	public var digit(default, set):Int = 0;

	static final numToString:Array<String> = ['ZERO', 'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT', 'NINE'];

	public function new(x:Float, y:Float, ?initDigit:Int = 0)
	{
		super(x, y);

		frames = Paths.getSparrowAtlas('digital_numbers');

		for (i in 0...10)
			animation.addByPrefix(numToString[i], '${numToString[i]} DIGITAL', 24, false);

		antialiasing = ClientPrefs.data.antialiasing;

		this.digit = initDigit;
		animation.play(numToString[digit], true);

		setGraphicSize(Std.int(width * 0.4));
		updateHitbox();
	}

	function set_digit(val:Int):Int
	{
		if (val < 0 || val > 9) val = 0;

		if (animation.curAnim == null || animation.curAnim.name != numToString[val])
		{
			animation.play(numToString[val], true, false, 0);
			updateHitbox();

			switch (val)
			{
				case 1: offset.x -= 15;
				default: centerOffsets(false);
			}
		}

		return digit = val;
	}
}

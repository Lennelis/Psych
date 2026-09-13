package states.freeplay;

import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.util.FlxSort;

/**
 * A line of text that scrolls sideways forever, like an html marquee.
 *
 * One `FlxText` drawn several times over, rather than several texts: the positions are
 * kept in a list, and `draw` walks it, moving the same sprite and drawing it again at
 * each one. A copy that runs off the end is moved behind the last one, so the line
 * never runs out.
 *
 * Ported from V-Slice, unchanged apart from the parts of `FlxText` Psych's Flixel
 * spells differently.
 */
class BGScrollingText extends FlxText
{
	var _textPositions:Array<FlxPoint> = [];
	var _positionCache:FlxPoint = FlxPoint.get();

	public var widthShit:Float = FlxG.width;
	public var placementOffset:Float = 20;
	public var speed:Float = 1;

	public function new(x:Float, y:Float, text:String, widthShit:Float = 100, ?bold:Bool = false, ?size:Int = 48)
	{
		super(x, y, 0, text, size);

		_positionCache = FlxPoint.get(x, y);
		font = Paths.font('5by7.ttf');
		this.bold = (bold == true);
		this.widthShit = widthShit;

		@:privateAccess
		regenGraphic();

		rebuildPositions();
	}

	public function updateText(newText:String):Void
	{
		this.text = newText;

		@:privateAccess
		regenGraphic();

		rebuildPositions();
	}

	function rebuildPositions():Void
	{
		var needed:Int = Math.ceil(widthShit / Math.max(1, frameWidth)) + 1;

		_textPositions.resize(0);

		for (i in 0...needed)
			_textPositions.push(FlxPoint.get((i * frameWidth) + (i * 20), 0));
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		for (txtPosition in _textPositions)
		{
			if (txtPosition == null) continue;

			txtPosition.x -= 1 * (speed * (elapsed / (1 / 60)));

			if (speed > 0) // going left
			{
				if (txtPosition.x < -frameWidth)
				{
					txtPosition.x = _textPositions[_textPositions.length - 1].x + frameWidth + placementOffset;
					sortTextShit();
				}
			}
			else // going right
			{
				if (txtPosition.x > frameWidth * 2)
				{
					txtPosition.x = _textPositions[0].x - frameWidth - placementOffset;
					sortTextShit();
				}
			}
		}
	}

	override public function draw():Void
	{
		_positionCache.set(x, y);

		for (position in _textPositions)
		{
			setPosition(_positionCache.x + position.x, _positionCache.y + position.y);
			super.draw();
		}

		setPosition(_positionCache.x, _positionCache.y);
	}

	function sortTextShit():Void
	{
		_textPositions.sort(function(a:FlxPoint, b:FlxPoint) return FlxSort.byValues(FlxSort.ASCENDING, a.x, b.x));
	}
}

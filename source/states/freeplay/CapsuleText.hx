package states.freeplay;

import flixel.group.FlxSpriteGroup;
import flixel.math.FlxRect;
import flixel.text.FlxText;
import openfl.display.BlendMode;
import openfl.filters.BitmapFilterQuality;
import openfl.filters.GlowFilter;
import shaders.freeplay.GaussianBlurShader;

/**
 * The song title on a capsule.
 *
 * Two copies of the same text: a blurred one underneath for the glow, and a sharp one
 * on top carrying a glow filter as well. A title too long for the capsule is clipped
 * and then slid back and forth so the rest can be read.
 *
 * Ported from V-Slice.
 */
class CapsuleText extends FlxSpriteGroup
{
	public var blurredText:FlxText;

	var whiteText:FlxText;

	public var text(default, set):String;
	public var clipWidth(default, set):Int = 255;
	public var tooLong:Bool = false;

	var glowColor:FlxColor = 0xFF00ccff;

	public function new(x:Float, y:Float, songTitle:String, size:Float)
	{
		super(x, y);

		blurredText = initText(songTitle, size);
		blurredText.shader = new GaussianBlurShader(1);
		whiteText = initText(songTitle, size);
		text = songTitle;

		blurredText.color = glowColor;
		whiteText.color = 0xFFFFFFFF;
		add(blurredText);
		add(whiteText);
	}

	static function initText(songTitle:String, size:Float):FlxText
	{
		var text:FlxText = new FlxText(0, 0, 0, songTitle, Std.int(size));
		text.font = Paths.font('5by7.ttf');
		return text;
	}

	function set_clipWidth(value:Int):Int
	{
		resetText();
		checkClipWidth(value);
		return clipWidth = value;
	}

	/** Clips the text when it is wider than the room the capsule has for it. */
	function checkClipWidth(?wid:Null<Int>):Void
	{
		if (wid == null) wid = clipWidth;
		if (whiteText == null || blurredText == null) return;

		if (whiteText.width > wid)
		{
			tooLong = true;

			blurredText.clipRect = new FlxRect(0, 0, wid, blurredText.height);
			whiteText.clipRect = new FlxRect(0, 0, wid, whiteText.height);
		}
		else
		{
			tooLong = false;

			blurredText.clipRect = null;
			whiteText.clipRect = null;
		}
	}

	function set_text(value:String):String
	{
		if (value == null) return value;
		if (blurredText == null || whiteText == null) return text = value;

		blurredText.text = value;
		whiteText.text = value;
		checkClipWidth();
		applyGlow(glowColor);

		return text = value;
	}

	function applyGlow(color:FlxColor):Void
		whiteText.textField.filters = [new GlowFilter(color, 1, 5, 5, 210, BitmapFilterQuality.MEDIUM)];

	var moveTimer:FlxTimer = new FlxTimer();
	var moveTween:FlxTween;

	public function initMove():Void
		moveTimer.start(0.6, function(_) moveTextRight());

	function moveTextRight():Void
	{
		var distToMove:Float = whiteText.width - clipWidth;
		moveTween = FlxTween.tween(whiteText.offset, {x: distToMove}, 2, {
			onUpdate: function(_) reclip(),
			onComplete: function(_) moveTimer.start(0.3, function(_) moveTextLeft()),
			ease: FlxEase.sineInOut
		});
	}

	function moveTextLeft():Void
	{
		moveTween = FlxTween.tween(whiteText.offset, {x: 0}, 2, {
			onUpdate: function(_) reclip(),
			onComplete: function(_) moveTimer.start(0.3, function(_) moveTextRight()),
			ease: FlxEase.sineInOut
		});
	}

	function reclip():Void
	{
		whiteText.clipRect = new FlxRect(whiteText.offset.x, 0, clipWidth, whiteText.height);
		blurredText.offset.copyFrom(whiteText.offset);
		blurredText.clipRect = new FlxRect(whiteText.offset.x, 0, clipWidth, blurredText.height);
	}

	public function resetText():Void
	{
		scale.set(1, 1);

		if (moveTween != null) moveTween.cancel();
		if (moveTimer != null) moveTimer.cancel();

		whiteText.offset.x = 0;
		reclip();
	}

	var flickerState:Bool = false;
	var flickerTimer:FlxTimer;

	/** The white flicker the title does when its song is picked. */
	public function flickerText():Void
	{
		resetText();
		flickerTimer = new FlxTimer().start(1 / 24, flickerProgress, 19);
	}

	function flickerProgress(timer:FlxTimer):Void
	{
		if (flickerState)
		{
			whiteText.blend = BlendMode.ADD;
			blurredText.blend = BlendMode.ADD;
			blurredText.color = 0xFFFFFFFF;
			whiteText.color = 0xFFFFFFFF;
			applyGlow(0xFFFFFFFF);
		}
		else
		{
			blurredText.color = glowColor;
			whiteText.color = 0xFFDDDDDD;
			applyGlow(0xFFDDDDDD);
		}

		flickerState = !flickerState;
	}

	override function destroy():Void
	{
		if (moveTween != null) moveTween.cancel();
		if (moveTimer != null) moveTimer.cancel();
		if (flickerTimer != null) flickerTimer.cancel();
		super.destroy();
	}
}

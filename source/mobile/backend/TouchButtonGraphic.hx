package mobile.backend;

import flixel.graphics.FlxGraphic;
import flixel.util.FlxColor;
import openfl.display.BitmapData;
import openfl.display.DisplayObject;
import openfl.display.Graphics;
import openfl.display.GradientType;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.geom.Matrix;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;

/**
 * Draws every graphic the touch controls need, at runtime.
 *
 * Doing it this way means the mobile port doesn't add a single PNG to `assets`,
 * so mods, mod folders and `Paths` keep behaving exactly like they did before,
 * and the buttons stay sharp no matter what resolution the phone reports.
 */
class TouchButtonGraphic
{
	static var cache:Map<String, FlxGraphic> = new Map<String, FlxGraphic>();

	/**
	 * A rounded square button with a symbol drawn in the middle.
	 * @param symbol 'up', 'down', 'left' and 'right' are drawn as arrows, anything else is drawn as text.
	 */
	public static function button(symbol:String, width:Int, height:Int, color:FlxColor = FlxColor.WHITE):FlxGraphic
	{
		final key:String = 'touchButton:$symbol:${width}x$height:${color.toHexString()}';
		final cached:FlxGraphic = getCached(key);
		if (cached != null) return cached;

		final container:Sprite = new Sprite();
		final shape:Shape = new Shape();
		final line:Float = Math.max(2, Math.min(width, height) * 0.045);
		final radius:Float = Math.min(width, height) * 0.32;

		shape.graphics.lineStyle(line, color, 1);
		shape.graphics.beginFill(color, 0.25);
		shape.graphics.drawRoundRect(line * 0.5, line * 0.5, width - line, height - line, radius, radius);
		shape.graphics.endFill();
		drawSymbol(shape.graphics, symbol, width, height, color);
		container.addChild(shape);

		if (!isArrow(symbol)) container.addChild(makeLabel(symbol, width, height, color));

		return store(key, container, width, height);
	}

	/**
	 * One of the four columns the player taps during gameplay.
	 * @param gradient when true the lane fades out towards the top of the screen instead of being a flat block.
	 */
	public static function lane(width:Int, height:Int, color:FlxColor, gradient:Bool = true):FlxGraphic
	{
		final key:String = 'touchLane:${width}x$height:${color.toHexString()}:$gradient';
		final cached:FlxGraphic = getCached(key);
		if (cached != null) return cached;

		final shape:Shape = new Shape();
		final rgb:Int = color;

		if (gradient)
		{
			final box:Matrix = new Matrix();
			box.createGradientBox(width, height, Math.PI * 0.5);
			shape.graphics.beginGradientFill(GradientType.LINEAR, [rgb, rgb], [0, 1], [0, 255], box);
		}
		else
			shape.graphics.beginFill(rgb, 1);

		shape.graphics.drawRect(0, 0, width, height);
		shape.graphics.endFill();

		// side lines, so the four lanes still read as separate columns when the fill is faint
		final edge:Float = Math.max(2, width * 0.008);
		shape.graphics.beginFill(FlxColor.WHITE, 0.4);
		shape.graphics.drawRect(0, 0, edge, height);
		shape.graphics.drawRect(width - edge, 0, edge, height);
		shape.graphics.endFill();

		return store(key, shape, width, height);
	}

	static inline function isArrow(symbol:String):Bool
		return symbol == 'up' || symbol == 'down' || symbol == 'left' || symbol == 'right';

	static function drawSymbol(graphics:Graphics, symbol:String, width:Float, height:Float, color:FlxColor):Void
	{
		if (!isArrow(symbol)) return;

		final centerX:Float = width * 0.5;
		final centerY:Float = height * 0.5;
		final size:Float = Math.min(width, height) * 0.22;
		final back:Float = size * 0.75;

		graphics.lineStyle(); // the rounded rect above set a stroke, the arrow shouldn't inherit it
		graphics.beginFill(color, 0.9);
		switch (symbol)
		{
			case 'up':
				graphics.moveTo(centerX, centerY - size);
				graphics.lineTo(centerX + size, centerY + back);
				graphics.lineTo(centerX - size, centerY + back);
			case 'down':
				graphics.moveTo(centerX, centerY + size);
				graphics.lineTo(centerX + size, centerY - back);
				graphics.lineTo(centerX - size, centerY - back);
			case 'left':
				graphics.moveTo(centerX - size, centerY);
				graphics.lineTo(centerX + back, centerY - size);
				graphics.lineTo(centerX + back, centerY + size);
			case 'right':
				graphics.moveTo(centerX + size, centerY);
				graphics.lineTo(centerX - back, centerY - size);
				graphics.lineTo(centerX - back, centerY + size);
		}
		graphics.endFill();
	}

	static function makeLabel(symbol:String, width:Int, height:Int, color:FlxColor):TextField
	{
		final field:TextField = new TextField();
		field.defaultTextFormat = new TextFormat('_sans', Std.int(Math.max(12, height * 0.4)), color, true);
		field.autoSize = TextFieldAutoSize.LEFT;
		field.selectable = false;
		field.mouseEnabled = false;
		field.text = symbol.toUpperCase();
		field.x = (width - field.width) * 0.5;
		field.y = (height - field.height) * 0.5;
		return field;
	}

	static function getCached(key:String):FlxGraphic
	{
		final graphic:FlxGraphic = cache.get(key);
		if (graphic == null) return null;
		if (graphic.bitmap == null || graphic.bitmap.readable == false)
		{
			cache.remove(key);
			return null;
		}
		return graphic;
	}

	static function store(key:String, source:DisplayObject, width:Int, height:Int):FlxGraphic
	{
		final bitmap:BitmapData = new BitmapData(width, height, true, FlxColor.TRANSPARENT);
		bitmap.draw(source);

		final graphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, key);
		graphic.persist = true;

		// `persist` alone isn't enough here. Paths.clearStoredMemory() destroys every
		// FlxG.bitmap entry it doesn't recognise, and several states call it from
		// create(), which would pull the graphic out from under a live pad. Registering
		// the key the way Paths expects is what actually keeps it alive.
		Paths.currentTrackedAssets.set(key, graphic);
		Paths.excludeAsset(key);

		cache.set(key, graphic);
		return graphic;
	}
}

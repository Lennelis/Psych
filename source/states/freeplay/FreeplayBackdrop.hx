package states.freeplay;

import flixel.addons.display.FlxBackdrop;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxAxes;
import flixel.group.FlxSpriteGroup;
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.geom.Rectangle;

/**
 * Everything behind the freeplay menu: the main menu's own art, a colour wash over it, and
 * a checker drifting across the whole thing on a loop that never ends and never seams.
 *
 * All of it comes out of images/freeplay/background.json, so it can be retuned without a
 * rebuild. The numbers shipped there were measured rather than guessed - Leo set them in a
 * live preview running the same maths this does.
 */
class FreeplayBackdrop extends FlxSpriteGroup
{
	public var bg:FlxSprite;
	public var tint:FlxSprite;
	public var checker:FlxBackdrop;

	/** One full repeat of the pattern, in pixels. Two squares, not one. */
	var period:Float = 1;

	public function new()
	{
		super();

		var settings:FreeplayBackdropSettings = readSettings();

		bg = fill(new FlxSprite().loadGraphic(Paths.image('menuBG')));
		add(bg);

		// menuDesat tinted, which is the layer the main menu flashes pink on its transitions.
		// Kept as its own sprite rather than baked into the art so a song can drive its colour
		// later - that is one setTint() call, nothing else has to move.
		tint = fill(new FlxSprite().loadGraphic(Paths.image('menuDesat')));
		tint.color = parseColor(settings.tintColor, 0xFF6F52FF);
		tint.alpha = settings.tintOpacity;
		tint.visible = settings.tintEnabled && settings.tintOpacity > 0;
		add(tint);

		period = Math.max(1, settings.tileSize * 2);

		checker = new FlxBackdrop(checkerGraphic(settings), FlxAxes.XY);
		checker.scrollFactor.set();
		checker.antialiasing = false;
		checker.alpha = settings.opacity;
		checker.angle = settings.gridAngle;
		checker.blend = parseBlend(settings.blend);
		checker.x = settings.offsetX;
		checker.y = settings.offsetY;

		// Screen axes: 0 drifts right, 90 down. The same convention the tuner used, and the
		// same one flixel uses, so a direction that looked right there looks right here.
		var radians:Float = settings.direction * Math.PI / 180;
		checker.velocity.set(Math.cos(radians) * settings.speed, Math.sin(radians) * settings.speed);
		add(checker);
	}

	/**
	 * Repoints the wash at a new colour, for driving it off the selected song the way stock
	 * Psych's freeplay does.
	 */
	public function setTint(color:FlxColor, ?alpha:Null<Float>):Void
	{
		tint.color = color;
		if (alpha != null) tint.alpha = alpha;
		tint.visible = tint.alpha > 0;
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// The backdrop tiles from its own position, so left alone the coordinates climb for as
		// long as the menu is open and eventually lose the precision the pattern is drawn with.
		// Wrapping by one period is invisible - the pattern at x and at x + period is the same
		// pattern - and keeps the numbers small forever.
		if (period > 0)
		{
			checker.x = wrap(checker.x, period);
			checker.y = wrap(checker.y, period);
		}
	}

	static inline function wrap(value:Float, by:Float):Float
		return value - Math.ffloor(value / by) * by;

	static function fill(sprite:FlxSprite):FlxSprite
	{
		sprite.antialiasing = ClientPrefs.data.antialiasing;
		sprite.scrollFactor.set();
		CoolUtil.fillScreen(sprite);
		return sprite;
	}

	/**
	 * One period of the checker as a bitmap: two squares of A on one diagonal, two of B on the
	 * other. Drawn rather than shipped as art so the size and both colours stay editable.
	 */
	static function checkerGraphic(settings:FreeplayBackdropSettings):FlxGraphic
	{
		var tile:Int = Std.int(Math.max(1, settings.tileSize));
		var span:Int = tile * 2;
		var key:String = 'freeplayChecker|$span|${settings.colorA}|${settings.colorB}';

		var cached:FlxGraphic = FlxG.bitmap.get(key);
		if (cached != null) return cached;

		var a:FlxColor = parseColor(settings.colorA, 0x88FFFFFF);
		var b:FlxColor = parseColor(settings.colorB, 0x00000000);

		var pixels:BitmapData = new BitmapData(span, span, true, 0);
		pixels.fillRect(new Rectangle(0, 0, tile, tile), a);
		pixels.fillRect(new Rectangle(tile, tile, tile, tile), a);
		pixels.fillRect(new Rectangle(tile, 0, tile, tile), b);
		pixels.fillRect(new Rectangle(0, tile, tile, tile), b);

		return FlxG.bitmap.add(pixels, false, key);
	}

	static function parseBlend(name:String):BlendMode
	{
		if (name == null) return null;

		return switch (name.toLowerCase().trim())
		{
			case 'add': BlendMode.ADD;
			case 'multiply': BlendMode.MULTIPLY;
			case 'screen': BlendMode.SCREEN;
			default: null; // flixel reads null as ordinary alpha blending
		}
	}

	/**
	 * AARRGGBB, as the rest of the freeplay's files write colours.
	 *
	 * One byte at a time, and deliberately not through FlxColor.fromString. That takes the whole
	 * string to Std.parseInt, and a colour with its alpha byte set - anything from 0x80000000 up
	 * - is larger than a signed 32-bit Int holds. What comes back is saturated rather than
	 * wrapped, so every opaque colour arrived as white: the purple wash rendered as plain
	 * menuDesat and the cyan checker as a faint grey one. Four bytes read separately are each at
	 * most 0xFF, so there is nothing to overflow.
	 */
	static function parseColor(value:String, fallback:FlxColor):FlxColor
	{
		if (value == null) return fallback;

		var clean:String = value.trim();
		if (clean.charAt(0) == '#') clean = clean.substr(1);
		if (clean.substr(0, 2).toLowerCase() == '0x') clean = clean.substr(2);

		// Six digits is an opaque colour written without its alpha.
		if (clean.length == 6) clean = 'FF' + clean;
		if (clean.length != 8) return fallback;

		var a:Null<Int> = byteAt(clean, 0);
		var r:Null<Int> = byteAt(clean, 2);
		var g:Null<Int> = byteAt(clean, 4);
		var b:Null<Int> = byteAt(clean, 6);
		if (a == null || r == null || g == null || b == null) return fallback;

		return FlxColor.fromRGB(r, g, b, a);
	}

	static function byteAt(hex:String, at:Int):Null<Int>
		return Std.parseInt('0x' + hex.substr(at, 2));

	static function readSettings():FreeplayBackdropSettings
	{
		var loaded:FreeplayBackdropSettings = {
			tileSize: 60, gridAngle: 0,
			colorA: 'D900AAFF', colorB: '0000EEFF',
			speed: 18, direction: 225, offsetX: 0, offsetY: 0,
			opacity: 0.36, blend: 'normal',
			tintEnabled: true, tintColor: 'FF6F52FF', tintOpacity: 1
		};

		try
		{
			var raw:String = Paths.getTextFromFile('images/freeplay/background.json');
			if (raw == null || raw.length < 1) return loaded;

			var parsed:Dynamic = haxe.Json.parse(raw);

			function number(name:String, fallback:Float):Float
			{
				var value:Dynamic = Reflect.field(parsed, name);
				if (value == null) return fallback;

				var asFloat:Float = cast value;
				return Math.isNaN(asFloat) ? fallback : asFloat;
			}

			function text(name:String, fallback:String):String
			{
				var value:Dynamic = Reflect.field(parsed, name);
				return (value == null) ? fallback : Std.string(value);
			}

			loaded.tileSize = Std.int(number('tileSize', loaded.tileSize));
			loaded.gridAngle = number('gridAngle', loaded.gridAngle);
			loaded.colorA = text('colorA', loaded.colorA);
			loaded.colorB = text('colorB', loaded.colorB);
			loaded.speed = number('speed', loaded.speed);
			loaded.direction = number('direction', loaded.direction);
			loaded.offsetX = number('offsetX', loaded.offsetX);
			loaded.offsetY = number('offsetY', loaded.offsetY);
			loaded.opacity = number('opacity', loaded.opacity);
			loaded.blend = text('blend', loaded.blend);
			loaded.tintColor = text('tintColor', loaded.tintColor);
			loaded.tintOpacity = number('tintOpacity', loaded.tintOpacity);

			var enabled:Dynamic = Reflect.field(parsed, 'tintEnabled');
			if (enabled != null) loaded.tintEnabled = (enabled == true);
		}
		catch (e:Dynamic)
			trace('FreeplayBackdrop: could not read background.json ($e)');

		return loaded;
	}
}

typedef FreeplayBackdropSettings =
{
	var tileSize:Int;
	var gridAngle:Float;
	var colorA:String;
	var colorB:String;
	var speed:Float;
	var direction:Float;
	var offsetX:Float;
	var offsetY:Float;
	var opacity:Float;
	var blend:String;
	var tintEnabled:Bool;
	var tintColor:String;
	var tintOpacity:Float;
}

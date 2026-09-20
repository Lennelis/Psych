package states.freeplay;

import flixel.addons.display.FlxBackdrop;
import flixel.graphics.FlxGraphic;
import flixel.group.FlxSpriteGroup;
import flixel.tweens.FlxEase;
import flixel.util.FlxAxes;
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.geom.Rectangle;

/**
 * Everything behind the freeplay menu: the main menu's own art, a colour wash over it, and a
 * checker drifting across the whole thing on a loop that never ends and never seams.
 *
 * The wash and the checker both take their colour from the selected song, and move to a new
 * one over a curve rather than cutting. All of it comes out of images/freeplay/background.json,
 * so it can be retuned without a rebuild.
 */
class FreeplayBackdrop extends FlxSpriteGroup
{
	public var bg:FlxSprite;
	public var tint:FlxSprite;
	public var checker:FlxBackdrop;

	var settings:FreeplayBackdropSettings;

	/** One full repeat of the pattern, in pixels. Two squares, not one. */
	var period:Float = 1;

	// Where the colours are coming from, where they are going, and how far along they are.
	var washFrom:FlxColor;
	var washTo:FlxColor;
	var checkerFrom:FlxColor;
	var checkerTo:FlxColor;
	var elapsedMs:Float = -1;

	public function new()
	{
		super();

		settings = readSettings();

		bg = fill(new FlxSprite().loadGraphic(Paths.image('menuBG')));
		add(bg);

		// menuDesat tinted, which is the layer the main menu flashes pink on its transitions.
		tint = fill(new FlxSprite().loadGraphic(Paths.image('menuDesat')));
		tint.alpha = settings.washOpacity;
		tint.visible = settings.washOpacity > 0;
		add(tint);

		period = Math.max(1, settings.tileSize * 2);

		// The pattern is drawn white and coloured through the sprite's own tint, so a colour
		// change is one multiply rather than a bitmap rebuilt every frame of every transition.
		checker = new FlxBackdrop(checkerGraphic(settings), FlxAxes.XY);
		checker.scrollFactor.set();
		checker.antialiasing = false;
		checker.alpha = settings.opacity;
		checker.angle = settings.gridAngle;
		checker.blend = parseBlend(settings.blendMode);
		checker.x = settings.offsetX;
		checker.y = settings.offsetY;

		// Screen axes: 0 drifts right, 90 down. The same convention flixel uses.
		var radians:Float = settings.direction * Math.PI / 180;
		checker.velocity.set(Math.cos(radians) * settings.speed, Math.sin(radians) * settings.speed);
		add(checker);

		var start:FlxColor = parseColor(settings.fallbackColor, 0xFF6F52FF);
		washFrom = washTo = washFor(start);
		checkerFrom = checkerTo = checkerFor(washTo);
		apply(washTo, checkerTo);
	}

	/**
	 * Point the background at a song's colour. `instant` skips the transition, for the first
	 * song the menu lands on - there is nothing to move away from yet.
	 */
	public function setSong(color:Null<FlxColor>, instant:Bool = false):Void
	{
		if (!settings.songColored) return;

		var base:FlxColor = (color != null) ? color : parseColor(settings.fallbackColor, 0xFF6F52FF);
		var wash:FlxColor = washFor(base);
		var check:FlxColor = checkerFor(wash);

		if (wash == washTo && check == checkerTo) return;

		washFrom = tint.color;
		checkerFrom = checker.color;
		washTo = wash;
		checkerTo = check;

		if (instant || settings.transitionMs <= 0)
		{
			elapsedMs = -1;
			apply(washTo, checkerTo);
		}
		else elapsedMs = 0;
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// The backdrop tiles from its own position, so left alone the coordinates climb for as
		// long as the menu is open and eventually lose the precision the pattern is drawn with.
		// Wrapping by one period is invisible and keeps the numbers small forever.
		if (period > 0)
		{
			checker.x = wrap(checker.x, period);
			checker.y = wrap(checker.y, period);
		}

		if (elapsedMs < 0) return;

		elapsedMs += elapsed * 1000;

		var ease:Float->Float = easeByName(settings.ease);
		var washT:Float = clamp01(elapsedMs / settings.transitionMs);
		var checkT:Float = clamp01((elapsedMs - settings.checkerLagMs) / settings.transitionMs);

		apply(blend(washFrom, washTo, ease(washT)), blend(checkerFrom, checkerTo, ease(checkT)));

		if (washT >= 1 && checkT >= 1) elapsedMs = -1;
	}

	inline function apply(wash:FlxColor, check:FlxColor):Void
	{
		tint.color = wash;
		checker.color = check;
	}

	/** The song's own colour, adjusted - a very dark or very grey week needs lifting. */
	function washFor(song:FlxColor):FlxColor
		return FlxColor.fromHSL(song.hue, clamp01(song.saturation * settings.bgSaturation),
			clamp01(song.lightness + settings.bgLightness));

	/** Described as a distance from the wash, so every song keeps the same relationship. */
	function checkerFor(wash:FlxColor):FlxColor
		return FlxColor.fromHSL(wash.hue + settings.hueApart, clamp01(wash.saturation + settings.saturationApart),
			clamp01(wash.lightness + settings.lightnessApart));

	/**
	 * Mixes two colours.
	 *
	 * Through hue by default, because a straight line between two colours in RGB passes near
	 * grey when they are close to opposite - gold to indigo visibly desaturates halfway. Going
	 * round the wheel keeps the colour saturated the whole way across.
	 */
	function blend(from:FlxColor, to:FlxColor, t:Float):FlxColor
	{
		if (settings.blend == 'rgb') return FlxColor.interpolate(from, to, t);

		var delta:Float = to.hue - from.hue;
		if (settings.blend == 'hueLong')
		{
			if (delta > 0 && delta < 180) delta -= 360;
			else if (delta <= 0 && delta > -180) delta += 360;
		}
		else
		{
			if (delta > 180) delta -= 360;
			else if (delta < -180) delta += 360;
		}

		return FlxColor.fromHSL(from.hue + delta * t, from.saturation + (to.saturation - from.saturation) * t,
			from.lightness + (to.lightness - from.lightness) * t);
	}

	static function easeByName(name:String):Float->Float
	{
		if (name == null) return FlxEase.quadOut;

		return switch (name.toLowerCase().trim())
		{
			case 'linear': FlxEase.linear;
			case 'cubeout': FlxEase.cubeOut;
			case 'expoout': FlxEase.expoOut;
			case 'sineinout': FlxEase.sineInOut;
			case 'backout': FlxEase.backOut;
			default: FlxEase.quadOut;
		}
	}

	static inline function clamp01(v:Float):Float
		return (v < 0) ? 0 : (v > 1 ? 1 : v);

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
	 * One period of the checker: two white squares on one diagonal, two on the other, each at
	 * its own opacity. White, because the colour arrives through the sprite's tint.
	 */
	static function checkerGraphic(settings:FreeplayBackdropSettings):FlxGraphic
	{
		var tile:Int = Std.int(Math.max(1, settings.tileSize));
		var span:Int = tile * 2;
		var key:String = 'freeplayChecker|$span|${settings.checkerAlphaA}|${settings.checkerAlphaB}';

		var cached:FlxGraphic = FlxG.bitmap.get(key);
		if (cached != null) return cached;

		var a:FlxColor = FlxColor.fromRGBFloat(1, 1, 1, clamp01(settings.checkerAlphaA));
		var b:FlxColor = FlxColor.fromRGBFloat(1, 1, 1, clamp01(settings.checkerAlphaB));

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
	 * string to Std.parseInt, and a colour with its alpha byte set is larger than a signed
	 * 32-bit Int holds. What comes back is saturated rather than wrapped, so every opaque colour
	 * arrives as white.
	 */
	static function parseColor(value:String, fallback:FlxColor):FlxColor
	{
		if (value == null) return fallback;

		var clean:String = value.trim();
		if (clean.charAt(0) == '#') clean = clean.substr(1);
		if (clean.substr(0, 2).toLowerCase() == '0x') clean = clean.substr(2);

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
			tileSize: 60, gridAngle: 0, checkerAlphaA: 0.85, checkerAlphaB: 0,
			opacity: 0.36, blendMode: 'normal',
			speed: 18, direction: 225, offsetX: 0, offsetY: 0,
			songColored: true, fallbackColor: 'FF6F52FF',
			bgSaturation: 1, bgLightness: 0, washOpacity: 1,
			hueApart: -52, saturationApart: 0.3, lightnessApart: 0.08,
			transitionMs: 450, ease: 'quadOut', blend: 'hue', checkerLagMs: 0
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
			loaded.checkerAlphaA = number('checkerAlphaA', loaded.checkerAlphaA);
			loaded.checkerAlphaB = number('checkerAlphaB', loaded.checkerAlphaB);
			loaded.opacity = number('opacity', loaded.opacity);
			loaded.blendMode = text('blendMode', loaded.blendMode);
			loaded.speed = number('speed', loaded.speed);
			loaded.direction = number('direction', loaded.direction);
			loaded.offsetX = number('offsetX', loaded.offsetX);
			loaded.offsetY = number('offsetY', loaded.offsetY);
			loaded.fallbackColor = text('fallbackColor', loaded.fallbackColor);
			loaded.bgSaturation = number('bgSaturation', loaded.bgSaturation);
			loaded.bgLightness = number('bgLightness', loaded.bgLightness);
			loaded.washOpacity = number('washOpacity', loaded.washOpacity);
			loaded.hueApart = number('hueApart', loaded.hueApart);
			loaded.saturationApart = number('saturationApart', loaded.saturationApart);
			loaded.lightnessApart = number('lightnessApart', loaded.lightnessApart);
			loaded.transitionMs = number('transitionMs', loaded.transitionMs);
			loaded.ease = text('ease', loaded.ease);
			loaded.blend = text('blend', loaded.blend);
			loaded.checkerLagMs = number('checkerLagMs', loaded.checkerLagMs);

			var colored:Dynamic = Reflect.field(parsed, 'songColored');
			if (colored != null) loaded.songColored = (colored == true);
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
	var checkerAlphaA:Float;
	var checkerAlphaB:Float;
	var opacity:Float;
	var blendMode:String;
	var speed:Float;
	var direction:Float;
	var offsetX:Float;
	var offsetY:Float;
	var songColored:Bool;
	var fallbackColor:String;
	var bgSaturation:Float;
	var bgLightness:Float;
	var washOpacity:Float;
	var hueApart:Float;
	var saturationApart:Float;
	var lightnessApart:Float;
	var transitionMs:Float;
	var ease:String;
	var blend:String;
	var checkerLagMs:Float;
}

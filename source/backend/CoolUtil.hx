package backend;

import openfl.utils.Assets;
import lime.utils.Assets as LimeAssets;

class CoolUtil
{
	public static function checkForUpdates(url:String = null):String {
		if (url == null || url.length == 0)
			url = "https://raw.githubusercontent.com/ShadowMario/FNF-PsychEngine/main/gitVersion.txt";
		var version:String = states.MainMenuState.psychEngineVersion.trim();
		if(ClientPrefs.data.checkForUpdates) {
			trace('checking for updates...');
			var http = new haxe.Http(url);
			http.onData = function (data:String)
			{
				var newVersion:String = data.split('\n')[0].trim();
				trace('version online: $newVersion, your version: $version');
				if(newVersion != version) {
					trace('versions arent matching! please update');
					version = newVersion;
					http.onData = null;
					http.onError = null;
					http = null;
				}
			}
			http.onError = function (error) {
				trace('error: $error');
			}
			http.request();
		}
		return version;
	}
	inline public static function quantize(f:Float, snap:Float){
		// changed so this actually works lol
		var m:Float = Math.fround(f * snap);
		//trace(snap);
		return (m / snap);
	}

	inline public static function capitalize(text:String)
		return text.charAt(0).toUpperCase() + text.substr(1).toLowerCase();

	inline public static function coolTextFile(path:String):Array<String>
	{
		// Either a real file - a mod, or anything unpacked beside the game - or something
		// sealed inside the build. Every list in the game comes through here, so checking
		// only one of the two is what emptied the note skin and splash menus, the intro
		// text and the dialogue on a phone the first time mods were switched on.
		var daList:String = Paths.getFileContent(path);
		return daList != null ? listFromString(daList) : [];
	}

	inline public static function colorFromString(color:String):FlxColor
	{
		var hideChars = ~/[\t\n\r]/;
		var color:String = hideChars.split(color).join('').trim();
		if(color.startsWith('0x')) color = color.substring(color.length - 6);

		var colorNum:Null<FlxColor> = FlxColor.fromString(color);
		if(colorNum == null) colorNum = FlxColor.fromString('#$color');
		return colorNum != null ? colorNum : FlxColor.WHITE;
	}

	inline public static function listFromString(string:String):Array<String>
	{
		var daList:Array<String> = [];
		daList = string.trim().split('\n');

		for (i in 0...daList.length)
			daList[i] = daList[i].trim();

		return daList;
	}

	/**
	 * Half the width the screen has beyond the 1280 the game is drawn for.
	 *
	 * Widescreen raises `FlxG.width`, and everything laid out at a fixed coordinate
	 * would otherwise sit against the left edge with all of the new room piled up on
	 * the right. Adding this to a sprite's x centres the composition again. Zero
	 * whenever the game is running at the size it was built for, so a call to it costs
	 * desktop nothing.
	 */
	public static function widescreenOffset():Float
		return Math.max(0, FlxG.width - FlxG.initialWidth) * 0.5;

	/**
	 * Grows a background until it covers the screen, and centres it.
	 *
	 * Menu backgrounds are drawn for 1280x720 and a wider screen leaves bars either
	 * side of them. Scaling keeps the art's proportions - a strip off the top and
	 * bottom is lost instead of the whole thing being stretched - and a background
	 * already big enough is left at the size it was given.
	 */
	public static function fillScreen(sprite:FlxSprite):FlxSprite
	{
		if(sprite == null || sprite.frameWidth <= 0 || sprite.frameHeight <= 0) return sprite;

		var needed:Float = Math.max(FlxG.width / sprite.frameWidth, FlxG.height / sprite.frameHeight);
		if(needed > Math.max(sprite.scale.x, sprite.scale.y))
		{
			sprite.scale.set(needed, needed);
			sprite.updateHitbox();
		}
		sprite.screenCenter();
		return sprite;
	}

	/**
	 * Grows a banner until it spans the screen, then trims it back to the strip it is
	 * allowed to occupy.
	 *
	 * `fillScreen` is for backgrounds that own the whole screen. A banner doesn't: the
	 * story menu's week art is a strip with a black bar above it and the week names
	 * below, and a wider screen left the 1280-wide art short of the right edge with the
	 * yellow behind it showing through. Scaling it to cover keeps the art's proportions,
	 * and the overflow it gains in height is cut off rather than allowed to spill over
	 * the things drawn either side of it.
	 *
	 * @param top    Screen y the strip starts at.
	 * @param height How tall the strip is, at the size the art was drawn for.
	 */
	public static function fillBanner(sprite:FlxSprite, top:Float, height:Float):FlxSprite
	{
		if(sprite == null || sprite.frameWidth <= 0 || sprite.frameHeight <= 0) return sprite;

		sprite.clipRect = null;
		sprite.scale.set(1, 1);
		sprite.setPosition(0, top);

		var scale:Float = FlxG.width / sprite.frameWidth;
		if(scale <= 1) return sprite; // already reaches both edges, leave it exactly as it was

		sprite.scale.set(scale, scale);

		// A sprite scales about its origin, which is its own centre, so lining that up
		// with the strip's centre is what puts the art where it belongs.
		sprite.setPosition((FlxG.width - sprite.frameWidth) * 0.5, top + (height - sprite.frameHeight) * 0.5);

		// clipRect is measured on the frame, before scale, so the strip has to be
		// converted back into the art's own pixels.
		var visible:Float = height / scale;
		if(visible < sprite.frameHeight)
			sprite.clipRect = new flixel.math.FlxRect(0, (sprite.frameHeight - visible) * 0.5, sprite.frameWidth, visible);

		return sprite;
	}

	public static function floorDecimal(value:Float, decimals:Int):Float
	{
		if(decimals < 1)
			return Math.floor(value);

		return Math.floor(value * Math.pow(10, decimals)) / Math.pow(10, decimals);
	}

	inline public static function dominantColor(sprite:flixel.FlxSprite):Int
	{
		var countByColor:Map<Int, Int> = [];
		for(col in 0...sprite.frameWidth)
		{
			for(row in 0...sprite.frameHeight)
			{
				var colorOfThisPixel:FlxColor = sprite.pixels.getPixel32(col, row);
				if(colorOfThisPixel.alphaFloat > 0.05)
				{
					colorOfThisPixel = FlxColor.fromRGB(colorOfThisPixel.red, colorOfThisPixel.green, colorOfThisPixel.blue, 255);
					var count:Int = countByColor.exists(colorOfThisPixel) ? countByColor[colorOfThisPixel] : 0;
					countByColor[colorOfThisPixel] = count + 1;
				}
			}
		}

		var maxCount = 0;
		var maxKey:Int = 0; //after the loop this will store the max color
		countByColor[FlxColor.BLACK] = 0;
		for(key => count in countByColor)
		{
			if(count >= maxCount)
			{
				maxCount = count;
				maxKey = key;
			}
		}
		countByColor = [];
		return maxKey;
	}

	inline public static function numberArray(max:Int, ?min = 0):Array<Int>
	{
		var dumbArray:Array<Int> = [];
		for (i in min...max) dumbArray.push(i);

		return dumbArray;
	}

	inline public static function browserLoad(site:String) {
		#if linux
		Sys.command('/usr/bin/xdg-open', [site]);
		#else
		FlxG.openURL(site);
		#end
	}

	inline public static function openFolder(folder:String, absolute:Bool = false) {
		#if sys
			if(!absolute) folder =  Sys.getCwd() + '$folder';

			folder = folder.replace('/', '\\');
			if(folder.endsWith('/')) folder.substr(0, folder.length - 1);

			#if linux
			var command:String = '/usr/bin/xdg-open';
			#else
			var command:String = 'explorer.exe';
			#end
			Sys.command(command, [folder]);
			trace('$command $folder');
		#else
			FlxG.error("Platform is not supported for CoolUtil.openFolder");
		#end
	}

	/**
		Helper Function to Fix Save Files for Flixel 5

		-- EDIT: [November 29, 2023] --

		this function is used to get the save path, period.
		since newer flixel versions are being enforced anyways.
		@crowplexus
	**/
	@:access(flixel.util.FlxSave.validate)
	inline public static function getSavePath():String {
		final company:String = FlxG.stage.application.meta.get('company');
		// #if (flixel < "5.0.0") return company; #else
		return '${company}/${flixel.util.FlxSave.validate(FlxG.stage.application.meta.get('file'))}';
		// #end
	}

	public static function setTextBorderFromString(text:FlxText, border:String)
	{
		switch(border.toLowerCase().trim())
		{
			case 'shadow':
				text.borderStyle = SHADOW;
			case 'outline':
				text.borderStyle = OUTLINE;
			case 'outline_fast', 'outlinefast':
				text.borderStyle = OUTLINE_FAST;
			default:
				text.borderStyle = NONE;
		}
	}
}

package objects;

import backend.animation.PsychAnimationController;

/**
 * The glow that sits over a strum for as long as a sustain is being held.
 *
 * Ported from V-Slice's `funkin.play.notes.NoteHoldCover`: a start animation when the
 * hold is taken, a looping middle for as long as it runs, and an end animation once it
 * finishes. Dropping a hold kills the cover outright - only holding one to the end
 * earns the end animation. The opponent gets covers too, and like V-Slice theirs vanish
 * at the end rather than playing it out.
 *
 * One of these is built per strum and lives as long as the strum does, so a hold never
 * waits on a pool and the sheet for a lane's colour is loaded exactly once.
 *
 * Missing art is not an error: a cover that could not load its sheet reports
 * `loaded == false` and quietly does nothing for the whole song.
 */
class HoldCover extends FlxSprite
{
	/** Sheets live at this path plus the colour name, e.g. `holdCovers/holdCoverPurple`. */
	public static var defaultPath(default, never):String = 'holdCovers/holdCover';

	/**
	 * Prefixes tried in order, most specific first. COLOR stands in for the title cased
	 * colour name, so the first start candidate looks for `holdCoverStartPurple`.
	 *
	 * A skin that names its animations something else says so in the json rather than
	 * being renamed to fit.
	 */
	static var START_PREFIXES(default, never):Array<String> = ["holdCoverStart$COLOR", "holdCoverStart", "hold cover start $COLOR", "hold cover start", "start"];
	static var HOLD_PREFIXES(default, never):Array<String> = ["holdCover$COLOR", "holdCoverHold$COLOR", "holdCoverHold", "hold cover hold $COLOR", "hold cover $COLOR", "hold cover hold", "hold"];
	static var END_PREFIXES(default, never):Array<String> = ["holdCoverEnd$COLOR", "holdCoverEnd", "hold cover end $COLOR", "hold cover end", "end"];

	/** Parsed `images/holdCovers/holdCover.json`, kept between songs. Cached even when absent. */
	static var config:Dynamic = null;
	static var configLoaded:Bool = false;

	public var strum:StrumNote;
	public var noteData(default, null):Int = 0;

	/** True once a sheet and at least a looping hold animation were found. */
	public var loaded(default, null):Bool = false;

	/** True while the start or hold animation is up - not while the end plays out. */
	public var running(default, null):Bool = false;

	/** Extra nudge from the strum centre, on top of anything the json asks for. */
	public var offsetX:Float = 0;
	public var offsetY:Float = 0;

	var hasStart:Bool = false;
	var hasEnd:Bool = false;

	public function new(noteData:Int, ?strum:StrumNote)
	{
		super();

		animation = new PsychAnimationController(this);

		this.noteData = noteData;
		this.strum = strum;

		visible = false;
		alpha = ClientPrefs.data.holdCoverAlpha;
		antialiasing = ClientPrefs.data.antialiasing;

		load();
	}

	public static function colorName(noteData:Int):String
	{
		var col:String = Note.colArray[noteData % Note.colArray.length];
		if (col == null || col.length < 1) return '';

		return col.charAt(0).toUpperCase() + col.substring(1);
	}

	/** The sheet a lane uses, pixel stages included. Null when there is no art for it. */
	public static function textureFor(noteData:Int):String
	{
		var color:String = colorName(noteData);
		if (color.length < 1) return null;

		var base:String = defaultPath + color;
		if (PlayState.isPixelStage && sheetExists(base + '-pixel')) return base + '-pixel';

		return sheetExists(base) ? base : null;
	}

	static function sheetExists(key:String):Bool
		return Paths.fileExists('images/$key.png', IMAGE) && Paths.fileExists('images/$key.xml', TEXT);

	function load():Void
	{
		var texture:String = textureFor(noteData);
		if (texture == null) return;

		frames = Paths.getSparrowAtlas(texture);
		if (frames == null) return;

		var color:String = colorName(noteData);
		var conf:Dynamic = getConfig();
		var colorConf:Dynamic = getColorConfig(conf, color);
		var named:Dynamic = readField(colorConf, 'animations');
		var fps:Int = Std.int(readNumber([colorConf, conf], 'fps', 24));

		hasStart = addAnim('start', readString(named, 'start'), START_PREFIXES, color, fps, false);
		var hasHold:Bool = addAnim('hold', readString(named, 'hold'), HOLD_PREFIXES, color, fps, true);
		hasEnd = addAnim('end', readString(named, 'end'), END_PREFIXES, color, fps, false);

		// The loop is the one animation a cover cannot do without: it is what is on
		// screen for all but a few frames of a hold.
		if (!hasHold) return;

		var newScale:Float = readNumber([colorConf, conf], 'scale', 1);
		scale.set(newScale, newScale);
		updateHitbox();

		var offsets:Array<Dynamic> = readArray([colorConf, conf], 'offsets');
		if (offsets != null && offsets.length > 1)
		{
			offsetX = numberOf(offsets[0], 0);
			offsetY = numberOf(offsets[1], 0);
		}

		var anti:Dynamic = readField(colorConf, 'antialiasing');
		if (anti == null) anti = readField(conf, 'antialiasing');

		if (anti != null) antialiasing = (anti == true && ClientPrefs.data.antialiasing);
		else if (PlayState.isPixelStage) antialiasing = false;

		animation.finishCallback = onAnimationFinished;
		loaded = true;
	}

	/** Adds one animation under `name`, trying the json's prefix ahead of the guesses. */
	function addAnim(name:String, prefix:String, candidates:Array<String>, color:String, fps:Int, looped:Bool):Bool
	{
		if (prefix != null && prefix.length > 0 && tryAnim(name, prefix, fps, looped)) return true;

		for (candidate in candidates)
			if (tryAnim(name, StringTools.replace(candidate, "$COLOR", color), fps, looped)) return true;

		return false;
	}

	function tryAnim(name:String, prefix:String, fps:Int, looped:Bool):Bool
	{
		var found:Array<flixel.graphics.frames.FlxFrame> = [];
		@:privateAccess
		animation.findByPrefix(found, prefix);
		if (found.length < 1) return false;

		animation.addByPrefix(name, prefix, fps, looped);
		return animation.exists(name);
	}

	/** Starts a hold. Calling it again mid-hold does nothing, so pieces can call it freely. */
	public function playStart():Void
	{
		if (!loaded || running) return;

		running = true;
		visible = true;
		alpha = ClientPrefs.data.holdCoverAlpha;
		animation.play(hasStart ? 'start' : 'hold', true);
		alignToStrum();
	}

	/** The hold was played to its end: see the end animation out, then disappear. */
	public function playEnd():Void
	{
		if (!running) return;

		running = false;
		if (!hasEnd)
		{
			stopCover();
			return;
		}

		animation.play('end', true);
		alignToStrum();
	}

	/** The hold was dropped, or the song moved on. Gone at once, no end animation. */
	public function stopCover():Void
	{
		running = false;
		visible = false;

		animation.finishCallback = null;
		animation.stop();
		animation.finishCallback = onAnimationFinished;
	}

	function onAnimationFinished(name:String):Void
	{
		if (name == 'start' && running) animation.play('hold', true);
		else if (name == 'end') stopCover();
	}

	/**
	 * Centres the cover on the strum, whatever size the current frame happens to be.
	 *
	 * `offset` is measured from the frame top left and `origin` sits at its centre, so
	 * shifting by half the frame puts both the drawn centre and the point the scale is
	 * taken about on (x, y). The cover stays put even if the sheet's frames differ in
	 * size, and it follows the strum through tweens and modcharts.
	 */
	function alignToStrum():Void
	{
		if (strum == null) return;

		offset.set(frameWidth * 0.5, frameHeight * 0.5);
		setPosition(strum.x + strum.width * 0.5 + offsetX, strum.y + strum.height * 0.5 + offsetY);
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (visible) alignToStrum();
	}

	override function destroy()
	{
		strum = null;
		super.destroy();
	}

	public static function clearConfig():Void
	{
		config = null;
		configLoaded = false;
	}

	static function getConfig():Dynamic
	{
		if (configLoaded) return config;

		configLoaded = true;
		config = null;

		var path:String = 'images/$defaultPath.json';
		if (!Paths.fileExists(path, TEXT)) return null;

		try
		{
			config = haxe.Json.parse(Paths.getTextFromFile(path));
		}
		catch (e:Dynamic)
		{
			FlxG.log.warn('Could not read $path: $e');
			config = null;
		}
		return config;
	}

	static function getColorConfig(conf:Dynamic, color:String):Dynamic
	{
		var colors:Dynamic = readField(conf, 'colors');
		if (colors == null) return null;

		var found:Dynamic = readField(colors, color);
		if (found == null) found = readField(colors, color.toLowerCase());
		return found;
	}

	static function readField(source:Dynamic, field:String):Dynamic
	{
		if (source == null || field == null) return null;

		return Reflect.hasField(source, field) ? Reflect.field(source, field) : null;
	}

	static function readString(source:Dynamic, field:String):String
	{
		var value:Dynamic = readField(source, field);
		return (value != null && Std.isOfType(value, String)) ? cast value : null;
	}

	static function readArray(sources:Array<Dynamic>, field:String):Array<Dynamic>
	{
		for (source in sources)
		{
			var value:Dynamic = readField(source, field);
			if (value != null && Std.isOfType(value, Array)) return cast value;
		}
		return null;
	}

	static function readNumber(sources:Array<Dynamic>, field:String, defaultValue:Float):Float
	{
		for (source in sources)
		{
			var value:Dynamic = readField(source, field);
			if (value != null) return numberOf(value, defaultValue);
		}
		return defaultValue;
	}

	static function numberOf(value:Dynamic, defaultValue:Float):Float
	{
		if (value == null || !Std.isOfType(value, Float)) return defaultValue;

		var num:Float = cast value;
		return Math.isNaN(num) ? defaultValue : num;
	}
}

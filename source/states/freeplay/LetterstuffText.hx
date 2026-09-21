package states.freeplay;

import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxFrame;

/**
 * A word set in Letterstuff, out of the drawn sheet rather than the font file.
 *
 * Letterstuff draws every glyph as a hollow ring - what the font contains is the stroke, and
 * the body of the letter is a hole - so setting it straight gives outlined text on whatever is
 * behind it, which is not how the rest of the menu reads. The insides used to be found and
 * painted at runtime, which meant labelling the transparent regions of the rendered word and
 * casting rays out of each one to tell the inside of a letter from a counter. That is a lot of
 * work to do while someone is scrolling a song list, and it had to happen again for every week
 * the menu had not drawn yet.
 *
 * The letters are drawn in now, so all of it goes away: a week name is its glyphs laid out side
 * by side, and nothing touches a pixel.
 *
 * `images/freeplay/letterstuff.png` is baked at `BASE`, and each frame is exactly one advance
 * wide with the artwork sitting inside it where the font puts the glyph - so frames laid edge to
 * edge reproduce the font's own spacing, and every frame being the same height keeps the letters
 * on their line while the face's wobble is kept.
 *
 * It also does the fitting, because a week name is whatever the week file says and the space
 * under the record is fixed: `Daddy Dearest` is three times the width of `PICO` and
 * `hating simulator ft. moawling` is six.
 */
class LetterstuffText extends FlxSpriteGroup
{
	/** How the name ended up being laid out, for whoever wants to place it. */
	public var lineCount(default, null):Int = 0;

	public var blockWidth(default, null):Float = 0;
	public var blockHeight(default, null):Float = 0;

	/** True when the name could not be made to fit and is running past its budget. */
	public var overflowing(default, null):Bool = false;

	public var settings(default, null):LetterstuffSettings;

	/** The size the sheet is baked at. Everything else is this scaled. */
	public static inline var BASE:Float = 100;

	/** The font's space, at that size. It has no glyph, so the sheet cannot carry it. */
	static inline var SPACE:Float = 25;

	var atlas:FlxAtlasFrames;
	var shownText:String = null;

	public function new(settings:LetterstuffSettings)
	{
		super();

		this.settings = settings;
		atlas = Paths.getSparrowAtlas('freeplay/letterstuff');
	}

	/**
	 * Sets the word, laying it out and rebuilding the letters.
	 *
	 * The same word twice does nothing, which matters because the menu asks on every selection
	 * change and most of those stay inside one week.
	 */
	public function setText(value:String, force:Bool = false):Void
	{
		if (value == null) value = '';
		value = value.toUpperCase();

		if (!force && value == shownText) return;

		shownText = value;
		clearLetters();

		if (value.length < 1 || atlas == null)
		{
			lineCount = 0;
			blockWidth = blockHeight = 0;
			visible = false;
			return;
		}

		var fit:LetterstuffFit = layout(value);
		lineCount = fit.lines.length;
		blockWidth = fit.width;
		overflowing = fit.width > settings.budget + 0.5;

		build(fit);
		visible = true;
	}

	function clearLetters():Void
	{
		while (members.length > 0)
		{
			var letter:FlxSprite = members[members.length - 1];
			remove(letter, true);
			if (letter != null) letter.destroy();
		}
	}

	// -------------------------------------------------------------------------------------
	// Fitting
	// -------------------------------------------------------------------------------------

	/** The frame a character is set with, or null for one the sheet does not carry. */
	function frameFor(char:String):FlxFrame
	{
		return atlas.getByName(char.toLowerCase() + ' bold0000');
	}

	function measure(line:String, size:Int):Float
	{
		var scale:Float = size / BASE;
		var width:Float = 0;

		for (i in 0...line.length)
		{
			var char:String = line.charAt(i);
			if (char == ' ')
			{
				width += SPACE * scale;
				continue;
			}

			var frame:FlxFrame = frameFor(char);
			if (frame != null) width += frame.sourceSize.x * scale;
		}

		return width;
	}

	function widestOf(lines:Array<String>, size:Int):Float
	{
		var most:Float = 0;
		for (line in lines)
			most = Math.max(most, measure(line, size));

		return most;
	}

	/** Greedy wrap: a word joins the line it fits on, and starts a new one when it does not. */
	function wrapTo(text:String, size:Int):Array<String>
	{
		var words:Array<String> = [];
		for (word in text.split(' '))
			if (word.length > 0) words.push(word);

		var lines:Array<String> = [];
		var line:String = '';

		for (word in words)
		{
			var candidate:String = (line.length > 0) ? line + ' ' + word : word;
			if (line.length > 0 && measure(candidate, size) > settings.budget)
			{
				lines.push(line);
				line = word;
			}
			else
				line = candidate;
		}
		if (line.length > 0) lines.push(line);

		return (lines.length > 0) ? lines : [text];
	}

	/**
	 * Works out the lines and the size a name ends up at.
	 *
	 * Shrinking re-wraps afterwards rather than keeping the breaks it started with: a smaller
	 * size holds more words per line, and breaking where the bigger size had to would leave a
	 * stranded last word for no reason.
	 */
	function layout(text:String):LetterstuffFit
	{
		var wraps:Bool = (settings.mode == WRAP || settings.mode == WRAP_THEN_SHRINK);
		var shrinks:Bool = (settings.mode == SHRINK || settings.mode == WRAP_THEN_SHRINK);

		var size:Int = settings.size;
		var lines:Array<String> = wraps ? wrapTo(text, size) : [text];
		var width:Float = widestOf(lines, size);

		if (shrinks && width > settings.budget && width > 0)
		{
			size = Std.int(Math.max(settings.floorSize, Math.floor(size * (settings.budget / width))));
			if (wraps) lines = wrapTo(text, size);
			width = widestOf(lines, size);
		}

		return {lines: lines, size: size, width: width};
	}

	// -------------------------------------------------------------------------------------
	// Drawing
	// -------------------------------------------------------------------------------------

	/**
	 * Lays the lines out as one sprite per letter, centred on each other.
	 *
	 * The letters go down in the group's own coordinates, which is what `add` expects - it
	 * folds the group's position in as each one joins. Colour is written on the way in for the
	 * same reason it cannot be left to the group: `set_color` only reaches the letters that
	 * exist when it runs, and these are made after the last time the menu set it.
	 */
	function build(fit:LetterstuffFit):Void
	{
		var scale:Float = fit.size / BASE;
		var pitch:Float = fit.size * settings.linePercent;

		blockHeight = 0;

		for (row in 0...fit.lines.length)
		{
			var line:String = fit.lines[row];
			var cursor:Float = Math.round((fit.width - measure(line, fit.size)) / 2);
			var top:Float = Math.round(pitch * row);

			for (i in 0...line.length)
			{
				var char:String = line.charAt(i);
				if (char == ' ')
				{
					cursor += SPACE * scale;
					continue;
				}

				var frame:FlxFrame = frameFor(char);
				if (frame == null) continue;

				var letter:FlxSprite = new FlxSprite();
				letter.frames = atlas;
				letter.animation.frameName = frame.name;
				letter.scale.set(scale, scale);
				letter.updateHitbox();
				letter.setPosition(cursor, top);
				letter.antialiasing = antialiasing;
				letter.color = color;
				add(letter);

				cursor += frame.sourceSize.x * scale;
				blockHeight = Math.max(blockHeight, top + letter.height);
			}
		}
	}
}

/** What `layout` decided: the lines, the size they are set at, and the widest of them. */
typedef LetterstuffFit =
{
	var lines:Array<String>;
	var size:Int;
	var width:Float;
}

/** What to do with a word that will not fit inside its budget. */
enum LetterstuffFitMode
{
	/** Nothing - let it run past, which is the honest way to see how far past it runs. */
	OVERFLOW;

	/** Set it smaller until it fits, down to the floor. */
	SHRINK;

	/** Break it across lines. */
	WRAP;

	/** Break it across lines, and if the widest line is still too wide, set it smaller. */
	WRAP_THEN_SHRINK;
}

typedef LetterstuffSettings =
{
	var mode:LetterstuffFitMode;

	/** How wide the word is allowed to be, in pixels. */
	var budget:Float;

	var size:Int;

	/** How small shrinking is allowed to go. Below this, the word overflows instead. */
	var floorSize:Int;

	/** The gap between line tops, as a share of the size. */
	var linePercent:Float;
}

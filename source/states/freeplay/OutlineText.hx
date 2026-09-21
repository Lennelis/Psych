package states.freeplay;

import openfl.Vector;
import openfl.display.BitmapData;
import openfl.geom.Point;
import openfl.geom.Rectangle;

/**
 * A word set in an outline face, with the insides of its letters filled in.
 *
 * Letterstuff draws every glyph as a hollow ring: what the font contains is the stroke, and
 * the body of the letter is a hole. Setting it straight gives outlined text on whatever is
 * behind it, which is not how the menu's own text reads, so the enclosed areas are found and
 * painted after the text is rendered.
 *
 * The hard part is telling the inside of a letter from a counter - the enclosed pocket in an
 * O, a P, an A - because both are areas the outside cannot reach. See `fillInteriors` for how
 * that is decided.
 *
 * It also does the fitting, because a week name is whatever the week file says and the space
 * under the record is fixed: `Daddy Dearest` is three times the width of `PICO` and
 * `hating simulator ft. moawling` is six.
 */
class OutlineText extends FlxSprite
{
	/** How the name ended up being laid out, for whoever wants to place it. */
	public var lineCount(default, null):Int = 1;

	public var blockWidth(default, null):Float = 0;
	public var blockHeight(default, null):Float = 0;

	/** True when the name could not be made to fit and is running past its budget. */
	public var overflowing(default, null):Bool = false;

	public var settings(default, null):OutlineTextSettings;

	var fontPath:String;
	var shownText:String = null;

	/**
	 * One text object, reused for every measurement.
	 *
	 * `textWidth` runs the layout and gives an answer without building a graphic, which is
	 * what makes wrapping affordable - a greedy wrap asks for a width once per word, and a
	 * shrink then asks again for every line at the new size.
	 */
	static var ruler:FlxText = null;

	public function new(fontPath:String, settings:OutlineTextSettings)
	{
		super();

		this.fontPath = fontPath;
		this.settings = settings;
		antialiasing = ClientPrefs.data.antialiasing;
	}

	/**
	 * Sets the word, laying it out and rebuilding the graphic.
	 *
	 * Rebuilding is the expensive part - a pixel pass over the rendered text - so the same
	 * word twice does nothing, which matters because the menu asks on every selection change
	 * and most of those stay inside one week.
	 */
	public function setText(value:String, force:Bool = false):Void
	{
		if (value == null) value = '';
		value = value.toUpperCase();

		if (!force && value == shownText) return;

		shownText = value;

		if (value.length < 1)
		{
			visible = false;
			return;
		}

		var fit:OutlineFit = layout(value);
		lineCount = fit.lines.length;
		blockWidth = fit.width;
		overflowing = fit.width > settings.budget + 0.5;

		build(fit);
		visible = true;
	}

	// -------------------------------------------------------------------------------------
	// Fitting
	// -------------------------------------------------------------------------------------

	function measure(line:String, size:Int):Float
	{
		if (ruler == null)
		{
			// Field width 0 turns word wrap off and auto size on, which is what makes
			// `textWidth` the width of the whole line rather than of a wrapped block.
			ruler = new FlxText(0, 0, 0, '');
			ruler.active = false;
		}

		ruler.setFormat(fontPath, size, FlxColor.WHITE);
		ruler.text = line;
		return ruler.textField.textWidth;
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
	function layout(text:String):OutlineFit
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

	/** Renders one line to its own bitmap, already filled. */
	function lineBitmap(line:String, size:Int):BitmapData
	{
		var text:FlxText = new FlxText(0, 0, 0, line);
		text.setFormat(fontPath, size, FlxColor.WHITE);
		text.antialiasing = antialiasing;

		@:privateAccess
		text.regenGraphic();

		var source:BitmapData = text.pixels;

		// A transparent border all the way round, for two reasons: the top left pixel has to
		// be outside the word for the region walk to know where outside is, and the rays cast
		// below have to be able to leave without clipping a glyph on the way out.
		var padded:BitmapData = new BitmapData(source.width + PAD * 2, source.height + PAD * 2, true, 0x00000000);
		padded.copyPixels(source, source.rect, new Point(PAD, PAD));
		text.destroy();

		fillInteriors(padded);
		return padded;
	}

	/**
	 * Stacks the lines into one graphic, centred on each other.
	 *
	 * Keyed into the bitmap cache before any of the work happens, the way the capsule's week
	 * text is: coming back to a week the menu has already drawn should not pay for the pixel
	 * pass a second time, and going back and forth between two weeks is the normal way to use
	 * this menu.
	 */
	function build(fit:OutlineFit):Void
	{
		var key:String = 'outlineText:${fontPath}:${fit.size}:${settings.linePercent}:${settings.outlineWeight}:'
			+ '${settings.fill.toHexString()}:${settings.outline.toHexString()}:${fit.lines.join("|")}';

		if (!FlxG.bitmap.checkCache(key))
		{
			var pitch:Float = fit.size * settings.linePercent;
			var parts:Array<BitmapData> = [];
			var widest:Int = 1;
			var tallest:Int = 1;

			for (line in fit.lines)
			{
				var part:BitmapData = lineBitmap(line, fit.size);
				parts.push(part);
				if (part.width > widest) widest = part.width;
				if (part.height > tallest) tallest = part.height;
			}

			var sheet:BitmapData = new BitmapData(widest, Math.ceil(pitch * (parts.length - 1)) + tallest, true, 0x00000000);

			for (i in 0...parts.length)
			{
				var part:BitmapData = parts[i];
				sheet.copyPixels(part, part.rect,
					new Point(Math.round((widest - part.width) / 2), Math.round(pitch * i + (tallest - part.height) / 2)));
				part.dispose();
			}

			FlxG.bitmap.add(sheet, false, key);
		}

		var graph:flixel.graphics.FlxGraphic = FlxG.bitmap.get(key);
		loadGraphic(graph);
		blockHeight = graph.height;
	}

	/** The transparent margin added around a line before its regions are worked out. */
	static inline var PAD:Int = 3;

	/** How many pixels of a region get to cast rays. More is steadier and slower. */
	static inline var SAMPLES:Int = 28;

	/**
	 * Paints the inside of every letter, leaving counters and the space around the word alone.
	 *
	 * Every enclosed region votes for itself. From a spread of its own pixels, four rays run
	 * out to the edges of the bitmap and the strokes each one crosses are counted; an odd
	 * count means that ray started inside a letter, an even one means it started outside or in
	 * a counter. The region takes the majority.
	 *
	 * The voting is the whole trick, and two simpler answers are why. Flooding in from the
	 * border and filling whatever it cannot reach calls every counter solid, so O, R and A come
	 * out as blobs. Counting stroke crossings along a single row is wrong from the first place
	 * two strokes touch, because the pair counts as one stroke and every letter to the right of
	 * it inverts. A single ray is wrong for the same reason wherever a region leaks out through
	 * a pinch - the narrow slot at the top of a U, the notch where K's diagonal meets its stem -
	 * since it crosses one stroke on the way out instead of two. Four rays from many pixels
	 * leave the pinches outvoted by the directions that see the truth.
	 */
	function fillInteriors(bitmap:BitmapData):Void
	{
		var w:Int = bitmap.width;
		var h:Int = bitmap.height;
		var n:Int = w * h;
		if (n < 1) return;

		var rect:Rectangle = new Rectangle(0, 0, w, h);
		var pixels:Vector<UInt> = bitmap.getVector(rect);

		var ink:haxe.ds.Vector<Int> = new haxe.ds.Vector<Int>(n);
		for (i in 0...n)
			ink[i] = (((pixels[i] >>> 24) & 0xFF) > 128) ? 1 : 0;

		// Label the transparent regions, four connected.
		var label:haxe.ds.Vector<Int> = new haxe.ds.Vector<Int>(n);
		for (i in 0...n)
			label[i] = -1;

		var stack:haxe.ds.Vector<Int> = new haxe.ds.Vector<Int>(n);
		var members:Array<Array<Int>> = [];

		for (seed in 0...n)
		{
			if (ink[seed] == 1 || label[seed] != -1) continue;

			var id:Int = members.length;
			var top:Int = 0;
			var cells:Array<Int> = [];
			label[seed] = id;
			stack[top++] = seed;

			while (top > 0)
			{
				var p:Int = stack[--top];
				cells.push(p);

				var px:Int = p % w;
				var py:Int = Std.int(p / w);

				if (px > 0 && ink[p - 1] == 0 && label[p - 1] == -1) { label[p - 1] = id; stack[top++] = p - 1; }
				if (px < w - 1 && ink[p + 1] == 0 && label[p + 1] == -1) { label[p + 1] = id; stack[top++] = p + 1; }
				if (py > 0 && ink[p - w] == 0 && label[p - w] == -1) { label[p - w] = id; stack[top++] = p - w; }
				if (py < h - 1 && ink[p + w] == 0 && label[p + w] == -1) { label[p + w] = id; stack[top++] = p + w; }
			}

			members.push(cells);
		}

		// How many separate strokes a ray from here crosses on its way off the bitmap.
		function strokesAlong(sx:Int, sy:Int, dx:Int, dy:Int):Int
		{
			var crossed:Int = 0;
			var inside:Bool = false;
			var cx:Int = sx;
			var cy:Int = sy;

			while (cx >= 0 && cy >= 0 && cx < w && cy < h)
			{
				if (ink[cy * w + cx] == 1)
				{
					if (!inside) { crossed++; inside = true; }
				}
				else
					inside = false;

				cx += dx;
				cy += dy;
			}

			return crossed;
		}

		var outer:Int = label[0];
		var filled:haxe.ds.Vector<Bool> = new haxe.ds.Vector<Bool>(members.length);

		for (id in 0...members.length)
		{
			if (id == outer)
			{
				filled[id] = false;
				continue;
			}

			var cells:Array<Int> = members[id];
			var step:Int = Std.int(Math.max(1, Math.floor(cells.length / SAMPLES)));
			var odd:Int = 0;
			var votes:Int = 0;
			var at:Int = 0;

			while (at < cells.length)
			{
				var x:Int = cells[at] % w;
				var y:Int = Std.int(cells[at] / w);

				if (strokesAlong(x, y, -1, 0) % 2 == 1) odd++;
				if (strokesAlong(x, y, 1, 0) % 2 == 1) odd++;
				if (strokesAlong(x, y, 0, -1) % 2 == 1) odd++;
				if (strokesAlong(x, y, 0, 1) % 2 == 1) odd++;
				votes += 4;

				at += step;
			}

			filled[id] = (odd * 2 > votes);
		}

		var fill:FlxColor = settings.fill;
		var outline:FlxColor = settings.outline;
		var weight:Float = settings.outlineWeight;

		var fillArgb:UInt = (0xFF << 24) | (fill.red << 16) | (fill.green << 8) | fill.blue;

		for (i in 0...n)
		{
			if (ink[i] == 1)
			{
				// At zero outline weight the stroke takes the fill colour too, which leaves a
				// flat silhouette rather than a letter with a line round it.
				var r:Int = Std.int(outline.red + (fill.red - outline.red) * (1 - weight));
				var g:Int = Std.int(outline.green + (fill.green - outline.green) * (1 - weight));
				var b:Int = Std.int(outline.blue + (fill.blue - outline.blue) * (1 - weight));
				pixels[i] = (0xFF << 24) | (r << 16) | (g << 8) | b;
			}
			else if (filled[label[i]])
				pixels[i] = fillArgb;
			else
			{
				// Outside the word, or a counter. The rendered alpha is kept so the soft edge
				// of the stroke stays soft instead of going to a staircase.
				var alpha:Int = Std.int(((pixels[i] >>> 24) & 0xFF) * weight);
				pixels[i] = (alpha << 24) | (outline.red << 16) | (outline.green << 8) | outline.blue;
			}
		}

		bitmap.setVector(rect, pixels);
	}
}

/** What `layout` decided: the lines, the size they are set at, and the widest of them. */
typedef OutlineFit =
{
	var lines:Array<String>;
	var size:Int;
	var width:Float;
}

/** What to do with a word that will not fit inside its budget. */
enum OutlineFitMode
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

typedef OutlineTextSettings =
{
	var mode:OutlineFitMode;

	/** How wide the word is allowed to be, in pixels. */
	var budget:Float;

	var size:Int;

	/** How small shrinking is allowed to go. Below this, the word overflows instead. */
	var floorSize:Int;

	/** The gap between line tops, as a share of the size. */
	var linePercent:Float;

	/** 0 gives a flat silhouette in the fill colour, 1 the full outline. */
	var outlineWeight:Float;

	var fill:FlxColor;
	var outline:FlxColor;
}

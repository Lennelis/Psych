package objects;

import flixel.FlxStrip;
import flixel.graphics.frames.FlxFrame;
import flixel.graphics.tile.FlxDrawTrianglesItem.DrawData;

/**
 * A hold drawn as one stretched mesh, the way V-Slice draws it.
 *
 * Psych builds a hold out of a note per step of the chart - a dozen sprites for a long one,
 * each stretched to a step's worth of height and clipped against the strum as it passes.
 * V-Slice builds one `SustainTrail` per hold instead: eight vertices, two quads, one draw
 * call, with the body stretched to whatever is left of the hold and the rounded cap hung off
 * the end of it. That is what this is.
 *
 * It replaces only the drawing. Every note Psych made is still there, still hit, still missed,
 * still scored - the pieces are simply told not to draw themselves while a trail is standing
 * in for them. Hold input, the miss cascade, the covers and the chart editor all key off those
 * notes, and none of them has to know this exists.
 *
 * The one place it cannot follow V-Slice is the body texture. V-Slice's hold sheet gives each
 * colour a body strip spanning the full height of the image, so letting the V coordinate run
 * past 1 tiles it; a wrap is a property of the whole texture, and Psych's hold piece is a small
 * rectangle inside a shared note atlas, which cannot be wrapped on its own. So the body is
 * stretched rather than tiled. For the art either engine ships that is not a difference at all -
 * V-Slice's body strip is one flat colour from its first row to its last - and Psych already
 * stretches its own hold pieces, so no skin is worse off than it is today.
 */
class SustainTrail extends FlxStrip
{
	/**
	 * Two quads: the body, then the cap.
	 * `top left, top right, bottom left` then `top right, bottom left, bottom right`.
	 */
	static final TRIANGLE_INDICES:Array<Int> = [0, 1, 2, 1, 2, 3, 4, 5, 6, 5, 6, 7];

	/**
	 * When the hold starts and which lane it is in.
	 *
	 * Copied off the head note rather than held as a reference to it, because Psych throws the
	 * head away the moment it is hit - `invalidateNote` destroys it - while the hold it started
	 * carries on for seconds afterwards. Everything here has to outlive the note it came from.
	 */
	public var strumTime(default, null):Float = 0;

	public var noteData(default, null):Int = 0;

	/** Whose strumline it belongs to, so the trail can find the strum it hangs from. */
	public var mustPress(default, null):Bool = false;

	/** How long the whole hold is, in song milliseconds. */
	public var lengthMs(default, null):Float = 0;

	/** True once the hold has run out and the trail has nothing left to draw. */
	public var spent(get, never):Bool;

	function get_spent():Bool
		return !bound || Conductor.songPosition > strumTime + lengthMs;

	var bound:Bool = false;

	var trailWidth:Float = 0;
	var capHeight:Float = 0;

	// Normalised texture coordinates, left/top/right/bottom, into the note atlas.
	var bodyU1:Float = 0;
	var bodyV1:Float = 0;
	var bodyU2:Float = 0;
	var bodyV2:Float = 0;
	var capU1:Float = 0;
	var capV1:Float = 0;
	var capU2:Float = 0;
	var capV2:Float = 0;

	public function new()
	{
		super();

		// Sixteen floats is eight x/y pairs: four corners of the body, four of the cap.
		vertices = new DrawData<Float>(16, true);
		uvtData = new DrawData<Float>(16, true);
		indices = new DrawData<Int>(TRIANGLE_INDICES.length, true, TRIANGLE_INDICES);

		scrollFactor.set();
		active = false;
	}

	/**
	 * Points the trail at a hold, reading its art off the notes Psych already made.
	 *
	 * The frames are taken from the pieces rather than looked up by name, so whatever skin is
	 * loaded is whatever gets drawn - including a mod's, which may not name its holds the way
	 * the built-in ones do. Every piece is created playing the end animation and the one before
	 * it is switched to the body, so the first of the tail is the body and the last is the cap.
	 *
	 * Returns false for a hold there is nothing to draw, which the caller takes as "leave the
	 * notes to draw themselves".
	 */
	public function bindTo(note:Note):Bool
	{
		bound = false;

		if (note == null || note.isSustainNote || note.tail == null || note.tail.length < 1) return false;

		var body:Note = note.tail[0];
		var cap:Note = note.tail[note.tail.length - 1];
		if (body == null || cap == null || body.frame == null || cap.frame == null || note.frames == null) return false;

		strumTime = note.strumTime;
		noteData = note.noteData;
		mustPress = note.mustPress;
		frames = note.frames;

		// The pieces are spaced a step apart and the last one closes the hold off, so the hold
		// runs from its head to the last piece plus that piece's own worth of time. The step is
		// measured off the pieces rather than asked of the conductor, because they were spaced
		// at the tempo in force where they sit, which is not necessarily the tempo now.
		var step:Float = (note.tail.length > 1) ? (note.tail[1].strumTime - note.tail[0].strumTime) : Conductor.stepCrochet;
		lengthMs = (cap.strumTime - note.strumTime) + step;

		// Psych stretches every piece but the last to a step's height; the last keeps the size
		// the art was drawn at, which is the cap's real height.
		trailWidth = body.width;
		capHeight = cap.height;

		if (graphic == null || graphic.width <= 0 || graphic.height <= 0) return false;

		readUV(body.frame, true);
		readUV(cap.frame, false);

		antialiasing = body.antialiasing;
		alpha = 1; // V-Slice's holds are solid where Psych's sit at 0.6.

		bound = true;
		return true;
	}

	/** Turns a frame's place in the atlas into normalised texture coordinates. */
	function readUV(source:FlxFrame, isBody:Bool):Void
	{
		var sheetWidth:Float = graphic.width;
		var sheetHeight:Float = graphic.height;

		var u1:Float = source.frame.x / sheetWidth;
		var v1:Float = source.frame.y / sheetHeight;
		var u2:Float = (source.frame.x + source.frame.width) / sheetWidth;
		var v2:Float = (source.frame.y + source.frame.height) / sheetHeight;

		if (isBody)
		{
			bodyU1 = u1;
			bodyV1 = v1;
			bodyU2 = u2;
			bodyV2 = v2;
		}
		else
		{
			capU1 = u1;
			capV1 = v1;
			capU2 = u2;
			capV2 = v2;
		}
	}

	/**
	 * Lays the mesh out for where the song is now.
	 *
	 * Two things move. Until the head reaches the strum the whole trail slides up with it and
	 * keeps its full length; after that its top is pinned to the strum and it is eaten from
	 * there, which is the same thing V-Slice does with `sustainLength - (songTime - strumTime)`.
	 */
	public function refresh(strum:StrumNote, songSpeed:Float):Void
	{
		if (!bound || strum == null)
		{
			visible = false;
			return;
		}

		var pixelsPerMs:Float = 0.45 * songSpeed;
		var elapsed:Float = Conductor.songPosition - strumTime;

		var remainingMs:Float = lengthMs - Math.max(0, elapsed);
		if (remainingMs <= 0)
		{
			visible = false;
			return;
		}

		// How far short of the strum the hold still is. Zero the moment it arrives.
		var approach:Float = Math.max(0, -elapsed) * pixelsPerMs;
		var trailLength:Float = remainingMs * pixelsPerMs;

		// Downscroll runs the other way and wants the art the other way up with it.
		var down:Bool = strum.downScroll;
		var step:Float = down ? -1 : 1;

		// Follows the strum's own opacity rather than forcing solid. V-Slice's holds are opaque
		// and a normal strum sits at 1, so that is what you get - but Psych dims the opponent's
		// to 0.35 on middlescroll and takes them to 0 entirely when opponent notes are off, and
		// a hold has no business being the one thing still showing.
		alpha = Math.min(1, strum.alpha);
		if (alpha <= 0)
		{
			visible = false;
			return;
		}

		x = strum.x + (strum.width - trailWidth) / 2;
		y = strum.y + strum.height / 2 + approach * step;

		var capLength:Float = Math.min(capHeight, trailLength);
		var bodyLength:Float = Math.max(0, trailLength - capLength);

		setQuad(0, bodyLength * step, trailWidth);
		setQuad(4, capLength * step, trailWidth, bodyLength * step);

		// The body is one frame stretched over whatever is left, so it always shows all of
		// itself. The cap is eaten from its top as the hold runs out, so the part of it still
		// to come is the part of the frame that gets sampled.
		var capShown:Float = (capHeight > 0) ? capLength / capHeight : 1;
		var capTop:Float = capV2 - (capV2 - capV1) * capShown;

		setUV(0, bodyU1, bodyU2, down ? bodyV2 : bodyV1, down ? bodyV1 : bodyV2);
		setUV(4, capU1, capU2, down ? capV2 : capTop, down ? capTop : capV2);

		visible = true;
	}

	/** One quad of the mesh: four vertices, starting at `at`, `height` tall from `from`. */
	function setQuad(at:Int, height:Float, width:Float, from:Float = 0):Void
	{
		vertices[(at + 0) * 2] = 0;
		vertices[(at + 0) * 2 + 1] = from;
		vertices[(at + 1) * 2] = width;
		vertices[(at + 1) * 2 + 1] = from;
		vertices[(at + 2) * 2] = 0;
		vertices[(at + 2) * 2 + 1] = from + height;
		vertices[(at + 3) * 2] = width;
		vertices[(at + 3) * 2 + 1] = from + height;
	}

	/** The same four corners in texture space. */
	function setUV(at:Int, u1:Float, u2:Float, v1:Float, v2:Float):Void
	{
		uvtData[(at + 0) * 2] = u1;
		uvtData[(at + 0) * 2 + 1] = v1;
		uvtData[(at + 1) * 2] = u2;
		uvtData[(at + 1) * 2 + 1] = v1;
		uvtData[(at + 2) * 2] = u1;
		uvtData[(at + 2) * 2 + 1] = v2;
		uvtData[(at + 3) * 2] = u2;
		uvtData[(at + 3) * 2 + 1] = v2;
	}

	/**
	 * Whether this trail is drawing the hold a given piece belongs to.
	 *
	 * Asked by lane and time rather than through the piece's `parent`, because that points at
	 * the head note - which Psych destroys the moment the hold is hit, long before the pieces
	 * behind it are done.
	 */
	public function covers(note:Note):Bool
	{
		return bound
			&& note != null
			&& note.noteData == noteData
			&& note.mustPress == mustPress
			&& note.strumTime >= strumTime - 1
			&& note.strumTime <= strumTime + lengthMs + 1;
	}

	public function release():Void
	{
		bound = false;
		visible = false;
	}
}

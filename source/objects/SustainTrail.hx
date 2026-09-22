package objects;

import flixel.group.FlxSpriteGroup;
import flixel.math.FlxRect;

/**
 * A hold drawn as one continuous piece with a cap on the end, the way V-Slice draws it.
 *
 * Psych builds a hold out of a note per step of the chart - a dozen sprites for a long one,
 * each stretched to a step's worth of height, all at 60% opacity. This draws the same hold as
 * one stretched body and one cap, solid.
 *
 * It replaces only the drawing. Every note Psych made is still there, still hit, still missed,
 * still scored - the pieces are told not to draw while a trail is standing in for them. The
 * input, the miss cascade, the covers and the chart editor all read those notes, and none of
 * them has to know.
 *
 * The first attempt at this built the hold as a triangle mesh, which is literally what V-Slice
 * does. It went out wrong and there was no way to tell from a screenshot which of the vertex
 * layout, the texture coordinates or the scroll direction was at fault - every number in it
 * checked out on its own. Two ordinary sprites get the same picture with flixel doing the
 * placing, which is the part that kept having to be derived by hand.
 */
class SustainTrail extends FlxSpriteGroup
{
	/**
	 * When the hold starts and which lane it is in.
	 *
	 * Copied off the head note rather than held as a reference to it, because Psych throws the
	 * head away the moment it is hit - `invalidateNote` destroys it - while the hold it started
	 * carries on for seconds afterwards.
	 */
	public var strumTime(default, null):Float = 0;

	public var noteData(default, null):Int = 0;

	public var mustPress(default, null):Bool = false;

	/** How long the whole hold is, in song milliseconds. */
	public var lengthMs(default, null):Float = 0;

	/**
	 * Set once the hold has been dropped, to dim it the way Psych dims the pieces it stands in
	 * for. PlayState sets it off the pieces rather than working out the miss here, because the
	 * miss cascade is its business and a hold can be lost in more than one way.
	 */
	public var faded:Bool = false;

	/** True once the hold has run out and there is nothing left to draw. */
	public var spent(get, never):Bool;

	function get_spent():Bool
		return !bound || Conductor.songPosition > strumTime + lengthMs;

	var bound:Bool = false;

	var body:FlxSprite;
	var cap:FlxSprite;

	/** The cap at the size the art was drawn, which is what a full one measures. */
	var capHeight:Float = 0;
	var capScaleY:Float = 1;

	/** Where each piece sits across its lane, taken off the notes Psych already placed. */
	var bodyOffsetX:Float = 0;
	var capOffsetX:Float = 0;

	var clip:FlxRect;

	public function new()
	{
		super();

		// The group hands its own scroll factor to whatever is added to it, so setting it on the
		// pieces would not survive the add.
		scrollFactor.set();
		directAlpha = true;

		clip = new FlxRect();

		body = new FlxSprite();
		cap = new FlxSprite();

		for (piece in [body, cap])
		{
			piece.active = false;
			add(piece);
		}

		active = false;
	}

	/**
	 * Points the trail at a hold, taking its art from the notes Psych already made.
	 *
	 * The frames come off the pieces rather than being looked up by name, so whatever skin is
	 * loaded is what gets drawn, mods included. Every piece is created playing the end
	 * animation and the one before it is switched to the body, so the first of a tail is the
	 * body and the last is the cap.
	 */
	public function bindTo(note:Note):Bool
	{
		bound = false;
		faded = false;

		if (note == null || note.isSustainNote || note.tail == null || note.tail.length < 1) return false;

		var source:Note = note.tail[0];
		var tip:Note = note.tail[note.tail.length - 1];
		if (source == null || tip == null || source.frames == null || tip.frames == null) return false;
		if (source.animation.curAnim == null || tip.animation.curAnim == null) return false;

		strumTime = note.strumTime;
		noteData = note.noteData;
		mustPress = note.mustPress;

		// The pieces are spaced a step apart and the last one closes the hold off. The step is
		// measured off the pieces rather than asked of the conductor, because they were spaced
		// at the tempo in force where they sit, which is not necessarily the tempo now.
		var step:Float = (note.tail.length > 1) ? (note.tail[1].strumTime - note.tail[0].strumTime) : Conductor.stepCrochet;
		lengthMs = (tip.strumTime - note.strumTime) + step;
		if (lengthMs <= 0) return false;

		wear(body, source);
		wear(cap, tip);

		// Psych stretches every piece but the last; the last keeps the size the art was drawn
		// at, so that is the cap's real height. The cap is never stretched off it - when there
		// is less left than that, it gets cut back instead, so the rounded tip keeps its shape.
		capScaleY = (tip.scale.y != 0) ? Math.abs(tip.scale.y) : 1;
		capHeight = cap.frameHeight * capScaleY;

		// Psych walks a sustain across its lane with `offsetX`, which lands differently for a
		// pixel skin and for a mod's own; reading it off the pieces gets all of those for free.
		bodyOffsetX = source.offsetX;
		capOffsetX = tip.offsetX;

		alpha = 1; // V-Slice's holds are solid where Psych's sit at 0.6.
		bound = true;
		return true;
	}

	/** Dresses one of the two sprites in the same frame a piece of the hold is wearing. */
	function wear(target:FlxSprite, source:Note):Void
	{
		target.clipRect = null;
		target.frames = source.frames;
		target.animation.copyFrom(source.animation);
		target.animation.play(source.animation.curAnim.name, true);

		target.scale.set(source.scale.x, source.scale.y);
		target.updateHitbox();

		target.antialiasing = source.antialiasing;
		target.flipY = source.flipY;
	}

	/**
	 * Lays the trail out for where the song is now.
	 *
	 * Until the head reaches the strum the whole thing slides with it at full length; after
	 * that its near end is pinned to the strum and it is eaten from there, which is what
	 * V-Slice does with `sustainLength - (songTime - strumTime)`.
	 */
	public function refresh(strum:StrumNote, songSpeed:Float):Void
	{
		if (!bound || strum == null)
		{
			visible = false;
			return;
		}

		var elapsed:Float = Conductor.songPosition - strumTime;
		var remainingMs:Float = lengthMs - Math.max(0, elapsed);
		if (remainingMs <= 0)
		{
			visible = false;
			return;
		}

		// Follows the strum's own opacity rather than forcing solid. A normal strum sits at 1,
		// which is what V-Slice looks like, but Psych dims the opponent's to 0.35 on
		// middlescroll and to nothing when opponent notes are off, and a hold has no business
		// being the one thing still showing.
		var shade:Float = Math.min(1, strum.alpha) * (faded ? 0.35 : 1);
		if (shade <= 0)
		{
			visible = false;
			return;
		}
		alpha = shade;

		var pixelsPerMs:Float = 0.45 * songSpeed;
		var approach:Float = Math.max(0, -elapsed) * pixelsPerMs;
		var trailLength:Float = remainingMs * pixelsPerMs;

		// Measured out from the middle of the receptor, which is the point Psych itself treats
		// as the strum's centre when it decides how much of a sustain is left to clip.
		var down:Bool = strum.downScroll;
		var anchor:Float = strum.y + Note.swagWidth / 2 + (down ? -approach : approach);

		var capLength:Float = Math.min(capHeight, trailLength);
		var bodyLength:Float = Math.max(0, trailLength - capLength);

		// The body runs from the strum out to where the cap starts; the cap closes off the far
		// end. Both are measured as a distance from the anchor, along whichever way the notes
		// are travelling, so the two scroll directions only differ in one sign.
		place(body, strum.x + bodyOffsetX, anchor, bodyLength, bodyLength, down,
			(body.frameHeight > 0) ? bodyLength / body.frameHeight : 0, null);

		// The cap is always drawn at the size its art was made, and cut back from the near end
		// when the hold has been eaten into it. The cut is the same rectangle either way round:
		// Psych flips the piece on downscroll, so the same rows of the frame are always the ones
		// nearest the strum.
		var capClip:FlxRect = null;
		if (capLength < capHeight && capScaleY != 0)
		{
			var shown:Float = capLength / capScaleY;
			capClip = clip.set(0, cap.frameHeight - shown, cap.frameWidth, shown);
		}
		place(cap, strum.x + capOffsetX, anchor, bodyLength + capLength, capHeight, down, capScaleY, capClip);

		visible = true;
		body.visible = bodyLength > 0;
	}

	/**
	 * Puts one piece with its far edge `far` pixels out from the strum, standing `height` tall.
	 *
	 * Out means down the screen on upscroll and up it on downscroll - the direction the rest of
	 * the hold is still coming from.
	 *
	 * The clip is set before the size, not after: setting one re-reads the frame, which puts
	 * the sprite's width and height back to the frame's own and undoes the sizing.
	 */
	function place(piece:FlxSprite, left:Float, anchor:Float, far:Float, height:Float, down:Bool, scaleY:Float, ?rect:FlxRect):Void
	{
		piece.clipRect = rect;
		piece.scale.y = scaleY;
		piece.updateHitbox();

		piece.x = left;
		piece.y = down ? anchor - far : anchor + far - height;
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
		faded = false;
		visible = false;
	}
}

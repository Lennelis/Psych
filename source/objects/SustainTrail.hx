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
	 * The pieces this trail is drawing instead of.
	 *
	 * Held rather than matched by lane and time. The pieces are the only thing that knows where
	 * a hold really is, and a window around the head's time was always going to let one through
	 * - which it did: the end piece went on drawing itself over the trail's cap.
	 */
	var pieces:Array<Note> = [];

	/**
	 * Set once the hold has been dropped, to dim it the way Psych dims the pieces it stands in
	 * for. PlayState sets it off the pieces rather than working out the miss here, because the
	 * miss cascade is its business and a hold can be lost in more than one way.
	 */
	public var faded:Bool = false;

	/** True once the hold has run out and there is nothing left to draw. */
	public var spent(get, never):Bool;

	function get_spent():Bool
	{
		if (!bound) return true;
		if (Conductor.songPosition <= strumTime + lengthMs) return false;

		// Psych keeps a piece around for `noteKillOffset` past its time. Retiring on the clock
		// alone would hand those back their visibility while they are still on screen.
		for (piece in pieces)
			if (piece != null && piece.exists) return false;

		return true;
	}

	var bound:Bool = false;

	/** Head to the last piece, which is where the cap starts. */
	var bodyMs:Float = 0;

	/** The per-note scroll multiplier, which `followStrumNote` folds in and scripts can change. */
	var multSpeed:Float = 1;

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
		reveal(); // Whatever this one was drawing before goes back to drawing itself.
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
		bodyMs = tip.strumTime - note.strumTime;
		lengthMs = bodyMs + step;
		if (lengthMs <= 0) return false;

		multSpeed = (note.multSpeed != 0) ? note.multSpeed : 1;
		pieces = note.tail.copy();

		wear(body, source);
		wear(cap, tip);

		// Psych stretches every piece but the last; the last keeps the size the art was drawn
		// at, so that is the cap's real height. The cap is never stretched off it - when there
		// is less left than that, it gets cut back instead, so the rounded tip keeps its shape.
		capScaleY = (tip.scale.y != 0) ? Math.abs(tip.scale.y) : 1;
		capHeight = cap.frameHeight * capScaleY;

		// The hold reaches a fixed number of pixels past the last piece - the height of the art -
		// not a step's worth of time. Those are different numbers, and treating the cap as a step
		// left the trail's end sitting short of where Psych draws the piece it replaces.

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

		// All four lanes share one rect in the atlas - every note skin Psych ships draws its
		// holds colourless and lets a palette shader do the colour. Taking the shader off the
		// piece rather than looking one up gets a note type's own palette and a mod's, and gets
		// null when the chart turned note RGB off, which is exactly what the piece would draw.
		target.shader = source.shader;

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

		// `followStrumNote` folds the note's own multiplier into the scroll speed, so a script
		// that speeds one note up moves its hold with it.
		var pixelsPerMs:Float = 0.45 * songSpeed * multSpeed;

		// The hold runs from the head to the last piece as a stretch of time, and then the cap's
		// own height in pixels beyond it. Those two do not convert into each other - the cap is a
		// fixed piece of art, not a step - and measuring it as a step is what left the trail's end
		// sitting short of Psych's.
		var trailLength:Float = (bodyMs * pixelsPerMs + capHeight) - Math.max(0, elapsed) * pixelsPerMs;
		if (trailLength <= 0)
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

		var approach:Float = Math.max(0, -elapsed) * pixelsPerMs;

		// Measured out from the middle of the receptor, which is the point Psych itself treats
		// as the strum's centre when it decides how much of a sustain is left to clip.
		var down:Bool = strum.downScroll;
		var anchor:Float = strum.y + Note.swagWidth / 2 + (down ? -approach : approach);

		var capLength:Float = Math.min(capHeight, trailLength);
		var bodyLength:Float = Math.max(0, trailLength - capLength);

		// The body's outermost row is a half transparent edge in the art, and it is the row that
		// lands against the cap - Psych flips the piece on downscroll, which puts the soft row at
		// whichever end is the far one. Stretched, that half pixel becomes a fade as wide as the
		// stretch factor, which is why it grew with the length of the hold and closed up as the
		// hold was eaten. So the body runs on underneath the cap far enough to bury it, the way
		// Psych's own pieces overlap each other by the 1.05 in their height.
		var stretch:Float = (body.frameHeight > 0) ? bodyLength / body.frameHeight : 0;
		var overlap:Float = (bodyLength > 0) ? Math.min(stretch * 2, capHeight * 0.5) : 0;
		var reach:Float = bodyLength + overlap;

		// The body runs from the strum out to where the cap starts; the cap closes off the far
		// end. Both are measured as a distance from the anchor, along whichever way the notes
		// are travelling, so the two scroll directions only differ in one sign.
		place(body, strum.x + bodyOffsetX, anchor, reach, reach, down,
			(body.frameHeight > 0) ? reach / body.frameHeight : 0, null);

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
	 * Hides the pieces this trail is drawing instead of, and takes their look while it is there.
	 *
	 * Called every frame. A piece Psych destroyed is skipped rather than remembered as gone, so
	 * a hold that outlives some of its own pieces - which every hold does - goes on working.
	 */
	public function conceal():Void
	{
		if (!bound) return;

		for (piece in pieces)
		{
			if (piece == null || !piece.exists) continue;

			piece.visible = false;
			if (piece.missed) faded = true;
			restyle(piece);
		}
	}

	/**
	 * Takes the colour from a piece the trail is standing in for.
	 *
	 * Done every frame rather than once at bind, because a palette is cloned the moment anything
	 * changes it - a note type, or a script recolouring a hold in flight - and the piece is
	 * handed the new shader while whoever copied the old one keeps drawing the old colour.
	 */
	public function restyle(piece:Note):Void
	{
		if (!bound || piece == null || body.shader == piece.shader) return;

		body.shader = piece.shader;
		cap.shader = piece.shader;
	}

	/**
	 * Whether this trail is drawing this exact piece.
	 *
	 * Asked of the pieces themselves rather than through `parent`, which points at the head note
	 * Psych destroys the moment the hold is hit, and rather than by lane and time, which is a
	 * guess that let the end piece through.
	 */
	public function covers(note:Note):Bool
	{
		if (!bound || note == null) return false;

		for (piece in pieces)
			if (piece == note) return true;

		return false;
	}

	public function release():Void
	{
		reveal();
		bound = false;
		faded = false;
		visible = false;
	}

	/**
	 * Hands every piece still standing back its own visibility.
	 *
	 * A piece outlives the trail whenever a hold is dropped or the song is scrubbed, and one left
	 * hidden by a trail that is no longer there would never draw again.
	 */
	function reveal():Void
	{
		for (piece in pieces)
			if (piece != null && piece.exists) piece.visible = true;

		pieces = [];
	}
}

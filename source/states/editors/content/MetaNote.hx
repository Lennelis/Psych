package states.editors.content;

import objects.Note;
import shaders.RGBPalette;
import flixel.util.FlxDestroyUtil;
import flixel.graphics.FlxGraphic;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;

class MetaNote extends Note
{
	public static var noteTypeTexts:Map<Int, FlxText> = [];
	public var isEvent:Bool = false;
	public var songData:Array<Dynamic>;
	/**
	 * The hold, drawn with the note's own art instead of a white bar.
	 *
	 * A MetaNote is built with isSustainNote false, so it never registered the hold frames
	 * itself - these take the same atlas and register them, and take the note's shader too,
	 * which is what carries the lane colour since every direction shares one greyscale
	 * graphic.
	 */
	public var sustainBody:FlxSprite;

	public var sustainEnd:FlxSprite;

	/** How far the hold reaches below the middle of the note, in pixels. */
	public var sustainPixelLength(default, null):Float = 0;
	public var chartY:Float = 0;
	public var chartNoteData:Int = 0;

	public function new(time:Float, data:Int, songData:Array<Dynamic>)
	{
		super(time, data, null, false, true);
		this.songData = songData;
		this.strumTime = time;
		this.chartNoteData = data;
	}

	public function changeNoteData(v:Int)
	{
		this.chartNoteData = v; //despite being so arbitrary its sadly needed to fix a bug on moving notes
		this.songData[1] = v;
		this.noteData = v % ChartingState.GRID_COLUMNS_PER_PLAYER;
		this.mustPress = (v < ChartingState.GRID_COLUMNS_PER_PLAYER);

		// While a note is being carried the data moves and the picture stays put, so the
		// arrow can swing round to its new direction on landing rather than snapping to it
		// halfway across the grid.
		if(deferVisuals) return;

		applyNoteVisuals();
	}

	function applyNoteVisuals()
	{
		visualNoteData = this.noteData;

		if(!PlayState.isPixelStage)
			loadNoteAnims();
		else
			loadPixelNoteAnims();

		if(Note.globalRgbShaders.contains(rgbShader.parent)) //Is using a default shader
			rgbShader = new RGBShaderReference(this, Note.initializeGlobalRGBShader(noteData));

		animation.play(Note.colArray[this.noteData % Note.colArray.length] + 'Scroll');
		updateHitbox();
		if(width > height)
			setGraphicSize(ChartingState.GRID_SIZE);
		else
			setGraphicSize(0, ChartingState.GRID_SIZE);

		updateHitbox();

		// The hold's frames and its shader both belong to the old direction now.
		if(sustainBody != null && _lastStepCrochet > 0)
		{
			sustainBody = FlxDestroyUtil.destroy(sustainBody);
			sustainEnd = FlxDestroyUtil.destroy(sustainEnd);
			setSustainLength(sustainLength, _lastStepCrochet, _lastZoom);
		}
	}

	public function setStrumTime(v:Float)
	{
		this.songData[0] = v;
		this.strumTime = v;
	}

	var _lastZoom:Float = -1;
	var _lastStepCrochet:Float = 0;
	public function setSustainLength(v:Float, stepCrochet:Float, zoom:Float = 1)
	{
		_lastZoom = zoom;
		_lastStepCrochet = stepCrochet;
		v = Math.round(v / (stepCrochet / 2)) * (stepCrochet / 2);
		songData[2] = sustainLength = Math.max(Math.min(v, stepCrochet * 128), 0);

		if(sustainLength > 0)
		{
			if(sustainBody == null)
			{
				sustainBody = buildSustainPiece(false);
				sustainEnd = buildSustainPiece(true);
			}

			sustainPixelLength = Math.max(ChartingState.GRID_SIZE / 4,
				(Math.round((v * ChartingState.GRID_SIZE + ChartingState.GRID_SIZE) / stepCrochet) * zoom) - ChartingState.GRID_SIZE / 2);

			var wide:Float = ChartingState.GRID_SIZE * 0.42;

			// Both pieces keep their own proportions and are drawn from their top left rather
			// than their middle, which is what lets the body be tiled down the hold in draw()
			// instead of stretched over it. Stretching one frame across a hold several bars
			// long is what turned the body to mush.
			for (piece in [sustainBody, sustainEnd])
			{
				piece.origin.set();
				piece.offset.set();
				var s:Float = wide / piece.frameWidth;
				piece.scale.set(s, s);
			}
		}
		else sustainPixelLength = 0;
	}

	public var hasSustain(get, never):Bool;
	function get_hasSustain() return (!isEvent && sustainLength > 0);

	public function updateSustainToZoom(stepCrochet:Float, zoom:Float = 1)
	{
		if(_lastZoom == zoom) return;
		setSustainLength(sustainLength, stepCrochet, zoom);
	}

	public function updateSustainToStepCrochet(stepCrochet:Float)
	{
		if(_lastZoom < 0) return;
		setSustainLength(sustainLength, stepCrochet, _lastZoom);
	}
	
	//
	// DRAG FEEL
	// Tuned on a bench rather than guessed. The constants live on ChartingState.
	//

	public static inline var DRAG_NONE:Int = 0;
	public static inline var DRAG_LIFT:Int = 1;
	public static inline var DRAG_CARRY:Int = 2;
	public static inline var DRAG_SETTLE:Int = 3;

	/**
	 * How far the sprite is drawn from where the note actually is, in pixels.
	 *
	 * The note's real position never stops being snapped - this is only what the eye sees.
	 * Every time the snapped position jumps, the jump is subtracted from here, so the sprite
	 * stays where it was and then catches up. That one trick covers all three phases: a big
	 * subtraction on pick-up is the lift, small ones while carrying are the lag, and the one
	 * on landing is the settle. All that differs between them is how fast it decays.
	 */
	public var dragOffsetX:Float = 0;

	public var dragOffsetY:Float = 0;

	/**
	 * Where the offset is heading.
	 *
	 * Zero everywhere but a note in the air: the snapped position is what a note settles
	 * onto, so letting go always ends at a grid cell. While it is held this carries the
	 * cursor's position inside its cell, which is what takes the note off the grid and puts
	 * it under the pointer instead of jumping a row at a time.
	 */
	public var dragTargetX:Float = 0;

	public var dragTargetY:Float = 0;

	public var dragPhase:Int = DRAG_NONE;

	/** While true, changeNoteData moves the data and leaves the picture where it was. */
	public var deferVisuals:Bool = false;

	/** The direction currently drawn, which lags the data while a note is carried. */
	public var visualNoteData:Int = -1;

	// Where the arrow points for each direction, in the order of Note.colArray:
	// purple/left, blue/down, green/up, red/right.
	static var DIR_ANGLE:Array<Float> = [180, 90, -90, 0];

	var dragVelX:Float = 0;
	var dragVelY:Float = 0;
	var dragBaseScaleX:Float = 0;
	var dragBaseScaleY:Float = 0;
	var dragScale:Float = 1;

	var fadeT:Float = 1;
	var fadeFrom:Array<FlxColor> = null;
	var fadeTo:Array<FlxColor> = null;

	/**
	 * Takes the note off the grid. The sprite stays where it is until the first move.
	 */
	public function beginDrag()
	{
		if(dragBaseScaleX == 0)
		{
			dragBaseScaleX = scale.x;
			dragBaseScaleY = scale.y;
		}

		dragTargetX = dragTargetY = 0;
		deferVisuals = true;
		if(visualNoteData < 0) visualNoteData = noteData;
		dragPhase = DRAG_LIFT;
		dragVelX = dragVelY = 0;
	}

	/**
	 * Puts it down: the picture catches up with the data it has been ignoring, and the
	 * offset it has accumulated settles out.
	 */
	public function endDrag()
	{
		deferVisuals = false;
		dragPhase = DRAG_SETTLE;
		dragVelX = dragVelY = 0;
		dragTargetX = dragTargetY = 0;

		// An event has no note graphic, no direction and no rgbShader - reading one is what
		// crashed this. There is nothing to turn or fade, so it only has to settle.
		if(isEvent)
		{
			angle = 0;
			fadeT = 1;
			return;
		}

		var wanted:Int = noteData % Note.colArray.length;
		var shown:Int = (visualNoteData < 0 ? wanted : visualNoteData) % Note.colArray.length;

		if(wanted != shown && !isEvent)
		{
			// The frame swaps to the new direction straight away and the sprite is turned
			// back to where the old one pointed, then unwinds. The arrows are rotations of
			// each other, so the first frame of that is indistinguishable from the old note
			// and nothing has to pop at the end of the turn.
			var from:Array<FlxColor> = [rgbShader.r, rgbShader.g, rgbShader.b];

			applyNoteVisuals();

			angle = -shortestTurn(DIR_ANGLE[shown], DIR_ANGLE[wanted]);

			// Cross-fade the palette rather than swapping it. Writing to the reference clones
			// the shared palette for this note alone, so the rest of the chart is untouched.
			fadeFrom = from;
			fadeTo = [rgbShader.r, rgbShader.g, rgbShader.b];
			fadeT = 0;
			rgbShader.r = fadeFrom[0];
			rgbShader.g = fadeFrom[1];
			rgbShader.b = fadeFrom[2];
		}
		else
		{
			applyNoteVisuals();
			angle = 0;
			fadeT = 1;
		}

		// applyNoteVisuals goes through setGraphicSize, so the resting scale is whatever it
		// just decided - re-read it rather than trusting what was captured before the lift.
		dragBaseScaleX = scale.x;
		dragBaseScaleY = scale.y;
	}

	static function shortestTurn(from:Float, to:Float):Float
	{
		var d:Float = (to - from) % 360;
		if(d > 180) d -= 360;
		if(d < -180) d += 360;
		return d;
	}

	/**
	 * Advances one frame of the drag. Returns whether anything is still moving.
	 */
	public function stepDrag(elapsed:Float):Bool
	{
		if(dragPhase == DRAG_NONE) return false;

		var held:Bool = (dragPhase == DRAG_LIFT || dragPhase == DRAG_CARRY);

		if(dragPhase == DRAG_SETTLE && ChartingState.LAND_OVERSHOOT > 0 && ChartingState.SETTLE_TAU > 0)
		{
			// A chase can only ever approach, so the landing is a damped spring instead and
			// the overshoot is its damping ratio. Substepped because a stiff spring goes
			// unstable on a long frame, and the editor drops frames on a big chart.
			var omega:Float = 1 / ChartingState.SETTLE_TAU;
			var zeta:Float = Math.max(0.08, 1 - ChartingState.LAND_OVERSHOOT);
			var steps:Int = Std.int(Math.max(1, Math.ceil(elapsed * 240)));
			var h:Float = elapsed / steps;

			for (i in 0...steps)
			{
				dragVelX += (-(omega * omega) * (dragOffsetX - dragTargetX) - 2 * zeta * omega * dragVelX) * h;
				dragVelY += (-(omega * omega) * (dragOffsetY - dragTargetY) - 2 * zeta * omega * dragVelY) * h;
				dragOffsetX += dragVelX * h;
				dragOffsetY += dragVelY * h;
			}
		}
		else
		{
			var tau:Float = switch(dragPhase)
			{
				case DRAG_LIFT: ChartingState.LIFT_TAU;
				case DRAG_CARRY: ChartingState.FOLLOW_TAU;
				default: ChartingState.SETTLE_TAU;
			}

			var k:Float = (tau <= 0) ? 1 : (1 - Math.exp(-elapsed / tau));
			dragOffsetX += (dragTargetX - dragOffsetX) * k;
			dragOffsetY += (dragTargetY - dragOffsetY) * k;
		}

		// The lift is over once the note has caught up with the cursor; from then on it is
		// the carry, which is usually a good deal tighter.
		var lagX:Float = dragOffsetX - dragTargetX;
		var lagY:Float = dragOffsetY - dragTargetY;

		if(dragPhase == DRAG_LIFT && Math.abs(lagX) < 1.5 && Math.abs(lagY) < 1.5)
			dragPhase = DRAG_CARRY;

		// Tilt reads the lag rather than the mouse, so it can never disagree with what is on
		// screen and it straightens itself the moment you stop moving.
		if(!isEvent)
		{
			var wantAngle:Float = 0;
			if(held && ChartingState.TILT_MAX > 0)
				wantAngle = Math.max(-ChartingState.TILT_MAX, Math.min(ChartingState.TILT_MAX, lagX * 0.55));
			else if(fadeT < 1 || angle != 0)
				wantAngle = 0;

			angle += (wantAngle - angle) * Math.min(1, elapsed / Math.max(0.001, ChartingState.TURN_TAU));
			if(!held && Math.abs(angle) < 0.35) angle = 0;
		}

		if(dragBaseScaleX != 0)
		{
			var wantScale:Float = held ? ChartingState.HELD_SCALE : 1;
			dragScale += (wantScale - dragScale) * Math.min(1, elapsed / Math.max(0.001, ChartingState.LIFT_TAU));
			scale.set(dragBaseScaleX * dragScale, dragBaseScaleY * dragScale);
		}

		if(fadeT < 1 && fadeFrom != null)
		{
			fadeT += (1 - fadeT) * (ChartingState.FADE_TAU <= 0 ? 1 : (1 - Math.exp(-elapsed / ChartingState.FADE_TAU)));
			if(fadeT > 0.997) fadeT = 1;

			rgbShader.r = FlxColor.interpolate(fadeFrom[0], fadeTo[0], fadeT);
			rgbShader.g = FlxColor.interpolate(fadeFrom[1], fadeTo[1], fadeT);
			rgbShader.b = FlxColor.interpolate(fadeFrom[2], fadeTo[2], fadeT);

			if(fadeT >= 1)
			{
				// Hand the shared palette back, so a dragged note does not keep a private
				// shader for the rest of the session.
				fadeFrom = fadeTo = null;
				if(!PlayState.isPixelStage)
					rgbShader = new RGBShaderReference(this, Note.initializeGlobalRGBShader(noteData));
			}
		}

		var resting:Bool = !held
			&& Math.abs(lagX) < 0.3 && Math.abs(lagY) < 0.3
			&& Math.abs(dragVelX) < 2 && Math.abs(dragVelY) < 2
			&& Math.abs(dragScale - 1) < 0.004
			&& angle == 0 && fadeT >= 1;

		if(resting)
		{
			dragOffsetX = dragOffsetY = 0;
			dragVelX = dragVelY = 0;
			dragScale = 1;
			if(dragBaseScaleX != 0) scale.set(dragBaseScaleX, dragBaseScaleY);
			dragPhase = DRAG_NONE;
			return false;
		}

		return true;
	}

	/**
	 * Drawn with a ring round it rather than pulsed.
	 *
	 * The old highlight rode the notes' own brightness up and down on a sine, which both
	 * fought the lane colours and made a long selection flicker. A ring says the same thing
	 * without moving, and it still reads on a note of any colour.
	 */
	public var selected:Bool = false;

	static var _ring:FlxSprite;

	static function getRing():FlxSprite
	{
		if(_ring != null) return _ring;

		var size:Int = Std.int(ChartingState.GRID_SIZE);
		var thick:Int = 3;

		_ring = new FlxSprite().makeGraphic(size, size, FlxColor.TRANSPARENT, true, 'chartingSelectionRing');
		_ring.pixels.fillRect(new Rectangle(0, 0, size, thick), FlxColor.WHITE);
		_ring.pixels.fillRect(new Rectangle(0, size - thick, size, thick), FlxColor.WHITE);
		_ring.pixels.fillRect(new Rectangle(0, 0, thick, size), FlxColor.WHITE);
		_ring.pixels.fillRect(new Rectangle(size - thick, 0, thick, size), FlxColor.WHITE);
		_ring.dirty = true;
		_ring.scrollFactor.x = 0;
		return _ring;
	}

	var _noteTypeText:FlxText;
	public function findNoteTypeText(num:Int)
	{
		var txt:FlxText = null;
		if(num != 0)
		{
			if(!noteTypeTexts.exists(num))
			{
				txt = new FlxText(0, 0, ChartingState.GRID_SIZE, (num > 0) ? Std.string(num) : '?', 16);
				txt.autoSize = false;
				txt.alignment = CENTER;
				txt.borderStyle = SHADOW;
				txt.shadowOffset.set(2, 2);
				txt.borderColor = FlxColor.BLACK;
				txt.scrollFactor.x = 0;
				noteTypeTexts.set(num, txt);
			}
			else txt = noteTypeTexts.get(num);
		}
		return (_noteTypeText = txt);
	}

	function buildSustainPiece(isEnd:Bool):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite();
		spr.frames = this.frames;
		spr.scrollFactor.x = 0;
		spr.antialiasing = this.antialiasing;
		spr.active = false;

		var col:String = Note.colArray[noteData % Note.colArray.length];

		if(!PlayState.isPixelStage)
		{
			if(isEnd)
			{
				spr.animation.addByPrefix('piece', col + ' hold end', 24, true);

				// The original .FLA shipped with 'pruple end hold' in it and every skin since
				// has copied the typo, so purple has to be asked for twice.
				if(spr.animation.getByName('piece') == null)
					spr.animation.addByPrefix('piece', 'pruple end hold', 24, true);
			}
			else spr.animation.addByPrefix('piece', col + ' hold piece', 24, true);
		}
		else
		{
			var d:Int = noteData % Note.colArray.length;
			spr.animation.add('piece', [isEnd ? d + 4 : d], 24, true);
		}

		spr.animation.play('piece', true);
		spr.updateHitbox();

		// Every direction is the same greyscale art tinted by a palette, so the colour comes
		// from the note's shader rather than from the frame.
		spr.shader = this.shader;
		return spr;
	}

	/** World Y of the far end of the hold, for hit-testing the resize handle. */
	public function sustainTailY():Float
		return y + height / 2 + sustainPixelLength;

	override function draw()
	{
		if(selected)
		{
			// Behind everything else the note draws, and squared to the cell rather than to
			// the sprite, so a ring round a hold and a ring round a tap are the same size.
			var ring:FlxSprite = getRing();
			ring.x = this.x + this.width / 2 - ring.width / 2;
			ring.y = this.y + this.height / 2 - ring.height / 2;
			ring.angle = this.angle;
			ring.color = 0xFF33E1FF;
			ring.alpha = this.alpha;
			ring.draw();
		}

		if(sustainBody != null && sustainBody.exists && sustainLength > 0)
		{
			var midX:Float = this.x + this.width / 2;
			var top:Float = this.y + this.height / 2;

			// Read once. Setting clipRect replaces the frame, and frameWidth and frameHeight
			// with it, so anything measured after the first clip is measuring the clip.
			var frameW:Int = sustainBody.frameWidth;
			var frameH:Int = sustainBody.frameHeight;
			var tileW:Float = frameW * sustainBody.scale.x;
			var tileH:Float = frameH * sustainBody.scale.y;

			var capH:Float = sustainEnd.frameHeight * sustainEnd.scale.y;
			var bodyLength:Float = Math.max(0, sustainPixelLength - capH);

			sustainBody.alpha = this.alpha;
			sustainBody.x = midX - tileW / 2;

			var drawn:Float = 0;
			while(tileH > 0 && drawn < bodyLength)
			{
				var remain:Float = bodyLength - drawn;

				// The last tile is cut off rather than squashed, so every repeat down the
				// hold is the same size as the one above it.
				if(remain < tileH)
					sustainBody.clipRect = new Rectangle(0, 0, frameW, frameH * (remain / tileH));

				sustainBody.y = top + drawn;
				sustainBody.draw();
				drawn += tileH;
			}
			sustainBody.clipRect = null;

			sustainEnd.alpha = this.alpha;
			sustainEnd.x = midX - (sustainEnd.frameWidth * sustainEnd.scale.x) / 2;
			sustainEnd.y = top + bodyLength;
			sustainEnd.draw();
		}
		super.draw();

		if(_noteTypeText != null && _noteTypeText.exists && _noteTypeText.visible)
		{
			_noteTypeText.x = this.x + this.width/2 - _noteTypeText.width/2;
			_noteTypeText.y = this.y + this.height/2 - _noteTypeText.height/2;
			_noteTypeText.alpha = this.alpha;
			_noteTypeText.draw();
		}
	}

	override function destroy()
	{
		sustainBody = FlxDestroyUtil.destroy(sustainBody);
		sustainEnd = FlxDestroyUtil.destroy(sustainEnd);
		super.destroy();
	}
}

class EventMetaNote extends MetaNote
{
	public var eventText:FlxText;
	public function new(time:Float, eventData:Dynamic)
	{
		super(time, -1, eventData);
		this.isEvent = true;
		events = eventData[1];
		//trace('events: $events');
		
		loadGraphic(Paths.image('editors/eventIcon'));
		setGraphicSize(ChartingState.GRID_SIZE);
		updateHitbox();

		eventText = new FlxText(0, 0, 400, '', 12);
		eventText.setFormat(Paths.font('vcr.ttf'), 12, FlxColor.WHITE, RIGHT);
		eventText.scrollFactor.x = 0;
		updateEventText();
	}
	
	override function draw()
	{
		if(tweenSprite != null && tweenSprite.exists && tweenSprite.visible)
		{
			tweenSprite.x = this.x + this.width/2 - tweenSprite.width/2;
			tweenSprite.y = this.y + this.height/2;
			tweenSprite.alpha = this.alpha * 0.9;
			tweenSprite.draw();
		}

		if(eventText != null && eventText.exists && eventText.visible)
		{
			eventText.y = this.y + this.height/2 - eventText.height/2;
			eventText.alpha = this.alpha;
			eventText.draw();
		}
		super.draw();
	}

	override function setSustainLength(v:Float, stepCrochet:Float, zoom:Float = 1) {}

	//
	// Camera event tween preview.
	//
	// Camera events say "move to here over four steps, easing out" and until now the only way to
	// find out what that looked like was to play the song. This hangs the ease curve off the event
	// in the chart grid, running down the same four steps it will actually take: time goes down the
	// column, the curve's horizontal position is how far through the move you are. Linear is a
	// diagonal, quadOut leans early, back and elastic visibly overshoot the edges.
	//
	// Both the shape and the length come from CameraEvents, the same parse gameplay runs, so the
	// picture can't drift away from what the song does.
	//

	/** Rendered once per ease and scaled per event, so the cache stays one entry per curve. */
	static final CURVE_WIDTH:Int = 48;
	static final CURVE_HEIGHT:Int = 192;
	/** Side room so an overshooting ease has somewhere to overshoot into. */
	static final CURVE_MARGIN:Int = 6;

	static function getCurveGraphic(ease:String, easeFunction:Float->Float):FlxGraphic
	{
		var key:String = 'chartCameraEase|$ease';
		if(FlxG.bitmap.checkCache(key)) return FlxG.bitmap.get(key);

		// Faint fill behind the curve, so the span the tween covers reads even where the line is
		// near-vertical.
		var bitmap:BitmapData = new BitmapData(CURVE_WIDTH, CURVE_HEIGHT, true, 0x18FFFFFF);
		var span:Float = CURVE_WIDTH - 1 - CURVE_MARGIN * 2;
		var previousX:Int = -1;

		for (row in 0...CURVE_HEIGHT)
		{
			var progress:Float = row / (CURVE_HEIGHT - 1);
			var value:Float = easeFunction(progress);

			var col:Int = Math.round(CURVE_MARGIN + value * span);
			if(col < 0) col = 0;
			else if(col > CURVE_WIDTH - 1) col = CURVE_WIDTH - 1;

			// Join to the previous sample. A steep ease moves several pixels sideways per row, and
			// without this it draws as a dotted line rather than a curve.
			var from:Int = (previousX < 0) ? col : previousX;
			var lo:Int = Std.int(Math.min(from, col));
			var hi:Int = Std.int(Math.max(from, col));
			for (x in lo...hi + 1) bitmap.setPixel32(x, row, FlxColor.WHITE);

			// Two pixels wide, since this gets scaled down to the width of one grid column.
			if(col < CURVE_WIDTH - 1) bitmap.setPixel32(col + 1, row, FlxColor.WHITE);
			previousX = col;
		}

		var graphic:FlxGraphic = FlxG.bitmap.add(bitmap, false, key);
		graphic.persist = true;
		graphic.destroyOnNoUse = false;
		return graphic;
	}

	public var tweenSprite:FlxSprite;
	var _tweenZoom:Float = 1;

	/** The first camera event on this note, or null if it carries none. */
	function findCameraEvent():Array<String>
	{
		for (event in events)
			if(event != null && event[0] != null && CameraEvents.hasTweenPreview(event[0])) return event;
		return null;
	}

	public function updateTweenPreview(zoom:Float = 1)
	{
		_tweenZoom = zoom;

		var event:Array<String> = findCameraEvent();
		if(event == null)
		{
			if(tweenSprite != null) tweenSprite.visible = false;
			return;
		}

		// Nothing to draw for an instant or classic move - there is no curve, it just happens.
		var tween = CameraEvents.parseTween(event[2]);
		if(tween.duration <= 0)
		{
			if(tweenSprite != null) tweenSprite.visible = false;
			return;
		}

		if(tweenSprite == null)
		{
			tweenSprite = new FlxSprite();
			tweenSprite.scrollFactor.x = 0;
			tweenSprite.antialiasing = ClientPrefs.data.antialiasing;
		}
		tweenSprite.visible = true;
		// Warm for zoom, cool for focus, so a chart with both stays readable at a glance.
		tweenSprite.color = (event[0] == CameraEvents.ZOOM) ? 0xFFFFD166 : 0xFF5BC8FF;

		var graphic:FlxGraphic = getCurveGraphic(tween.ease, tween.easeFunction);
		if(tweenSprite.graphic != graphic) tweenSprite.loadGraphic(graphic);

		// One step is one grid square tall, the same conversion sustains use.
		var height:Float = Math.max(ChartingState.GRID_SIZE * 0.25, tween.duration * ChartingState.GRID_SIZE * zoom);
		tweenSprite.setGraphicSize(ChartingState.GRID_SIZE, height);
		tweenSprite.updateHitbox();
	}

	public var events:Array<Array<String>>;
	public function updateEventText()
	{
		updateTweenPreview(_tweenZoom);

		var myTime:Float = Math.floor(this.strumTime);
		if(events.length == 1)
		{
			var event = events[0];
			eventText.text = 'Event: ${event[0]} ($myTime ms)\nValue 1: ${event[1]}\nValue 2: ${event[2]}';
			if(CameraEvents.isCameraEvent(event[0]))
				eventText.text += '\n${CameraEvents.describe(event[0], event[1], event[2])}';
		}
		else if(events.length > 1)
		{
			var eventNames:Array<String> = [for (event in events) event[0]];
			eventText.text = '${events.length} Events ($myTime ms):\n${eventNames.join(', ')}';
		}
		else eventText.text = 'ERROR FAILSAFE';
	}

	override function destroy()
	{
		eventText = FlxDestroyUtil.destroy(eventText);
		tweenSprite = FlxDestroyUtil.destroy(tweenSprite);
		super.destroy();
	}
}
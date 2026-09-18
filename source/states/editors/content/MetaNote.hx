package states.editors.content;

import objects.Note;
import shaders.RGBPalette;
import flixel.util.FlxDestroyUtil;
import flixel.graphics.FlxGraphic;
import openfl.display.BitmapData;

class MetaNote extends Note
{
	public static var noteTypeTexts:Map<Int, FlxText> = [];
	public var isEvent:Bool = false;
	public var songData:Array<Dynamic>;
	public var sustainSprite:FlxSprite;
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
	}

	public function setStrumTime(v:Float)
	{
		this.songData[0] = v;
		this.strumTime = v;
	}

	var _lastZoom:Float = -1;
	public function setSustainLength(v:Float, stepCrochet:Float, zoom:Float = 1)
	{
		_lastZoom = zoom;
		v = Math.round(v / (stepCrochet / 2)) * (stepCrochet / 2);
		songData[2] = sustainLength = Math.max(Math.min(v, stepCrochet * 128), 0);

		if(sustainLength > 0)
		{
			if(sustainSprite == null)
			{
				sustainSprite = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
				sustainSprite.scrollFactor.x = 0;
			}
			sustainSprite.setGraphicSize(8, Math.max(ChartingState.GRID_SIZE/4, (Math.round((v * ChartingState.GRID_SIZE + ChartingState.GRID_SIZE) / stepCrochet) * zoom) - ChartingState.GRID_SIZE/2));
			sustainSprite.updateHitbox();
		}
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

	override function draw()
	{
		if(sustainSprite != null && sustainSprite.exists && sustainSprite.visible && sustainLength > 0)
		{
			sustainSprite.x = this.x + this.width/2 - sustainSprite.width/2;
			sustainSprite.y = this.y + this.height/2;
			sustainSprite.alpha = this.alpha;
			sustainSprite.draw();
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
		sustainSprite = FlxDestroyUtil.destroy(sustainSprite);
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
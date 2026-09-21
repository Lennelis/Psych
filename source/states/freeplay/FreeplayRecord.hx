package states.freeplay;

import backend.WeekData;
import states.freeplay.OutlineText.OutlineFitMode;
import states.freeplay.VSliceFreeplayState.ExitMoverData;

/**
 * The spinning record in the bottom right of freeplay, with the week's name under it.
 *
 * It stands where V-Slice's album roll does and does the same job - say what you are looking
 * at - with the things Psych actually has. Psych has no album metadata, so every song would
 * have shown the same Volume 1 cover; it does have a week per song and a colour per song, and
 * a record whose label takes that colour says more than one cover repeated down the list.
 *
 * The label is a second sprite sitting on the record rather than a recolour of it, so changing
 * song is one `color` assignment instead of a pass over the pixels. The artwork was cut into
 * the two pieces for exactly that.
 *
 * The name is set in Letterstuff, which is an outline face - see `OutlineText` for how it gets
 * filled in, and for the fitting, which a week name badly needs: they run from `PICO` to
 * `hating simulator ft. moawling`.
 */
class FreeplayRecord extends FlxSpriteGroup
{
	public var record:FlxSprite;
	public var label:FlxSprite;
	public var weekName:OutlineText;

	public var settings(default, null):RecordSettings;

	/** Where the record sits, in the 1280x720 the menu is laid out for. */
	var centreX:Float;

	var centreY:Float;

	public function new()
	{
		super();

		settings = readSettings();

		// Held at the same distance from the right edge on a wider screen, which is what the
		// rest of the right hand furniture does - the score, the completion box, the album it
		// replaces. Measuring from the left instead would leave it stranded in the middle.
		centreX = FlxG.width - (1280 - settings.centreX);
		centreY = settings.recordY;

		record = new FlxSprite().loadGraphic(Paths.image('freeplay/vinylRecord'));
		label = new FlxSprite().loadGraphic(Paths.image('freeplay/vinylLabel'));

		for (piece in [record, label])
		{
			piece.setGraphicSize(settings.recordSize, settings.recordSize);
			piece.updateHitbox();
			piece.setPosition(centreX - piece.width / 2, centreY - piece.height / 2);
			piece.antialiasing = ClientPrefs.data.antialiasing;
			piece.visible = settings.showRecord;
		}

		weekName = new OutlineText(Paths.font('Letterstuff.ttf'), {
			mode: settings.mode,
			budget: settings.budget,
			size: settings.size,
			floorSize: settings.floorSize,
			linePercent: settings.linePercent,
			outlineWeight: settings.outlineWeight,
			fill: settings.fill,
			outline: settings.outline
		});
		weekName.visible = false;

		add(record);
		add(label);
		add(weekName);

		visible = false;
	}

	/**
	 * Points the record at a song: its week's name, and its colour on the label.
	 *
	 * A null song empties it rather than leaving the last one showing, which is what happens
	 * on an empty search.
	 */
	public function setSong(song:FreeplaySongData):Void
	{
		if (song == null)
		{
			weekName.setText('');
			return;
		}

		weekName.setText(storyNameFor(song));
		place();

		var color:FlxColor = song.color;
		label.color = color;

		// White leaves the fill as drawn; the song colour multiplies the white through to the
		// colour and leaves the black outline where it is, so no bitmap has to be rebuilt.
		weekName.color = settings.fillTakesSongColor ? color : FlxColor.WHITE;
	}

	/**
	 * Centres the name under the record, which has to happen again whenever it rewraps.
	 *
	 * Offset by the group's own position rather than set outright: a sprite group keeps its
	 * members in screen coordinates and `x` is the offset already folded into them, so writing
	 * a bare position mid-slide would lose that offset and the tween would then take it off the
	 * left of the screen on the way to settling.
	 */
	function place():Void
	{
		weekName.x = x + centreX - weekName.width / 2;
		weekName.y = y + (centreY + settings.gapUnderRecord) - weekName.height / 2;
	}

	/**
	 * The week's display name, the same one the story menu shows.
	 *
	 * Through `Language` so a translated week reads translated here too, and falling back to
	 * the week's own file name so a week that never set a story name still says something.
	 */
	static function storyNameFor(song:FreeplaySongData):String
	{
		if (song.levelName == null) return '';

		var week:WeekData = WeekData.weeksLoaded.get(song.levelName);
		if (week == null) return song.levelName;

		var name:String = Language.getPhrase('storyname_${week.fileName}', week.storyName);
		return (name != null && name.trim().length > 0) ? name : song.levelName;
	}

	/** Slides in from off the right, the way it leaves. */
	public function playIntro():Void
	{
		visible = true;
		weekName.visible = true;

		x = FlxG.width;
		FlxTween.cancelTweensOf(this);
		FlxTween.tween(this, {x: 0}, 0.6, {ease: FlxEase.quartOut});
	}

	public function skipIntro():Void
	{
		visible = true;
		weekName.visible = true;

		FlxTween.cancelTweensOf(this);
		x = 0;
	}

	public function applyExitMovers(?exitMovers:ExitMoverData):Void
	{
		if (exitMovers == null) return;

		exitMovers.set([record, label, weekName], {x: FlxG.width, speed: 0.4, wait: 0});
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (!settings.showRecord || settings.spinRpm == 0) return;

		// Both pieces turn about their own centres, which `updateHitbox` put the origin at,
		// and they are concentric and the same size - so one angle keeps them together.
		record.angle += settings.spinRpm * 6 * elapsed; // rpm to degrees a second
		label.angle = record.angle;
	}

	// -----------------------------------------------------------------------------------------
	// Configuration
	// -----------------------------------------------------------------------------------------

	/**
	 * Read fresh every time the menu is built, so `images/freeplay/record.json` can be edited
	 * and the change seen by backing out of freeplay and going back in - the same deal as the
	 * background and the album nudges.
	 */
	static function readSettings():RecordSettings
	{
		var loaded:RecordSettings = {
			mode: WRAP_THEN_SHRINK, budget: 315, size: 62, floorSize: 30, linePercent: 0.92,
			outlineWeight: 1, fill: FlxColor.WHITE, outline: FlxColor.BLACK, fillTakesSongColor: false,
			centreX: 1062, recordY: 360, gapUnderRecord: 176, recordSize: 300, showRecord: true, spinRpm: 14
		};

		try
		{
			var raw:String = Paths.getTextFromFile('images/freeplay/record.json');
			if (raw == null || raw.length < 1) return loaded;

			var parsed:Dynamic = haxe.Json.parse(raw);

			function number(name:String, fallback:Float):Float
			{
				var value:Dynamic = Reflect.field(parsed, name);
				if (value == null) return fallback;

				var asFloat:Float = cast value;
				return Math.isNaN(asFloat) ? fallback : asFloat;
			}
			function flag(name:String, fallback:Bool):Bool
			{
				var value:Dynamic = Reflect.field(parsed, name);
				return (value == null) ? fallback : value == true;
			}
			function text(name:String, fallback:String):String
			{
				var value:Dynamic = Reflect.field(parsed, name);
				return (value == null) ? fallback : Std.string(value);
			}

			loaded.mode = switch (text('fitMode', 'wrapThenShrink').toLowerCase())
			{
				case 'overflow' | 'none': OVERFLOW;
				case 'shrink': SHRINK;
				case 'wrap': WRAP;
				default: WRAP_THEN_SHRINK;
			};

			loaded.budget = number('widthBudget', loaded.budget);
			loaded.size = Std.int(number('size', loaded.size));
			loaded.floorSize = Std.int(number('shrinkFloor', loaded.floorSize));

			// Written as a percentage in the file because that is how it was tuned; the text
			// wants it as a share of the size.
			loaded.linePercent = number('linePercent', loaded.linePercent * 100) / 100;
			loaded.outlineWeight = number('outlineWeight', loaded.outlineWeight * 100) / 100;

			// Shared with the background's reader: the freeplay files all write colours the
			// same way, and FlxColor.fromString cannot be used for any of them.
			loaded.fill = FreeplayBackdrop.parseColor(text('fill', null), loaded.fill);
			loaded.outline = FreeplayBackdrop.parseColor(text('outline', null), loaded.outline);
			loaded.fillTakesSongColor = flag('fillTakesSongColor', loaded.fillTakesSongColor);

			loaded.centreX = number('centreX', loaded.centreX);
			loaded.recordY = number('recordY', loaded.recordY);
			loaded.gapUnderRecord = number('gapUnderRecord', loaded.gapUnderRecord);
			loaded.recordSize = number('recordSize', loaded.recordSize);
			loaded.showRecord = flag('showRecord', loaded.showRecord);
			loaded.spinRpm = number('spinRpm', loaded.spinRpm);
		}
		catch (e:Dynamic)
			trace('FreeplayRecord: could not read record.json ($e)');

		return loaded;
	}
}

/** What `images/freeplay/record.json` is allowed to change. */
typedef RecordSettings =
{
	var mode:OutlineFitMode;
	var budget:Float;
	var size:Int;
	var floorSize:Int;
	var linePercent:Float;
	var outlineWeight:Float;
	var fill:FlxColor;
	var outline:FlxColor;
	var fillTakesSongColor:Bool;

	var centreX:Float;
	var recordY:Float;
	var gapUnderRecord:Float;
	var recordSize:Float;
	var showRecord:Bool;
	var spinRpm:Float;
}

package options;

import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText.FlxTextBorderStyle;

/**
 * Measures how far behind the sound is, by asking the player to tap along to it.
 *
 * Android holds a buffer of audio the player has not heard yet, so what is coming out of the
 * speaker is a few tens of milliseconds behind what the engine thinks is playing. Nothing on the
 * device reports how far behind, and neither the audio backend nor the OS offers a number worth
 * trusting - V-Slice does not try either. What it does instead is what this does: play a steady
 * beat, have the player tap it, and take the delay from how late their taps land.
 *
 * The taps are not the measurement on their own - a person is not accurate to the millisecond and
 * some of them are just bad. What is wanted is the middle of the distribution, so the worst
 * quarter of the taps is dropped before averaging, which throws out the fumbles without letting a
 * player's own consistent rush or drag be thrown out with them.
 *
 * Psych's own delay setting is nudged a millisecond at a time against a metronome, which measures
 * the same thing but asks the player to judge it by ear. This asks their hands.
 */
class CalibrationState extends MusicBeatState
{
	/** The tempo `offsetSong` is written at - the same one `NoteOffsetState` sets for it. */
	static inline var SONG_BPM:Float = 128.0;

	/** How many taps to take before offering a result. */
	static inline var TAPS_WANTED:Int = 16;

	/** The share of the taps, worst first, thrown away before averaging. */
	static inline var DISCARD_SHARE:Float = 0.25;

	/** Beats of pulse given before any tap counts, so the player has the tempo first. */
	static inline var LEAD_IN_BEATS:Int = 4;

	/** How long a marker is on screen before it lands, in beats. */
	static inline var LEAD_BEATS:Float = 2.0;

	/** How far a marker falls in that time. */
	static inline var FALL:Float = 420.0;

	static inline var LINE_Y:Float = 520.0;

	/** A tap further than this from any beat is a miss rather than a reading. */
	static inline var STRAY_MS:Float = 260.0;

	var savedOffset:Int = 0;
	var taps:Array<Float> = [];
	var nextBeat:Int = 0;
	var finished:Bool = false;

	var markers:FlxTypedGroup<FlxSprite>;
	var line:FlxSprite;
	var glow:FlxSprite;

	var headline:FlxText;
	var readout:FlxText;
	var hint:FlxText;

	override public function create():Void
	{
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Calibrating Offset", null);
		#end

		persistentUpdate = true;

		// Held rather than read back later, and zeroed while calibrating, so the beat the player
		// is tapping is the raw one. Measuring through the correction already applied would fold
		// it in twice. V-Slice's offset menu does the same before it starts counting.
		savedOffset = ClientPrefs.data.noteOffset;
		ClientPrefs.data.noteOffset = 0;

		var bg:FlxSprite = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		bg.scale.set(FlxG.width, FlxG.height);
		bg.updateHitbox();
		bg.color = 0xFF17141F;
		bg.scrollFactor.set();
		add(bg);

		line = new FlxSprite(0, LINE_Y).makeGraphic(1, 1, FlxColor.WHITE);
		line.scale.set(FlxG.width, 4);
		line.updateHitbox();
		line.alpha = 0.45;
		line.scrollFactor.set();
		add(line);

		// Flashes on the beat, so the eye has the same thing to follow as the ear.
		glow = new FlxSprite(0, LINE_Y - 3).makeGraphic(1, 1, FlxColor.WHITE);
		glow.scale.set(FlxG.width, 10);
		glow.updateHitbox();
		glow.alpha = 0;
		glow.scrollFactor.set();
		add(glow);

		markers = new FlxTypedGroup<FlxSprite>();
		add(markers);

		headline = makeText(0, 60, 48, 'TAP ON THE BEAT');
		readout = makeText(0, LINE_Y + 70, 40, '');
		hint = makeText(0, FlxG.height - 90, 26, 'Tap anywhere, or hit a note key.   BACK to give up.');
		hint.alpha = 0.7;

		Conductor.bpm = SONG_BPM;
		FlxG.sound.playMusic(Paths.music('offsetSong'), 1, true);
		Conductor.songPosition = 0;

		// The first beats go by untapped, to give the player the pulse before it counts.
		nextBeat = LEAD_IN_BEATS;

		#if TOUCH_CONTROLS_ALLOWED
		addVirtualPad(NONE, B);
		#end

		super.create();
		refreshReadout();
	}

	function makeText(x:Float, y:Float, size:Int, content:String):FlxText
	{
		var text:FlxText = new FlxText(x, y, FlxG.width, content, size);
		text.setFormat(Paths.font("vcr.ttf"), size, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		text.scrollFactor.set();
		add(text);
		return text;
	}

	override public function update(elapsed:Float):Void
	{
		if (FlxG.sound.music != null) Conductor.songPosition = FlxG.sound.music.time;

		spawnMarkers();
		placeMarkers();

		glow.alpha = Math.max(0, glow.alpha - elapsed * 4);

		if (controls.BACK)
		{
			leave(false);
			return;
		}

		if (finished)
		{
			if (controls.ACCEPT) leave(true);
			else if (controls.RESET) restart();
		}
		else if (tapped())
		{
			takeTap();
		}

		super.update(elapsed);
	}

	/** True on the frame a note key, the accept key, or a finger lands. */
	function tapped():Bool
	{
		if (controls.NOTE_LEFT_P || controls.NOTE_DOWN_P || controls.NOTE_UP_P || controls.NOTE_RIGHT_P || controls.ACCEPT) return true;

		#if TOUCH_CONTROLS_ALLOWED
		// Anywhere but the back button, which is a live touch button and excluded for us.
		if (TouchUtil.justPressedOutsideButtons()) return true;
		#end

		return false;
	}

	function takeTap():Void
	{
		final beat:Float = Math.round(Conductor.songPosition / Conductor.crochet);
		final error:Float = Conductor.songPosition - beat * Conductor.crochet;

		glow.alpha = 1;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);

		// Nothing counts until the markers are flowing - a tap during the count-in is the player
		// finding the pulse, not telling us anything about the delay.
		if (beat < LEAD_IN_BEATS)
		{
			readout.text = 'GET READY';
			return;
		}

		// A tap nowhere near a beat says nothing about the delay, so it is not counted - but it
		// is not silently swallowed either, or a player mashing would wonder why nothing moved.
		if (Math.abs(error) > STRAY_MS)
		{
			readout.text = 'MISSED THE BEAT';
			return;
		}

		taps.push(error);
		if (taps.length >= TAPS_WANTED) finished = true;

		refreshReadout();
	}

	/**
	 * The offset the taps point at.
	 *
	 * Sorted by how far each tap is from the middle and the worst quarter dropped, so a fumble
	 * does not drag the answer with it. The middle is taken before any of them are dropped, so a
	 * player who is consistently early keeps that - it is the scatter being trimmed, not the bias.
	 */
	function measured():Int
	{
		if (taps.length == 0) return 0;

		var sorted:Array<Float> = taps.copy();
		sorted.sort(function(a:Float, b:Float):Int return (a < b) ? -1 : (a > b) ? 1 : 0);

		final middle:Float = sorted[Std.int(sorted.length / 2)];
		sorted.sort(function(a:Float, b:Float):Int
		{
			final da:Float = Math.abs(a - middle);
			final db:Float = Math.abs(b - middle);
			return (da < db) ? -1 : (da > db) ? 1 : 0;
		});

		final keep:Int = Std.int(Math.max(1, Math.ceil(sorted.length * (1 - DISCARD_SHARE))));

		var total:Float = 0;
		for (i in 0...keep)
			total += sorted[i];

		return Math.round(total / keep);
	}

	function refreshReadout():Void
	{
		if (finished)
		{
			final value:Int = measured();
			headline.text = 'DELAY: ' + (value >= 0 ? '+' : '') + value + ' MS';
			readout.text = 'Was ' + savedOffset + ' ms.';
			hint.text = 'ACCEPT to keep it.   RESET to measure again.   BACK to leave it alone.';
			return;
		}

		readout.text = taps.length + ' / ' + TAPS_WANTED;
	}

	function restart():Void
	{
		taps = [];
		finished = false;
		headline.text = 'TAP ON THE BEAT';
		hint.text = 'Tap anywhere, or hit a note key.   BACK to give up.';
		refreshReadout();
	}

	/**
	 * Puts markers out far enough ahead that they are already falling when they matter.
	 *
	 * Driven off the song position rather than `beatHit`, because a dropped frame skips a beat
	 * callback and would leave a hole in the run of markers - the one thing the player is meant
	 * to be able to rely on here.
	 */
	function spawnMarkers():Void
	{
		if (Conductor.crochet <= 0) return; // a zero beat length would spawn markers forever

		final lead:Float = Conductor.crochet * LEAD_BEATS;
		final beatNow:Int = Math.floor(Conductor.songPosition / Conductor.crochet);

		// The track loops, which takes the song position back to the beginning. Left unnoticed,
		// the next marker due would be one that is now minutes away and none would ever appear
		// again - so the run is picked back up wherever the position actually is.
		if (nextBeat < beatNow || nextBeat > beatNow + Std.int(LEAD_BEATS) + LEAD_IN_BEATS)
		{
			markers.forEachAlive(function(marker:FlxSprite) marker.kill());
			nextBeat = beatNow + 1;
		}

		while (nextBeat * Conductor.crochet - Conductor.songPosition < lead)
		{
			var marker:FlxSprite = markers.recycle(FlxSprite);
			if (marker.graphic == null)
			{
				marker.makeGraphic(1, 1, FlxColor.WHITE);
				marker.scrollFactor.set();
			}

			marker.scale.set(70, 14);
			marker.updateHitbox();
			marker.x = (FlxG.width - marker.width) * 0.5;
			marker.color = FlxColor.WHITE;
			marker.alpha = 1;
			marker.ID = nextBeat;
			markers.add(marker);

			nextBeat++;
		}
	}

	function placeMarkers():Void
	{
		final lead:Float = Conductor.crochet * LEAD_BEATS;

		markers.forEachAlive(function(marker:FlxSprite)
		{
			final remaining:Float = marker.ID * Conductor.crochet - Conductor.songPosition;
			if (remaining < -Conductor.crochet)
			{
				marker.kill();
				return;
			}

			marker.y = LINE_Y - (remaining / lead) * FALL - marker.height * 0.5;
			marker.alpha = (remaining < 0) ? Math.max(0, 1 + remaining / Conductor.crochet) : 1;
		});
	}

	function leave(keep:Bool):Void
	{
		ClientPrefs.data.noteOffset = keep ? measured() : savedOffset;
		if (keep) ClientPrefs.saveSettings();

		FlxG.sound.play(Paths.sound(keep ? 'confirmMenu' : 'cancelMenu'));
		FlxG.sound.playMusic(Paths.music('freakyMenu'));
		MusicBeatState.switchState(new options.OptionsState());
	}
}

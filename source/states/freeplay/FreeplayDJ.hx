package states.freeplay;

import flixel.util.FlxSignal;
import flxanimate.PsychFlxAnimate;
import haxe.Json;

/**
 * What the DJ is doing. V-Slice's `FreeplayDJState`, minus the states that belong to
 * things this port hasn't got - the results screen's fist pump and character select.
 */
enum FreeplayDJState
{
	/**
	 * Character enters the frame and transitions to Idle.
	 */
	Intro;

	/**
	 * Character loops in idle.
	 */
	Idle;

	/**
	 * Plays an easter egg animation after a period in Idle, then reverts to Idle.
	 */
	IdleEasterEgg;

	/**
	 * Plays an elaborate easter egg animation. Does not revert until another animation is triggered.
	 */
	Cartoon;

	/**
	 * Player has selected a song.
	 */
	Confirm;
}

/**
 * Which frame label in the atlas each of the DJ's animations lives at.
 *
 * V-Slice reads this out of `data/players/bf.json` through its player registry. Psych
 * has no such registry, so boyfriend's entry is the default here, and a mod can hand a
 * different set in when there is somewhere for it to come from.
 */
typedef FreeplayDJData =
{
	var assetPath:String;
	var intro:String;
	var idle:String;
	var confirm:String;
	var idleEasterEgg:String;
	var cartoon:String;
}

/**
 * The DJ at his decks on the left of the freeplay menu.
 *
 * Ported from V-Slice's `BaseFreeplayDJ` and `AnimateAtlasFreeplayDJ`, which are split
 * because V-Slice renders its DJs four different ways; boyfriend is an Adobe Animate
 * texture atlas, which is the only one that matters here, so the two are one class.
 *
 * The state machine and its timings are V-Slice's: he plays his intro once, loops on
 * idle, and if you leave him alone for a minute he does his AFK bit, and for two minutes
 * he goes and watches television.
 */
class FreeplayDJ extends PsychFlxAnimate
{
	public static final BOYFRIEND:FreeplayDJData = {
		assetPath: 'freeplay/freeplay-boyfriend',
		intro: 'Intro',
		idle: 'Idle',
		confirm: 'Confirm',
		idleEasterEgg: 'AFK',
		cartoon: 'Watching TV'
	};

	public var IDLE_EGG_PERIOD:Float = 60.0;
	public var IDLE_CARTOON_PERIOD:Float = 120.0;

	// Represents the sprite's current status.
	// Without state machines I would have driven myself crazy years ago.
	var currentState:FreeplayDJState = Intro;

	// A callback activated when the intro animation finishes.
	public var onIntroDone:FlxSignal = new FlxSignal();

	// A callback activated when the idle easter egg plays.
	public var onIdleEasterEgg:FlxSignal = new FlxSignal();

	var seenIdleEasterEgg:Bool = false;
	var timeIdling:Float = 0;

	final data:FreeplayDJData;

	/** flxanimate's finish signal carries no name, so the name is kept here. */
	var currentAnimation:String = null;

	/** False when the atlas wouldn't load, which leaves the menu to carry on without him. */
	public var loaded(default, null):Bool = false;

	/**
	 * The animations that actually got added, by name.
	 *
	 * Kept here rather than asked of flxanimate: which of `existsByName`, `getByName` and
	 * friends exist depends on the exact commit the engine is pinned to, and this needs
	 * none of them.
	 */
	var loadedAnimations:Map<String, Bool> = [];

	public function new(x:Float, y:Float, ?data:FreeplayDJData)
	{
		super(x, y);

		this.data = (data != null) ? data : BOYFRIEND;

		try
		{
			Paths.loadAnimateAtlas(this, this.data.assetPath);
			loaded = true;
		}
		catch (e:Dynamic)
		{
			trace('FreeplayDJ: could not load "${this.data.assetPath}" ($e)');
			return;
		}

		loadAnimations();

		// No animations means a DJ frozen on whatever frame the atlas opens at, which for
		// boyfriend is him still below the screen. Better to have no DJ than that.
		if (!loadedAnimations.exists('intro') && !loadedAnimations.exists('idle'))
		{
			trace('FreeplayDJ: no animations were loaded, leaving him out');
			loaded = false;
			return;
		}

		antialiasing = ClientPrefs.data.antialiasing;

		// One signal for both: flxanimate fires this at the end of a run whether or not
		// the animation loops, which is V-Slice hooking onFinish and onLoop together.
		anim.onComplete.add(onFinishAnim);
	}

	function loadAnimations():Void
	{
		readStageLabels();

		// Everything but the idle plays once. The idle loops, and every time round it
		// gets a chance to decide it has been idling long enough to do something else.
		addAnimation('intro', data.intro, false);
		addAnimation('idle', data.idle, true);
		addAnimation('confirm', data.confirm, false);
		addAnimation('idleEasterEgg', data.idleEasterEgg, false);
		addAnimation('cartoon', data.cartoon, false);
	}

	/** The name of the atlas's own stage symbol, and where each label sits on it. */
	var stageSymbol:String = null;

	var labelFrames:Map<String, Array<Int>> = [];

	/**
	 * The translation the atlas's stage sits at, which an added animation has to carry.
	 *
	 * This is what made him vanish once the animations started working. The atlas draws
	 * its stage through an instance holding a matrix - boyfriend's is a move of 640 by
	 * 360, half the screen he was authored on - and an animation added with
	 * `addBySymbolIndices` gets a fresh instance with an identity matrix instead, so
	 * playing one dropped that move and drew him 640 left and 360 up, off the screen.
	 * V-Slice has the same problem and answers it with its `applyStageMatrix` flag; the
	 * matrix goes straight into the animation here instead.
	 */
	var stageOffsetX:Float = 0;

	var stageOffsetY:Float = 0;

	/**
	 * Works out which frames each of the atlas's labels covers, by reading the atlas.
	 *
	 * `anim.addByFrameLabel` would do this, and it is what V-Slice uses, but it is doing
	 * the lookup through `curSymbol` and coming back with nothing here - so the DJ sat
	 * frozen on the first frame of his drop-in, which is him below the screen with only
	 * his decks showing. The animation data is a JSON file in the atlas folder either
	 * way, so this reads it and hands flxanimate the frame numbers directly.
	 *
	 * Adobe's exporter writes the same structure under two sets of key names depending
	 * on its version - `AN.TL.L[].FR[]` or `ANIMATION.TIMELINE.LAYERS[].Frames[]` - and
	 * both turn up among these assets, so both are read.
	 */
	function readStageLabels():Void
	{
		var raw:String = Paths.getTextFromFile('images/${data.assetPath}/Animation.json');
		if (raw == null || raw.length < 1) return;

		try
		{
			// The exporter writes a byte order mark, which the JSON parser won't have.
			if (raw.charCodeAt(0) == 0xFEFF) raw = raw.substr(1);

			var parsed:Dynamic = Json.parse(raw);
			var animation:Dynamic = field(parsed, 'AN', 'ANIMATION');
			if (animation == null) return;

			stageSymbol = field(animation, 'SN', 'SYMBOL_name');

			readStageMatrix(animation);

			var timeline:Dynamic = field(animation, 'TL', 'TIMELINE');
			if (timeline == null) return;

			var layers:Array<Dynamic> = cast field(timeline, 'L', 'LAYERS');
			if (layers == null) return;

			for (layer in layers)
			{
				var frames:Array<Dynamic> = cast field(layer, 'FR', 'Frames');
				if (frames == null) continue;

				for (frame in frames)
				{
					var name:String = field(frame, 'N', 'name');
					if (name == null || name.length < 1) continue;

					var index:Int = Std.int(numberOr(field(frame, 'I', 'index'), 0));
					var duration:Int = Std.int(numberOr(field(frame, 'DU', 'duration'), 1));

					labelFrames.set(name, [for (i in index...(index + Std.int(Math.max(1, duration)))) i]);
				}
			}
		}
		catch (e:Dynamic)
			trace('FreeplayDJ: could not read the labels out of the atlas ($e)');
	}

	/** Pulls the stage instance's move out of its matrix, whichever shape it was written in. */
	function readStageMatrix(animation:Dynamic):Void
	{
		var stageInstance:Dynamic = field(animation, 'STI', 'StageInstance');
		if (stageInstance == null) return;

		var symbol:Dynamic = field(stageInstance, 'SI', 'SYMBOL_Instance');
		if (symbol == null) return;

		var matrix:Array<Dynamic> = cast field(symbol, 'MX', 'Matrix3D');
		if (matrix == null) matrix = cast Reflect.field(symbol, 'M3D');
		if (matrix == null) return;

		// Two shapes turn up: a flat 2D matrix, where the move is the last two numbers,
		// and a 4x4 one, where it is the thirteenth and fourteenth.
		if (matrix.length >= 16)
		{
			stageOffsetX = numberOr(matrix[12], 0);
			stageOffsetY = numberOr(matrix[13], 0);
		}
		else if (matrix.length >= 6)
		{
			stageOffsetX = numberOr(matrix[4], 0);
			stageOffsetY = numberOr(matrix[5], 0);
		}
	}

	static function field(source:Dynamic, short:String, long:String):Dynamic
	{
		if (source == null) return null;

		var value:Dynamic = Reflect.field(source, short);
		if (value == null) value = Reflect.field(source, long);

		return value;
	}

	static function numberOr(value:Dynamic, fallback:Float):Float
	{
		if (value == null || !(Std.isOfType(value, Float) || Std.isOfType(value, Int))) return fallback;

		return cast value;
	}

	function addAnimation(name:String, frameLabel:String, looped:Bool):Void
	{
		if (frameLabel == null || frameLabel.length < 1) return;
		if (stageSymbol == null || !labelFrames.exists(frameLabel))
		{
			trace('FreeplayDJ: the atlas has no label called "$frameLabel"');
			return;
		}

		try
		{
			anim.addBySymbolIndices(name, stageSymbol, labelFrames.get(frameLabel), 24, looped, stageOffsetX, stageOffsetY);
			loadedAnimations.set(name, true);
		}
		catch (e:Dynamic)
			trace('FreeplayDJ: could not add "$name" from "$frameLabel" ($e)');
	}

	public function hasAnimation(name:String):Bool
		return loaded && loadedAnimations.exists(name);

	public function getCurrentAnimation():String
		return currentAnimation;

	public function onPlayerAction():Void
		resetAFKTimer();

	public function resetAFKTimer():Void
	{
		timeIdling = 0;
		seenIdleEasterEgg = false;
	}

	/** How much of its volume the song preview gets while he is doing something. */
	public function getMusicPreviewMult():Float
		return 1;

	public function onConfirm():Void
		currentState = Confirm;

	override public function update(elapsed:Float):Void
	{
		if (!loaded)
		{
			super.update(elapsed);
			return;
		}

		switch (currentState)
		{
			case Intro:
				// Play the intro animation then leave this state immediately.
				if (getCurrentAnimation() != 'intro') playFlashAnimation('intro', true);
				timeIdling = 0;

			case Idle:
				// We are in this state the majority of the time.
				if (getCurrentAnimation() != 'idle') playFlashAnimation('idle', true, true);
				timeIdling += elapsed;

			case Confirm:
				if (getCurrentAnimation() != 'confirm') playFlashAnimation('confirm', false);
				timeIdling = 0;

			case IdleEasterEgg:
				if (getCurrentAnimation() != 'idleEasterEgg')
				{
					onIdleEasterEgg.dispatch();
					playFlashAnimation('idleEasterEgg', false);
					seenIdleEasterEgg = true;
				}
				timeIdling = 0;

			case Cartoon:
				if (!hasAnimation('cartoon')) currentState = IdleEasterEgg;
				else
				{
					if (getCurrentAnimation() != 'cartoon') playFlashAnimation('cartoon', true);
					timeIdling = 0;
				}
		}

		// Call the superclass function AFTER updating the current state and playing the
		// next animation. This ensures that flixel-animate starts rendering it immediately.
		super.update(elapsed);
	}

	function onFinishAnim():Void
	{
		switch (currentAnimation)
		{
			case 'intro':
				currentState = Idle;
				onIntroDone.dispatch();

			case 'idle':
				if (timeIdling >= IDLE_EGG_PERIOD && !seenIdleEasterEgg) currentState = IdleEasterEgg;
				else if (timeIdling >= IDLE_CARTOON_PERIOD) currentState = Cartoon;

			case 'idleEasterEgg':
				currentState = Idle;

			default:
		}
	}

	public function playFlashAnimation(id:String, force:Bool = false, loop:Bool = false, frame:Int = 0):Void
	{
		if (!hasAnimation(id)) return;

		currentAnimation = id;
		anim.play(id, force, false, frame);
	}

	override function destroy():Void
	{
		onIntroDone.removeAll();
		onIdleEasterEgg.removeAll();
		super.destroy();
	}
}

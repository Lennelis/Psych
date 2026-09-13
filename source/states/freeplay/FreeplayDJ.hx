package states.freeplay;

import flixel.util.FlxSignal;
import flxanimate.PsychFlxAnimate;

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

		antialiasing = ClientPrefs.data.antialiasing;

		// One signal for both: flxanimate fires this at the end of a run whether or not
		// the animation loops, which is V-Slice hooking onFinish and onLoop together.
		anim.onComplete.add(onFinishAnim);
	}

	function loadAnimations():Void
	{
		// Everything but the idle plays once. The idle loops, and every time round it
		// gets a chance to decide it has been idling long enough to do something else.
		addAnimation('intro', data.intro, false);
		addAnimation('idle', data.idle, true);
		addAnimation('confirm', data.confirm, false);
		addAnimation('idleEasterEgg', data.idleEasterEgg, false);
		addAnimation('cartoon', data.cartoon, false);
	}

	function addAnimation(name:String, frameLabel:String, looped:Bool):Void
	{
		if (frameLabel == null || frameLabel.length < 1) return;

		try
		{
			anim.addByFrameLabel(name, frameLabel, 24, looped);
		}
		catch (e:Dynamic)
			trace('FreeplayDJ: no frame label "$frameLabel" for "$name" ($e)');
	}

	public function hasAnimation(name:String):Bool
		return loaded && anim != null && anim.existsByName(name);

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

package backend;

import flixel.FlxSubState;

#if TOUCH_CONTROLS_ALLOWED
import mobile.objects.VirtualPad;
import mobile.objects.VirtualPad.VirtualPadAction;
import mobile.objects.VirtualPad.VirtualPadDPad;
#end

class MusicBeatSubstate extends FlxSubState
{
	public function new()
	{
		super();
	}

	private var curSection:Int = 0;
	private var stepsToDo:Int = 0;

	private var lastBeat:Float = 0;
	private var lastStep:Float = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;

	private var curDecStep:Float = 0;
	private var curDecBeat:Float = 0;
	private var controls(get, never):Controls;

	inline function get_controls():Controls
		return Controls.instance;

	#if TOUCH_CONTROLS_ALLOWED
	public var virtualPad:VirtualPad;
	public var virtualPadCamera:FlxCamera;

	/** Set when we hid the controls belonging to the state underneath, so we know to put them back. */
	var hidStatePad:Bool = false;

	/**
	 * Gives this substate its own pad, hiding the controls belonging to the state
	 * underneath so two sets can't stack up on screen.
	 */
	public function addVirtualPad(dPad:VirtualPadDPad = FULL, action:VirtualPadAction = A_B):VirtualPad
	{
		removeVirtualPad();

		final state:MusicBeatState = Std.isOfType(FlxG.state, MusicBeatState) ? cast FlxG.state : null;
		if (state != null && state.touchControlsShowing)
		{
			state.showTouchControls(false);
			hidStatePad = true;
		}

		virtualPad = new VirtualPad(dPad, action);
		// Buttons are hit-tested against the camera they say they are on, and a button
		// that names none is tested against the game camera - which during a song is
		// zoomed and scrolled somewhere else entirely, so taps landed a hundred pixels
		// from where the pad was drawn. Naming the camera it is drawn through keeps the
		// two in step. FlxSpriteGroup passes this down to every button.
		virtualPad.cameras = [camera];
		add(virtualPad);
		return virtualPad;
	}

	public function addVirtualPadCamera(defaultDrawTarget:Bool = false):FlxCamera
	{
		if (virtualPad == null) return null;

		virtualPadCamera = new FlxCamera();
		virtualPadCamera.bgColor.alpha = 0;
		FlxG.cameras.add(virtualPadCamera, defaultDrawTarget);
		virtualPad.cameras = [virtualPadCamera];
		return virtualPadCamera;
	}

	public function removeVirtualPad():Void
	{
		if (virtualPad != null)
		{
			remove(virtualPad, true);
			virtualPad.destroy();
			virtualPad = null;
		}

		if (virtualPadCamera != null)
		{
			FlxG.cameras.remove(virtualPadCamera, true);
			virtualPadCamera = null;
		}

		if (hidStatePad)
		{
			hidStatePad = false;
			final state:MusicBeatState = Std.isOfType(FlxG.state, MusicBeatState) ? cast FlxG.state : null;
			if (state != null) state.showTouchControls(true);
		}
	}

	/**
	 * Keeps the pad on whatever camera this substate ends up on.
	 *
	 * A pad is pinned to a camera by name, because a button is hit-tested against the camera
	 * it claims rather than against wherever it is drawn. The name is taken when the pad is
	 * made - and Psych's substates build themselves in their constructors, so that happens
	 * before the state that opened one has had a chance to say which camera it wants it on.
	 * The pad kept the default draw target it was born with while the rest of the substate
	 * moved, and a state that draws over that target - freeplay's backdrop covers the screen -
	 * then buried it: invisible, but still updating and still answering taps where it lay.
	 *
	 * A pad on a camera of its own asked for that camera, so it is left alone.
	 */
	override function set_cameras(value:Array<FlxCamera>):Array<FlxCamera>
	{
		super.set_cameras(value);

		if (virtualPad != null && virtualPadCamera == null) virtualPad.cameras = value;

		return value;
	}

	override function destroy():Void
	{
		removeVirtualPad();
		super.destroy();
	}
	#end

	override function update(elapsed:Float)
	{
		//everyStep();
		if(!persistentUpdate) MusicBeatState.timePassedOnState += elapsed;
		var oldStep:Int = curStep;

		updateCurStep();
		updateBeat();

		if (oldStep != curStep)
		{
			if(curStep > 0)
				stepHit();

			if(PlayState.SONG != null)
			{
				if (oldStep < curStep)
					updateSection();
				else
					rollbackSection();
			}
		}

		super.update(elapsed);
	}

	private function updateSection():Void
	{
		if(stepsToDo < 1) stepsToDo = Math.round(getBeatsOnSection() * 4);
		while(curStep >= stepsToDo)
		{
			curSection++;
			var beats:Float = getBeatsOnSection();
			stepsToDo += Math.round(beats * 4);
			sectionHit();
		}
	}

	private function rollbackSection():Void
	{
		if(curStep < 0) return;

		var lastSection:Int = curSection;
		curSection = 0;
		stepsToDo = 0;
		for (i in 0...PlayState.SONG.notes.length)
		{
			if (PlayState.SONG.notes[i] != null)
			{
				stepsToDo += Math.round(getBeatsOnSection() * 4);
				if(stepsToDo > curStep) break;
				
				curSection++;
			}
		}

		if(curSection > lastSection) sectionHit();
	}

	private function updateBeat():Void
	{
		curBeat = Math.floor(curStep / 4);
		curDecBeat = curDecStep/4;
	}

	private function updateCurStep():Void
	{
		var lastChange = Conductor.getBPMFromSeconds(Conductor.songPosition);

		var shit = ((Conductor.songPosition - ClientPrefs.data.noteOffset) - lastChange.songTime) / lastChange.stepCrochet;
		curDecStep = lastChange.stepTime + shit;
		curStep = lastChange.stepTime + Math.floor(shit);
	}

	public function stepHit():Void
	{
		if (curStep % 4 == 0)
			beatHit();
	}

	public function beatHit():Void
	{
		//do literally nothing dumbass
	}
	
	public function sectionHit():Void
	{
		//yep, you guessed it, nothing again, dumbass
	}
	
	function getBeatsOnSection()
	{
		var val:Null<Float> = 4;
		if(PlayState.SONG != null && PlayState.SONG.notes[curSection] != null) val = PlayState.SONG.notes[curSection].sectionBeats;
		return val == null ? 4 : val;
	}
}

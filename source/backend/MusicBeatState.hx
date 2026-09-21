package backend;

import flixel.FlxState;
import flixel.FlxSubState;
import backend.PsychCamera;

#if TOUCH_CONTROLS_ALLOWED
import mobile.objects.VirtualPad;
import mobile.objects.VirtualPad.VirtualPadAction;
import mobile.objects.VirtualPad.VirtualPadDPad;
#end

class MusicBeatState extends FlxState
{
	private var curSection:Int = 0;
	private var stepsToDo:Int = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;

	private var curDecStep:Float = 0;
	private var curDecBeat:Float = 0;
	public var controls(get, never):Controls;
	private function get_controls()
	{
		return Controls.instance;
	}

	var _psychCameraInitialized:Bool = false;

	#if TOUCH_CONTROLS_ALLOWED
	/** The on-screen pad for this state, if it asked for one. */
	public var virtualPad:VirtualPad;
	public var virtualPadCamera:FlxCamera;

	/** The extra buttons this state put on screen beside the pad. */
	public var touchButtons:Array<TouchButton> = [];
	#end

	public var variables:Map<String, Dynamic> = new Map<String, Dynamic>();
	public static function getVariables()
		return getState().variables;

	override function create() {
		var skip:Bool = FlxTransitionableState.skipNextTransOut;
		#if MODS_ALLOWED Mods.updatedOnState = false; #end

		if(!_psychCameraInitialized) initPsychCamera();

		super.create();

		if(!skip) {
			openSubState(new CustomFadeTransition(0.5, true));
		}
		FlxTransitionableState.skipNextTransOut = false;
		timePassedOnState = 0;
	}

	#if TOUCH_CONTROLS_ALLOWED
	/**
	 * Gives this state an on-screen pad. The buttons carry `Controls` action names,
	 * so the state's existing `controls.UI_UP_P` / `controls.ACCEPT` checks start
	 * responding to touch with no further changes.
	 *
	 * Call it at the end of `create()`, after everything else is added, so the pad
	 * ends up on top.
	 */
	public function addVirtualPad(dPad:VirtualPadDPad = FULL, action:VirtualPadAction = A_B):VirtualPad
	{
		removeVirtualPad();

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

	/**
	 * Moves the pad onto a camera of its own.
	 *
	 * Worth doing wherever the state's camera moves - PlayState zooms and shakes it
	 * every beat, and a pad riding along with that is unusable.
	 */
	public function addVirtualPadCamera(defaultDrawTarget:Bool = false):FlxCamera
	{
		if (virtualPad == null) return null;

		virtualPadCamera = new FlxCamera();
		virtualPadCamera.bgColor.alpha = 0;
		FlxG.cameras.add(virtualPadCamera, defaultDrawTarget);
		virtualPad.cameras = [virtualPadCamera];
		return virtualPadCamera;
	}

	/**
	 * One extra on-screen button, for something a keyboard reaches with a key and a
	 * touchscreen otherwise cannot reach at all.
	 *
	 * Drawn on the pad's own camera where there is one, for the same reason the pad is:
	 * a button is hit-tested against the camera it says it is on, so one riding a camera
	 * that moves takes its taps with it.
	 */
	public function addTouchButton(label:String, x:Float, y:Float, width:Int, height:Int, onPress:Void->Void):TouchButton
	{
		var button:TouchButton = new TouchButton(x, y, [label.toLowerCase()]);
		button.setGraphic(label, width, height);
		button.antialiasing = ClientPrefs.data.antialiasing;
		button.idleAlpha = ClientPrefs.data.controlsAlpha;
		button.alpha = button.idleAlpha;
		button.onDown.add(function(_) onPress());
		button.cameras = [(virtualPadCamera != null) ? virtualPadCamera : camera];
		add(button);
		touchButtons.push(button);
		return button;
	}

	/** True while any of this state's on-screen controls are showing. */
	public var touchControlsShowing(get, never):Bool;

	function get_touchControlsShowing():Bool
	{
		if (virtualPad != null && virtualPad.visible) return true;

		for (button in touchButtons)
			if (button != null && button.visible) return true;

		return false;
	}

	/**
	 * Shows or hides everything this state put on screen, pad and extra buttons together.
	 *
	 * They go as a set because they are one set to whoever is looking at them. Hiding the pad
	 * on its own used to leave the extra buttons behind - drawn on the pad's camera, which is
	 * the last one added and so sits over everything a substate puts up, and dead to the touch
	 * because the state underneath has stopped updating.
	 *
	 * Fingers are dropped on the way either way: the tap that opened a substate must not still
	 * be on a button when the state comes back, or it reads as a press nobody made.
	 */
	public function showTouchControls(show:Bool):Void
	{
		if (virtualPad != null)
		{
			virtualPad.releaseAll();
			virtualPad.visible = show;
			virtualPad.active = show;
		}

		for (button in touchButtons)
		{
			if (button == null) continue;

			button.release();
			button.visible = show;
			button.active = show;
		}
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
	}
	#end

	override function openSubState(SubState:FlxSubState):Void
	{
		#if TOUCH_CONTROLS_ALLOWED
		// the tap that opened the substate shouldn't also be read by the substate
		if (virtualPad != null) virtualPad.releaseAll();
		for (button in touchButtons)
			if (button != null) button.release();
		#end
		super.openSubState(SubState);
	}

	override function closeSubState():Void
	{
		#if TOUCH_CONTROLS_ALLOWED
		showTouchControls(true);
		#end
		super.closeSubState();
	}

	override function destroy():Void
	{
		#if TOUCH_CONTROLS_ALLOWED
		removeVirtualPad();
		touchButtons = [];
		#end
		super.destroy();
	}

	public function initPsychCamera():PsychCamera
	{
		var camera = new PsychCamera();
		FlxG.cameras.reset(camera);
		FlxG.cameras.setDefaultDrawTarget(camera, true);
		_psychCameraInitialized = true;
		//trace('initialized psych camera ' + Sys.cpuTime());
		return camera;
	}

	public static var timePassedOnState:Float = 0;
	override function update(elapsed:Float)
	{
		//everyStep();
		var oldStep:Int = curStep;
		timePassedOnState += elapsed;

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

		if(FlxG.save.data != null) FlxG.save.data.fullscreen = FlxG.fullscreen;
		
		stagesFunc(function(stage:BaseStage) {
			stage.update(elapsed);
		});

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

	public static function switchState(nextState:FlxState = null) {
		if(nextState == null) nextState = FlxG.state;
		if(nextState == FlxG.state)
		{
			resetState();
			return;
		}

		if(FlxTransitionableState.skipNextTransIn) FlxG.switchState(nextState);
		else startTransition(nextState);
		FlxTransitionableState.skipNextTransIn = false;
	}

	public static function resetState() {
		if(FlxTransitionableState.skipNextTransIn) FlxG.resetState();
		else startTransition();
		FlxTransitionableState.skipNextTransIn = false;
	}

	// Custom made Trans in
	public static function startTransition(nextState:FlxState = null)
	{
		if(nextState == null)
			nextState = FlxG.state;

		FlxG.state.openSubState(new CustomFadeTransition(0.5, false));
		if(nextState == FlxG.state)
			CustomFadeTransition.finishCallback = function() FlxG.resetState();
		else
			CustomFadeTransition.finishCallback = function() FlxG.switchState(nextState);
	}

	public static function getState():MusicBeatState {
		return cast (FlxG.state, MusicBeatState);
	}

	public function stepHit():Void
	{
		stagesFunc(function(stage:BaseStage) {
			stage.curStep = curStep;
			stage.curDecStep = curDecStep;
			stage.stepHit();
		});

		if (curStep % 4 == 0)
			beatHit();
	}

	public var stages:Array<BaseStage> = [];
	public function beatHit():Void
	{
		//trace('Beat: ' + curBeat);
		stagesFunc(function(stage:BaseStage) {
			stage.curBeat = curBeat;
			stage.curDecBeat = curDecBeat;
			stage.beatHit();
		});
	}

	public function sectionHit():Void
	{
		//trace('Section: ' + curSection + ', Beat: ' + curBeat + ', Step: ' + curStep);
		stagesFunc(function(stage:BaseStage) {
			stage.curSection = curSection;
			stage.sectionHit();
		});
	}

	function stagesFunc(func:BaseStage->Void)
	{
		for (stage in stages)
			if(stage != null && stage.exists && stage.active)
				func(stage);
	}

	function getBeatsOnSection()
	{
		var val:Null<Float> = 4;
		if(PlayState.SONG != null && PlayState.SONG.notes[curSection] != null) val = PlayState.SONG.notes[curSection].sectionBeats;
		return val == null ? 4 : val;
	}
}

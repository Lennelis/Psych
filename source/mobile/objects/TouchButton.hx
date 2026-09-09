package mobile.objects;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import flixel.util.FlxSignal.FlxTypedSignal;
import mobile.backend.TouchButtonGraphic;
import mobile.backend.TouchUtil;

/**
 * A button meant for fingers instead of a cursor.
 *
 * `FlxButton` tracks a single pointer, which makes it useless for a rhythm game:
 * you need two, three or four fingers down at once and each of them has to keep
 * holding its own button. This tracks every touch point that landed on it, so
 * holds survive other fingers being pressed and released elsewhere.
 *
 * Buttons announce themselves to `TouchButton.list`, and `Controls` walks that
 * list, which is what lets every existing menu react to touch without a single
 * line of that menu changing.
 */
class TouchButton extends FlxSprite
{
	/** Every living button. `Controls` reads this, don't mutate it from outside. */
	public static var list(default, null):Array<TouchButton> = [];

	/** Lets you drive the touch controls with a cursor when testing on desktop. */
	public static var mouseEnabled:Bool = #if mobile false #else true #end;

	static inline var MOUSE_ID:Int = -1000;

	/** Names of the `Controls` actions this button stands in for, i.e. `['ui_up']`. */
	public var actions:Array<String>;

	public var pressed(default, null):Bool = false;
	public var justPressed(default, null):Bool = false;
	public var justReleased(default, null):Bool = false;

	/** When true a finger that slides onto the button counts as a press. Wanted on note lanes, not on menu buttons. */
	public var allowSlideIn:Bool = false;

	public var idleAlpha:Float = 0.6;
	public var pressedAlpha:Float = 1;

	/** How quickly the button fades between its two alphas. Set to 0 to snap. */
	public var alphaTweenSpeed:Float = 16;

	public var onDown(default, null):FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();
	public var onUp(default, null):FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();

	/**
	 * Frame this button last ran its input check on. `Controls` ignores buttons that
	 * have gone cold, so a pad left behind by a state that stopped updating can't
	 * keep reporting a press forever.
	 */
	var lastUpdatedFrame:Int = -1;

	var heldIDs:Array<Int> = [];

	public function new(x:Float = 0, y:Float = 0, ?actions:Array<String>)
	{
		super(x, y);

		this.actions = actions == null ? [] : actions;
		scrollFactor.set();
		moves = false;
		list.push(this);
	}

	/** Gives the button its look. Call before adding it to a state. */
	public function setGraphic(symbol:String, width:Int, height:Int, color:FlxColor = FlxColor.WHITE):TouchButton
	{
		loadGraphic(TouchButtonGraphic.button(symbol, width, height, color));
		alpha = idleAlpha;
		return this;
	}

	public function setLaneGraphic(width:Int, height:Int, color:FlxColor, gradient:Bool = true):TouchButton
	{
		loadGraphic(TouchButtonGraphic.lane(width, height, color, gradient));
		alpha = idleAlpha;
		return this;
	}

	public inline function hasAction(action:String):Bool
		return actions.indexOf(action) != -1;

	/** True while the button is being updated. Stale buttons are ignored by `Controls`. */
	public var isAwake(get, never):Bool;

	inline function get_isAwake():Bool
		return exists && active && visible && (TouchUtil.frameCount - lastUpdatedFrame) <= 1;

	/**
	 * Drops every finger currently on the button without firing `onUp`.
	 * Used when a state hands control over to a substate, so the press that opened
	 * the substate can't immediately be read again by whatever opened.
	 */
	public function release():Void
	{
		heldIDs.resize(0);
		pressed = justPressed = justReleased = false;
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		updateInput();
		updateAlpha(elapsed);
		lastUpdatedFrame = TouchUtil.frameCount;
	}

	function updateInput():Void
	{
		final wasPressed:Bool = pressed;
		final stillHeld:Array<Int> = [];

		if (visible && active && exists)
		{
			for (touch in FlxG.touches.list)
			{
				if (touch.justReleased || !touch.overlaps(this, camera)) continue;

				if (heldIDs.indexOf(touch.touchPointID) != -1) stillHeld.push(touch.touchPointID);
				else if (touch.justPressed || allowSlideIn) stillHeld.push(touch.touchPointID);
			}

			if (mouseEnabled && FlxG.mouse.pressed && FlxG.mouse.overlaps(this, camera))
			{
				if (heldIDs.indexOf(MOUSE_ID) != -1) stillHeld.push(MOUSE_ID);
				else if (FlxG.mouse.justPressed || allowSlideIn) stillHeld.push(MOUSE_ID);
			}
		}

		heldIDs = stillHeld;
		pressed = heldIDs.length > 0;
		justPressed = pressed && !wasPressed;
		justReleased = !pressed && wasPressed;

		if (justPressed)
		{
			TouchUtil.vibrate();
			onDown.dispatch(this);
		}
		else if (justReleased)
			onUp.dispatch(this);
	}

	function updateAlpha(elapsed:Float):Void
	{
		final target:Float = pressed ? pressedAlpha : idleAlpha;
		if (alphaTweenSpeed <= 0) alpha = target;
		else alpha = FlxMath.lerp(alpha, target, Math.min(1, elapsed * alphaTweenSpeed));
	}

	override function destroy():Void
	{
		list.remove(this);
		heldIDs = null;
		actions = null;
		onDown.removeAll();
		onUp.removeAll();
		super.destroy();
	}
}

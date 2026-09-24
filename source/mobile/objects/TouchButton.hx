package mobile.objects;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
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

	/**
	 * When true, a finger inside this button and another one at the same time counts only for
	 * whichever of them it is nearest the middle of.
	 *
	 * Needed by the Arrows layout, whose zones are wider than the gap between lanes on purpose
	 * - about 13px of each lies under its neighbour, so that a thumb sliding from one note to
	 * the next is never over nothing. Without a rule for the overlap that same thumb would be
	 * holding two lanes at once in it.
	 *
	 * V-Slice settles it by having the last hint to see the touch take it off the previous one
	 * (`buttonsTouchID` in `FunkinButton`). Nearest wins instead, because that puts the seam
	 * halfway between two arrows rather than wherever the draw order happens to fall, and
	 * because it needs no state to undo.
	 *
	 * Off by default: the hitbox lanes and the pads do not overlap, and the pause button is
	 * kept out of the way by `deadZones` rather than by distance.
	 */
	public var exclusive:Bool = false;

	public var idleAlpha:Float = 0.6;
	public var pressedAlpha:Float = 1;

	/** How quickly the button fades between its two alphas. Set to 0 to snap. */
	public var alphaTweenSpeed:Float = 16;

	/**
	 * Things sitting on top of this button that take priority over it: a touch inside
	 * one of them is not a touch on this.
	 *
	 * The pause button overlaps the top of a hitbox lane, and without this a tap on it
	 * would pause the game and be played as a note on the way. V-Slice calls the same
	 * idea `deadZones` on its hitbox hints.
	 */
	public var deadZones:Array<FlxSprite> = [];

	/** Animation played on press, for buttons whose art has one. Null for none. */
	public var pressAnim:String = null;

	/** What to go back to once a press animation has played out. */
	public var idleAnim:String = 'idle';

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
				// `pressed`, not just "not released": Flixel keeps a touch in the list for
				// one more frame after it ends, in the RELEASED state with justReleased
				// already false. Skipping only justReleased let allowSlideIn take that
				// stale entry as a fresh press, so every tap fired the button twice - the
				// second one landing after the finger was gone.
				if (!touch.pressed || !touch.overlaps(this, camera) || blocked(touch) || !nearest(touch)) continue;

				if (heldIDs.indexOf(touch.touchPointID) != -1) stillHeld.push(touch.touchPointID);
				else if (touch.justPressed || allowSlideIn) stillHeld.push(touch.touchPointID);
			}

			if (mouseEnabled && FlxG.mouse.pressed && FlxG.mouse.overlaps(this, camera) && !blocked(FlxG.mouse) && nearest(FlxG.mouse))
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
			playPressAnim();
			onDown.dispatch(this);
		}
		else if (justReleased)
			onUp.dispatch(this);
	}

	public function playPressAnim():Void
	{
		if (pressAnim != null && animation.exists(pressAnim)) animation.play(pressAnim, true);
	}

	public function playIdleAnim():Void
	{
		if (idleAnim != null && animation.exists(idleAnim)) animation.play(idleAnim, true);
	}

	/**
	 * Whether this is the closest of the overlapping buttons to where the finger is.
	 *
	 * Only asked of buttons that say their zones overlap, and only against others that say the
	 * same, so nothing else in `list` is considered - a pad button and a note lane are not two
	 * answers to one touch.
	 */
	function nearest(input:flixel.input.FlxPointer):Bool
	{
		if (!exclusive) return true;

		final at:FlxPoint = input.getWorldPosition(camera, FlxPoint.weak());
		final mine:Float = distanceSquared(at);
		var closest:Bool = true;

		for (other in list)
		{
			if (other == this || !other.exclusive || !other.isAwake) continue;
			if (!input.overlaps(other, other.camera)) continue;

			if (other.distanceSquared(at) < mine)
			{
				closest = false;
				break;
			}
		}

		at.putWeak();
		return closest;
	}

	function distanceSquared(at:FlxPoint):Float
	{
		final dx:Float = at.x - (x + width * 0.5);
		final dy:Float = at.y - (y + height * 0.5);
		return dx * dx + dy * dy;
	}

	function blocked(input:flixel.input.FlxPointer):Bool
	{
		for (zone in deadZones)
			if (zone != null && zone.exists && zone.visible && input.overlaps(zone, zone.camera)) return true;

		return false;
	}

	/**
	 * Dresses the button in real art instead of a drawn one, showing a single frame of a
	 * Sparrow sheet.
	 *
	 * Returns false and leaves the button untouched when the sheet isn't there, so the
	 * caller can fall back to the drawn graphic rather than ending up with an invisible
	 * button.
	 */
	public function setSparrowGraphic(texture:String, prefix:String, frame:Int = 0, scaleTo:Float = 1, ?pressFrames:Array<Int>):Bool
	{
		if (!Paths.fileExists('images/$texture.png', IMAGE) || !Paths.fileExists('images/$texture.xml', TEXT)) return false;

		var atlas:flixel.graphics.frames.FlxAtlasFrames = Paths.getSparrowAtlas(texture);
		if (atlas == null) return false;

		frames = atlas;
		animation.addByIndices('idle', prefix, [frame], '', 24, false);
		if (!animation.exists('idle')) return false;

		if (pressFrames != null && pressFrames.length > 0)
		{
			animation.addByIndices('press', prefix, pressFrames, '', 24, false);
			if (animation.exists('press'))
			{
				pressAnim = 'press';
				animation.finishCallback = function(name:String) if (name == pressAnim) playIdleAnim();
			}
		}

		animation.play('idle');
		scale.set(scaleTo, scaleTo);
		updateHitbox();
		alpha = idleAlpha;
		return true;
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

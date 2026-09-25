package mobile.objects;

import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import mobile.backend.TouchButtonGraphic;
import mobile.backend.WidescreenScaleMode;

/**
 * The on-screen controls for Psych's editors.
 *
 * The editors were written for a keyboard and a mouse. A phone already has the mouse
 * half - OpenFL turns a single finger into mouse events, so placing and dragging notes
 * works untouched - and this stands in for the keys: scrolling, playback, zoom, the
 * offset nudge, the modifier that turns a tap from "place" into "select".
 *
 * Buttons carry a tag of their own rather than a `Controls` action, because none of
 * these are `Controls` actions. The editor asks `held` or `tapped` beside its existing
 * key checks, so a build without touch controls reads exactly as it did before.
 */
class EditorPad extends FlxTypedSpriteGroup<TouchButton>
{
	public static inline var BUTTON_WIDTH:Int = 104;
	public static inline var BUTTON_HEIGHT:Int = 58;

	static inline var TOGGLE_WIDTH:Int = 62;
	static inline var GAP:Int = 8;
	static inline var MARGIN:Int = 14;

	/** Tag to button, for the lookups the editors do by name. */
	var buttons:Map<String, TouchButton> = new Map<String, TouchButton>();

	/** Tags that latch on a tap instead of following the finger, and where each one stands. */
	var latched:Map<String, Bool> = new Map<String, Bool>();

	/** Everything but the show/hide toggle, which stays put so the pad can be got back. */
	var body:Array<TouchButton> = [];

	var toggle:TouchButton;

	/**
	 * @param layout   Rows of tags, laid out bottom row first - the row you reach for most
	 *                 should be the first one.
	 * @param sticky   Tags that latch. A latched button reports `on`, not `held`.
	 */
	public function new(layout:Array<Array<String>>, ?sticky:Array<String>)
	{
		super();

		scrollFactor.set();

		// Asked of the device here rather than trusted from the last resize, which on a phone
		// may have happened before there was a view to ask. Same reason `VirtualPad` does it.
		WidescreenScaleMode.refreshNotch();

		final left:Float = MARGIN + WidescreenScaleMode.notchLeft;
		final bottom:Float = FlxG.height - MARGIN - WidescreenScaleMode.notchBottom;

		toggle = build('hide', left, bottom - BUTTON_HEIGHT, TOGGLE_WIDTH);
		toggle.onDown.add(function(_) expanded = !expanded);

		for (row in 0...layout.length)
		{
			final y:Float = bottom - BUTTON_HEIGHT - row * (BUTTON_HEIGHT + GAP);
			var x:Float = left + TOGGLE_WIDTH + GAP;

			for (tag in layout[row])
			{
				final button:TouchButton = build(tag, x, y, BUTTON_WIDTH);
				body.push(button);
				x += BUTTON_WIDTH + GAP;
			}
		}

		if (sticky != null)
			for (tag in sticky)
			{
				if (!buttons.exists(tag)) continue;
				latched.set(tag, false);
				final button:TouchButton = buttons.get(tag);
				button.onDown.add(function(_) setLatch(tag, !latched.get(tag)));
			}
	}

	function build(tag:String, x:Float, y:Float, width:Int):TouchButton
	{
		final button:TouchButton = new TouchButton(x, y);
		button.setGraphic(tag, width, BUTTON_HEIGHT);
		button.antialiasing = ClientPrefs.data.antialiasing;
		button.idleAlpha = ClientPrefs.data.controlsAlpha;
		button.alpha = button.idleAlpha;
		buttons.set(tag, button);
		add(button);
		return button;
	}

	/** True while the finger is down on this button. */
	public function held(tag:String):Bool
	{
		final button:TouchButton = buttons.get(tag);
		return button != null && button.visible && button.pressed;
	}

	/** True on the frame the button was pressed. */
	public function tapped(tag:String):Bool
	{
		final button:TouchButton = buttons.get(tag);
		return button != null && button.visible && button.justPressed;
	}

	/** Where a latching button stands. Always false for one that does not latch. */
	public function on(tag:String):Bool
		return latched.exists(tag) && latched.get(tag);

	function setLatch(tag:String, value:Bool):Void
	{
		latched.set(tag, value);

		// A latched button has to look held while nothing is touching it, which is the one
		// thing `TouchButton`'s own alpha tween will not do on its own.
		final button:TouchButton = buttons.get(tag);
		if (button != null) button.idleAlpha = value ? button.pressedAlpha : ClientPrefs.data.controlsAlpha;
	}

	/** True while the pointer is over any part of the pad, pad hidden or not. */
	public function underPointer():Bool
	{
		if (toggle == null) return false;

		if (toggle.visible && FlxG.mouse.overlaps(toggle, toggle.camera)) return true;

		for (button in body)
			if (button.visible && FlxG.mouse.overlaps(button, button.camera)) return true;

		return false;
	}

	public var expanded(default, set):Bool = true;

	function set_expanded(value:Bool):Bool
	{
		expanded = value;

		// The initialiser for this field runs through the setter, before the constructor has
		// built anything for it to hide.
		if (toggle == null) return value;

		for (button in body)
		{
			button.release();
			button.visible = button.active = value;
		}
		toggle.loadGraphic(TouchButtonGraphic.button(value ? 'hide' : 'show', TOGGLE_WIDTH, BUTTON_HEIGHT));
		return value;
	}

	override function destroy():Void
	{
		buttons.clear();
		latched.clear();
		body = null;
		toggle = null;
		super.destroy();
	}
}

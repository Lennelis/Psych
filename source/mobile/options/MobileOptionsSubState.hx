package mobile.options;

import options.BaseOptionsMenu;
import options.Option;
import mobile.objects.MobileControls;

/**
 * Settings for the touch controls.
 *
 * Rebuilds whatever pad is on screen as soon as something changes, so the player
 * can see what an opacity or a layout actually looks like instead of having to
 * back out and come in again.
 */
class MobileOptionsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = Language.getPhrase('mobile_menu', 'Mobile Settings');
		rpcTitle = 'Mobile Settings Menu';

		var option:Option = new Option('Gameplay Controls',
			"How you hit notes during a song.\nHitbox is four columns filling the screen, Pad is four buttons on one side.\nKeyboard hides them, for playing with a bluetooth keyboard or a controller.",
			'gameplayControls',
			STRING,
			MobileControls.MODES);
		addOption(option);

		var option:Option = new Option('Hitbox Style',
			"How the four gameplay columns are drawn.\nGradient fades them out towards the top, Solid fills them evenly,\nHidden leaves them invisible but still tappable.",
			'hitboxType',
			STRING,
			['Gradient', 'Solid', 'Hidden']);
		option.onChange = refreshControls;
		addOption(option);

		var option:Option = new Option('Controls Opacity',
			'How visible the on-screen buttons are.',
			'controlsAlpha',
			PERCENT);
		option.minValue = 0.1;
		option.maxValue = 1;
		option.changeValue = 0.05;
		option.decimals = 2;
		option.onChange = refreshControls;
		addOption(option);

		var option:Option = new Option('Vibration',
			'If checked, buttons give a short buzz when pressed.',
			'vibration',
			BOOL);
		addOption(option);

		super();
	}

	/** Rebuilds this menu's pad so opacity and style changes show up right away. */
	function refreshControls():Void
	{
		if (virtualPad == null) return;

		final dPad:VirtualPadDPad = virtualPad.dPadMode;
		final action:VirtualPadAction = virtualPad.actionMode;
		addVirtualPad(dPad, action);
	}
}

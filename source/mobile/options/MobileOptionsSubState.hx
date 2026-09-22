package mobile.options;

import options.BaseOptionsMenu;
import options.Option;
import mobile.backend.StorageUtil;
import mobile.backend.WidescreenScaleMode;
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
			"How you hit notes during a song.\nHitbox is four columns filling the screen, Arrows is four buttons standing in the note lanes,\nPad is four buttons on one side. Keyboard hides them, for a bluetooth keyboard or a controller.",
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

		var option:Option = new Option('Widescreen',
			"If checked, the game fills a screen wider than 16:9 instead of sitting between black bars.\nIt widens the view rather than stretching, so nothing is squashed, and the on-screen\nbuttons reach the real edges. Menu backgrounds drawn for 16:9 may not reach the sides.\nTakes effect when you leave this menu.",
			'widescreen',
			BOOL);
		option.onChange = onChangeWidescreen;
		addOption(option);

		var option:Option = new Option('Vibration',
			'If checked, buttons give a short buzz when pressed.',
			'vibration',
			BOOL);
		addOption(option);

		var option:Option = new Option('Note Vibration',
			"If checked, hitting a note buzzes too. A chord buzzes harder than a single note.\nNeeds Vibration on.",
			'noteVibration',
			BOOL);
		addOption(option);

		var option:Option = new Option('Vibration Strength',
			'How long each buzz lasts, against the normal length.',
			'vibrationStrength',
			PERCENT);
		option.minValue = 0.0;
		option.maxValue = 2.0;
		option.scrollSpeed = 1.0;
		addOption(option);

		var option:Option = new Option('Keep Screen Awake',
			"If checked, the screen won't dim or lock while a song is playing.",
			'keepScreenOn',
			BOOL);
		addOption(option);

		#if android
		// Not a preference: the checkbox shows whether the mods folder in shared storage
		// is reachable, and pressing it asks Android for it again. Option reads its value
		// through getValue every frame, so overriding that is enough to make a row that
		// reports on something instead of storing it.
		storageOption = new Option('Mods Folder', StorageUtil.describe(), 'storageAccess', BOOL);
		storageOption.getValue = () -> StorageUtil.usingSharedStorage;
		storageOption.setValue = function(value:Dynamic)
		{
			// Reset-to-default hits this too, and that shouldn't open a settings page.
			if (value == true) StorageUtil.requestStorageAccess();
			return StorageUtil.usingSharedStorage;
		};
		addOption(storageOption);
		#end

		super();
	}

	#if android
	var storageOption:Option;
	var storageDescription:String;
	var storageCheck:Float = 0;

	/**
	 * Keeps the storage row's description current.
	 *
	 * All files access is granted on a settings page, so the player comes back to this menu
	 * with the answer already decided - the row has to notice on its own rather than being
	 * told. `changeSelection` would do it, but it also plays the scroll sound.
	 */
	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (storageOption == null) return;

		// Asking Android whether it granted all files access is a JNI call, and the answer
		// only ever changes while the player is away in Settings.
		storageCheck -= elapsed;
		if (storageCheck > 0) return;
		storageCheck = 0.5;

		final description:String = StorageUtil.describe();
		if (description == storageDescription) return;

		storageDescription = description;
		storageOption.description = description;

		if (curOption != storageOption) return;

		descText.text = description;
		descText.screenCenter(Y);
		descText.y += 270;
		descBox.setPosition(descText.x - 10, descText.y - 10);
		descBox.setGraphicSize(Std.int(descText.width + 20), Std.int(descText.height + 25));
		descBox.updateHitbox();
	}
	#end

	function onChangeWidescreen():Void
	{
		// Cameras take their size from FlxG.width when a state is built, so the change
		// only lands properly on the next state - backing out of here is enough.
		WidescreenScaleMode.apply(ClientPrefs.data.widescreen);
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

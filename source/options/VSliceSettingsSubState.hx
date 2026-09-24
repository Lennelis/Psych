package options;

import backend.VSliceVisuals;

/**
 * How much of V-Slice this is, in as few questions as it takes.
 *
 * There were eleven rows here, which is eleven decisions to make before playing, and for
 * almost anyone they are two: whether it should look like V-Slice, and whether it should
 * score like it. Neither is a matter of taste - whether the word COMBO appears, or whether a
 * hold is worth anything, is a question of which game you are looking at - so they are asked
 * once each, and the switches behind them are still there, one row further in, for the case
 * where the answer really is "some of it".
 */
class VSliceSettingsSubState extends BaseOptionsMenu
{
	var visualsOption:Option;

	/**
	 * The seven switches as they last stood while they disagreed.
	 *
	 * Without this, a mix could be left but never returned to: picking Psych writes all seven
	 * off, and picking Custom afterwards would have nothing left to put back. Held for as long
	 * as the menu is open, which is as long as cycling the row can lose it.
	 */
	// Left uninitialised on purpose: it is filled in before super(), and Haxe is free to place
	// a field's initialiser after that call, which would wipe it.
	var customMix:Array<Bool>;

	public function new()
	{
		title = Language.getPhrase('vslice_menu', 'V-Slice Settings');
		rpcTitle = 'V-Slice Settings Menu'; //for Discord Rich Presence

		rememberMix();
		ClientPrefs.data.vslicePreset = VSliceVisuals.presetName();

		visualsOption = new Option('Visuals',
			"How much of V-Slice's look to wear: where the strumlines sit, how holds are drawn,\nthe judgement and combo art, the icon bop, the health bar colors, the score counter\nand the flourishes either side of a song.\n\nCustomize below sets them one at a time; this is all of them at once.",
			'vslicePreset',
			STRING,
			presetChoices());
		visualsOption.onChange = onVisualsChanged;
		addOption(visualsOption);

		// Kept beside the look rather than under Gameplay, where it was first put and promptly
		// lost: the hold scoring it switches on is the thing people come looking for, and they
		// come looking in the V-Slice menu.
		var option:Option = new Option('Scoring',
			"Psych scores a note by its judgement. V-Slice scores the timing itself on a curve,\nand pays 250 a second for a hold, which Psych pays nothing at all for.\nHealth follows the judgement too, instead of a flat amount for anything you touch.\n\nJudgement windows are the same either way, but the totals are not comparable -\na high score set under one will read oddly beside the other.",
			'scoringSystem',
			STRING,
			['Psych', 'V-Slice']);
		addOption(option);

		var option:Option = new Option('Customize',
			"The seven switches the row above sets in one go, one at a time - for wanting\nV-Slice's strumline but Psych's popups, or its holds but not its score counter.\n\nAlso the three that were never part of the look: the strumline background, the\nrestart animation, and the half frame off the input.",
			null,
			SUBMENU);
		option.onAccept = openCustomize;
		addOption(option);

		super();
	}

	function openCustomize():Void
	{
		var detail:VSliceDetailSubState = new VSliceDetailSubState();

		// This menu draws a full-screen background of its own, so leaving the one underneath
		// drawn would put two sets of rows and two touch pads on the screen at once. It stops
		// updating on its own - Flixel skips a state's update while it has a substate up - so
		// only the drawing has to be said.
		persistentDraw = false;
		detail.closeCallback = function()
		{
			persistentDraw = true;
			rememberMix();
			refreshVisualsRow();
		};

		openSubState(detail);
	}

	/** What the row can be cycled to. Custom only once there is a mix to go back to. */
	function presetChoices():Array<String>
	{
		var list:Array<String> = ['Psych', 'V-Slice'];
		if (customMix != null) list.push('Custom');

		return list;
	}

	function rememberMix():Void
	{
		if (VSliceVisuals.presetName() != 'Custom') return;

		customMix = [for (name in VSliceVisuals.VISUAL_SWITCHES) Reflect.getProperty(ClientPrefs.data, name) == true];
	}

	function onVisualsChanged():Void
	{
		var picked:String = ClientPrefs.data.vslicePreset;
		if (picked == 'Custom')
		{
			if (customMix != null)
				for (i => name in VSliceVisuals.VISUAL_SWITCHES)
					Reflect.setProperty(ClientPrefs.data, name, customMix[i]);
		}
		else VSliceVisuals.applyPreset(picked);
	}

	/** Puts the row back in step with the switches after they have been set one at a time. */
	function refreshVisualsRow():Void
	{
		ClientPrefs.data.vslicePreset = VSliceVisuals.presetName();

		visualsOption.options = presetChoices();
		var at:Int = visualsOption.options.indexOf(ClientPrefs.data.vslicePreset);
		if (at > -1) visualsOption.curOption = at;
		updateTextFrom(visualsOption);
	}
}

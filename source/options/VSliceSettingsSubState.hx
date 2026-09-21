package options;

/**
 * V-Slice's gameplay look, and the few things around it that are a matter of taste.
 *
 * Grouped rather than listed one switch at a time - see `backend.VSliceVisuals` for why -
 * with the four that are nobody's preference bundled and the rest given their own row.
 */
class VSliceSettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = Language.getPhrase('vslice_menu', 'V-Slice Settings');
		rpcTitle = 'V-Slice Settings Menu'; //for Discord Rich Presence

		var option:Option = new Option('Popups',
			"V-Slice's judgement and combo art: no COMBO word, no number until a combo of ten,\na zero popped when you break one, and its own sizes and placement.\n\nLeft alone on a mod with its own UI art, which was drawn for Psych's placement.",
			'vslicePopups',
			BOOL);
		addOption(option);

		var option:Option = new Option('Strumline',
			"Puts the strumlines where V-Slice has them - a little left of Psych's - and draws\nhold covers and note splashes over the oncoming notes instead of under them.",
			'vsliceStrumline',
			BOOL);
		addOption(option);

		var option:Option = new Option('Icons',
			"The health icons land their bop instead of easing out of it forever.",
			'vsliceIcons',
			BOOL);
		addOption(option);

		var option:Option = new Option('Transitions',
			"The flourishes either side of a song: the arrows rise as they fade in, fade out\nagain at the end, and pixel art fades in steps rather than smoothly.",
			'vsliceTransitions',
			BOOL);
		addOption(option);

		var option:Option = new Option('Health Bar Colors',
			"V-Slice's fixed red and green, instead of the two characters' own icon colors.",
			'vsliceHealthBar',
			BOOL);
		addOption(option);

		var option:Option = new Option('Score Counter',
			"Shows the score on its own, the way V-Slice does, instead of Psych's score,\nmisses and rating.",
			'vsliceScoreCounter',
			BOOL);
		addOption(option);

		var option:Option = new Option('Strumline Background',
			"A dark column behind each strumline, to read the notes against.\nV-Slice has this as a setting of its own too. 0% is off.",
			'strumlineBackground',
			PERCENT);
		option.minValue = 0.0;
		option.maxValue = 1.0;
		addOption(option);

		var option:Option = new Option('Restart Animation',
			"Flies the notes off the screen and the new ones back in when you restart a song.\nIt costs a second before every retry, which is why it is its own switch.",
			'restartAnimation',
			BOOL);
		addOption(option);

		super();
	}
}

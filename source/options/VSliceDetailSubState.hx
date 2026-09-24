package options;

/**
 * Every V-Slice switch on its own, for when the two presets aren't the answer.
 *
 * The menu above this offers the seven visual ones as a single row, because for almost
 * anyone they are one decision - which game this is meant to look like. This is the other
 * case: wanting V-Slice's strumline but Psych's popups, or its holds but not its score
 * counter. Nothing here is unavailable above; above is the shortcut, and this is the thing
 * it is a shortcut for.
 *
 * The three at the bottom never belonged to the preset. A strumline background, a restart
 * animation and half a frame off the input are each a preference rather than a question of
 * which game you are looking at, so setting the look to V-Slice leaves all three alone.
 */
class VSliceDetailSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = Language.getPhrase('vslice_customize_menu', 'Customize');
		rpcTitle = 'V-Slice Customize Menu'; //for Discord Rich Presence

		var option:Option = new Option('Popups',
			"V-Slice's judgement and combo art: no COMBO word, no number until a combo of ten,\na zero popped when you break one, and its own sizes and placement.\n\nLeft alone on a mod with its own UI art, which was drawn for Psych's placement.",
			'vslicePopups',
			BOOL);
		addOption(option);

		var option:Option = new Option('Strumline',
			"Puts the strumlines where V-Slice has them - a little left of Psych's - draws hold\ncovers and note splashes over the oncoming notes instead of under them, and moves\nthe health bar the one percent of the screen nearer the edge that V-Slice has it.",
			'vsliceStrumline',
			BOOL);
		addOption(option);

		var option:Option = new Option('Sustains',
			"Draws a hold as one solid stretched piece with a rounded end, the way V-Slice does,\ninstead of a sprite per step of the chart at 60% opacity.\n\nUses whichever note skin is loaded - it reads the hold art off the notes themselves.",
			'vsliceSustains',
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

		var option:Option = new Option('Input Lag Compensation',
			"Input only arrives once a frame, so a press lands somewhere in the frame that just went by\nbut is judged as if it happened at the end of it - always read a little late, never early.\nThis takes half a frame back off, which is about 8ms at 60fps and 4 at 120.\n\nV-Slice reads the real figure off the OS event, which Psych cannot: the timestamp is\ndiscarded before Haxe sees it. This is the part of it that can be had without that.\n\nRecalibrate your delay after turning this on or off - it moves where hits land.",
			'inputLagComp',
			BOOL);
		addOption(option);

		super();
	}
}

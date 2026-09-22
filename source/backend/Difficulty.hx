package backend;

class Difficulty
{
	public static final defaultList:Array<String> = [
		'Easy',
		'Normal',
		'Hard'
	];
	private static final defaultDifficulty:String = 'Normal'; //The chart that has no postfix and starting difficulty on Freeplay/Story Mode

	public static var list:Array<String> = [];

	inline public static function getFilePath(num:Null<Int> = null)
	{
		if(num == null) num = PlayState.storyDifficulty;

		var filePostfix:String = list[num];
		if(filePostfix != null && Paths.formatToSongPath(filePostfix) != Paths.formatToSongPath(defaultDifficulty))
			filePostfix = '-' + filePostfix;
		else
			filePostfix = '';
		return Paths.formatToSongPath(filePostfix);
	}

	inline public static function loadFromWeek(week:WeekData = null)
	{
		if(week == null) week = WeekData.getCurrentWeek();

		var diffStr:String = week.difficulties;
		if(diffStr != null && diffStr.length > 0)
		{
			var diffs:Array<String> = diffStr.trim().split(',');
			var i:Int = diffs.length - 1;
			while (i > 0)
			{
				if(diffs[i] != null)
				{
					diffs[i] = diffs[i].trim();
					if(diffs[i].length < 1) diffs.remove(diffs[i]);
				}
				--i;
			}

			if(diffs.length > 0 && diffs[0].length > 0)
				list = diffs;
		}
		else resetList();
	}

	/**
	 * Difficulties a song can carry on its own rather than being handed by its week.
	 *
	 * The Erect remixes are a second chart and a second recording of a song that already
	 * exists, not a song of their own, so they belong on the original's difficulty list the
	 * way V-Slice puts them there - not in a week of their own where the same song would be
	 * listed twice.
	 */
	public static final variationList:Array<String> = ['Erect', 'Nightmare'];

	/**
	 * The week's difficulties, plus whichever variations this song actually has a chart for.
	 *
	 * Asked per song rather than per week because that is the only honest answer: Week 1
	 * holds Tutorial, which has no Erect chart, alongside Bopeebo, which does. Offering the
	 * week's list to both would put a difficulty on Tutorial that cannot be loaded.
	 *
	 * Story mode is deliberately left alone - it runs a whole week on one difficulty, so a
	 * per-song list has nowhere to go there.
	 */
	public static function listForSong(songName:String, week:WeekData = null):Array<String>
	{
		loadFromWeek(week);

		var result:Array<String> = list.copy();
		var folder:String = Paths.formatToSongPath(songName);

		for (name in variationList)
		{
			if (result.contains(name)) continue;

			var file:String = folder + '-' + Paths.formatToSongPath(name);
			if (Paths.fileExists('data/$folder/$file.json', TEXT)) result.push(name);
		}

		return result;
	}

	inline public static function resetList()
	{
		list = defaultList.copy();
	}

	inline public static function copyFrom(diffs:Array<String>)
	{
		list = diffs.copy();
	}

	inline public static function getString(?num:Null<Int> = null, ?canTranslate:Bool = true):String
	{
		var diffName:String = list[num == null ? PlayState.storyDifficulty : num];
		if(diffName == null) diffName = defaultDifficulty;
		return canTranslate ? Language.getPhrase('difficulty_$diffName', diffName) : diffName;
	}

	inline public static function getDefault():String
	{
		return defaultDifficulty;
	}
}
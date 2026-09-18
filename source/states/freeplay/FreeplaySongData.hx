package states.freeplay;

import backend.Highscore;
import backend.Song;
import backend.Song.SwagSong;
import backend.WeekData;
import haxe.Json;

/**
 * What the freeplay menu knows about one song.
 *
 * V-Slice reads this out of its own registries, where every song carries an album, a
 * character, a difficulty rating and a per-difficulty score with note tallies. Psych
 * has none of that: a song is a line in a week file - a name, an icon and a colour -
 * and `Highscore` remembers a score and an accuracy per difficulty. So this is built
 * out of what Psych does have, and the rest is either derived or left at a default a
 * mod can override later.
 *
 * Everything is keyed by a difficulty's name rather than its number, the way V-Slice
 * does it, because in Psych a number means nothing on its own: difficulties belong to
 * a week, so `1` is `hard` in one week and something else in the next. Anything that
 * needs the number asks `Difficulty` for it after pointing it at this song's week,
 * which is what the rest of the engine expects to be looking at anyway.
 *
 * Everything expensive is worked out on demand. A chart is only opened when its BPM is
 * actually asked for, which is when the song becomes the selected one - reading every
 * chart in the game up front to fill in a number on a capsule would cost seconds.
 */
class FreeplaySongData
{
	/** As it appears in the week file, which is also how `Highscore` keys it. */
	public var songName(default, null):String;

	/** Index of the week this came out of. */
	public var week(default, null):Int;

	/** Week name, which is what the capsule prints. V-Slice calls this the level id. */
	public var levelName(default, null):String;

	/** Icon character, used for the capsule's little pixel icon. */
	public var songCharacter(default, null):String;

	/** The colour the week file gives this song. */
	public var color(default, null):Int;

	/** Mod folder this song belongs to, so selecting it can switch back to that mod. */
	public var folder(default, null):String;

	/** Difficulties this song has, in the order the week lists them. */
	public var difficulties(default, null):Array<String>;

	public var isFav:Bool = false;

	/** Psych has no "new" flag for a song, so this stays false unless something sets it. */
	public var isNew:Bool = false;

	var bpmCache:Map<String, Int> = [];

	public function new(songName:String, week:Int, levelName:String, songCharacter:String, color:Int, folder:String, difficulties:Array<String>)
	{
		this.songName = songName;
		this.week = week;
		this.levelName = levelName;
		this.songCharacter = songCharacter;
		this.color = color;
		this.folder = folder;
		this.difficulties = difficulties;
		this.isFav = FreeplayFavourites.has(songName);
	}

	public function hasDifficulty(difficulty:String):Bool
		return difficulties.contains(difficulty);

	/**
	 * Points `Difficulty` at this song's week and gives back where a difficulty sits in it.
	 *
	 * Everything in Psych that takes a difficulty number - the score keys, the chart file
	 * name, the story difficulty - reads that number against whatever `Difficulty.list`
	 * happens to hold, so the two have to be set together or they mean different things.
	 */
	public function difficultyIndex(difficulty:String):Int
	{
		Difficulty.copyFrom(difficulties);

		var index:Int = difficulties.indexOf(difficulty);
		if (index < 0) index = Math.round(Math.max(0, difficulties.indexOf(Difficulty.getDefault())));

		return index;
	}

	/** Highest score saved for a difficulty, 0 if it has never been finished. */
	public function getScore(difficulty:String):Int
		return Highscore.getScore(formatted(), difficultyIndex(difficulty));

	/** Saved accuracy for a difficulty, 0 to 1. Negative when there is nothing saved. */
	public function getAccuracy(difficulty:String):Float
		return Highscore.getRating(formatted(), difficultyIndex(difficulty));

	public function getRank(difficulty:String):FreeplayRankTier
		return FreeplayRankTier.fromAccuracy(getAccuracy(difficulty), getScore(difficulty));

	/**
	 * The number printed under DIFFICULTY on the capsule.
	 *
	 * V-Slice has a hand-authored 0-20 rating per difficulty in the song's metadata.
	 * Nothing in Psych carries one, and guessing it from the chart would mean opening
	 * and counting every note of it, so this is the difficulty's place in the list -
	 * which at least rises the way the rating would.
	 */
	public function getDifficultyRating(difficulty:String):Int
		return difficultyIndex(difficulty) + 1;

	/**
	 * BPM the chart starts at, read from the chart itself the first time it is asked for.
	 *
	 * Only the header is wanted, but a chart is one JSON object, so the whole thing gets
	 * parsed. That is why the answer is kept - flicking up and down a list would
	 * otherwise re-read the same files over and over.
	 */
	public function getStartingBpm(difficulty:String):Int
	{
		if (bpmCache.exists(difficulty)) return bpmCache.get(difficulty);

		var bpm:Int = 0;
		var index:Int = difficultyIndex(difficulty);

		var previousMod:String = Mods.currentModDirectory;
		Mods.currentModDirectory = folder;

		try
		{
			// Through Song.getChart rather than reading the file here. Resolving a chart path
			// is not one lookup - mods, then the song's own level folder, then shared, with a
			// different reader for each - and doing it by hand got mod charts wrong, which is
			// why every modded song showed a bpm of 000. This is the same call gameplay makes,
			// so whatever it can load, this can read.
			var chart:SwagSong = Song.getChart(Highscore.formatSong(formatted(), index), formatted());
			if (chart != null) bpm = Math.round(chart.bpm);
		}
		catch (e:Dynamic)
			trace('FreeplaySongData: could not read a bpm for "$songName" ($e)');

		Mods.currentModDirectory = previousMod;

		bpmCache.set(difficulty, bpm);
		return bpm;
	}

	public inline function formatted():String
		return Paths.formatToSongPath(songName);

	/** Reads the whole song list out of the week files, exactly as Psych's own freeplay does. */
	public static function listAll():Array<FreeplaySongData>
	{
		var result:Array<FreeplaySongData> = [];

		WeekData.reloadWeekFiles(false);

		for (i in 0...WeekData.weeksList.length)
		{
			var week:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			if (week == null) continue;

			WeekData.setDirectoryFromWeek(week);

			var difficulties:Array<String> = (week.difficulties != null
				&& week.difficulties.trim().length > 0) ? CoolUtil.listFromString(week.difficulties.trim()) : Difficulty.defaultList.copy();

			for (song in week.songs)
			{
				var colors:Array<Int> = song[2];
				if (colors == null || colors.length < 3) colors = [146, 113, 253];

				result.push(new FreeplaySongData(song[0], i, WeekData.weeksList[i], song[1], FlxColor.fromRGB(colors[0], colors[1], colors[2]),
					Mods.currentModDirectory != null ? Mods.currentModDirectory : '', difficulties));
			}
		}

		Mods.loadTopMod();
		return result;
	}

	/**
	 * Every difficulty any song has, in the order they were first met.
	 *
	 * V-Slice cycles the difficulty through one list belonging to the whole game, and
	 * lands on the nearest song that has whatever you landed on. Psych has no such list -
	 * each week brings its own - so this stands in for it, and a mod week's `insane`
	 * takes its place in the cycle after everything that came before it.
	 */
	public static function listAllDifficulties(songs:Array<FreeplaySongData>):Array<String>
	{
		var result:Array<String> = [];

		for (song in songs)
		{
			if (song == null) continue;

			for (difficulty in song.difficulties)
				if (!result.contains(difficulty)) result.push(difficulty);
		}

		if (result.length < 1) result = Difficulty.defaultList.copy();

		return result;
	}
}

/**
 * The rank badge on a capsule.
 *
 * V-Slice works this out from note tallies it keeps per save: a full clear of sicks is
 * gold, otherwise `(sick + good - miss) / notes` against four thresholds. Psych saves
 * an accuracy and a score and nothing else, so the accuracy stands in for that ratio
 * and the thresholds are V-Slice's own. A hundred percent in Psych means every note
 * was hit at full rating, which is the same thing gold is asking for.
 */
enum abstract FreeplayRankTier(String) from String to String
{
	var NONE = 'none';
	var LOSS = 'LOSS';
	var GOOD = 'GOOD';
	var GREAT = 'GREAT';
	var EXCELLENT = 'EXCELLENT';
	var PERFECT = 'PERFECT';
	var PERFECT_GOLD = 'PERFECTSICK';

	/** V-Slice's thresholds, and its name for the animation on the badge sheet. */
	public static function fromAccuracy(accuracy:Float, score:Int):FreeplayRankTier
	{
		// Nothing saved at all. A score with no accuracy is an old save, from before
		// Psych kept one, and there is no honest rank to give that.
		if (score <= 0 || accuracy < 0) return NONE;

		if (accuracy >= 1) return PERFECT_GOLD;
		if (accuracy >= 0.99) return PERFECT;
		if (accuracy >= 0.9) return EXCELLENT;
		if (accuracy >= 0.8) return GREAT;
		if (accuracy >= 0.6) return GOOD;
		return LOSS;
	}

	/** Colour the capsule flashes when a rank lands. V-Slice's palette. */
	public function getColor():FlxColor
	{
		return switch (cast this : FreeplayRankTier)
		{
			case LOSS: 0xFF6044FF;
			case GOOD: 0xFFEF8764;
			case GREAT: 0xFFEAF6FF;
			case EXCELLENT: 0xFFFDCB42;
			case PERFECT: 0xFFFF58B4;
			case PERFECT_GOLD: 0xFFFFB619;
			default: 0xFF6044FF;
		}
	}

	public inline function exists():Bool
		return (cast this : FreeplayRankTier) != NONE;
}

/**
 * Songs the player has starred, kept in Psych's own save file.
 *
 * V-Slice keeps favourites in its `Save`; Psych's save is `FlxG.save.data`, which takes
 * anything, so a list of song names lives there under its own key.
 */
class FreeplayFavourites
{
	public static function list():Array<String>
	{
		var saved:Dynamic = FlxG.save.data.freeplayFavourites;
		if (saved == null || !Std.isOfType(saved, Array)) return [];

		return cast saved;
	}

	public static function has(songName:String):Bool
		return list().contains(songName);

	/** @return whether the song is a favourite now. */
	public static function toggle(songName:String):Bool
	{
		var favourites:Array<String> = list();
		var nowFavourite:Bool = !favourites.remove(songName);
		if (nowFavourite) favourites.push(songName);

		FlxG.save.data.freeplayFavourites = favourites;
		FlxG.save.flush();
		return nowFavourite;
	}
}

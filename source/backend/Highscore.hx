package backend;

class Highscore
{
	public static var weekScores:Map<String, Int> = new Map();
	public static var songScores:Map<String, Int> = new Map<String, Int>();
	public static var songRating:Map<String, Float> = new Map<String, Float>();

	public static var songMaxCombo:Map<String, Int> = new Map<String, Int>();
	public static var songMisses:Map<String, Int> = new Map<String, Int>();
	public static var songCompleted:Map<String, Bool> = new Map<String, Bool>();

	public static function resetSong(song:String, diff:Int = 0):Void
	{
		var daSong:String = formatSong(song, diff);
		setScore(daSong, 0);
		setRating(daSong, 0);
		setMaxCombo(daSong, 0);
		setMisses(daSong, 0);
		setCompleted(daSong, false);
	}

	public static function resetWeek(week:String, diff:Int = 0):Void
	{
		var daWeek:String = formatSong(week, diff);
		setWeekScore(daWeek, 0);
	}

	public static function saveScore(song:String, score:Int = 0, ?diff:Int = 0, ?rating:Float = -1):Void
	{
		if(song == null) return;
		var daSong:String = formatSong(song, diff);

		if (songScores.exists(daSong))
		{
			if (songScores.get(daSong) < score)
			{
				setScore(daSong, score);
				if(rating >= 0) setRating(daSong, rating);
			}
		}
		else
		{
			setScore(daSong, score);
			if(rating >= 0) setRating(daSong, rating);
		}
	}

	public static function saveStats(song:String, score:Int = 0, ?diff:Int = 0, accuracy:Float = -1, maxCombo:Int = 0, misses:Int = 0, completed:Bool = true):Void
	{
		if(song == null) return;
		var daSong:String = formatSong(song, diff);
		var isNewBest:Bool = !songScores.exists(daSong) || songScores.get(daSong) < score;

		saveScore(song, score, diff, accuracy);

		if(isNewBest)
		{
			setMaxCombo(daSong, maxCombo);
			setMisses(daSong, misses);
		}
		if(completed) setCompleted(daSong, true);
	}

	public static function saveWeekScore(week:String, score:Int = 0, ?diff:Int = 0):Void
	{
		var daWeek:String = formatSong(week, diff);

		if (weekScores.exists(daWeek))
		{
			if (weekScores.get(daWeek) < score)
				setWeekScore(daWeek, score);
		}
		else setWeekScore(daWeek, score);
	}

	static function setScore(song:String, score:Int):Void
	{
		songScores.set(song, score);
		FlxG.save.data.songScores = songScores;
		FlxG.save.flush();
	}
	static function setWeekScore(week:String, score:Int):Void
	{
		weekScores.set(week, score);
		FlxG.save.data.weekScores = weekScores;
		FlxG.save.flush();
	}

	static function setRating(song:String, rating:Float):Void
	{
		songRating.set(song, rating);
		FlxG.save.data.songRating = songRating;
		FlxG.save.flush();
	}

	static function setMaxCombo(song:String, combo:Int):Void
	{
		songMaxCombo.set(song, combo);
		FlxG.save.data.songMaxCombo = songMaxCombo;
		FlxG.save.flush();
	}
	static function setMisses(song:String, misses:Int):Void
	{
		songMisses.set(song, misses);
		FlxG.save.data.songMisses = songMisses;
		FlxG.save.flush();
	}
	static function setCompleted(song:String, completed:Bool):Void
	{
		songCompleted.set(song, completed);
		FlxG.save.data.songCompleted = songCompleted;
		FlxG.save.flush();
	}

	public static function formatSong(song:String, diff:Int):String
	{
		return Paths.formatToSongPath(song) + Difficulty.getFilePath(diff);
	}

	public static function getScore(song:String, diff:Int):Int
	{
		var daSong:String = formatSong(song, diff);
		if (!songScores.exists(daSong))
			setScore(daSong, 0);

		return songScores.get(daSong);
	}

	public static function getRating(song:String, diff:Int):Float
	{
		var daSong:String = formatSong(song, diff);
		if (!songRating.exists(daSong))
			setRating(daSong, 0);

		return songRating.get(daSong);
	}

	public static function getMaxCombo(song:String, diff:Int):Int
	{
		var daSong:String = formatSong(song, diff);
		return songMaxCombo.exists(daSong) ? songMaxCombo.get(daSong) : 0;
	}
	public static function getMisses(song:String, diff:Int):Int
	{
		var daSong:String = formatSong(song, diff);
		return songMisses.exists(daSong) ? songMisses.get(daSong) : 0;
	}
	public static function isCompleted(song:String, diff:Int):Bool
	{
		var daSong:String = formatSong(song, diff);
		return songCompleted.exists(daSong) && songCompleted.get(daSong);
	}
	public static function getRank(song:String, diff:Int):String
	{
		return SongRank.fromAccuracy(getRating(song, diff));
	}

	public static function getWeekScore(week:String, diff:Int):Int
	{
		var daWeek:String = formatSong(week, diff);
		if (!weekScores.exists(daWeek))
			setWeekScore(daWeek, 0);

		return weekScores.get(daWeek);
	}

	public static function load():Void
	{
		if (FlxG.save.data.weekScores != null)
			weekScores = FlxG.save.data.weekScores;

		if (FlxG.save.data.songScores != null)
			songScores = FlxG.save.data.songScores;

		if (FlxG.save.data.songRating != null)
			songRating = FlxG.save.data.songRating;

		if (FlxG.save.data.songMaxCombo != null)
			songMaxCombo = FlxG.save.data.songMaxCombo;
		if (FlxG.save.data.songMisses != null)
			songMisses = FlxG.save.data.songMisses;
		if (FlxG.save.data.songCompleted != null)
			songCompleted = FlxG.save.data.songCompleted;
	}
}
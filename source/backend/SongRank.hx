package backend;

class SongRank
{
	public static var thresholds:Array<{rank:String, minAccuracy:Float}> = [
		{rank: 'P', minAccuracy: 1.0},
		{rank: 'S', minAccuracy: 0.90},
		{rank: 'A', minAccuracy: 0.80},
		{rank: 'B', minAccuracy: 0.70},
		{rank: 'C', minAccuracy: 0.60},
		{rank: 'D', minAccuracy: 0.50},
		{rank: 'F', minAccuracy: 0.0}
	];

	public static function fromAccuracy(accuracy:Float):String
	{
		if (Math.isNaN(accuracy)) accuracy = 0;
		for (t in thresholds)
			if (accuracy >= t.minAccuracy)
				return t.rank;
		return 'F';
	}

	public static function hasNoAttempt(song:String, diff:Int):Bool
	{
		return Highscore.getScore(song, diff) <= 0 && Highscore.getRating(song, diff) <= 0;
	}

	public static function colorFor(rank:String):Int
	{
		return switch (rank)
		{
			case 'P': 0xFFFFD866;
			case 'S': 0xFF52E7FF;
			case 'A': 0xFF6BFF95;
			case 'B': 0xFF6BAFFF;
			case 'C': 0xFFFFE066;
			case 'D': 0xFFFFA352;
			case 'F': 0xFFFF5C77;
			default:  0xFF5A5470;
		}
	}
}

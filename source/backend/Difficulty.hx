package backend;

class Difficulty
{
	public static final defaultList:Array<String> = [
		'Easy',
		'Normal',
		'Hard'
	];
	private static final defaultDifficulty:String = 'Normal';

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

	public static function pickAvailable(song:String, preferred:Int):Int
	{
		try
		{
			var order:Array<Int> = [preferred];
			var i:Int = list.length - 1;
			while (i >= 0)
			{
				if (i != preferred) order.push(i);
				i--;
			}
			for (idx in order)
				if (chartExists(song, idx)) return idx;
		}
		catch (e:Dynamic) {}
		return preferred;
	}

	public static function chartExists(song:String, num:Int):Bool
	{
		try
		{
			var folder:String = Paths.formatToSongPath(song);
			var path:String = Paths.json('$folder/$folder' + getFilePath(num));
			#if sys
			if (sys.FileSystem.exists(path)) return true;
			#end
			return openfl.utils.Assets.exists(path);
		}
		catch (e:Dynamic) {}
		return false;
	}

	public static function available(song:String):Array<Int>
	{
		var found:Array<Int> = [for (i in 0...list.length) if (chartExists(song, i)) i];
		return found.length > 0 ? found : [for (i in 0...list.length) i];
	}

	public static var lastPicked:String = null;

	public static function startIndex(song:String):Int
	{
		var avail:Array<Int> = available(song);
		if (lastPicked != null)
			for (i in avail) if (list[i] == lastPicked) return i;
		var normal:Int = list.indexOf(defaultDifficulty);
		return pickAvailable(song, normal > -1 ? normal : 0);
	}

	public static function step(song:String, cur:Int, change:Int):Int
	{
		var avail:Array<Int> = available(song);
		var pos:Int = avail.indexOf(cur);
		if (pos < 0) pos = 0;
		pos = FlxMath.wrap(pos + change, 0, avail.length - 1);
		return avail[pos];
	}

	inline public static function getDefault():String
	{
		return defaultDifficulty;
	}
}
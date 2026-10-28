package psychlua;

class ScriptLog
{
	public static inline var FILE:String = 'vortex_script_log.txt';
	public static var errorCount:Int = 0;

	static var seen:Map<String, Bool> = new Map<String, Bool>();
	static var started:Bool = false;

	public static function error(source:String, message:String, ?details:String):Bool
	{
		var key:String = source + '\n' + message;
		if(seen.exists(key)) return false;
		seen.set(key, true);
		errorCount++;
		write('[ERROR] ' + source + '\n  ' + message.split('\n').join('\n  ') + (details != null && details.length > 0 ? '\n  ' + details.split('\n').join('\n  ') : ''));
		return true;
	}

	public static function info(message:String)
		write('[info] ' + message);

	public static function reset()
	{
		seen.clear();
		errorCount = 0;
	}

	static function write(text:String)
	{
		#if sys
		try
		{
			var out:sys.io.FileOutput = null;
			if(!started)
			{
				started = true;
				out = sys.io.File.write(FILE, false);
				out.writeString('Vortex Engine script log (' + Date.now().toString() + ')\n\n');
			}
			else out = sys.io.File.append(FILE, false);
			out.writeString(Date.now().toString().split(' ').pop() + ' ' + text + '\n');
			out.close();
		}
		catch(e:Dynamic) {}
		#end
	}
}

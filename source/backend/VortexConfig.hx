package backend;

class VortexConfig
{
	public static var engineName(default, null):String = "Vortex Engine";
	public static var engineVersion(default, null):String = "1.0X";

	public static var discordAppId(default, null):String = "0";

	public static var updateCheckUrl(default, null):String = "";

	public static var issueTrackerUrl(default, null):String = "";

	static var loaded:Bool = false;

	public static function load():Void
	{
		if (loaded) return;
		loaded = true;

		try
		{
			var raw:String = Paths.getTextFromFile('data/vortexConfig.json');
			if (raw == null || raw.trim().length == 0)
			{
				trace('VortexConfig: no vortexConfig.json found, using built-in defaults');
				return;
			}

			var parsed:Dynamic = haxe.Json.parse(raw);
			if (Reflect.hasField(parsed, 'engineName') && parsed.engineName != null)
				engineName = Std.string(parsed.engineName);
			if (Reflect.hasField(parsed, 'engineVersion') && parsed.engineVersion != null)
				engineVersion = Std.string(parsed.engineVersion);
			if (Reflect.hasField(parsed, 'discordAppId') && parsed.discordAppId != null)
				discordAppId = Std.string(parsed.discordAppId);
			if (Reflect.hasField(parsed, 'updateCheckUrl') && parsed.updateCheckUrl != null)
				updateCheckUrl = Std.string(parsed.updateCheckUrl);
			if (Reflect.hasField(parsed, 'issueTrackerUrl') && parsed.issueTrackerUrl != null)
				issueTrackerUrl = Std.string(parsed.issueTrackerUrl);
		}
		catch (e:Dynamic)
		{
			trace('VortexConfig: failed to parse vortexConfig.json, using built-in defaults ($e)');
		}
	}
}

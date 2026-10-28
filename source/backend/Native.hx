package backend;

class Native
{
	public static function __init__():Void {}

	public static function registerDPIAware():Void {}

	private static var fixedScaling:Bool = false;
	public static function fixScaling():Void {}

	public static function setDarkMode():Void {}

	public static function updateFrameRate(fps:Int):Void {}

	#if (cpp && windows)
	public static function getWindowsConsoleMode(handleType:Int):Int return 0;
	public static function setWindowsConsoleMode(handleType:Int, mode:Int):Bool return false;
	#end
}

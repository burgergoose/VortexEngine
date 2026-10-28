package backend;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

class BuildInfo
{
	public static macro function date():ExprOf<String>
	{
		return macro $v{Date.now().toString()};
	}

	public static macro function commit():ExprOf<String>
	{
		var c:String = 'unknown';
		try
		{
			var p = new sys.io.Process('git', ['rev-parse', '--short', 'HEAD']);
			var out:String = StringTools.trim(p.stdout.readAll().toString());
			if (p.exitCode() == 0 && out.length > 0) c = out;
			p.close();
		}
		catch (e:Dynamic) {}
		return macro $v{c};
	}
}

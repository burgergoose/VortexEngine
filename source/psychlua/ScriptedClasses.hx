package psychlua;

import flixel.FlxBasic;

class ScriptedClasses
{
	static var classes:Map<String, ClassScript> = new Map<String, ClassScript>();
	static var instances:Map<String, ScriptedInstance> = new Map<String, ScriptedInstance>();
	static var order:Array<String> = [];

	public static function classExists(name:String):Bool
		return findFile(name, '.lua') != null || findFile(name, '.hx') != null;

	static function findFile(name:String, ext:String):String
	{
		if(name == null || name.length < 1) return null;
		return Mods.findInAnyMod('classes/' + name + ext);
	}

	static function getClass(name:String):ClassScript
	{
		if(classes.exists(name)) return classes.get(name);

		var script:ClassScript = null;
		#if LUA_ALLOWED
		var luaFile:String = findFile(name, '.lua');
		if(luaFile != null)
		{
			var lua = new FunkinLua(luaFile, false);
			if(lua.lua != null) script = new ClassScript(name, lua, null);
			else lua.stop();
		}
		#end
		#if HSCRIPT_ALLOWED
		if(script == null)
		{
			var hxFile:String = findFile(name, '.hx');
			if(hxFile != null)
			{
				try { script = new ClassScript(name, null, new HScript(null, hxFile)); }
				catch(e:Dynamic) { LuaUtils.debugPrint('Error in class "$name": $e', FlxColor.RED); }
			}
		}
		#end
		if(script == null) LuaUtils.debugPrint('createScripted: class "$name" not found (put it in classes/$name.lua or classes/$name.hx)', FlxColor.RED);
		else classes.set(name, script);
		return script;
	}

	public static function create(className:String, tag:String, x:Float = 0, y:Float = 0, ?args:Array<Dynamic>):FlxSprite
	{
		if(tag == null || tag.length < 1) return null;
		tag = tag.replace('.', '');
		var cls:ClassScript = getClass(className);
		if(cls == null) return null;

		if(instances.exists(tag)) destroyInstance(tag);
		else LuaUtils.destroyObject(tag);

		var spr:ModchartSprite = new ModchartSprite(x, y);
		spr.active = true;
		MusicBeatState.getVariables().set(tag, spr);
		var inst:ScriptedInstance = {tag: tag, cls: cls, sprite: spr};
		instances.set(tag, inst);
		order.push(tag);

		cls.callFor(inst, 'new', args != null ? args : []);
		return spr;
	}

	public static function callMethod(tag:String, method:String, ?args:Array<Dynamic>):Dynamic
	{
		var inst:ScriptedInstance = instances.get(tag);
		if(inst == null)
		{
			LuaUtils.debugPrint('callScripted: no instance called "$tag"', FlxColor.RED);
			return null;
		}
		return inst.cls.callFor(inst, method, args != null ? args : []);
	}

	public static function destroyInstance(tag:String):Bool
	{
		var inst:ScriptedInstance = instances.get(tag);
		if(inst == null) return false;
		instances.remove(tag);
		order.remove(tag);
		try { inst.cls.callFor(inst, 'destroy', []); } catch(e:Dynamic) {}

		var vars = MusicBeatState.getVariables();
		if(vars.get(tag) == inst.sprite) vars.remove(tag);
		if(inst.sprite != null)
		{
			var host:Dynamic = LuaUtils.getTargetInstance();
			if(host != null) host.remove(inst.sprite, true);
			inst.sprite.destroy();
		}
		return true;
	}

	public static function instanceExists(tag:String):Bool
		return instances.exists(tag);

	public static function getSprite(tag:String):FlxSprite
	{
		var inst = instances.get(tag);
		return inst != null ? inst.sprite : null;
	}

	public static function instancesOf(className:String):Array<String>
		return [for (tag in order) if(instances.get(tag).cls.name == className) tag];

	static inline function alive(inst:ScriptedInstance):Bool
	{
		return inst.sprite != null && inst.sprite.exists && MusicBeatState.getVariables().get(inst.tag) == inst.sprite;
	}

	public static function update(elapsed:Float)
	{
		if(order.length < 1) return;
		for (tag in order.copy())
		{
			var inst = instances.get(tag);
			if(inst == null) continue;
			if(!alive(inst)) { instances.remove(tag); order.remove(tag); continue; }
			if(inst.cls.hasUpdate) inst.cls.callFor(inst, 'update', [elapsed]);
		}
	}

	public static function beatHit(beat:Int)
	{
		if(order.length < 1) return;
		for (tag in order.copy())
		{
			var inst = instances.get(tag);
			if(inst != null && inst.cls.hasBeat && alive(inst)) inst.cls.callFor(inst, 'beatHit', [beat]);
		}
	}

	public static function stepHit(step:Int)
	{
		if(order.length < 1) return;
		for (tag in order.copy())
		{
			var inst = instances.get(tag);
			if(inst != null && inst.cls.hasStep && alive(inst)) inst.cls.callFor(inst, 'stepHit', [step]);
		}
	}

	public static function dispatch(func:String, args:Array<Dynamic>, lua:Bool = true, hscript:Bool = true)
	{
		if(order.length < 1 || func == null) return;
		for (tag in order.copy())
		{
			var inst = instances.get(tag);
			if(inst == null || !alive(inst)) continue;
			if(!(inst.cls.isLua ? lua : hscript) || !inst.cls.hasCached(func)) continue;
			try { inst.cls.callFor(inst, func, args != null ? args : []); }
			catch(e:Dynamic) { ScriptLog.error('Scripted class "${inst.cls.name}" ($func)', Std.string(e)); }
		}
	}

	public static function setVar(variable:String, value:Dynamic, lua:Bool = true, hscript:Bool = true)
	{
		if(order.length < 1) return;
		for (cls in classes)
		{
			if(cls.isLua ? !lua : !hscript) continue;
			cls.set(variable, value);
		}
	}

	public static function clear()
	{
		for (cls in classes) cls.dispose();
		classes.clear();
		instances.clear();
		order = [];
	}
}

typedef ScriptedInstance = {
	var tag:String;
	var cls:ClassScript;
	var sprite:FlxSprite;
}

class ClassScript
{
	public var name:String;
	public var hasUpdate:Bool = true;
	public var hasBeat:Bool = true;
	public var hasStep:Bool = true;
	public var isLua:Bool = false;
	#if LUA_ALLOWED var lua:FunkinLua; #end
	#if HSCRIPT_ALLOWED var hx:HScript; #end
	var hasCache:Map<String, Bool> = new Map<String, Bool>();

	public function new(name:String, lua:Dynamic, hx:Dynamic)
	{
		this.name = name;
		isLua = (lua != null);
		#if LUA_ALLOWED this.lua = lua; #end
		#if HSCRIPT_ALLOWED this.hx = hx; #end
		hasUpdate = has('update');
		hasBeat = has('beatHit');
		hasStep = has('stepHit');
	}

	public function has(func:String):Bool
	{
		#if LUA_ALLOWED
		if(lua != null && lua.lua != null)
		{
			Lua.getglobal(lua.lua, func);
			var isFunc:Bool = Lua.type(lua.lua, -1) == Lua.LUA_TFUNCTION;
			Lua.pop(lua.lua, 1);
			return isFunc;
		}
		#end
		#if HSCRIPT_ALLOWED
		if(hx != null) return hx.exists(func);
		#end
		return false;
	}

	public function hasCached(func:String):Bool
	{
		var v:Null<Bool> = hasCache.get(func);
		if(v == null) hasCache.set(func, v = has(func));
		return v;
	}

	public function callFor(inst:ScriptedInstance, func:String, args:Array<Dynamic>):Dynamic
	{
		#if LUA_ALLOWED
		if(lua != null)
		{
			if(lua.closed) return null;
			var full:Array<Dynamic> = [inst.tag];
			var r:Dynamic = lua.call(func, full.concat(args));
			return (r == LuaUtils.Function_Continue) ? null : r;
		}
		#end
		#if HSCRIPT_ALLOWED
		if(hx != null && hx.exists(func))
		{
			var full:Array<Dynamic> = [inst.sprite];
			var c = hx.call(func, full.concat(args));
			return (c != null) ? c.returnValue : null;
		}
		#end
		return null;
	}

	public function set(variable:String, value:Dynamic)
	{
		#if LUA_ALLOWED if(lua != null && !lua.closed) lua.set(variable, value); #end
		#if HSCRIPT_ALLOWED if(hx != null) hx.set(variable, value); #end
	}

	public function dispose()
	{
		#if LUA_ALLOWED if(lua != null) { lua.stop(); lua = null; } #end
		#if HSCRIPT_ALLOWED if(hx != null) { hx.destroy(); hx = null; } #end
	}
}

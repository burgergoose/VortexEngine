package states;

import flixel.FlxState;
import states.MainMenuState;
import states.FreeplayState;
import states.StoryMenuState;
import states.CreditsState;
import states.TitleState;
import options.OptionsState;

class ScriptedState extends MusicBeatState
{
	public var name:String;
	public var args:Array<Dynamic>;

	public function new(name:String, ?args:Array<Dynamic>)
	{
		super();
		this.name = name;
		this.args = (args != null) ? args : [];
		stateScriptName = name;
	}

	override function create()
	{
		persistentUpdate = persistentDraw = true;
		super.create();

		if(!hasStateScripts())
		{
			Main.showToast('Custom state "$name" not found.\nPut it in mods/<your mod>/states/$name.lua (or .hx)');
			new FlxTimer().start(0.01, function(_) MusicBeatState.switchState(new MainMenuState()));
		}
	}

	public static function stateExists(name:String):Bool
	{
		if(name == null || name.length < 1) return false;
		return Mods.findInAnyMod('states/$name.lua') != null || Mods.findInAnyMod('states/$name.hx') != null;
	}

	public static function currentName():String
	{
		var st = Std.downcast(FlxG.state, ScriptedState);
		if(st != null) return st.name;
		return (FlxG.state != null) ? Type.getClassName(Type.getClass(FlxG.state)).split('.').pop() : '';
	}

	static function builtIn(name:String):FlxState
	{
		switch(name.toLowerCase())
		{
			case 'mainmenustate', 'mainmenu': return new MainMenuState();
			case 'freeplaystate', 'freeplay': return new FreeplayState();
			case 'storymenustate', 'storymode', 'storymenu': return new StoryMenuState();
			case 'optionsstate', 'options': return new OptionsState();
			case 'creditsstate', 'credits': return new CreditsState();
			case 'titlestate', 'title': return new TitleState();
			#if MODS_ALLOWED case 'modsmenustate', 'mods': return new ModsMenuState(); #end
		}
		return null;
	}

	public static function switchToState(name:String, ?args:Array<Dynamic>):Bool
	{
		if(name == null || name.trim().length < 1) return false;
		name = name.trim();

		var target:FlxState = null;
		if(stateExists(name)) target = new ScriptedState(name, args);
		else target = builtIn(name);

		if(target == null)
		{
			psychlua.LuaUtils.debugPrint('switchState: no state called "$name" (custom states go in states/$name.lua or .hx)', FlxColor.RED);
			return false;
		}

		if(PlayState.instance != null)
		{
			PlayState.instance.paused = true;
			PlayState.instance.canResync = false;
			if(PlayState.instance.vocals != null) PlayState.instance.vocals.stop();
			if(PlayState.instance.opponentVocals != null) PlayState.instance.opponentVocals.stop();
			if(FlxG.sound.music != null) FlxG.sound.music.stop();
			PlayState.chartingMode = false;
		}
		MusicBeatState.switchState(target);
		return true;
	}
}

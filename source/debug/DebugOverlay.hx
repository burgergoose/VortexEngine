package debug;

import openfl.text.TextField;
import openfl.text.TextFormat;
import backend.VortexConfig;
import debug.FPSCounter;
import states.MainMenuState;
import states.FreeplayState;

class DebugOverlay extends TextField
{
	public var overlayEnabled(default, set):Bool = false;

	public function new(x:Float = 10, y:Float = 68)
	{
		super();
		this.x = x;
		this.y = y;
		selectable = false;
		mouseEnabled = false;
		multiline = true;
		autoSize = LEFT;
		defaultTextFormat = new TextFormat("_sans", 13, 0xFFB8FFEA);
		background = true;
		backgroundColor = 0x000000;
		alpha = 0.85;
		visible = false;
		text = '';
	}

	function set_overlayEnabled(value:Bool):Bool
	{
		overlayEnabled = value;
		visible = value;
		return value;
	}

	var textTimer:Float = 1000;
	override private function __enterFrame(deltaTime:Float):Void
	{
		#if !mobile
		if (FlxG.keys.justPressed.F3)
			overlayEnabled = !overlayEnabled;

		if (!overlayEnabled) return;

		if (FlxG.keys.justPressed.F6) restartSong();
		else if (FlxG.keys.justPressed.F7) reloadEverything();
		else if (FlxG.keys.justPressed.F8) returnToMenu();

		textTimer += deltaTime;
		if (textTimer < 100) return;
		textTimer = 0;
		updateText();
		#end
	}

	inline function inPlayState():Bool
		return PlayState.instance != null && FlxG.state == PlayState.instance;

	public dynamic function updateText():Void
	{
		var lines:Array<String> = [];
		lines.push('${VortexConfig.engineName} v${VortexConfig.engineVersion} -- Developer Mode (F3 to hide)');
		lines.push('FPS: ${Main.fpsVar != null ? Main.fpsVar.currentFPS : 0}  |  Memory: ${flixel.util.FlxStringUtil.formatBytes(FPSCounter.getMemoryBytes())}');

		if (inPlayState())
		{
			var play:PlayState = PlayState.instance;
			lines.push('Song: ${PlayState.SONG != null ? PlayState.SONG.song : "?"}  |  Position: ${Math.round(Conductor.songPosition)}ms  |  BPM: ${Conductor.bpm}  |  Section: ${play.curSection}');
			lines.push('Score: ${play.songScore}  |  Combo: ${play.combo} (best ${play.highestCombo})  |  Misses: ${play.songMisses}');

			var bfAnim:String = (play.boyfriend != null) ? play.boyfriend.getAnimationName() : '-';
			var dadAnim:String = (play.dad != null) ? play.dad.getAnimationName() : '-';
			var gfAnim:String = (play.gf != null) ? play.gf.getAnimationName() : '-';
			lines.push('BF anim: $bfAnim  |  Dad anim: $dadAnim  |  GF anim: $gfAnim');

			var hxCount:Int = 0;
			#if HSCRIPT_ALLOWED if (play.hscriptArray != null) hxCount = play.hscriptArray.length; #end
			var luaCount:Int = 0;
			#if LUA_ALLOWED if (play.luaArray != null) luaCount = play.luaArray.length; #end
			lines.push('Notes: ${play.notes != null ? play.notes.length : 0} on screen, ${play.unspawnNotes.length} waiting  |  Chart built in ${play.chartBuildMs}ms  |  Scripts: $luaCount Lua, $hxCount HScript');

			if (play.camGame != null && play.camHUD != null)
				lines.push('Cam Game: zoom=${flixelRound(play.camGame.zoom)} pos=(${flixelRound(play.camGame.scroll.x)}, ${flixelRound(play.camGame.scroll.y)})  |  Cam HUD: zoom=${flixelRound(play.camHUD.zoom)}');

			lines.push('[F6] Restart Song   [F7] Reload Scripts/Stage/Characters   [F8] Return to Menu');
		}
		else
		{
			lines.push('(Song info only shows up while a song is loaded)');
		}

		if (psychlua.ScriptLog.errorCount > 0)
			lines.push('Script errors: ${psychlua.ScriptLog.errorCount} (details in ${psychlua.ScriptLog.FILE})');
			lines.push('Build: ' + backend.BuildVerifier.describe());
		lines.push(backend.AntiAliasing.describe());

		text = lines.join('\n');
		textColor = 0xFFB8FFEA;
	}

	inline function flixelRound(n:Float):Float
		return Math.round(n * 100) / 100;

	function restartSong():Void
	{
		if (!inPlayState() || FlxG.state.subState != null) return;

		FlxTransitionableState.skipNextTransIn = true;
		FlxTransitionableState.skipNextTransOut = true;
		PlayState.nextReloadAll = true;
		MusicBeatState.resetState();
	}

	function reloadEverything():Void
	{
		psychlua.ScriptLog.reset();
		restartSong();
	}

	function returnToMenu():Void
	{
		if (!inPlayState() || FlxG.state.subState != null) return;

		FlxG.sound.music.stop();
		FreeplayState.destroyFreeplayVocals();
		#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
		Mods.loadTopMod();
		overlayEnabled = false;
		MusicBeatState.switchState(new MainMenuState());
	}
}

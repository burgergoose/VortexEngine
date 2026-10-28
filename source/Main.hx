package;

#if android
import android.content.Context;
#end

import debug.FPSCounter;
import debug.DebugOverlay;
import backend.VortexConfig;

import flixel.graphics.FlxGraphic;
import flixel.FlxGame;
import flixel.addons.transition.FlxTransitionableState;
import flixel.FlxState;
import haxe.io.Path;
import openfl.Assets;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.display.StageScaleMode;
import lime.app.Application;
import states.TitleState;

#if HSCRIPT_ALLOWED
import crowplexus.iris.Iris;
import psychlua.HScript.HScriptInfos;
#end

#if (linux || mac)
import lime.graphics.Image;
#end

#if desktop
import backend.ALSoftConfig;
#end

#if CRASH_HANDLER
import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
import haxe.io.Path;
#end

import backend.Highscore;

#if (linux && !debug)
@:cppInclude('./external/gamemode_client.h')
@:cppFileCode('#define GAMEMODE_AUTO')
#end

class Main extends Sprite
{
	public static final game = {
		width: 1280,
		height: 720,
		initialState: TitleState,
		framerate: 60,
		skipSplash: true,
		startFullscreen: false
	};

	public static var fpsVar:FPSCounter;
	public static var debugOverlay:DebugOverlay;

	public static function main():Void
	{
		Lib.current.addChild(new Main());
	}

	static var __bootLog:sys.io.FileOutput = null;
	static function checkpoint(msg:String):Void
	{
		try
		{
			if (__bootLog == null)
				__bootLog = sys.io.File.append("vortex_boot_log.txt", false);
			__bootLog.writeString(Date.now().toString() + " - " + msg + "\n");
			__bootLog.flush();
		}
		catch (e:Dynamic) {}
	}

	public function new()
	{
		super();
		checkpoint("Main.new() started");

		#if CRASH_HANDLER
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onCrash);
		#end
		checkpoint("crash handler registered");

		#if (desktop && sys)
		try
		{
			var exeDir:String = Path.directory(Sys.programPath());
			if (exeDir != null && exeDir.length > 0 && sys.FileSystem.exists(Path.join([exeDir, 'assets'])))
				Sys.setCwd(exeDir);
		}
		catch (e:Dynamic) {}
		#end
		#if sys checkpoint("working directory set to " + Sys.getCwd()); #end

		VortexConfig.load();
		checkpoint("VortexConfig.load() done");
		states.MainMenuState.psychEngineVersion = VortexConfig.engineVersion;

		#if (cpp && windows)
		backend.Native.fixScaling();
		checkpoint("Native.fixScaling() done");
		#end

		// Credits to MAJigsaw77 (he's the og author for this code)
		#if android
		Sys.setCwd(Path.addTrailingSlash(Context.getExternalFilesDir()));
		#elseif ios
		Sys.setCwd(lime.system.System.applicationStorageDirectory);
		#end
		#if VIDEOS_ALLOWED
		hxvlc.util.Handle.init(#if (hxvlc >= "1.8.0")  ['--no-lua'] #end);
		#end

		#if LUA_ALLOWED
		Mods.pushGlobalMods();
		checkpoint("Mods.pushGlobalMods() done");
		#end
		Mods.loadTopMod();
		checkpoint("Mods.loadTopMod() done");
		backend.ModDiagnostics.write();

		FlxG.save.bind('funkin', CoolUtil.getSavePath());
		checkpoint("FlxG.save.bind() done");
		Highscore.load();
		checkpoint("Highscore.load() done");

		#if HSCRIPT_ALLOWED
		for (old => now in ['flixel.system.FlxSound' => 'flixel.sound.FlxSound', 'flixel.system.FlxSoundGroup' => 'flixel.sound.FlxSoundGroup', 'flixel.util.FlxPath' => 'flixel.path.FlxPath'])
		{
			var c:Dynamic = Type.resolveClass(now);
			if (c != null) Iris.addProxyImport(old, c);
		}
		Iris.warn = function(x, ?pos:haxe.PosInfos) {
			Iris.logLevel(WARN, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null) newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '')  + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true) {
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true) {
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('WARNING: $msgInfo', FlxColor.YELLOW);
		}
		Iris.error = function(x, ?pos:haxe.PosInfos) {
			Iris.logLevel(ERROR, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null) newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '')  + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true) {
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true) {
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (psychlua.ScriptLog.error('HScript: ${newPos.fileName}', '$msgInfo'))
				psychlua.LuaUtils.debugPrint('ERROR: $msgInfo', FlxColor.RED);
		}
		Iris.fatal = function(x, ?pos:haxe.PosInfos) {
			Iris.logLevel(FATAL, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null) newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '')  + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true) {
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true) {
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			psychlua.ScriptLog.error('HScript: ${newPos.fileName}', 'FATAL: $msgInfo');
			psychlua.LuaUtils.debugPrint('FATAL: $msgInfo', 0xFFBB0000);
		}
		checkpoint("HScript callbacks wired");
		#end

		#if (LUA_ALLOWED && cpp) Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(psychlua.CallbackHandler.call)); #end
		checkpoint("Lua callbacks wired");
		Controls.instance = new Controls();
		ClientPrefs.loadDefaultKeys();
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end
		checkpoint("Controls+ClientPrefs+Achievements done -- about to create FlxGame window");
		addChild(new FlxGame(game.width, game.height, game.initialState, game.framerate, game.framerate, game.skipSplash, game.startFullscreen));
		checkpoint("FlxGame created (window should exist now)");

		#if !mobile
		fpsVar = new FPSCounter(10, 3, 0xFFFFFF);
		addChild(fpsVar);
		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
		if(fpsVar != null) {
			fpsVar.visible = ClientPrefs.data.showFPS;
		}

		debugOverlay = new DebugOverlay(10, fpsVar.y + 24);
		addChild(debugOverlay);
		#end
		checkpoint("FPSCounter+DebugOverlay added");

		#if (linux || mac)
		var icon = Image.fromFile("icon.png");
		Lib.current.stage.window.setIcon(icon);
		#end

		#if desktop
		Lib.current.stage.window.title = "Friday Night Funkin': " + VortexConfig.engineName;
		#end
		try { backend.BuildVerifier.start(); } catch(e:Dynamic) { trace('Build check could not start: $e'); }
		checkpoint("Main.new() fully complete");

		#if html5
		FlxG.autoPause = false;
		FlxG.mouse.visible = false;
		#end

		FlxG.fixedTimestep = false;
		FlxG.game.focusLostFramerate = 60;
		FlxG.keys.preventDefaultKeys = [TAB];

		#if DISCORD_ALLOWED
		DiscordClient.prepare();
		#end

		FlxG.signals.gameResized.add(function (w, h) {
		     if (FlxG.cameras != null) {
			   for (cam in FlxG.cameras.list) {
				if (cam != null && cam.filters != null)
					resetSpriteCache(cam.flashSprite);
			   }
			}

			if (FlxG.game != null)
			resetSpriteCache(FlxG.game);
		});
	}

	static function resetSpriteCache(sprite:Sprite):Void {
		@:privateAccess {
		        sprite.__cacheBitmap = null;
			sprite.__cacheBitmapData = null;
		}
	}

	// Code was entirely made by sqirra-rng for their fnf engine named "Izzy Engine", big props to them!!!
	public static function showToast(text:String):Void
	{
		try
		{
			var tf:openfl.text.TextField = new openfl.text.TextField();
			var fontName:String = '_sans';
			try { fontName = openfl.utils.Assets.getFont(backend.Paths.font('vcr.ttf')).fontName; } catch (_:Dynamic) {}
			tf.embedFonts = (fontName != '_sans');
			tf.defaultTextFormat = new openfl.text.TextFormat(fontName, 15, 0xFFFFFF);
			tf.background = true;
			tf.backgroundColor = 0x7A1020;
			tf.width = 700;
			tf.height = 84;
			tf.multiline = true;
			tf.wordWrap = true;
			tf.selectable = false;
			tf.mouseEnabled = false;
			tf.text = text;
			tf.x = 20;
			tf.y = 20;
			Lib.current.stage.addChild(tf);
			haxe.Timer.delay(function() { try { Lib.current.stage.removeChild(tf); } catch (_:Dynamic) {} }, 9000);
			trace('toast shown: ' + text.split('\n')[0]);
		}
		catch (e:Dynamic) { trace('toast failed: $e'); }
	}

	#if CRASH_HANDLER
	function onCrash(e:UncaughtErrorEvent):Void
	{
		var errMsg:String = "";
		var path:String;
		var callStack:Array<StackItem> = CallStack.exceptionStack(true);
		var dateNow:String = Date.now().toString();

		dateNow = dateNow.replace(" ", "_");
		dateNow = dateNow.replace(":", "'");

		var enginePrefix:String = VortexConfig.engineName.replace(" ", "");
		path = "./crash/" + enginePrefix + "_" + dateNow + ".txt";

		for (stackItem in callStack)
		{
			switch (stackItem)
			{
				case FilePos(s, file, line, column):
					errMsg += file + " (line " + line + ")\n";
				default:
					Sys.println(stackItem);
			}
		}

		errMsg += "\nUncaught Error: " + e.error;
		#if officialBuild
		if(VortexConfig.issueTrackerUrl != null && VortexConfig.issueTrackerUrl.length > 0)
			errMsg += "\nPlease report this error to: " + VortexConfig.issueTrackerUrl;
		#end
		errMsg += "\n\n> Crash Handler written by: sqirra-rng";

		if (!FileSystem.exists("./crash/"))
			FileSystem.createDirectory("./crash/");

		File.saveContent(path, errMsg + "\n");

		Sys.println(errMsg);
		Sys.println("Crash dump saved in " + Path.normalize(path));

		var now:Float = Sys.time();
		recentCrashes = recentCrashes.filter(function(t:Float) return now - t < 10);
		recentCrashes.push(now);
		if (recentCrashes.length <= 2 && FlxG.game != null)
		{
			try
			{
				e.preventDefault();
				var firstLine:String = e.error != null ? Std.string(e.error) : 'unknown error';
				FlxTransitionableState.skipNextTransIn = true;
				FlxTransitionableState.skipNextTransOut = true;
				try { if (FlxG.sound.music != null) FlxG.sound.music.stop(); } catch (_:Dynamic) {}
				FlxG.switchState(new states.MainMenuState());
				try { FlxG.sound.playMusic(Paths.music('freakyMenu'), 0.7); } catch (_:Dynamic) {}
				showToast('Something went wrong and the game recovered.\n(' + firstLine + ')\nDetails: ' + Path.normalize(path));
				return;
			}
			catch (_:Dynamic) {}
		}

		Application.current.window.alert(errMsg, "Error!");
		#if DISCORD_ALLOWED
		DiscordClient.shutdown();
		#end
		Sys.exit(1);
	}

	static var recentCrashes:Array<Float> = [];


	#end
}

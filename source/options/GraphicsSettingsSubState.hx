package options;

import objects.Character;

class GraphicsSettingsSubState extends BaseOptionsMenu
{
	var antialiasingOption:Int;
	var boyfriend:Character = null;
	public function new()
	{
		title = Language.getPhrase('graphics_menu', 'Graphics Settings');
		rpcTitle = 'Graphics Settings Menu';

		boyfriend = new Character(840, 170, 'bf', true);
		boyfriend.setGraphicSize(Std.int(boyfriend.width * 0.75));
		boyfriend.updateHitbox();
		boyfriend.dance();
		boyfriend.animation.finishCallback = function (name:String) boyfriend.dance();
		boyfriend.visible = false;

		var option:Option = new Option('Low Quality',
			'If checked, disables some background details,\ndecreases loading times and improves performance.',
			'lowQuality',
			BOOL);
		addOption(option);

		var option:Option = new Option('Anti-Aliasing',
			'If unchecked, disables anti-aliasing, increases performance\nat the cost of sharper visuals.',
			'antialiasing',
			BOOL);
		option.onChange = onChangeAntiAliasing;
		addOption(option);
		antialiasingOption = optionsArray.length-1;

		var option:Option = new Option('Anti-Aliasing Quality',
			'Ultra: everything drawn at 2x and scaled down (smoothest, needs a good GPU). Max: smooth edges\n(MSAA) and smooth shrunk sprites (mipmaps). High: edges only. Classic: like Psych. Needs Anti-Aliasing on.',
			'antialiasingQuality',
			STRING,
			backend.AntiAliasing.LEVELS);
		option.onChange = backend.AntiAliasing.apply;
		addOption(option);

		var option:Option = new Option('Shaders',
			"If unchecked, disables shaders.\nIt's used for some visual effects, and also CPU intensive for weaker PCs.",
			'shaders',
			BOOL);
		addOption(option);

		var option:Option = new Option('GPU Caching',
			"If checked, textures are only kept on the GPU, which saves a lot of RAM.\nTurn it off only if a mod needs to read pixels from its images.",
			'cacheOnGPU',
			BOOL);
		addOption(option);

		var option:Option = new Option('VortexPixel',
			"If checked, sprites get cached on the GPU in a smaller format (BC7) after the first time\nyou see them, so they load faster. Needs GPU Caching.",
			'vortexPixel',
			BOOL);
		addOption(option);

		var option:Option = new Option('VortexPixel Enhance',
			"If checked, VortexPixel goes over every pixel of a sprite and makes a sharper 2x version\n(same colours and outlines). Only used when sprites are drawn 1.6x bigger or more. Uses more RAM.",
			'vortexEnhance',
			BOOL);
		addOption(option);

		var option:Option = new Option('Stream Song Audio',
			"If checked, songs play straight from the .ogg file instead of being decoded into RAM first.\nLoads faster and uses a lot less RAM. Turn it off if a mod needs the raw audio.",
			'streamAudio',
			BOOL);
		addOption(option);

		#if !html5
		var option:Option = new Option('Framerate',
			"Pretty self explanatory, isn't it?",
			'framerate',
			INT);
		addOption(option);

		final refreshRate:Int = FlxG.stage.application.window.displayMode.refreshRate;
		option.minValue = 60;
		option.maxValue = 240;
		option.defaultValue = Std.int(FlxMath.bound(refreshRate, option.minValue, option.maxValue));
		option.displayFormat = '%v FPS';
		option.onChange = onChangeFramerate;
		#end

		super();
		insert(1, boyfriend);
	}

	function onChangeAntiAliasing()
	{
		for (sprite in members)
		{
			var sprite:FlxSprite = cast sprite;
			if(sprite != null && (sprite is FlxSprite) && !(sprite is FlxText)) {
				sprite.antialiasing = ClientPrefs.data.antialiasing;
			}
		}
		backend.AntiAliasing.apply();
	}

	function onChangeFramerate()
	{
		if(ClientPrefs.data.framerate > FlxG.drawFramerate)
		{
			FlxG.updateFramerate = ClientPrefs.data.framerate;
			FlxG.drawFramerate = ClientPrefs.data.framerate;
		}
		else
		{
			FlxG.drawFramerate = ClientPrefs.data.framerate;
			FlxG.updateFramerate = ClientPrefs.data.framerate;
		}
	}

	override function changeSelection(change:Int = 0)
	{
		super.changeSelection(change);
		boyfriend.visible = (antialiasingOption == curSelected);
	}
}
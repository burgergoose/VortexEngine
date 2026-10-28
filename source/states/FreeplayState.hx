package states;

import backend.WeekData;
import backend.Highscore;
import backend.Song;
import backend.SongRank;
import backend.VortexConfig;

import objects.MusicPlayer;
import objects.SongCard;
import objects.HealthIcon;
import objects.CosmicBackground;
import objects.SongInfoPanel;
import objects.KeyHints;

import options.GameplayChangersSubstate;
import substates.ResetScoreSubState;

import flixel.math.FlxMath;
import flixel.util.FlxDestroyUtil;

import openfl.utils.Assets;

import haxe.Json;

class FreeplayState extends MusicBeatState
{
	var songs:Array<SongMetadata> = [];

	var selector:FlxText;
	private static var curSelected:Int = 0;
	var lerpSelected:Float = 0;
	var curDifficulty:Int = -1;

	var scoreBG:FlxSprite;
	var scoreText:FlxText;
	var lerpScore:Int = 0;
	var lerpRating:Float = 0;
	var intendedScore:Int = 0;
	var intendedRating:Float = 0;

	private var grpSongs:FlxTypedGroup<SongCard>;
	private var curPlaying:Bool = false;

	var cosmicBg:CosmicBackground;

	var missingTextBG:FlxSprite;
	var missingText:FlxText;
	public var diffText:FlxText;
	var songStartDiff:Array<Int> = [];

	var bottomString:String;
	var bottomText:FlxText;
	var bottomBG:FlxSprite;

	var player:MusicPlayer;

	static inline var LIST_X:Float = 40;
	static inline var LIST_W:Int = 700;
	static inline var HEADER_H:Int = 84;
	var infoPanel:SongInfoPanel;
	var keyHints:KeyHints;
	var headerSub:FlxText;
	var headerCount:FlxText;
	var classic:Bool = false;
	var showInfo:Bool = true;
	var listX:Float = LIST_X;
	var classicBg:FlxSprite;
	var classicTexts:Array<Alphabet> = [];
	var classicIcons:Array<HealthIcon> = [];
	var classicColorTween:FlxTween;

	override function create()
	{
		Paths.clearStoredMemory();

		persistentUpdate = true;
		PlayState.isStoryMode = false;
		WeekData.reloadWeekFiles(false);

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("In Freeplay", null);
		#end

		if(WeekData.weeksList.length < 1)
		{
			FlxTransitionableState.skipNextTransIn = true;
			persistentUpdate = false;
			MusicBeatState.switchState(new states.ErrorState("NO WEEKS ADDED FOR FREEPLAY\n\nPress ACCEPT to go to the Week Editor Menu.\nPress BACK to return to Main Menu.",
				function() MusicBeatState.switchState(new states.editors.WeekEditorState()),
				function() MusicBeatState.switchState(new states.MainMenuState())));
			return;
		}

		for (i in 0...WeekData.weeksList.length)
		{
			if(weekIsLocked(WeekData.weeksList[i])) continue;

			var leWeek:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			var leSongs:Array<String> = [];
			var leChars:Array<String> = [];

			for (j in 0...leWeek.songs.length)
			{
				leSongs.push(leWeek.songs[j][0]);
				leChars.push(leWeek.songs[j][1]);
			}

			WeekData.setDirectoryFromWeek(leWeek);
			for (song in leWeek.songs)
			{
				var colors:Array<Int> = song[2];
				if(colors == null || colors.length < 3)
				{
					colors = [146, 113, 253];
				}
				addSong(song[0], i, song[1], FlxColor.fromRGB(colors[0], colors[1], colors[2]));
			}
		}
		Mods.loadTopMod();

		classic = MenuTheme.isClassic;
		showInfo = !classic && MenuTheme.screenValue('freeplay', 'showInfoPanel', true) != false;
		if (!showInfo) listX = (FlxG.width - LIST_W) / 2;
		if (classic)
		{
			classicBg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
			classicBg.antialiasing = ClientPrefs.data.antialiasing;
			classicBg.screenCenter();
			add(classicBg);
		}
		else
		{
			var bgObj = MenuTheme.background('freeplay');
			if (Std.isOfType(bgObj, CosmicBackground)) cosmicBg = cast bgObj;
			add(bgObj);
		}

		grpSongs = new FlxTypedGroup<SongCard>();
		add(grpSongs);

		for (i in 0...songs.length)
		{
			Mods.currentModDirectory = songs[i].folder;
			PlayState.storyWeek = songs[i].week;
			Difficulty.loadFromWeek();
			var songDiff:Int = Difficulty.startIndex(songs[i].songName);
			songStartDiff.push(songDiff);

			var card:SongCard = new SongCard(songs[i].songName, songs[i].songCharacter, songDiff, LIST_W);
			card.x = LIST_X;
			card.y = 0;

			card.visible = card.active = false;

			grpSongs.add(card);

			if (classic)
			{
				var songText:Alphabet = new Alphabet(90, 320, songs[i].songName, true);
				songText.targetY = i;
				songText.scaleX = Math.min(1, 980 / songText.width);
				songText.snapToPosition();
				songText.visible = songText.active = songText.isMenuItem = false;
				add(songText);
				classicTexts.push(songText);
				var icon:HealthIcon = new HealthIcon(songs[i].songCharacter);
				icon.sprTracker = songText;
				icon.visible = icon.active = false;
				add(icon);
				classicIcons.push(icon);
			}
		}
		WeekData.setDirectoryFromWeek();

		scoreText = new FlxText(40, 36, FlxG.width - 80, "", 36);
		scoreText.setFormat(MenuTheme.font(), 36, MenuTheme.TEXT_BRIGHT, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scoreText.text = Std.string(MenuTheme.screenValue('freeplay', 'title', 'FREEPLAY'));

		scoreBG = new FlxSprite(0, 0).makeGraphic(1, HEADER_H, FlxColor.WHITE);
		scoreBG.color = MenuTheme.PANEL_FILL;
		scoreBG.alpha = 0.92;
		scoreBG.scale.x = FlxG.width;
		scoreBG.updateHitbox();
		add(scoreBG);

		add(scoreText);

		headerSub = new FlxText(0, 16, FlxG.width - 40, VortexConfig.engineName.toUpperCase(), 16);
		headerSub.setFormat(MenuTheme.font(), 16, MenuTheme.TEXT_DIM, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(headerSub);
		headerCount = new FlxText(0, 42, FlxG.width - 40, songs.length + (songs.length == 1 ? " SONG" : " SONGS"), 24);
		headerCount.setFormat(MenuTheme.font(), 24, MenuTheme.ACCENT_CYAN, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(headerCount);

		infoPanel = new SongInfoPanel(LIST_X + LIST_W + 40, HEADER_H + 30);
		add(infoPanel);
		if (!showInfo) infoPanel.visible = false;
		if (classic)
		{
			scoreText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, RIGHT);
			scoreText.fieldWidth = 0;
			scoreText.setPosition(FlxG.width * 0.7, 5);
			scoreBG.makeGraphic(1, 66, FlxColor.BLACK);
			scoreBG.color = FlxColor.WHITE;
			scoreBG.alpha = 0.6;
			headerSub.visible = headerCount.visible = false;
		}

		diffText = new FlxText(0, 40, FlxG.width, '', 28);
		diffText.setFormat(MenuTheme.font(), 28, MenuTheme.ACCENT_CYAN, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		if (classic)
		{
			diffText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, LEFT);
			diffText.fieldWidth = 0;
			diffText.y = scoreText.y + 36;
		}
		add(diffText);


		missingTextBG = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		missingTextBG.alpha = 0.6;
		missingTextBG.visible = false;
		add(missingTextBG);
		
		missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		missingText.setFormat(MenuTheme.font(), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingText.scrollFactor.set();
		missingText.visible = false;
		add(missingText);

		if(curSelected >= songs.length) curSelected = 0;
		lerpSelected = curSelected;
		if(grpSongs.members[curSelected] != null) grpSongs.members[curSelected].setSelected(true);

		bottomBG = new FlxSprite(0, FlxG.height - 34).makeGraphic(FlxG.width, 34, 0xFF000000);
		bottomBG.alpha = 0.6;
		add(bottomBG);

		var leText:String = Language.getPhrase("freeplay_tip", "Press SPACE to listen to the Song / Press CTRL to open the Gameplay Changers Menu / Press RESET to Reset your Score and Accuracy.");
		bottomString = leText;
		var size:Int = 16;
		bottomText = new FlxText(bottomBG.x, bottomBG.y + 8, FlxG.width, leText, size);
		bottomText.setFormat(MenuTheme.font(), size, FlxColor.WHITE, CENTER);
		bottomText.scrollFactor.set();
		add(bottomText);

		keyHints = new KeyHints(0, bottomBG.y + 6, FlxG.width, [['ENTER', 'Play'], ['< >', 'Difficulty'], ['SPACE', 'Listen'], ['CTRL', 'Gameplay changers'], ['R', 'Reset score'], ['ESC', 'Back']]);
		add(keyHints);
		
		player = new MusicPlayer(this);
		add(player);
		
		changeSelection();
		updateTexts();
		super.create();

		Paths.clearUnusedSounds();
		Paths.clearUnusedMemory();
	}

	override function closeSubState()
	{
		changeSelection(0, false);
		if(grpSongs.members[curSelected] != null) grpSongs.members[curSelected].refreshStats();
		persistentUpdate = true;
		super.closeSubState();
	}

	public function addSong(songName:String, weekNum:Int, songCharacter:String, color:Int)
	{
		songs.push(new SongMetadata(songName, weekNum, songCharacter, color));
	}

	function weekIsLocked(name:String):Bool
	{
		var leWeek:WeekData = WeekData.weeksLoaded.get(name);
		return (!leWeek.startUnlocked && leWeek.weekBefore.length > 0 && (!StoryMenuState.weekCompleted.exists(leWeek.weekBefore) || !StoryMenuState.weekCompleted.get(leWeek.weekBefore)));
	}

	var instPlaying:Int = -1;
	public static var vocals:FlxSound = null;
	public static var opponentVocals:FlxSound = null;
	var holdTime:Float = 0;

	var stopMusicPlay:Bool = false;
	override function update(elapsed:Float)
	{
		if(WeekData.weeksList.length < 1)
			return;

		if (FlxG.sound.music.volume < 0.7)
			FlxG.sound.music.volume += 0.5 * elapsed;

		lerpScore = Math.floor(FlxMath.lerp(intendedScore, lerpScore, Math.exp(-elapsed * 24)));
		lerpRating = FlxMath.lerp(intendedRating, lerpRating, Math.exp(-elapsed * 12));

		if (Math.abs(lerpScore - intendedScore) <= 10)
			lerpScore = intendedScore;
		if (Math.abs(lerpRating - intendedRating) <= 0.01)
			lerpRating = intendedRating;

		var ratingSplit:Array<String> = Std.string(CoolUtil.floorDecimal(lerpRating * 100, 2)).split('.');
		if(ratingSplit.length < 2)
			ratingSplit.push('');
		
		while(ratingSplit[1].length < 2)
			ratingSplit[1] += '0';

		var shiftMult:Int = 1;
		if(FlxG.keys.pressed.SHIFT) shiftMult = 3;

		if (!player.playingMusic)
		{
			if(songs.length > 1)
			{
				if(FlxG.keys.justPressed.HOME)
				{
					curSelected = 0;
					changeSelection();
					holdTime = 0;	
				}
				else if(FlxG.keys.justPressed.END)
				{
					curSelected = songs.length - 1;
					changeSelection();
					holdTime = 0;	
				}
				if (controls.UI_UP_P)
				{
					changeSelection(-shiftMult);
					holdTime = 0;
				}
				if (controls.UI_DOWN_P)
				{
					changeSelection(shiftMult);
					holdTime = 0;
				}

				if(controls.UI_DOWN || controls.UI_UP)
				{
					var checkLastHold:Int = Math.floor((holdTime - 0.5) * 10);
					holdTime += elapsed;
					var checkNewHold:Int = Math.floor((holdTime - 0.5) * 10);

					if(holdTime > 0.5 && checkNewHold - checkLastHold > 0)
						changeSelection((checkNewHold - checkLastHold) * (controls.UI_UP ? -shiftMult : shiftMult));
				}

				if(FlxG.mouse.wheel != 0)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.2);
					changeSelection(-shiftMult * FlxG.mouse.wheel, false);
				}
			}
			if (controls.UI_LEFT_P) changeDiff(-1);
			else if (controls.UI_RIGHT_P) changeDiff(1);
		}

		if (controls.BACK)
		{
			if (player.playingMusic)
			{
				FlxG.sound.music.stop();
				destroyFreeplayVocals();
				FlxG.sound.music.volume = 0;
				instPlaying = -1;

				player.playingMusic = false;
				player.switchPlayMusic();

				FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
				FlxTween.tween(FlxG.sound.music, {volume: 1}, 1);
			}
			else 
			{
				persistentUpdate = false;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new MainMenuState());
			}
		}

		if(FlxG.keys.justPressed.CONTROL && !player.playingMusic)
		{
			persistentUpdate = false;
			openSubState(new GameplayChangersSubstate());
		}
		else if(FlxG.keys.justPressed.SPACE)
		{
			if(instPlaying != curSelected && !player.playingMusic)
			{
				destroyFreeplayVocals();
				FlxG.sound.music.volume = 0;

				Mods.currentModDirectory = songs[curSelected].folder;
				var poop:String = Highscore.formatSong(songs[curSelected].songName.toLowerCase(), curDifficulty);
				Song.loadFromJson(poop, songs[curSelected].songName.toLowerCase());
				if (PlayState.SONG.needsVoices)
				{
					vocals = new FlxSound();
					try
					{
						var playerVocals:String = getVocalFromCharacter(PlayState.SONG.player1);
						var loadedVocals = Paths.voices(PlayState.SONG.song, (playerVocals != null && playerVocals.length > 0) ? playerVocals : 'Player');
						if(loadedVocals == null) loadedVocals = Paths.voices(PlayState.SONG.song);
						
						if(loadedVocals != null && loadedVocals.length > 0)
						{
							vocals.loadEmbedded(loadedVocals);
							FlxG.sound.list.add(vocals);
							vocals.persist = vocals.looped = true;
							vocals.volume = 0.8;
							vocals.play();
							vocals.pause();
						}
						else vocals = FlxDestroyUtil.destroy(vocals);
					}
					catch(e:Dynamic)
					{
						vocals = FlxDestroyUtil.destroy(vocals);
					}
					
					opponentVocals = new FlxSound();
					try
					{
						var oppVocals:String = getVocalFromCharacter(PlayState.SONG.player2);
						var loadedVocals = Paths.voices(PlayState.SONG.song, (oppVocals != null && oppVocals.length > 0) ? oppVocals : 'Opponent');
						
						if(loadedVocals != null && loadedVocals.length > 0)
						{
							opponentVocals.loadEmbedded(loadedVocals);
							FlxG.sound.list.add(opponentVocals);
							opponentVocals.persist = opponentVocals.looped = true;
							opponentVocals.volume = 0.8;
							opponentVocals.play();
							opponentVocals.pause();
						}
						else opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
					}
					catch(e:Dynamic)
					{
						opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
					}
				}

				FlxG.sound.playMusic(Paths.inst(PlayState.SONG.song), 0.8);
				FlxG.sound.music.pause();
				instPlaying = curSelected;

				player.playingMusic = true;
				player.curTime = 0;
				player.switchPlayMusic();
				player.pauseOrResume(true);
			}
			else if (instPlaying == curSelected && player.playingMusic)
			{
				player.pauseOrResume(!player.playing);
			}
		}
		else if (controls.ACCEPT && !player.playingMusic)
		{
			persistentUpdate = false;
			var songLowercase:String = Paths.formatToSongPath(songs[curSelected].songName);
			var poop:String = Highscore.formatSong(songLowercase, curDifficulty);

			try
			{
				Song.loadFromJson(poop, songLowercase);
				PlayState.isStoryMode = false;
				PlayState.storyDifficulty = curDifficulty;

				trace('CURRENT WEEK: ' + WeekData.getWeekFileName());
			}
			catch(e:haxe.Exception)
			{
				trace('ERROR! ${e.message}');

				var errorStr:String = e.message;
				if(errorStr.contains('There is no TEXT asset with an ID of')) errorStr = 'Missing file: ' + errorStr.substring(errorStr.indexOf(songLowercase), errorStr.length-1);
				else errorStr += '\n\n' + e.stack;

				missingText.text = 'ERROR WHILE LOADING CHART:\n$errorStr';
				missingText.screenCenter(Y);
				missingText.visible = true;
				missingTextBG.visible = true;
				FlxG.sound.play(Paths.sound('cancelMenu'));

				updateTexts(elapsed);
				super.update(elapsed);
				return;
			}

			@:privateAccess
			if(PlayState._lastLoadedModDirectory != Mods.currentModDirectory)
			{
				trace('CHANGED MOD DIRECTORY, RELOADING STUFF');
				Paths.freeGraphicsFromMemory();
			}
			LoadingState.prepareToSong();
			LoadingState.loadAndSwitchState(new PlayState());
			#if !SHOW_LOADING_SCREEN FlxG.sound.music.stop(); #end
			stopMusicPlay = true;

			destroyFreeplayVocals();
			#if (MODS_ALLOWED && DISCORD_ALLOWED)
			DiscordClient.loadModRPC();
			#end
		}
		else if(controls.RESET && !player.playingMusic)
		{
			persistentUpdate = false;
			openSubState(new ResetScoreSubState(songs[curSelected].songName, curDifficulty, songs[curSelected].songCharacter));
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}

		updateTexts(elapsed);
		super.update(elapsed);
	}

	function updateInfoPanel():Void
	{
		if (infoPanel == null) return;
		if (classic)
		{
			keyHints.visible = false;
			bottomText.alpha = 1;
			headerSub.visible = headerCount.visible = false;
			return;
		}
		infoPanel.setLive(lerpScore, lerpRating);
		var showHints:Bool = (bottomText.text == bottomString);
		keyHints.visible = showHints && bottomText.visible;
		bottomText.alpha = showHints ? 0 : 1;
		headerSub.visible = headerCount.visible = scoreText.visible;
	}
	
	function getVocalFromCharacter(char:String)
	{
		try
		{
			var path:String = Paths.getPath('characters/$char.json', TEXT);
			#if MODS_ALLOWED
			var character:Dynamic = Json.parse(File.getContent(path));
			#else
			var character:Dynamic = Json.parse(Assets.getText(path));
			#end
			return character.vocals_file;
		}
		catch (e:Dynamic) {}
		return null;
	}

	public static function destroyFreeplayVocals() {
		if(vocals != null) vocals.stop();
		vocals = FlxDestroyUtil.destroy(vocals);

		if(opponentVocals != null) opponentVocals.stop();
		opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
	}

	function resolveDifficulty():Void
	{
		curDifficulty = Difficulty.startIndex(songs[curSelected].songName);
		refreshDifficulty();
	}

	function changeDiff(change:Int = 0)
	{
		if (player.playingMusic || songs.length < 1) return;
		var old:Int = curDifficulty;
		curDifficulty = Difficulty.step(songs[curSelected].songName, curDifficulty, change);
		if (change != 0 && old != curDifficulty) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		Difficulty.lastPicked = Difficulty.getString(curDifficulty, false);
		refreshDifficulty();
		refreshInfoPanel();
	}

	function refreshDifficulty():Void
	{
		#if !switch
		intendedScore = Highscore.getScore(songs[curSelected].songName, curDifficulty);
		intendedRating = Highscore.getRating(songs[curSelected].songName, curDifficulty);
		#end

		if (diffText != null)
		{
			var shown:String = Difficulty.getString(curDifficulty).toUpperCase();
			diffText.text = Difficulty.available(songs[curSelected].songName).length > 1 ? '< ' + shown + ' >' : shown;
			if (classic) positionClassicDiff();
		}
		if (grpSongs.members[curSelected] != null) grpSongs.members[curSelected].setDifficulty(curDifficulty);

		missingText.visible = false;
		missingTextBG.visible = false;
	}

	function positionClassicDiff():Void
	{
		diffText.x = Std.int(FlxG.width - scoreBG.scale.x / 2 - diffText.width / 2);
	}

	function changeSelection(change:Int = 0, playSound:Bool = true)
	{
		if (player.playingMusic)
			return;

		var previousSelected:Int = curSelected;
		curSelected = FlxMath.wrap(curSelected + change, 0, songs.length-1);
		if(playSound) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		if(grpSongs.members[previousSelected] != null) grpSongs.members[previousSelected].setSelected(false);
		if(grpSongs.members[curSelected] != null) grpSongs.members[curSelected].setSelected(true);

		Mods.currentModDirectory = songs[curSelected].folder;
		PlayState.storyWeek = songs[curSelected].week;
		Difficulty.loadFromWeek();

		if (grpSongs.members[previousSelected] != null && previousSelected != curSelected)
			grpSongs.members[previousSelected].setDifficulty(songStartDiff[previousSelected]);
		resolveDifficulty();

		if (classic && classicBg != null)
		{
			if (classicColorTween != null) classicColorTween.cancel();
			classicColorTween = FlxTween.color(classicBg, 1, classicBg.color, songs[curSelected].color, {onComplete: function(t) classicColorTween = null});
		}

		refreshInfoPanel();
	}

	function refreshInfoPanel():Void
	{
		if (infoPanel != null)
		{
			var song:SongMetadata = songs[curSelected];
			var leWeek:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[song.week]);
			var weekName:String = '';
			if (leWeek != null)
			{
				weekName = Language.getPhrase('storyname_${leWeek.fileName}', leWeek.storyName);
				if (weekName == null || weekName.trim().length < 1 || leWeek.hideStoryMode) weekName = leWeek.weekName;
				if (weekName == null || weekName.trim().length < 1) weekName = leWeek.fileName;
			}
			infoPanel.showSong(song.songName, song.songCharacter, curDifficulty, song.color, weekName,
				song.folder.length > 0 ? 'Mod: ' + song.folder : 'Base game', curSelected, songs.length);
		}
	}

	var _drawDistance:Int = 4;
	var _lastVisibles:Array<Int> = [];
	static inline var CARD_FOCUS_Y:Float = 340;
	static inline var CARD_SPACING:Float = 100;
	var introTime:Float = 0;
	public function updateTexts(elapsed:Float = 0.0)
	{
		if (classic) { updateClassicTexts(elapsed); return; }
		introTime += elapsed;
		var headerE:Float = easeOutCubic(introTime / 0.45);
		scoreBG.y = -scoreBG.height * (1 - headerE);
		scoreText.y = 36 - HEADER_H * (1 - headerE);
		diffText.y = 40 - HEADER_H * (1 - headerE);
		headerSub.y = 16 - HEADER_H * (1 - headerE);
		headerCount.y = 42 - HEADER_H * (1 - headerE);
		var panelE:Float = easeOutCubic((introTime - 0.15) / 0.5);
		infoPanel.x = LIST_X + LIST_W + 40 + (1 - panelE) * 520;
		infoPanel.alpha = Math.max(0.001, panelE);
		var baseX:Float = listX;
		updateInfoPanel();

		lerpSelected = FlxMath.lerp(curSelected, lerpSelected, Math.exp(-elapsed * 9.6));
		for (i in _lastVisibles)
		{
			if(grpSongs.members[i] != null)
				grpSongs.members[i].visible = grpSongs.members[i].active = false;
		}
		_lastVisibles = [];

		var min:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected - _drawDistance)));
		var max:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected + _drawDistance)));
		for (i in min...max)
		{
			var card:SongCard = grpSongs.members[i];
			card.visible = card.active = true;

			var dist:Float = i - lerpSelected;
			card.y = CARD_FOCUS_Y + dist * CARD_SPACING;
			var style:String = MenuTheme.introStyle();
			var intro:Float = (style == 'none') ? 1 : easeOutCubic((introTime * MenuTheme.animSpeed() - 0.07 * Math.abs(i - curSelected)) / 0.5);
			card.x = baseX + card.selectNudge() + (style == 'slide' ? (1 - intro) * 560 : 0);

			var falloff:Float = Math.max(0, 1 - Math.abs(dist) / (_drawDistance + 1));
			var underHeader:Float = Math.max(0, Math.min(1, (card.y - (HEADER_H - 30)) / 70));
			card.alpha = Math.max(0.001, (0.3 + 0.7 * falloff) * intro * underHeader);

			if (!player.playingMusic && FlxG.mouse.justPressed && i != curSelected && FlxG.mouse.overlaps(card))
			{
				curSelected = i;
				changeSelection(0, true);
			}

			_lastVisibles.push(i);
		}
	}

	function updateClassicTexts(elapsed:Float)
	{
		lerpSelected = FlxMath.lerp(curSelected, lerpSelected, Math.exp(-elapsed * 9.6));
		for (i in 0...classicTexts.length)
		{
			var item:Alphabet = classicTexts[i];
			var near:Bool = Math.abs(i - lerpSelected) <= _drawDistance;
			item.visible = item.active = near;
			classicIcons[i].visible = classicIcons[i].active = near;
			if (!near) continue;
			item.x = ((item.targetY - lerpSelected) * item.distancePerItem.x) + item.startPosition.x;
			item.y = ((item.targetY - lerpSelected) * 1.3 * item.distancePerItem.y) + item.startPosition.y;
			item.alpha = classicIcons[i].alpha = (i == curSelected) ? 1 : 0.6;
			if (!player.playingMusic && FlxG.mouse.justPressed && i != curSelected && FlxG.mouse.overlaps(item))
			{
				curSelected = i;
				changeSelection(0, true);
			}
		}
		if (!player.playingMusic)
		{
			var ratingSplit:Array<String> = Std.string(CoolUtil.floorDecimal(lerpRating * 100, 2)).split('.');
			if (ratingSplit.length < 2) ratingSplit.push('');
			while (ratingSplit[1].length < 2) ratingSplit[1] += '0';
			scoreText.text = Language.getPhrase('personal_best', 'PERSONAL BEST: {1} ({2}%)', [lerpScore, ratingSplit.join('.')]);
			scoreText.x = FlxG.width - scoreText.width - 6;
			scoreBG.scale.x = FlxG.width - scoreText.x + 6;
			scoreBG.x = FlxG.width - (scoreBG.scale.x / 2);
			positionClassicDiff();
		}
		updateInfoPanel();
	}

	static function easeOutCubic(t:Float):Float
	{
		t = Math.max(0, Math.min(1, t));
		return 1 - Math.pow(1 - t, 3);
	}

	override function destroy():Void
	{
		super.destroy();

		FlxG.autoPause = ClientPrefs.data.autoPause;
		if (!FlxG.sound.music.playing && !stopMusicPlay)
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
	}	
}

class SongMetadata
{
	public var songName:String = "";
	public var week:Int = 0;
	public var songCharacter:String = "";
	public var color:Int = -7179779;
	public var folder:String = "";

	public function new(song:String, week:Int, songCharacter:String, color:Int)
	{
		this.songName = song;
		this.week = week;
		this.songCharacter = songCharacter;
		this.color = color;
		this.folder = Mods.currentModDirectory;
		if(this.folder == null) this.folder = '';
	}
}
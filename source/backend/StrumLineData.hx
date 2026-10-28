package backend;

import backend.Song.SwagSong;

typedef StrumLineFile =
{
	@:optional var name:String;
	@:optional var type:String;
	@:optional var characters:Array<StrumLineCharacter>;
	@:optional var visible:Null<Bool>;
	@:optional var strumX:Null<Float>;
	@:optional var strumY:Null<Float>;
	@:optional var strumScale:Null<Float>;
}

typedef StrumLineCharacter =
{
	var name:String;
	@:optional var position:String;
	@:optional var x:Null<Float>;
	@:optional var y:Null<Float>;
	@:optional var flipX:Null<Bool>;
}

class StrumLineData
{
	public static inline var MAX_LINES:Int = 8;
	public static final TYPES:Array<String> = ['player', 'opponent', 'additional'];
	public static final POSITIONS:Array<String> = ['boyfriend', 'dad', 'gf', 'custom'];

	public static function get(song:SwagSong):Array<StrumLineFile>
	{
		var raw:Dynamic = (song != null) ? Reflect.field(song, 'strumLines') : null;
		var lines:Array<StrumLineFile> = [];
		if(raw != null && Std.isOfType(raw, Array))
		{
			for (entry in (raw:Array<Dynamic>))
				if(entry != null) lines.push(entry);
		}
		if(lines.length > MAX_LINES)
		{
			psychlua.ScriptLog.error('Chart: ${song.song}', 'More than $MAX_LINES strumlines, the extra ones were ignored.');
			lines = lines.slice(0, MAX_LINES);
		}
		while(lines.length < 2) lines.push({});

		for (i in 0...lines.length)
		{
			var line:StrumLineFile = lines[i];
			if(i == 0) line.type = 'player';
			else if(i == 1) line.type = 'opponent';
			else
			{
				var t:String = (line.type != null) ? Std.string(line.type).toLowerCase().trim() : 'additional';
				if(!TYPES.contains(t))
				{
					psychlua.ScriptLog.error('Chart: ${song.song}', 'Strumline ${i + 1} has an unknown type "${line.type}", using "additional".');
					t = 'additional';
				}
				line.type = t;
			}
			if(line.name == null || Std.string(line.name).trim().length < 1)
				line.name = (i == 0) ? 'Player' : ((i == 1) ? 'Opponent' : 'Strumline ${i + 1}');
			if(line.visible == null) line.visible = true;

			var chars:Array<StrumLineCharacter> = [];
			if(line.characters != null && Std.isOfType(line.characters, Array))
				for (c in (line.characters:Array<Dynamic>))
				{
					if(c == null) continue;
					if(Std.isOfType(c, String)) c = {name: c};
					if(c.name == null || Std.string(c.name).trim().length < 1) continue;
					var ch:StrumLineCharacter = {name: Std.string(c.name).trim()};
					var pos:String = (c.position != null) ? Std.string(c.position).toLowerCase() : null;
					ch.position = (pos != null && POSITIONS.contains(pos)) ? pos : defaultPosition(line.type);
					ch.x = (c.x != null && !Math.isNaN(Std.parseFloat(Std.string(c.x)))) ? Std.parseFloat(Std.string(c.x)) : 0;
					ch.y = (c.y != null && !Math.isNaN(Std.parseFloat(Std.string(c.y)))) ? Std.parseFloat(Std.string(c.y)) : 0;
					ch.flipX = (c.flipX == true);
					chars.push(ch);
				}
			if(i < 2 && song != null)
			{
				var main:String = (i == 0) ? song.player1 : song.player2;
				if(chars.length < 1) chars.push({name: main, position: defaultPosition(line.type), x: 0, y: 0, flipX: false});
				else chars[0].name = main;
			}
			line.characters = chars;
		}
		if(raw != null) Reflect.setField(song, 'strumLines', lines);
		return lines;
	}

	public static function defaultPosition(type:String):String
		return (type == 'player') ? 'boyfriend' : (type == 'opponent' ? 'dad' : 'gf');

	public static function isModular(song:SwagSong):Bool
		return song != null && Reflect.field(song, 'strumLines') != null;
}

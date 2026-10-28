package objects;

import backend.StrumLineData;

class StrumLine
{
	public var index:Int;
	public var name:String;
	public var type:String;
	public var strums:FlxTypedGroup<StrumNote>;
	public var characters:Array<Character> = [];
	public var characterTags:Array<String> = [];
	public var data:StrumLineFile;
	public var visible(default, set):Bool = true;
	public var scale:Float = 1;

	public function new(index:Int, data:StrumLineFile, strums:FlxTypedGroup<StrumNote>)
	{
		this.index = index;
		this.data = data;
		this.name = data.name;
		this.type = data.type;
		this.strums = strums;
		this.scale = (data.strumScale != null && data.strumScale > 0) ? data.strumScale : (index < 2 ? 1 : 0.5);
	}

	public var mustPress(get, never):Bool;
	inline function get_mustPress():Bool
		return type == 'player';

	public var isAdditional(get, never):Bool;
	inline function get_isAdditional():Bool
		return type == 'additional';

	function set_visible(v:Bool):Bool
	{
		visible = v;
		if(strums != null) for (s in strums) if(s != null) s.visible = v;
		return v;
	}

	public function singersFor(singer:Int):Array<Character>
	{
		if(singer >= 0 && singer < characters.length && characters[singer] != null) return [characters[singer]];
		return [for (c in characters) if(c != null) c];
	}
}

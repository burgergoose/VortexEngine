package backend.pixel;

import haxe.io.Bytes;

#if cpp
abstract Mem(cpp.Pointer<cpp.UInt8>)
{
	public static inline function of(b:Bytes):Mem
		return cast cpp.Pointer.arrayElem(b.getData(), 0);

	public inline function get(i:Int):Int
		return this[i];

	public inline function set(i:Int, v:Int):Void
		this[i] = v;
}
#else
abstract Mem(Bytes)
{
	public static inline function of(b:Bytes):Mem
		return cast b;

	public inline function get(i:Int):Int
		return this.get(i);

	public inline function set(i:Int, v:Int):Void
		this.set(i, v);
}
#end

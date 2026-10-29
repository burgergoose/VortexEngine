package backend.pixel;

import haxe.ds.Vector;

#if cpp
abstract Ptr<T>(cpp.Pointer<T>)
{
	public static inline function of<T>(v:Vector<T>):Ptr<T>
		return cast cpp.Pointer.arrayElem(v.toData(), 0);

	public static inline function ofArray<T>(a:Array<T>):Ptr<T>
		return cast cpp.Pointer.arrayElem(a, 0);

	@:arrayAccess public inline function get(i:Int):T
		return this[i];

	@:arrayAccess public inline function set(i:Int, v:T):T
	{
		this[i] = v;
		return v;
	}
}
#else
abstract Ptr<T>(Vector<T>)
{
	public static inline function of<T>(v:Vector<T>):Ptr<T>
		return cast v;

	public static inline function ofArray<T>(a:Array<T>):Ptr<T>
		return cast Vector.fromArrayCopy(a);

	@:arrayAccess public inline function get(i:Int):T
		return this[i];

	@:arrayAccess public inline function set(i:Int, v:T):T
	{
		this[i] = v;
		return v;
	}
}
#end

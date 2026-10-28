package backend.pixel;

import backend.pixel.BC7;
import haxe.ds.Vector;
import haxe.io.Bytes;
import lime.graphics.Image;
import lime.utils.UInt8Array;
import openfl.Lib;
import openfl.display.BitmapData;
import openfl.display3D.textures.TextureBase;
import sys.FileSystem;
import sys.io.File;
import sys.thread.Deque;
import sys.thread.Lock;
import sys.thread.Mutex;
import sys.thread.Thread;

class VortexPixel
{
	public static inline var VERSION:Int = 2;
	public static inline var MIN_PIXELS:Int = 256 * 256;
	public static inline var MIN_PSNR:Float = 44;
	public static inline var MAX_BAD:Float = 0.005;
	public static inline var MAX_BAD_PIXEL_ART:Float = 0.0002;
	public static inline var PIXEL_ART_EDGES:Float = 0.002;

	static inline var BPTC:Int = 0x8E8C;
	static inline var TEXTURE_MAX_LEVEL:Int = 0x813D;
	static inline var MAGIC:Int = 0x31505856;

	public static var supported(default, null):Bool = false;
	public static var status(default, null):String = 'not started';
	public static var fromCache(default, null):Int = 0;
	public static var encoded(default, null):Int = 0;
	public static var kept(default, null):Int = 0;
	public static var encodeSeconds(default, null):Float = 0;
	public static var loadSeconds(default, null):Float = 0;
	public static var lastResult(default, null):String = '';

	public static var active(get, never):Bool;

	static var started:Bool = false;
	static var dir:String;
	static var mutex:Mutex = new Mutex();
	static var known:Map<String, Int> = [];
	static var jobs:Array<String> = [];
	static var workerLock:Lock;
	static var workerRunning:Bool = false;
	static var tasks:Deque<Task>;
	static var helpers:Int = 0;
	static var hold:Bool = false;
	static var owned:Map<TextureBase, Owned> = new Map();

	static function get_active():Bool
		return supported && ClientPrefs.data.vortexPixel && ClientPrefs.data.cacheOnGPU;

	@:access(openfl.display3D.Context3D)
	public static function init():Void
	{
		if (started) return;
		started = true;
		try
		{
			var context = Lib.current.stage.context3D;
			var gl = context.gl;
			var version:String = Std.string(gl.getParameter(gl.VERSION));
			if (StringTools.startsWith(version, 'OpenGL ES'))
			{
				status = 'off (OpenGL ES)';
				return;
			}
			var ext:Array<String> = gl.getSupportedExtensions();
			var bptc = ext != null && (ext.contains('GL_ARB_texture_compression_bptc') || ext.contains('ARB_texture_compression_bptc')
				|| ext.contains('GL_EXT_texture_compression_bptc') || ext.contains('EXT_texture_compression_bptc'));
			var nums = version.split(' ')[0].split('.');
			var major = Std.parseInt(nums[0]);
			var minor = nums.length > 1 ? Std.parseInt(nums[1]) : 0;
			if (major != null && minor != null && (major > 4 || (major == 4 && minor >= 2))) bptc = true;
			if (!bptc)
			{
				status = 'off (this GPU has no BC7)';
				return;
			}
			if (!pickFolder())
			{
				status = 'off (no folder to save the cache in)';
				return;
			}
			var failed = selfTest();
			if (failed != 0)
			{
				status = 'off (GPU check failed on $failed blocks)';
				return;
			}
			supported = true;
			status = 'on';
			FlxG.signals.preUpdate.add(updateHold);
			var cores = Std.int(Math.max(1, states.LoadingState.getCPUThreadsCount()));
			helpers = Std.int(Math.max(1, Math.min(6, cores - 2)));
		}
		catch (e:Dynamic)
		{
			status = 'off ($e)';
			supported = false;
		}
	}

	static function pickFolder():Bool
	{
		var options = ['vortex_cache/pixel/'];
		try
		{
			options.push(haxe.io.Path.addTrailingSlash(lime.system.System.applicationStorageDirectory) + 'vortex_cache/pixel/');
		}
		catch (e:Dynamic) {}
		for (option in options)
		{
			try
			{
				FileSystem.createDirectory(option);
				var probe = option + '.probe';
				File.saveContent(probe, 'ok');
				FileSystem.deleteFile(probe);
				dir = option;
				return true;
			}
			catch (e:Dynamic) {}
		}
		return false;
	}

	static function updateHold():Void
	{
		var state = FlxG.state;
		hold = (Std.isOfType(state, states.PlayState) && state.subState == null) || Std.isOfType(state, states.LoadingState)
			|| states.LoadingState.loadMax > 0;
	}

	public static function cacheFile(file:String):String
	{
		var path = haxe.io.Path.normalize(FileSystem.absolutePath(file)).toLowerCase();
		var h1 = 0x811C9DC5;
		var h2 = 0x01000193;
		for (i in 0...path.length)
		{
			var c = StringTools.fastCodeAt(path, i);
			h1 = (h1 ^ c) * 0x01000193;
			h2 = (h2 + c) * 0x5BD1E995;
			h2 ^= h2 >>> 15;
		}
		return dir + StringTools.hex(h1, 8) + StringTools.hex(h2, 8) + '.vxp';
	}

	static function sourceInfo(file:String):Array<Float>
	{
		try
		{
			if (!FileSystem.exists(file)) return null;
			var st = FileSystem.stat(file);
			return [st.size, st.mtime.getTime()];
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	static function forget(file:String):Void
	{
		mutex.acquire();
		if (known.get(file) != 3) known.remove(file);
		mutex.release();
	}

	public static function busy():Bool
	{
		mutex.acquire();
		var b = workerRunning;
		mutex.release();
		return b;
	}

	public static function readCached(file:String, mips:Bool):Payload
	{
		if (!active || file == null) return null;
		mutex.acquire();
		var state = known.get(file);
		mutex.release();
		if (state == 2 || state == 3) return null;
		var start = Sys.time();
		try
		{
			var path = cacheFile(file);
			if (!FileSystem.exists(path))
			{
				if (state == 1) forget(file);
				return null;
			}
			var info = sourceInfo(file);
			if (info == null) return null;
			var input = File.read(path, true);
			var p:Payload = null;
			try
			{
				if (input.readInt32() != MAGIC || input.readByte() != VERSION) throw 'old';
				var flags = input.readByte();
				var size = input.readDouble();
				var time = input.readDouble();
				var w = input.readInt32();
				var h = input.readInt32();
				var levels = input.readByte();
				var src = input.readString(input.readUInt16());
				if (size != info[0] || time != info[1] || src != haxe.io.Path.normalize(FileSystem.absolutePath(file))) throw 'changed';
				if (flags & 1 == 1)
				{
					mutex.acquire();
					known.set(file, 2);
					mutex.release();
					input.close();
					return null;
				}
				p = new Payload(file, w, h, levels);
				var count = mips ? levels : 1;
				for (i in 0...count)
				{
					var raw = input.readInt32();
					var z = input.read(input.readInt32());
					p.levels.push(haxe.zip.Uncompress.run(z, raw));
				}
				input.close();
			}
			catch (e:Dynamic)
			{
				input.close();
				forget(file);
				return null;
			}
			mutex.acquire();
			known.set(file, 1);
			loadSeconds += Sys.time() - start;
			mutex.release();
			return p;
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	@:access(openfl.display.BitmapData)
	@:access(openfl.display3D.Context3D)
	@:access(openfl.display3D.textures.TextureBase)
	public static function upload(p:Payload):BitmapData
	{
		if (p == null || p.levels.length == 0) return null;
		prune();
		var context = Lib.current.stage.context3D;
		var gl = context.gl;
		var texture:TextureBase = context.createRectangleTexture(4, 4, BGRA, false);
		texture.__width = p.width;
		texture.__height = p.height;
		var guard = 0;
		while (gl.getError() != gl.NO_ERROR && guard++ < 16) {}
		context.__bindGLTexture2D(texture.__textureID);
		var ok = sendLevels(gl, p, 0);
		gl.texParameteri(gl.TEXTURE_2D, TEXTURE_MAX_LEVEL, p.levels.length - 1);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
		ok = ok && gl.getError() == gl.NO_ERROR;
		context.__bindGLTexture2D(null);
		if (!ok)
		{
			texture.dispose();
			mutex.acquire();
			known.set(p.file, 2);
			mutex.release();
			return null;
		}
		var bitmap = BitmapData.fromTexture(texture);
		bitmap.__textureWidth = p.width;
		bitmap.__textureHeight = p.height;
		bitmap.readable = true;
		var entry = new Owned(p.file, p.width, p.height, p.total, p.levels.length);
		owned.set(texture, entry);
		p.levels = null;
		fromCache++;
		return bitmap;
	}

	static function sendLevels(gl:lime.graphics.WebGLRenderContext, p:Payload, first:Int):Bool
	{
		for (i in first...first + p.levels.length)
		{
			var w = p.width >> i;
			var h = p.height >> i;
			if (w < 1) w = 1;
			if (h < 1) h = 1;
			var data = p.levels[i - first];
			gl.compressedTexImage2D(gl.TEXTURE_2D, i, BPTC, w, h, 0, UInt8Array.fromBytes(data));
		}
		return true;
	}

	@:access(openfl.display3D.textures.TextureBase)
	static function prune():Void
	{
		var gone = [for (texture in owned.keys()) if (texture.__textureID == null) texture];
		for (texture in gone) owned.remove(texture);
	}

	public static function isCompressed(texture:TextureBase):Bool
		return texture != null && owned.exists(texture);

	@:access(openfl.display3D.Context3D)
	@:access(openfl.display3D.textures.TextureBase)
	public static function ensureMips(texture:TextureBase):Bool
	{
		var entry = owned.get(texture);
		if (entry == null) return false;
		if (entry.loaded >= entry.total) return true;
		var p = readCached(entry.file, true);
		if (p == null || p.levels.length != entry.total) return false;
		p.levels.splice(0, entry.loaded);
		var context = Lib.current.stage.context3D;
		var gl = context.gl;
		var guard = 0;
		while (gl.getError() != gl.NO_ERROR && guard++ < 16) {}
		context.__bindGLTexture2D(texture.__textureID);
		sendLevels(gl, p, entry.loaded);
		gl.texParameteri(gl.TEXTURE_2D, TEXTURE_MAX_LEVEL, entry.total - 1);
		var ok = gl.getError() == gl.NO_ERROR;
		context.__bindGLTexture2D(null);
		if (ok) entry.loaded = entry.total;
		return ok;
	}

	public static function request(file:String, width:Int, height:Int):Void
	{
		if (!active || file == null || width * height < MIN_PIXELS) return;
		mutex.acquire();
		if (known.exists(file))
		{
			mutex.release();
			return;
		}
		known.set(file, 3);
		jobs.push(file);
		var start = !workerRunning;
		workerRunning = true;
		mutex.release();
		if (start) Thread.create(work);
	}

	@:access(openfl.display3D.textures.TextureBase)
	public static function describe():String
	{
		if (!supported) return 'VortexPixel: $status';
		var count = 0;
		var bc7 = 0.0;
		var rgba = 0.0;
		var gone = [];
		for (texture => entry in owned)
		{
			if (texture.__textureID == null)
			{
				gone.push(texture);
				continue;
			}
			count++;
			var mipScale = entry.loaded > 1 ? 4 / 3 : 1;
			bc7 += entry.width * entry.height * mipScale;
			rgba += entry.width * entry.height * 4 * mipScale;
		}
		for (texture in gone) owned.remove(texture);
		mutex.acquire();
		var waiting = jobs.length;
		mutex.release();
		return 'VortexPixel: ${active ? 'on' : 'off in options'}, $count BC7 textures (${Math.round(bc7 / 1048576)} MB instead of ${Math.round(rgba / 1048576)} MB)'
			+ ', $fromCache loaded from cache, $encoded made${waiting > 0 ? ', $waiting waiting' + (hold ? ' (paused)' : '') : ''}, $kept kept as PNG'
			+ (lastResult.length > 0 ? '\n  last: $lastResult' : '');
	}

	static function work():Void
	{
		if (tasks == null)
		{
			tasks = new Deque<Task>();
			for (i in 0...helpers)
				Thread.create(function() {
					while (true)
					{
						var t = tasks.pop(true);
						try
						{
							t.encoder.encodeRows(t.rgba, t.width, t.height, t.out, 0, t.from, t.to, pausePoint);
						}
						catch (e:Dynamic)
						{
							t.failed = true;
						}
						t.done.release();
					}
				});
		}
		var encoders = [for (i in 0...helpers) new BC7Encoder()];
		while (true)
		{
			while (hold) Sys.sleep(0.25);
			mutex.acquire();
			var file = jobs.shift();
			if (file == null) workerRunning = false;
			mutex.release();
			if (file == null) return;
			var result = 0;
			try
			{
				result = encodeFile(file, encoders);
			}
			catch (e:Dynamic)
			{
				result = -1;
			}
			mutex.acquire();
			if (result == 0)
			{
				known.remove(file);
				jobs.unshift(file);
			}
			else known.set(file, result);
			mutex.release();
		}
	}

	static function pausePoint():Void
	{
		if (hold) throw new Paused();
	}

	static function encodeFile(file:String, encoders:Array<BC7Encoder>):Int
	{
		var info = sourceInfo(file);
		if (info == null) return 2;
		var start = Sys.time();
		var image = Image.fromFile(file);
		if (image == null || image.buffer == null || image.data == null) return 2;
		if (hold) return 0;
		var w = image.width;
		var h = image.height;
		var rgba:Bytes = image.data.toBytes();
		if (image.buffer.premultiplied) image.buffer.premultiplied = false;
		var pixelArt = BC7.premultiply(rgba) < PIXEL_ART_EDGES;
		image = null;

		var levels:Array<Bytes> = [];
		var raws:Array<Int> = [];
		var lw = w;
		var lh = h;
		var psnr = 0.0;
		var bad = 0.0;
		var level = 0;
		while (true)
		{
			var out = Bytes.alloc(BC7.blocksSize(lw, lh));
			var bh = (lh + 3) >> 2;
			var parts = Std.int(Math.min(encoders.length, bh));
			var done = new Lock();
			var list:Array<Task> = [];
			for (i in 0...parts)
			{
				var e = encoders[i];
				e.sse = 0;
				e.counted = 0;
				e.badPixels = 0;
				e.maxErr = 0;
				e.checkDecode = level == 0;
				var t = new Task(e, rgba, lw, lh, out, Std.int(bh * i / parts), Std.int(bh * (i + 1) / parts), done);
				list.push(t);
				tasks.add(t);
			}
			for (i in 0...parts) done.wait();
			for (t in list) if (t.failed) return 0;
			if (level == 0)
			{
				var sse = 0.0, counted = 0.0, badPx = 0.0;
				for (i in 0...parts)
				{
					sse += encoders[i].sse;
					counted += encoders[i].counted;
					badPx += encoders[i].badPixels;
				}
				psnr = counted > 0 && sse > 0 ? 10 * Math.log(65025 / (sse / (counted * 4))) / Math.log(10) : 99;
				bad = counted > 0 ? badPx / counted : 0;
				if (psnr < MIN_PSNR || bad > (pixelArt ? MAX_BAD_PIXEL_ART : MAX_BAD))
				{
					writeEntry(file, info, w, h, 1, [], []);
					finish(file, start, psnr, bad, false, pixelArt);
					return 2;
				}
			}
			raws.push(out.length);
			levels.push(haxe.zip.Compress.run(out, 3));
			if (lw == 1 && lh == 1) break;
			if (hold) return 0;
			rgba = BC7.halve(rgba, lw, lh);
			lw = lw > 1 ? lw >> 1 : 1;
			lh = lh > 1 ? lh >> 1 : 1;
			level++;
		}
		writeEntry(file, info, w, h, 0, levels, raws);
		finish(file, start, psnr, bad, true, pixelArt);
		return 1;
	}

	static function finish(file:String, start:Float, psnr:Float, bad:Float, ok:Bool, pixelArt:Bool):Void
	{
		mutex.acquire();
		encodeSeconds += Sys.time() - start;
		if (ok) encoded++;
		else kept++;
		lastResult = haxe.io.Path.withoutDirectory(file) + ' ' + (ok ? 'BC7' : 'kept as PNG') + (pixelArt ? ' (pixel art)' : '') + ', ${Math.round(psnr * 10) / 10} dB, '
			+ '${Math.round(bad * 100000) / 1000}% pixels off by >8, ${Math.round((Sys.time() - start) * 10) / 10} s';
		mutex.release();
		trace('VortexPixel: $lastResult');
	}

	static function writeEntry(file:String, info:Array<Float>, w:Int, h:Int, flags:Int, levels:Array<Bytes>, raws:Array<Int>):Void
	{
		var path = cacheFile(file);
		var tmp = path + '.tmp';
		var out = File.write(tmp, true);
		out.writeInt32(MAGIC);
		out.writeByte(VERSION);
		out.writeByte(flags);
		out.writeDouble(info[0]);
		out.writeDouble(info[1]);
		out.writeInt32(w);
		out.writeInt32(h);
		out.writeByte(levels.length);
		var src = haxe.io.Path.normalize(FileSystem.absolutePath(file));
		var srcBytes = Bytes.ofString(src);
		out.writeUInt16(srcBytes.length);
		out.write(srcBytes);
		for (i in 0...levels.length)
		{
			out.writeInt32(raws[i]);
			out.writeInt32(levels[i].length);
			out.write(levels[i]);
		}
		out.close();
		if (FileSystem.exists(path)) FileSystem.deleteFile(path);
		FileSystem.rename(tmp, path);
	}

	@:access(openfl.display.BitmapData)
	@:access(openfl.display3D.Context3D)
	@:access(openfl.display3D.textures.TextureBase)
	static function selfTest():Int
	{
		var modes = [6, 5, 5, 5, 5, 4, 4, 4, 4, 4, 4, 4, 4];
		var parts = [0, 0, 1, 2, 3, 0, 1, 2, 3, 4, 5, 6, 7];
		for (m in [1, 3, 7]) for (p in 0...64)
		{
			modes.push(m);
			parts.push(p);
		}
		var bw = 16;
		var bh = Std.int(Math.ceil(modes.length / bw));
		var w = bw * 4;
		var h = bh * 4;
		var blocks = Bytes.alloc(bw * bh * 16);
		var expected = Bytes.alloc(w * h * 4);
		var encoder = new BC7Encoder();
		var decoder = new BC7Decoder();
		var px = new Vector<Int>(64);
		var dec = new Vector<Int>(64);
		var seed = 12345;
		inline function rnd():Int
		{
			seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
			return (seed >> 8) & 255;
		}
		for (b in 0...bw * bh)
		{
			var mode = b < modes.length ? modes[b] : 6;
			var part = b < modes.length ? parts[b] : 0;
			var ca = [rnd(), rnd(), rnd(), rnd()];
			var cb = [rnd(), rnd(), rnd(), rnd()];
			for (i in 0...16)
			{
				var s = (mode == 4 || mode == 5 || mode == 6) ? 0 : (BC7.PART2[part] >> i) & 1;
				var c = s == 1 ? cb : ca;
				var t = (i & 3) * 12;
				for (k in 0...3) px[i * 4 + k] = Std.int(Math.min(255, c[k] + t));
				px[i * 4 + 3] = (mode == 1 || mode == 3) ? 255 : Std.int(Math.max(c[3] - (mode == 4 || mode == 5 ? (i & 3) * 30 : 0), 40));
				for (k in 0...3) px[i * 4 + k] = Std.int(px[i * 4 + k] * px[i * 4 + 3] / 255);
			}
			encoder.testBlock(px, mode, part, blocks, b * 16);
			decoder.decodeBlock(blocks, b * 16, dec);
			var bx = b % bw;
			var by = Std.int(b / bw);
			for (i in 0...16)
			{
				var o = ((by * 4 + (i >> 2)) * w + bx * 4 + (i & 3)) * 4;
				for (k in 0...4) expected.set(o + k, dec[i * 4 + k]);
			}
		}

		var context = Lib.current.stage.context3D;
		var gl = context.gl;
		var guard = 0;
		while (gl.getError() != gl.NO_ERROR && guard++ < 16) {}
		var texture:TextureBase = context.createRectangleTexture(4, 4, BGRA, false);
		texture.__width = w;
		texture.__height = h;
		context.__bindGLTexture2D(texture.__textureID);
		gl.compressedTexImage2D(gl.TEXTURE_2D, 0, BPTC, w, h, 0, UInt8Array.fromBytes(blocks));
		gl.texParameteri(gl.TEXTURE_2D, TEXTURE_MAX_LEVEL, 0);
		var err = gl.getError();
		context.__bindGLTexture2D(null);
		if (err != gl.NO_ERROR)
		{
			texture.dispose();
			return bw * bh;
		}
		var source = BitmapData.fromTexture(texture);
		source.__textureWidth = w;
		source.__textureHeight = h;
		var targetTexture = context.createRectangleTexture(w, h, BGRA, true);
		var target = BitmapData.fromTexture(targetTexture);
		target.fillRect(target.rect, 0);
		target.draw(source, null, null, null, null, false);
		var pixels = Bytes.alloc(w * h * 4);
		context.__bindGLFramebuffer(targetTexture.__getGLFramebuffer(false, 0, 0));
		gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, UInt8Array.fromBytes(pixels));
		context.__bindGLFramebuffer(null);
		source.dispose();
		texture.dispose();
		target.dispose();
		targetTexture.dispose();

		var best = 0x7FFFFFFF;
		for (flip in 0...2)
		{
			var failed = 0;
			for (b in 0...modes.length)
			{
				var bx = b % bw;
				var by = Std.int(b / bw);
				var wrong = false;
				for (i in 0...16)
				{
					var y = by * 4 + (i >> 2);
					var x = bx * 4 + (i & 3);
					var o = (y * w + x) * 4;
					var g = ((flip == 1 ? h - 1 - y : y) * w + x) * 4;
					for (k in 0...4)
					{
						var d = pixels.get(g + k) - expected.get(o + k);
						if (d > 2 || d < -2) wrong = true;
					}
				}
				if (wrong) failed++;
			}
			if (failed < best) best = failed;
		}
		return best;
	}
}

class Payload
{
	public var file:String;
	public var width:Int;
	public var height:Int;
	public var total:Int;
	public var levels:Array<Bytes> = [];

	public function new(file:String, width:Int, height:Int, total:Int)
	{
		this.file = file;
		this.width = width;
		this.height = height;
		this.total = total;
	}
}

private class Owned
{
	public var file:String;
	public var width:Int;
	public var height:Int;
	public var total:Int;
	public var loaded:Int;

	public function new(file:String, width:Int, height:Int, total:Int, loaded:Int)
	{
		this.file = file;
		this.width = width;
		this.height = height;
		this.total = total;
		this.loaded = loaded;
	}
}

private class Task
{
	public var encoder:BC7Encoder;
	public var rgba:Bytes;
	public var width:Int;
	public var height:Int;
	public var out:Bytes;
	public var from:Int;
	public var to:Int;
	public var done:Lock;
	public var failed:Bool = false;

	public function new(encoder:BC7Encoder, rgba:Bytes, width:Int, height:Int, out:Bytes, from:Int, to:Int, done:Lock)
	{
		this.encoder = encoder;
		this.rgba = rgba;
		this.width = width;
		this.height = height;
		this.out = out;
		this.from = from;
		this.to = to;
		this.done = done;
	}
}

private class Paused
{
	public function new() {}
}

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
import sys.io.FileSeek;
import sys.thread.Deque;
import sys.thread.Lock;
import sys.thread.Mutex;
import sys.thread.Thread;

class VortexPixel
{
	public static inline var VERSION:Int = 3;
	public static inline var MIN_PIXELS:Int = 64 * 64;
	public static inline var SHARP_AT:Float = 1.15;
	public static inline var DROP_AFTER:Float = 15;
	public static inline var MIN_PSNR:Float = 44;
	public static inline var MAX_BAD:Float = 0.005;
	public static inline var MAX_BAD_PIXEL_ART:Float = 0.0002;
	public static inline var PIXEL_ART_EDGES:Float = 0.002;
	public static inline var MIN_BACK_PSNR:Float = 50;
	static inline var BAND_BLOCKS:Int = 16;
	static inline var BAND_ROWS:Int = 32;

	static inline var BPTC:Int = 0x8E8C;
	static inline var TEXTURE_MAX_LEVEL:Int = 0x813D;
	static inline var TEXTURE_LOD_BIAS:Int = 0x8501;
	static inline var MAGIC:Int = 0x31505856;

	public static var supported(default, null):Bool = false;
	public static var status(default, null):String = 'not started';
	public static var fromCache(default, null):Int = 0;
	public static var encoded(default, null):Int = 0;
	public static var kept(default, null):Int = 0;
	public static var enhancedCount(default, null):Int = 0;
	public static var resumedUnits(default, null):Int = 0;
	public static var maxTexture(default, null):Int = 4096;
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
	static var sharpJobs:Deque<Sharp>;
	static var sharpDone:Deque<Sharp>;
	static var spare:Deque<Bytes>;
	static var current:Sharp;
	static var streamZ:Bytes;
	static var streamSwaps:Bool = false;
	static inline var SWAP_BYTES:Int = 2 * 1048576;
	public static var sharpened(default, null):Int = 0;
	public static var lastSharp(default, null):String = '';
	public static var dropped(default, null):Int = 0;
	public static var swapError(default, null):String = '';
	static var lastDropCheck:Float = 0;
	static var budgetMutex:Mutex = new Mutex();
	static var inFlight:Float = 0;
	static inline var BUDGET:Float = 256 * 1048576;

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
			streamSwaps = major != null && minor != null && (major > 4 || (major == 4 && minor >= 2));
			if (!bptc)
			{
				status = 'off (this GPU has no BC7)';
				return;
			}
			var max:Dynamic = gl.getParameter(gl.MAX_TEXTURE_SIZE);
			if (max != null && Std.int(max) > 0) maxTexture = Std.int(max);
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
			helpers = Std.int(Math.max(1, Math.min(31, cores - 1)));
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
		applySharp();
		var state = FlxG.state;
		hold = Std.isOfType(state, states.PlayState) || Std.isOfType(state, states.LoadingState)
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

	public static function readCached(file:String, mips:Bool, ?budget:Bool = false, ?sharp:Null<Bool>):Payload
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
			var upgrade = false;
			try
			{
				var head = header(input, file, info);
				var flags = head[0];
				var w = head[1];
				var h = head[2];
				var levels = head[3];
				if (flags & 1 == 1)
				{
					mutex.acquire();
					known.set(file, 2);
					mutex.release();
					input.close();
					return null;
				}
				var wantEnhance = ClientPrefs.data.vortexEnhance;
				if (flags & 4 == 4 && wantEnhance) throw 'redo';
				var enhanced = flags & 2 == 2 && wantEnhance;
				var useSharp = enhanced && (sharp != null ? sharp : sharpNow());
				var skip = flags & 2 == 2 && !useSharp ? 1 : 0;
				upgrade = flags & 8 == 8 && wantEnhance;
				var scale = useSharp ? 2 : 1;
				p = new Payload(file, w, h, levels - skip, scale);
				p.later = enhanced && !useSharp;
				var count = (scale > 1 || mips) ? p.total : 1;
				if (budget)
				{
					var bytes = 0.0;
					for (i in 0...count)
					{
						var lw = (w * scale) >> i;
						var lh = (h * scale) >> i;
						bytes += BC7.blocksSize(lw < 1 ? 1 : lw, lh < 1 ? 1 : lh);
					}
					reserve(bytes);
					p.reserved = bytes;
				}
				for (i in 0...skip + count)
				{
					var level = readLevel(input, i < skip);
					if (i >= skip) p.levels.push(level);
				}
				input.close();
			}
			catch (e:Dynamic)
			{
				input.close();
				if (p != null) unreserve(p);
				forget(file);
				return null;
			}
			mutex.acquire();
			var queued = known.get(file) == 4;
			if (!queued) known.set(file, 1);
			loadSeconds += Sys.time() - start;
			mutex.release();
			if (upgrade && !queued) queue(file, 4);
			return p;
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	static function reserve(bytes:Float):Void
	{
		var start = Sys.time();
		while (true)
		{
			budgetMutex.acquire();
			if (inFlight <= 0 || inFlight + bytes <= BUDGET || Sys.time() - start > 3)
			{
				inFlight += bytes;
				budgetMutex.release();
				return;
			}
			budgetMutex.release();
			Sys.sleep(0.005);
		}
	}

	public static function unreserve(p:Payload):Void
	{
		if (p == null || p.reserved <= 0) return;
		budgetMutex.acquire();
		inFlight -= p.reserved;
		if (inFlight < 0) inFlight = 0;
		budgetMutex.release();
		p.reserved = 0;
	}

	static function header(input:sys.io.FileInput, file:String, info:Array<Float>):Array<Int>
	{
		if (info == null) throw 'gone';
		if (input.readInt32() != MAGIC || input.readByte() != VERSION) throw 'old';
		var flags = input.readByte();
		var size = input.readDouble();
		var time = input.readDouble();
		var w = input.readInt32();
		var h = input.readInt32();
		var levels = input.readByte();
		var src = input.readString(input.readUInt16());
		if (size != info[0] || time != info[1] || src != haxe.io.Path.normalize(FileSystem.absolutePath(file))) throw 'changed';
		return [flags, w, h, levels];
	}

	static function inflate(z:Bytes, zlen:Int, out:Bytes, pos:Int, raw:Int):Void
	{
		var u = new haxe.zip.Uncompress();
		var read = 0;
		var wrote = 0;
		try
		{
			while (wrote < raw && read < zlen)
			{
				var r = u.execute(z, read, out, pos + wrote);
				read += r.read;
				wrote += r.write;
				if (r.done || (r.read == 0 && r.write == 0)) break;
			}
		}
		catch (e:Dynamic)
		{
			u.close();
			throw e;
		}
		u.close();
		if (wrote != raw) throw 'bad chunk';
	}

	static function readLevel(input:sys.io.FileInput, discard:Bool):Bytes
	{
		var total = input.readInt32();
		var chunks = input.readInt32();
		var data = discard ? null : Bytes.alloc(total);
		var pos = 0;
		var zbuf:Bytes = null;
		for (i in 0...chunks)
		{
			var raw = input.readInt32();
			var zlen = input.readInt32();
			if (discard)
			{
				input.seek(zlen, SeekCur);
				continue;
			}
			if (zbuf == null || zbuf.length < zlen) zbuf = Bytes.alloc(zlen + (zlen >> 2));
			input.readFullBytes(zbuf, 0, zlen);
			if (pos + raw > total) throw 'long level';
			inflate(zbuf, zlen, data, pos, raw);
			pos += raw;
		}
		if (!discard && pos != total) throw 'short level';
		return data;
	}

	@:access(openfl.display.BitmapData)
	@:access(openfl.display3D.Context3D)
	@:access(openfl.display3D.textures.TextureBase)
	public static function upload(p:Payload):BitmapData
	{
		var bitmap = uploadLevels(p);
		if (p != null)
		{
			unreserve(p);
			p.levels = null;
		}
		return bitmap;
	}

	@:access(openfl.display.BitmapData)
	@:access(openfl.display3D.Context3D)
	@:access(openfl.display3D.textures.TextureBase)
	static function uploadLevels(p:Payload):BitmapData
	{
		if (p == null || p.levels == null || p.levels.length == 0) return null;
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
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, p.scale > 1 ? gl.LINEAR_MIPMAP_LINEAR : gl.LINEAR);
		if (p.scale > 1) gl.texParameterf(gl.TEXTURE_2D, TEXTURE_LOD_BIAS, backend.AntiAliasing.mipmapBias);
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
		var entry = new Owned(p.file, p.width, p.height, p.total, p.levels.length, p.scale);
		entry.later = p.later;
		entry.hasSharp = p.later || p.scale > 1;
		entry.lastBig = Sys.time();
		owned.set(texture, entry);
		p.levels = null;
		fromCache++;
		return bitmap;
	}

	static function sendLevels(gl:lime.graphics.WebGLRenderContext, p:Payload, first:Int):Bool
	{
		for (i in first...first + p.levels.length)
		{
			var w = (p.width * p.scale) >> i;
			var h = (p.height * p.scale) >> i;
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

	public static function isEnhanced(texture:TextureBase):Bool
	{
		if (texture == null) return false;
		var entry = owned.get(texture);
		return entry != null && entry.scale > 1;
	}

	@:access(openfl.display3D.Context3D)
	@:access(openfl.display3D.textures.TextureBase)
	public static function ensureMips(texture:TextureBase):Bool
	{
		var entry = owned.get(texture);
		if (entry == null) return false;
		if (entry.loaded >= entry.total) return true;
		var p = readCached(entry.file, true, false, entry.scale > 1);
		if (p == null || p.levels.length != entry.total || p.scale != entry.scale) return false;
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

	public static function sharpNow():Bool
		return FlxG.scaleMode.scale.x > SHARP_AT;

	public static function watchesScale(texture:TextureBase):Bool
	{
		if (texture == null) return false;
		var entry = owned.get(texture);
		return entry != null && entry.hasSharp;
	}

	public static function drawnAt(texture:TextureBase, scale:Float):Void
	{
		if (scale <= SHARP_AT) return;
		var entry = owned.get(texture);
		if (entry == null || !entry.hasSharp) return;
		entry.lastBig = Sys.time();
		if (!entry.later || entry.asked) return;
		entry.asked = true;
		lastSharp = haxe.io.Path.withoutDirectory(entry.file) + ' at ' + (Math.round(scale * 100) / 100) + 'x';
		queueSharp(new Sharp(texture, entry.file, false));
	}

	public static function canSharpen(texture:TextureBase):Bool
	{
		if (texture == null) return false;
		var entry = owned.get(texture);
		return entry != null && entry.later && !entry.asked;
	}

	static function queueSharp(job:Sharp):Void
	{
		if (!streamSwaps) return;
		if (sharpJobs == null)
		{
			sharpJobs = new Deque<Sharp>();
			sharpDone = new Deque<Sharp>();
			spare = new Deque<Bytes>();
			for (i in 0...4) spare.add(Bytes.alloc(0));
			Thread.create(function() {
				ProcessInfo.lowPriorityThread();
				while (true)
				{
					var job = sharpJobs.pop(true);
					sharpDone.add(job);
					stream(job);
				}
			});
		}
		sharpJobs.add(job);
	}

	static function stream(job:Sharp):Void
	{
		var input:sys.io.FileInput = null;
		var ok = false;
		try
		{
			input = File.read(cacheFile(job.file), true);
			var head = header(input, job.file, sourceInfo(job.file));
			if (head[0] & 1 == 1 || head[0] & 2 != 2 || !ClientPrefs.data.vortexEnhance) throw 'plain';
			var skip = job.down ? 1 : 0;
			job.scale = job.down ? 1 : 2;
			job.width = head[1];
			job.height = head[2];
			job.levels = head[3] - skip;
			for (i in 0...skip) readLevel(input, true);
			for (l in 0...job.levels)
			{
				var lw = (job.width * job.scale) >> l;
				var lh = (job.height * job.scale) >> l;
				if (lw < 1) lw = 1;
				if (lh < 1) lh = 1;
				var rowBytes = ((lw + 3) >> 2) * 16;
				var total = input.readInt32();
				var chunks = input.readInt32();
				if (total != BC7.blocksSize(lw, lh)) throw 'size';
				var whole = (lw & 3) != 0 || (lh & 3) != 0 ? Bytes.alloc(total) : null;
				var pos = 0;
				for (c in 0...chunks)
				{
					var raw = input.readInt32();
					var zlen = input.readInt32();
					if (streamZ == null || streamZ.length < zlen) streamZ = Bytes.alloc(zlen + (zlen >> 2));
					input.readFullBytes(streamZ, 0, zlen);
					if (pos + raw > total || pos % rowBytes != 0 || (raw % rowBytes != 0 && pos + raw != total)) throw 'chunk';
					if (whole != null)
					{
						inflate(streamZ, zlen, whole, pos, raw);
						pos += raw;
						continue;
					}
					var buf = spare.pop(true);
					if (buf.length < raw) buf = Bytes.alloc(raw);
					try
					{
						inflate(streamZ, zlen, buf, 0, raw);
					}
					catch (e:Dynamic)
					{
						spare.add(buf);
						throw e;
					}
					var piece = new Piece(l, Std.int(pos / rowBytes) * 4, lw, buf, raw);
					var bottom = Std.int((pos + raw + rowBytes - 1) / rowBytes) * 4;
					piece.rows = (bottom > lh ? lh : bottom) - piece.y;
					job.pieces.add(piece);
					pos += raw;
				}
				if (pos != total) throw 'short';
				if (whole != null)
				{
					var piece = new Piece(l, 0, lw, whole, total);
					piece.rows = lh;
					piece.pooled = false;
					job.pieces.add(piece);
				}
			}
			ok = true;
		}
		catch (e:Dynamic)
		{
			swapError = haxe.io.Path.withoutDirectory(job.file) + ': ' + Std.string(e);
		}
		if (input != null) input.close();
		job.pieces.add(new Piece(ok ? -1 : -2, 0, 0, null, 0));
	}

	@:access(openfl.display3D.textures.TextureBase)
	static function checkDrops():Void
	{
		var now = Sys.time();
		if (now - lastDropCheck < 1) return;
		lastDropCheck = now;
		for (texture => entry in owned)
		{
			if (entry.scale < 2 || entry.dropping || now - entry.lastBig < DROP_AFTER || texture.__textureID == null) continue;
			entry.dropping = true;
			queueSharp(new Sharp(texture, entry.file, true));
		}
	}

	@:access(openfl.display3D.Context3D)
	@:access(openfl.display3D.textures.TextureBase)
	static function applySharp():Void
	{
		if (sharpDone == null) return;
		checkDrops();
		if (current == null) current = sharpDone.pop(false);
		var job = current;
		if (job == null) return;
		var entry = owned.get(job.texture);
		var alive = entry != null && job.texture.__textureID != null;
		var context = Lib.current.stage.context3D;
		var gl = context.gl;
		var spent = 0;
		var started = haxe.Timer.stamp();
		while (true)
		{
			var piece = job.pieces.pop(false);
			if (piece == null) break;
			if (piece.level < 0)
			{
				finishSwap(job, entry, alive && !job.broken && piece.level == -1);
				current = null;
				break;
			}
			if (alive && !job.broken)
			{
				var guard = 0;
				while (gl.getError() != gl.NO_ERROR && guard++ < 16) {}
				if (job.glTexture == null)
				{
					job.glTexture = gl.createTexture();
					context.__bindGLTexture2D(job.glTexture);
					var gl2:lime.graphics.WebGL2RenderContext = cast gl;
					gl2.texStorage2D(gl.TEXTURE_2D, job.levels, BPTC, job.width * job.scale, job.height * job.scale);
				}
				else context.__bindGLTexture2D(job.glTexture);
				gl.compressedTexSubImage2D(gl.TEXTURE_2D, piece.level, 0, piece.y, piece.width, piece.rows, BPTC, UInt8Array.fromBytes(piece.data, 0, piece.len));
				var error = gl.getError();
				if (error != gl.NO_ERROR)
				{
					job.broken = true;
					swapError = haxe.io.Path.withoutDirectory(job.file) + ': GL error ' + error + ' on level ' + piece.level + ' rows ' + piece.y + '+' + piece.rows;
				}
				context.__bindGLTexture2D(null);
			}
			spent += piece.len;
			if (piece.pooled) spare.add(piece.data);
			piece.data = null;
			if (spent >= SWAP_BYTES || haxe.Timer.stamp() - started > 0.003) break;
		}
	}

	@:access(openfl.display3D.Context3D)
	@:access(openfl.display3D.textures.TextureBase)
	static function finishSwap(job:Sharp, entry:Owned, ok:Bool):Void
	{
		var context = Lib.current.stage.context3D;
		var gl = context.gl;
		if (ok && (job.glTexture == null || job.width != entry.width || job.height != entry.height)) ok = false;
		if (ok)
		{
			var guard = 0;
			while (gl.getError() != gl.NO_ERROR && guard++ < 16) {}
			context.__bindGLTexture2D(job.glTexture);
			gl.texParameteri(gl.TEXTURE_2D, TEXTURE_MAX_LEVEL, job.levels - 1);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, job.levels > 1 ? gl.LINEAR_MIPMAP_LINEAR : gl.LINEAR);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
			gl.texParameterf(gl.TEXTURE_2D, TEXTURE_LOD_BIAS, AntiAliasing.mipmapBias);
			var error = gl.getError();
			ok = error == gl.NO_ERROR;
			if (!ok) swapError = haxe.io.Path.withoutDirectory(job.file) + ': GL error ' + error + ' on finish';
			context.__bindGLTexture2D(null);
		}
		if (ok)
		{
			var old = job.texture.__textureID;
			job.texture.__textureID = job.glTexture;
			job.texture.__samplerState = null;
			gl.deleteTexture(old);
			entry.scale = job.scale;
			entry.total = job.levels;
			entry.loaded = job.levels;
			entry.later = job.down;
			entry.asked = false;
			entry.dropping = false;
			entry.lastBig = Sys.time();
			if (job.down) dropped++;
			else sharpened++;
			return;
		}
		if (job.glTexture != null) gl.deleteTexture(job.glTexture);
		job.glTexture = null;
		if (entry == null) return;
		entry.dropping = false;
		if (job.down) entry.lastBig = Sys.time();
		else entry.later = false;
	}

	public static function request(file:String, width:Int, height:Int):Void
	{
		if (!active || file == null || width * height < MIN_PIXELS) return;
		queue(file, 3);
	}

	static function queue(file:String, state:Int):Void
	{
		mutex.acquire();
		var now = known.get(file);
		if (now == 3 || now == 4 || (state == 3 && known.exists(file)))
		{
			mutex.release();
			return;
		}
		known.set(file, state);
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
		var sharp = 0;
		var waitingSharp = 0;
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
			if (entry.scale > 1) sharp++;
			if (entry.later) waitingSharp++;
			var mipScale = entry.loaded > 1 ? 4 / 3 : 1;
			bc7 += entry.width * entry.height * entry.scale * entry.scale * mipScale;
			rgba += entry.width * entry.height * 4 * (backend.AntiAliasing.mipmapsActive ? 4 / 3 : 1);
		}
		for (texture in gone) owned.remove(texture);
		mutex.acquire();
		var waiting = jobs.length;
		mutex.release();
		return 'VortexPixel: ${active ? 'on' : 'off in options'}${ClientPrefs.data.vortexEnhance ? '' : ' (enhance off)'}, $count cached textures, $sharp enhanced 2x ($waitingSharp more when zoomed in, $sharpened switched, $dropped dropped back)'
			+ ' (${Math.round(bc7 / 1048576)} MB, plain PNGs would be ${Math.round(rgba / 1048576)} MB)'
			+ ', $fromCache loaded from cache, $encoded made${waiting > 0 ? ', $waiting waiting' + (hold ? ' (paused)' : '') : ''}, $kept kept as PNG'
			+ (lastResult.length > 0 ? '\n  last: $lastResult' : '') + (lastSharp.length > 0 ? '\n  last switched to 2x: $lastSharp' : '') + (swapError.length > 0 ? '\n  last switch failed: $swapError' : '');
	}

	static function work():Void
	{
		ProcessInfo.lowPriorityThread();
		if (tasks == null)
		{
			tasks = new Deque<Task>();
			for (i in 0...helpers)
				Thread.create(function() {
					ProcessInfo.lowPriorityThread();
					var encoder = new BC7Encoder();
					var enhancer = new Enhance();
					while (true)
					{
						var t = tasks.pop(true);
						try
						{
							runTask(t, encoder, enhancer);
							t.raw = t.out.length;
							t.out = haxe.zip.Compress.run(t.out, 3);
						}
						catch (e:Dynamic)
						{
							t.failed = true;
						}
						t.done.add(t);
					}
				});
		}
		while (true)
		{
			while (hold) Sys.sleep(0.25);
			mutex.acquire();
			var file = jobs.shift();
			if (file == null) workerRunning = false;
			mutex.release();
			if (file == null)
			{
				#if cpp
				cpp.vm.Gc.run(true);
				#end
				return;
			}
			var result = 0;
			try
			{
				result = encodeFile(file);
			}
			catch (e:Dynamic)
			{
				trace('VortexPixel: $file failed: $e');
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

	static function runTask(t:Task, encoder:BC7Encoder, enhancer:Enhance):Void
	{
		encoder.sse = 0;
		encoder.counted = 0;
		encoder.badPixels = 0;
		encoder.maxErr = 0;
		encoder.checkDecode = t.check;
		if (t.enhance)
		{
			enhancer.sse = 0;
			enhancer.counted = 0;
			var band = enhancer.band(t.rgba, t.width, t.height, t.from, t.to);
			var bh = (t.to - t.from) * 2;
			var blocks = (bh + 3) >> 2;
			t.out = Bytes.alloc(BC7.blocksSize(t.width * 2, bh));
			encoder.encodeRows(band, t.width * 2, bh, t.out, 0, 0, blocks, pausePoint);
			t.bpSse = enhancer.sse;
			t.bpCounted = enhancer.counted;
		}
		else
		{
			var bw = (t.width + 3) >> 2;
			t.out = Bytes.alloc((t.to - t.from) * bw * 16);
			encoder.encodeRows(t.rgba, t.width, t.height, t.out, -t.from * bw * 16, t.from, t.to, pausePoint);
		}
		t.sse = encoder.sse;
		t.counted = encoder.counted;
		t.bad = encoder.badPixels;
	}

	static function pausePoint():Void
	{
		if (hold) throw new Paused();
	}

	static function encodeFile(file:String):Int
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
		var wantEnhance = ClientPrefs.data.vortexEnhance;
		var enh = wantEnhance && !pixelArt && w * 2 <= maxTexture && h * 2 <= maxTexture;

		var part = new Partial(cacheFile(file) + '.part', info, w, h, enh);
		var mipSizes = [];
		var mw = w;
		var mh = h;
		while (true)
		{
			mipSizes.push([mw, mh]);
			if (mw == 1 && mh == 1) break;
			mw = mw > 1 ? mw >> 1 : 1;
			mh = mh > 1 ? mh >> 1 : 1;
		}
		var images:Array<Bytes> = [rgba];

		function plain(level:Int):Bool
		{
			while (images.length <= level)
			{
				var prev = mipSizes[images.length - 1];
				images.push(BC7.halve(images[images.length - 1], prev[0], prev[1]));
			}
			var size = mipSizes[level];
			var bh = (size[1] + 3) >> 2;
			var units = [];
			var b = 0;
			while (b < bh)
			{
				var e = b + BAND_BLOCKS > bh ? bh : b + BAND_BLOCKS;
				units.push([b, e]);
				b = e;
			}
			return runUnits(part, kindOf(level), units, images[level], size[0], size[1], level == 0, false);
		}

		if (!plain(0)) return pause(part);
		var main = part.stats(0);
		var psnr = main[0];
		var bad = main[1];
		if (psnr < MIN_PSNR || bad > (pixelArt ? MAX_BAD_PIXEL_ART : MAX_BAD))
		{
			writeEntry(file, info, w, h, 1, [], part);
			part.remove();
			finish(file, start, psnr, bad, false, pixelArt, false, 0);
			return 2;
		}
		for (level in 1...mipSizes.length) if (!plain(level)) return pause(part);
		images.splice(1, images.length);
		var oneX = [for (level in 0...mipSizes.length) kindOf(level)];
		if (!enh)
		{
			writeEntry(file, info, w, h, wantEnhance ? 0 : 4, oneX, part);
			part.remove();
			finish(file, start, psnr, bad, true, pixelArt, false, 0);
			return 1;
		}
		if (part.count(1) == 0) writeEntry(file, info, w, h, 8, oneX, part);
		var units = [];
		var y = 0;
		while (y < h)
		{
			var e = y + BAND_ROWS > h ? h : y + BAND_ROWS;
			units.push([y, e]);
			y = e;
		}
		if (!runUnits(part, 1, units, rgba, w, h, true, true)) return pause(part);
		var up = part.stats(1);
		var upOk = up[0] >= MIN_PSNR && up[1] <= MAX_BAD && up[2] >= MIN_BACK_PSNR;
		writeEntry(file, info, w, h, upOk ? 2 : 0, upOk ? [1].concat(oneX) : oneX, part);
		part.remove();
		finish(file, start, psnr, bad, true, pixelArt, upOk, up[2]);
		return 1;
	}

	static inline function kindOf(level:Int):Int
		return level == 0 ? 0 : level + 1;

	static function pause(part:Partial):Int
	{
		part.close();
		return 0;
	}

	static function runUnits(part:Partial, kind:Int, units:Array<Array<Int>>, rgba:Bytes, w:Int, h:Int, check:Bool, enhance:Bool):Bool
	{
		var todo = [for (i in 0...units.length) if (!part.has(kind, i)) i];
		resumedUnits += units.length - todo.length;
		var window = helpers * 2;
		var done = new Deque<Task>();
		var next = 0;
		var running = 0;
		var failed = false;
		while (true)
		{
			while (!failed && !hold && running < window && next < todo.length)
			{
				var u = units[todo[next]];
				var t = new Task(rgba, w, h, u[0], u[1], done, check, enhance);
				t.index = todo[next];
				tasks.add(t);
				next++;
				running++;
			}
			if (running == 0) break;
			var t = done.pop(true);
			running--;
			if (t.failed)
			{
				failed = true;
				continue;
			}
			part.add(kind, t.index, t.out, t.raw, t.sse, t.counted, t.bad, t.bpSse, t.bpCounted);
			t.out = null;
		}
		return !failed && part.count(kind) >= units.length;
	}

	static function finish(file:String, start:Float, psnr:Float, bad:Float, ok:Bool, pixelArt:Bool, enhanced:Bool, back:Float):Void
	{
		mutex.acquire();
		encodeSeconds += Sys.time() - start;
		if (ok) encoded++;
		else kept++;
		if (enhanced) enhancedCount++;
		lastResult = haxe.io.Path.withoutDirectory(file) + ' ' + (ok ? (enhanced ? 'enhanced 2x + BC7' : 'BC7') : 'kept as PNG') + (pixelArt ? ' (pixel art)' : '')
			+ ', ${Math.round(psnr * 10) / 10} dB, ${Math.round(bad * 100000) / 1000}% pixels off by >8'
			+ (enhanced ? ', shrinks back at ${Math.round(back * 10) / 10} dB' : '') + ', ${Math.round((Sys.time() - start) * 10) / 10} s';
		mutex.release();
		trace('VortexPixel: $lastResult');
	}

	static function writeEntry(file:String, info:Array<Float>, w:Int, h:Int, flags:Int, kinds:Array<Int>, part:Partial):Void
	{
		var path = cacheFile(file);
		var tmp = path + '.tmp';
		var out = File.write(tmp, true);
		try
		{
			out.writeInt32(MAGIC);
			out.writeByte(VERSION);
			out.writeByte(flags);
			out.writeDouble(info[0]);
			out.writeDouble(info[1]);
			out.writeInt32(w);
			out.writeInt32(h);
			out.writeByte(kinds.length);
			var src = haxe.io.Path.normalize(FileSystem.absolutePath(file));
			var srcBytes = Bytes.ofString(src);
			out.writeUInt16(srcBytes.length);
			out.write(srcBytes);
			for (kind in kinds) part.copyKind(kind, out);
			out.close();
		}
		catch (e:Dynamic)
		{
			out.close();
			try FileSystem.deleteFile(tmp) catch (e2:Dynamic) {}
			throw e;
		}
		var tries = 0;
		while (true)
		{
			try
			{
				if (FileSystem.exists(path)) FileSystem.deleteFile(path);
				FileSystem.rename(tmp, path);
				break;
			}
			catch (e:Dynamic)
			{
				if (++tries >= 20)
				{
					try FileSystem.deleteFile(tmp) catch (e2:Dynamic) {}
					throw e;
				}
				Sys.sleep(0.1);
			}
		}
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
	public var scale:Int;
	public var reserved:Float = 0;
	public var later:Bool = false;
	public var levels:Array<Bytes> = [];

	public function new(file:String, width:Int, height:Int, total:Int, scale:Int)
	{
		this.file = file;
		this.width = width;
		this.height = height;
		this.total = total;
		this.scale = scale;
	}
}

private class Owned
{
	public var file:String;
	public var width:Int;
	public var height:Int;
	public var total:Int;
	public var loaded:Int;
	public var scale:Int;
	public var later:Bool = false;
	public var asked:Bool = false;
	public var hasSharp:Bool = false;
	public var dropping:Bool = false;
	public var lastBig:Float = 0;

	public function new(file:String, width:Int, height:Int, total:Int, loaded:Int, scale:Int)
	{
		this.file = file;
		this.width = width;
		this.height = height;
		this.total = total;
		this.loaded = loaded;
		this.scale = scale;
	}
}

private class Sharp
{
	public var texture:TextureBase;
	public var file:String;
	public var down:Bool;
	public var pieces:Deque<Piece> = new Deque<Piece>();
	public var width:Int = 0;
	public var height:Int = 0;
	public var scale:Int = 1;
	public var levels:Int = 0;
	public var broken:Bool = false;
	public var glTexture:lime.graphics.opengl.GLTexture;

	public function new(texture:TextureBase, file:String, down:Bool)
	{
		this.texture = texture;
		this.file = file;
		this.down = down;
	}
}

private class Piece
{
	public var level:Int;
	public var y:Int;
	public var rows:Int = 0;
	public var pooled:Bool = true;
	public var width:Int;
	public var data:Bytes;
	public var len:Int;

	public function new(level:Int, y:Int, width:Int, data:Bytes, len:Int)
	{
		this.level = level;
		this.y = y;
		this.width = width;
		this.data = data;
		this.len = len;
	}
}

private class Task
{
	public var rgba:Bytes;
	public var width:Int;
	public var height:Int;
	public var from:Int;
	public var to:Int;
	public var done:Deque<Task>;
	public var check:Bool;
	public var enhance:Bool;
	public var index:Int = 0;
	public var out:Bytes;
	public var raw:Int = 0;
	public var failed:Bool = false;
	public var sse:Float = 0;
	public var counted:Float = 0;
	public var bad:Float = 0;
	public var bpSse:Float = 0;
	public var bpCounted:Float = 0;

	public function new(rgba:Bytes, width:Int, height:Int, from:Int, to:Int, done:Deque<Task>, check:Bool, enhance:Bool)
	{
		this.rgba = rgba;
		this.width = width;
		this.height = height;
		this.from = from;
		this.to = to;
		this.done = done;
		this.check = check;
		this.enhance = enhance;
	}
}

private class Record
{
	public var kind:Int = 0;
	public var index:Int = 0;
	public var raw:Int = 0;
	public var zlen:Int = 0;
	public var offset:Int = 0;
	public var sse:Float = 0;
	public var counted:Float = 0;
	public var bad:Float = 0;
	public var bpSse:Float = 0;
	public var bpCounted:Float = 0;

	public function new() {}
}

private class Partial
{
	static inline var MAGIC:Int = 0x50505856;
	static inline var HEADER:Int = 30;
	static inline var RECORD:Int = 53;

	var path:String;
	var out:sys.io.FileOutput;
	var size:Int = 0;
	var kinds:Map<Int, Map<Int, Record>> = [];

	public function new(path:String, info:Array<Float>, w:Int, h:Int, enh:Bool)
	{
		this.path = path;
		var ok = false;
		if (FileSystem.exists(path))
		{
			try
			{
				var total = FileSystem.stat(path).size;
				var input = File.read(path, true);
				var good = input.readInt32() == MAGIC && input.readByte() == VortexPixel.VERSION && input.readDouble() == info[0]
					&& input.readDouble() == info[1] && input.readInt32() == w && input.readInt32() == h && input.readByte() == (enh ? 1 : 0);
				var pos = HEADER;
				if (good)
				{
					while (pos + RECORD <= total)
					{
						var r = new Record();
						r.kind = input.readByte();
						r.index = input.readInt32();
						r.raw = input.readInt32();
						r.zlen = input.readInt32();
						r.sse = input.readDouble();
						r.counted = input.readDouble();
						r.bad = input.readDouble();
						r.bpSse = input.readDouble();
						r.bpCounted = input.readDouble();
						r.offset = pos + RECORD;
						if (r.offset + r.zlen > total) break;
						input.seek(r.zlen, SeekCur);
						pos = r.offset + r.zlen;
						keep(r);
					}
				}
				input.close();
				ok = good && pos == total;
				size = pos;
			}
			catch (e:Dynamic)
			{
				ok = false;
			}
		}
		if (ok)
		{
			out = File.append(path, true);
			return;
		}
		kinds = [];
		out = File.write(path, true);
		out.writeInt32(MAGIC);
		out.writeByte(VortexPixel.VERSION);
		out.writeDouble(info[0]);
		out.writeDouble(info[1]);
		out.writeInt32(w);
		out.writeInt32(h);
		out.writeByte(enh ? 1 : 0);
		out.flush();
		size = HEADER;
	}

	function keep(r:Record):Void
	{
		var map = kinds.get(r.kind);
		if (map == null)
		{
			map = new Map();
			kinds.set(r.kind, map);
		}
		map.set(r.index, r);
	}

	public function has(kind:Int, index:Int):Bool
	{
		var map = kinds.get(kind);
		return map != null && map.exists(index);
	}

	public function count(kind:Int):Int
	{
		var map = kinds.get(kind);
		var n = 0;
		if (map != null) for (r in map) n++;
		return n;
	}

	public function add(kind:Int, index:Int, z:Bytes, raw:Int, sse:Float, counted:Float, bad:Float, bpSse:Float, bpCounted:Float):Void
	{
		var r = new Record();
		r.kind = kind;
		r.index = index;
		r.raw = raw;
		r.zlen = z.length;
		r.sse = sse;
		r.counted = counted;
		r.bad = bad;
		r.bpSse = bpSse;
		r.bpCounted = bpCounted;
		out.writeByte(kind);
		out.writeInt32(index);
		out.writeInt32(r.raw);
		out.writeInt32(r.zlen);
		out.writeDouble(sse);
		out.writeDouble(counted);
		out.writeDouble(bad);
		out.writeDouble(bpSse);
		out.writeDouble(bpCounted);
		out.write(z);
		out.flush();
		r.offset = size + RECORD;
		size = r.offset + r.zlen;
		keep(r);
	}

	public function stats(kind:Int):Array<Float>
	{
		var sse = 0.0, counted = 0.0, bad = 0.0, bpSse = 0.0, bpCounted = 0.0;
		var map = kinds.get(kind);
		if (map != null) for (r in map)
		{
			sse += r.sse;
			counted += r.counted;
			bad += r.bad;
			bpSse += r.bpSse;
			bpCounted += r.bpCounted;
		}
		inline function db(e:Float, n:Float):Float
			return n > 0 && e > 0 ? 10 * Math.log(65025 / (e / (n * 4))) / Math.log(10) : 99;
		return [db(sse, counted), counted > 0 ? bad / counted : 0, db(bpSse, bpCounted)];
	}

	public function copyKind(kind:Int, dest:haxe.io.Output):Void
	{
		out.flush();
		var map = kinds.get(kind);
		var list = map == null ? [] : [for (r in map) r];
		list.sort((a, b) -> a.index - b.index);
		var total = 0;
		for (r in list) total += r.raw;
		dest.writeInt32(total);
		dest.writeInt32(list.length);
		var input = File.read(path, true);
		try
		{
			for (r in list)
			{
				input.seek(r.offset, SeekBegin);
				dest.writeInt32(r.raw);
				dest.writeInt32(r.zlen);
				dest.write(input.read(r.zlen));
			}
		}
		catch (e:Dynamic)
		{
			input.close();
			throw e;
		}
		input.close();
	}

	public function close():Void
	{
		try out.close() catch (e:Dynamic) {}
	}

	public function remove():Void
	{
		close();
		try FileSystem.deleteFile(path) catch (e:Dynamic) {}
	}
}

private class Paused
{
	public function new() {}
}

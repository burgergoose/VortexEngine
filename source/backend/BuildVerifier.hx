package backend;

import haxe.io.Bytes;
import haxe.crypto.Sha256;

enum BuildStatus
{
	CHECKING;
	VERIFIED;
	UNVERIFIED(reason:String);
	INTEGRITY_FAILURE(problems:Array<String>);
}

class BuildVerifier
{
	public static inline var README_NAME:String = 'UNOFFICIAL_BUILD_README.txt';
	public static inline var README_HEADER:String = '=== Vortex Engine: unofficial build notice ===';
	public static inline var OFFICIAL_URL:String = 'https://github.com/burgergoose/VortexEngine/releases';

	public static inline var PUBLIC_KEY_N:String = 'bb3a550621b03130d7d4f073fb9030fe2c505a2f0235eabe14700a900f130916b87eb92ddfbb5a6473c1dc1911647f34af2cc08fa8ee9077d42ae8a41eec6b2d77798d24e03ea766514770869ac721bb7aca33cb8d2880adb437963bd16010c420f7db8c236ed8e3f3ceac6e2363df03a064ea1e7ca897748915a1688e7cdaa145309c782ee69253ccb4235bfc17e92fe89e73d5988ba1b0a1a2d74d31af400fc825e5b7f69441ae2d4dfcc4c376325de9d66312184385aae554b2cb800fbc6b81047155a0804fa217b798a92bb19b22a4d9d10b119c01a13fd31afeeb256588bf09bc13a3e6aab3a11b06ff6bbae01aa04533265ec0a786a5cc320198420a21';
	static inline var PUBLIC_KEY_E:Int = 65537;

	public static var status(default, null):BuildStatus = CHECKING;
	public static var readmePath(default, null):String = null;
	public static var manifestInfo(default, null):Dynamic = null;
	static var started:Bool = false;
	static var pendingToast:String = null;

	public static function start():Void
	{
		#if sys
		if (started) return;
		started = true;
		var dir:String = gameDir();
		#if target.threaded
		sys.thread.Thread.create(function() runCheck(dir));
		#else
		runCheck(dir);
		#end
		FlxG.signals.postUpdate.add(showPending);
		#end
	}

	public static function describe():String
	{
		return switch (status)
		{
			case CHECKING: 'checking...';
			case VERIFIED: 'official release (verified)';
			case UNVERIFIED(r): 'unofficial / unverified build';
			case INTEGRITY_FAILURE(p): 'INTEGRITY CHECK FAILED (${p.length} files)';
		}
	}

	static function showPending()
	{
		if (pendingToast == null) return;
		var msg:String = pendingToast;
		pendingToast = null;
		FlxG.signals.postUpdate.remove(showPending);
		try Main.showToast(msg) catch (e:Dynamic) {}
	}

	#if sys
	static function gameDir():String
	{
		var p:String = haxe.io.Path.directory(Sys.programPath());
		if (p == null || p.length < 1 || !sys.FileSystem.exists(p)) p = Sys.getCwd();
		return haxe.io.Path.addTrailingSlash(p.replace('\\', '/'));
	}

	static function runCheck(dir:String)
	{
		try
		{
			status = verify(dir);
		}
		catch (e:Dynamic)
		{
			status = UNVERIFIED('the check itself failed: $e');
		}
		trace('Build check: ' + describe());
		try handleReadme(dir) catch (e:Dynamic) trace('Build check: could not write $README_NAME: $e');
	}

	public static function verify(dir:String):BuildStatus
	{
		var manifestPath:String = dir + 'vortex_manifest.json';
		var sigPath:String = dir + 'vortex_manifest.sig';
		if (!sys.FileSystem.exists(manifestPath) || !sys.FileSystem.exists(sigPath))
			return UNVERIFIED('this copy has no signed release manifest (vortex_manifest.json + .sig). Builds made from the source code never have one.');
		if (PUBLIC_KEY_N.indexOf('__') == 0)
			return UNVERIFIED('this executable was built without a release public key, so it cannot verify anything.');

		var manifestBytes:Bytes = sys.io.File.getBytes(manifestPath);
		var sigHex:String = sys.io.File.getContent(sigPath).trim();
		if (!Rsa.verifySha256(manifestBytes, sigHex, PUBLIC_KEY_N, PUBLIC_KEY_E))
			return UNVERIFIED('the release signature does not match vortex_manifest.json (the manifest was changed, or it was not signed with the official key).');

		var manifest:Dynamic = haxe.Json.parse(manifestBytes.toString());
		manifestInfo = manifest;
		var version:String = Std.string(manifest.version);
		if (version != VortexConfig.engineVersion)
			return UNVERIFIED('the signed manifest is for version $version, but this executable reports ${VortexConfig.engineVersion}.');

		var problems:Array<String> = [];
		var files:Dynamic = manifest.files;
		for (rel in Reflect.fields(files))
		{
			var p:String = dir + rel;
			if (!sys.FileSystem.exists(p)) { problems.push('missing: $rel'); continue; }
			var expected:String = Std.string(Reflect.field(files, rel)).toLowerCase();
			if (Sha256File.hex(p) != expected) problems.push('changed: $rel');
		}
		for (name in sys.FileSystem.readDirectory(dir))
		{
			var low:String = name.toLowerCase();
			if ((low.endsWith('.exe') || low.endsWith('.dll') || low.endsWith('.ndll')) && Reflect.field(files, name) == null)
				problems.push('added program file: $name');
		}
		return problems.length > 0 ? INTEGRITY_FAILURE(problems) : VERIFIED;
	}

	static function handleReadme(dir:String)
	{
		var target:String = dir + README_NAME;
		switch (status)
		{
			case VERIFIED:
				if (sys.FileSystem.exists(target) && !sys.FileSystem.isDirectory(target) && sys.io.File.getContent(target).startsWith(README_HEADER))
					sys.FileSystem.deleteFile(target);
				return;
			case CHECKING:
				return;
			default:
		}
		var text:String = readmeText();
		var written:String = writeIfChanged(target, text);
		if (written == null)
		{
			var fallback:String = haxe.io.Path.addTrailingSlash(lime.system.System.applicationStorageDirectory) + README_NAME;
			written = writeIfChanged(fallback, text);
			if (written != null) pendingToast = 'This build is not a verified official release.\nThe game folder can\'t be written to, so the notice was saved to:\n$written';
		}
		readmePath = written;
		switch (status)
		{
			case INTEGRITY_FAILURE(p):
				pendingToast = 'Integrity check failed: ${p.length} game file(s) differ from the official release.\nSee ' + (written != null ? written : README_NAME) + (pendingToast != null ? '\n\n' + pendingToast : '');
			default:
		}
	}

	static function writeIfChanged(path:String, text:String):String
	{
		try
		{
			if (sys.FileSystem.exists(path))
			{
				if (sys.FileSystem.isDirectory(path)) return null;
				var old:String = sys.io.File.getContent(path);
				if (old == text) return path;
				if (!old.startsWith(README_HEADER)) return null;
			}
			var dir:String = haxe.io.Path.directory(path);
			if (dir.length > 0 && !sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
			sys.io.File.saveContent(path, text);
			return path;
		}
		catch (e:Dynamic) {}
		return null;
	}
	#end

	public static function readmeText():String
	{
		var b:StringBuf = new StringBuf();
		b.add(README_HEADER + '\n\n');
		b.add('Detected version: ${VortexConfig.engineName} ${VortexConfig.engineVersion}\n');
		b.add('Executable built: ${BuildInfo.date()} (source commit ${BuildInfo.commit()})\n');
		if (manifestInfo != null) b.add('Release manifest: version ${manifestInfo.version}, commit ${manifestInfo.commit}, signed ${manifestInfo.built}\n');
		b.add('\nVerification status: ');
		switch (status)
		{
			case UNVERIFIED(reason):
				b.add('UNVERIFIED\n  $reason\n\n');
				b.add('This copy isn\'t an official release. Thats normal if you compiled it yourself, if its a fork or if it came in a mod pack.\n'
					+ 'It doesn\'t mean anything is wrong with it.\n');
			case INTEGRITY_FAILURE(problems):
				b.add('INTEGRITY CHECK FAILED\n');
				b.add('  The release signature is valid, but these files are not the ones that were released:\n');
				for (p in problems.slice(0, 50)) b.add('    - $p\n');
				if (problems.length > 50) b.add('    ... and ${problems.length - 50} more\n');
				b.add('\nSome game files were changed after the release. If you didn\'t change them, download the game again.\n');
			default:
				b.add('${describe()}\n');
		}
		b.add('\nOfficial releases: $OFFICIAL_URL\n');
		b.add('\nYou can delete this file.\n');
		return b.toString();
	}
}

class Rsa
{
	static inline var BITS:Int = 15;
	static inline var MASK:Int = 0x7FFF;
	static final DIGEST_INFO:Array<Int> = [0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20];

	public static function verifySha256(message:Bytes, sigHex:String, nHex:String, e:Int):Bool
	{
		if (sigHex == null || !~/^[0-9a-fA-F]+$/.match(sigHex)) return false;
		var n:Array<Int> = fromHex(nHex);
		var k:Int = Std.int((nHex.length + 1) / 2);
		var s:Array<Int> = fromHex(sigHex);
		if (compare(s, n) >= 0) return false;
		var m:Array<Int> = modPow(s, e, n);
		var hash:Bytes = Sha256.make(message);
		var em:Bytes = Bytes.alloc(k);
		em.fill(0, k, 0xFF);
		em.set(0, 0);
		em.set(1, 1);
		var tLen:Int = DIGEST_INFO.length + hash.length;
		em.set(k - tLen - 1, 0);
		for (i in 0...DIGEST_INFO.length) em.set(k - tLen + i, DIGEST_INFO[i]);
		em.blit(k - hash.length, hash, 0, hash.length);
		return compare(m, fromHex(em.toHex())) == 0;
	}

	static function fromHex(hex:String):Array<Int>
	{
		var out:Array<Int> = [];
		var acc:Int = 0, accBits:Int = 0;
		var i:Int = hex.length;
		while (i > 0)
		{
			var c:Int = Std.parseInt('0x' + hex.charAt(--i));
			acc |= c << accBits;
			accBits += 4;
			if (accBits >= BITS)
			{
				out.push(acc & MASK);
				acc >>= BITS;
				accBits -= BITS;
			}
		}
		if (accBits > 0) out.push(acc & MASK);
		trim(out);
		return out;
	}

	static function trim(a:Array<Int>)
	{
		while (a.length > 0 && a[a.length - 1] == 0) a.pop();
	}

	static function compare(a:Array<Int>, b:Array<Int>):Int
	{
		trim(a); trim(b);
		if (a.length != b.length) return a.length < b.length ? -1 : 1;
		var i:Int = a.length;
		while (i-- > 0) if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
		return 0;
	}

	static function mul(a:Array<Int>, b:Array<Int>):Array<Int>
	{
		var r:Array<Int> = [for (i in 0...(a.length + b.length + 1)) 0];
		for (i in 0...a.length)
		{
			var carry:Int = 0;
			var ai:Int = a[i];
			for (j in 0...b.length)
			{
				var t:Int = r[i + j] + ai * b[j] + carry;
				r[i + j] = t & MASK;
				carry = t >>> BITS;
			}
			var k:Int = i + b.length;
			while (carry != 0)
			{
				var t:Int = r[k] + carry;
				r[k] = t & MASK;
				carry = t >>> BITS;
				k++;
			}
		}
		trim(r);
		return r;
	}

	static function mod(x:Array<Int>, n:Array<Int>):Array<Int>
	{
		var r:Array<Int> = [];
		var bits:Int = x.length * BITS;
		var i:Int = bits;
		while (i-- > 0)
		{
			var carry:Int = (x[Std.int(i / BITS)] >> (i % BITS)) & 1;
			for (j in 0...r.length)
			{
				var t:Int = (r[j] << 1) | carry;
				r[j] = t & MASK;
				carry = t >> BITS;
			}
			if (carry != 0) r.push(carry);
			if (compare(r, n) >= 0) sub(r, n);
		}
		return r;
	}

	static function sub(a:Array<Int>, b:Array<Int>)
	{
		var borrow:Int = 0;
		for (i in 0...a.length)
		{
			var t:Int = a[i] - (i < b.length ? b[i] : 0) - borrow;
			if (t < 0) { t += MASK + 1; borrow = 1; } else borrow = 0;
			a[i] = t;
		}
		trim(a);
	}

	static function modPow(base:Array<Int>, e:Int, n:Array<Int>):Array<Int>
	{
		var result:Array<Int> = [1];
		var b:Array<Int> = mod(base, n);
		var exp:Int = e;
		while (exp > 0)
		{
			if (exp & 1 == 1) result = mod(mul(result, b), n);
			exp >>= 1;
			if (exp > 0) b = mod(mul(b, b), n);
		}
		return result;
	}
}

#if sys
class Sha256File
{
	static var K:Array<Int> = [
		0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
		0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
		0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
		0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
		0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
		0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
		0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
		0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
	];

	var h:Array<Int> = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
	var w:Array<Int> = [for (i in 0...64) 0];

	function new() {}

	public static function hex(path:String):String
	{
		var sha = new Sha256File();
		var input = sys.io.File.read(path, true);
		var buf:Bytes = Bytes.alloc(65536);
		var used:Int = 0;
		var total:haxe.Int64 = 0;
		try
		{
			while (true)
			{
				var n:Int = 0;
				try n = input.readBytes(buf, used, buf.length - used) catch (e:haxe.io.Eof) { break; }
				if (n <= 0) break;
				total += n;
				used += n;
				var blocks:Int = used >> 6;
				for (i in 0...blocks) sha.block(buf, i << 6);
				var left:Int = used - (blocks << 6);
				if (left > 0) buf.blit(0, buf, blocks << 6, left);
				used = left;
			}
		}
		catch (e:Dynamic)
		{
			input.close();
			throw e;
		}
		input.close();

		var tail:Bytes = Bytes.alloc(used + 9 <= 64 ? 64 : 128);
		tail.fill(0, tail.length, 0);
		tail.blit(0, buf, 0, used);
		tail.set(used, 0x80);
		var bits:haxe.Int64 = total << 3;
		var end:Int = tail.length;
		for (i in 0...4)
		{
			tail.set(end - 1 - i, (bits.low >>> (i * 8)) & 0xFF);
			tail.set(end - 5 - i, (bits.high >>> (i * 8)) & 0xFF);
		}
		var p:Int = 0;
		while (p < tail.length) { sha.block(tail, p); p += 64; }

		var out:StringBuf = new StringBuf();
		for (v in sha.h) out.add(StringTools.hex(v, 8));
		return out.toString().toLowerCase();
	}

	function block(b:Bytes, p:Int):Void
	{
		for (i in 0...16)
		{
			var q:Int = p + (i << 2);
			w[i] = (b.get(q) << 24) | (b.get(q + 1) << 16) | (b.get(q + 2) << 8) | b.get(q + 3);
		}
		for (i in 16...64)
		{
			var x:Int = w[i - 15];
			var y:Int = w[i - 2];
			var s0:Int = ((x >>> 7) | (x << 25)) ^ ((x >>> 18) | (x << 14)) ^ (x >>> 3);
			var s1:Int = ((y >>> 17) | (y << 15)) ^ ((y >>> 19) | (y << 13)) ^ (y >>> 10);
			w[i] = w[i - 16] + s0 + w[i - 7] + s1;
		}
		var a:Int = h[0], bb:Int = h[1], c:Int = h[2], d:Int = h[3];
		var e:Int = h[4], f:Int = h[5], g:Int = h[6], hh:Int = h[7];
		for (i in 0...64)
		{
			var s1:Int = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7));
			var t1:Int = hh + s1 + ((e & f) ^ (~e & g)) + K[i] + w[i];
			var s0:Int = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10));
			var t2:Int = s0 + ((a & bb) ^ (a & c) ^ (bb & c));
			hh = g; g = f; f = e; e = d + t1;
			d = c; c = bb; bb = a; a = t1 + t2;
		}
		h[0] += a; h[1] += bb; h[2] += c; h[3] += d;
		h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
	}
}
#end

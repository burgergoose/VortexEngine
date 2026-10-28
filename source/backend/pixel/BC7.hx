package backend.pixel;

import haxe.ds.Vector;
import haxe.io.Bytes;

class BC7
{
	public static final W2:Array<Int> = [0, 21, 43, 64];
	public static final W3:Array<Int> = [0, 9, 18, 27, 37, 46, 55, 64];
	public static final W4:Array<Int> = [0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64];

	public static final PART2:Array<Int> = [
		0xCCCC, 0x8888, 0xEEEE, 0xECC8, 0xC880, 0xFEEC, 0xFEC8, 0xEC80, 0xC800, 0xFFEC, 0xFE80, 0xE800, 0xFFE8, 0xFF00, 0xFFF0, 0xF000,
		0xF710, 0x008E, 0x7100, 0x08CE, 0x008C, 0x7310, 0x3100, 0x8CCE, 0x088C, 0x3110, 0x6666, 0x366C, 0x17E8, 0x0FF0, 0x718E, 0x399C,
		0xAAAA, 0xF0F0, 0x5A5A, 0x33CC, 0x3C3C, 0x55AA, 0x9696, 0xA55A, 0x73CE, 0x13C8, 0x324C, 0x3BDC, 0x6996, 0xC33C, 0x9966, 0x0660,
		0x0272, 0x04E4, 0x4E40, 0x2720, 0xC936, 0x936C, 0x39C6, 0x639C, 0x9336, 0x9CC6, 0x817E, 0xE718, 0xCCF0, 0x0FCC, 0x7744, 0xEE22
	];

	public static final ANCHOR2:Array<Int> = [
		15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
		15, 2, 8, 2, 2, 8, 8, 15, 2, 8, 2, 2, 8, 8, 2, 2,
		15, 15, 6, 8, 2, 8, 15, 15, 2, 8, 2, 2, 2, 15, 15, 6,
		6, 2, 6, 8, 15, 15, 2, 2, 15, 15, 15, 15, 15, 2, 2, 15
	];

	public static inline function expand(v:Int, n:Int):Int
		return n >= 8 ? v : (v << (8 - n)) | (v >> (2 * n - 8));

	public static inline function weights(bits:Int):Array<Int>
		return bits == 2 ? W2 : (bits == 3 ? W3 : W4);

	public static inline function blocksSize(w:Int, h:Int):Int
		return ((w + 3) >> 2) * ((h + 3) >> 2) * 16;

	public static function premultiply(data:Bytes):Float
	{
		var a16 = new Vector<Int>(256);
		for (i in 0...256) a16[i] = Math.ceil(i * (65536 / 255));
		var i = 0;
		var n = data.length;
		var soft = 0.0;
		var solid = 0.0;
		var clear = 0.0;
		while (i < n)
		{
			var a = data.get(i + 3);
			if (a == 255) solid++;
			else if (a != 0) soft++;
			else clear++;
			if (a == 0)
			{
				data.set(i, 0);
				data.set(i + 1, 0);
				data.set(i + 2, 0);
			}
			else if (a != 255)
			{
				var m = a16[a];
				data.set(i, (data.get(i) * m) >> 16);
				data.set(i + 1, (data.get(i + 1) * m) >> 16);
				data.set(i + 2, (data.get(i + 2) * m) >> 16);
			}
			i += 4;
		}
		if (clear == 0) return 1;
		return soft + solid > 0 ? soft / (soft + solid) : 0;
	}

	public static function halve(src:Bytes, w:Int, h:Int):Bytes
	{
		var w2 = w > 1 ? w >> 1 : 1;
		var h2 = h > 1 ? h >> 1 : 1;
		if (w & 1 == 1 || h & 1 == 1) return resample(src, w, h, w2, h2);
		var dst = Bytes.alloc(w2 * h2 * 4);
		for (y in 0...h2)
		{
			var y0 = y * 2;
			var y1 = y0 + 1 < h ? y0 + 1 : y0;
			for (x in 0...w2)
			{
				var x0 = x * 2;
				var x1 = x0 + 1 < w ? x0 + 1 : x0;
				var a = (y0 * w + x0) * 4;
				var b = (y0 * w + x1) * 4;
				var c = (y1 * w + x0) * 4;
				var d = (y1 * w + x1) * 4;
				var o = (y * w2 + x) * 4;
				for (k in 0...4)
					dst.set(o + k, (src.get(a + k) + src.get(b + k) + src.get(c + k) + src.get(d + k) + 2) >> 2);
			}
		}
		return dst;
	}

	static function taps(n:Int, n2:Int):Array<Array<Int>>
	{
		var out = [];
		for (i in 0...n2)
		{
			var t = [];
			var lo = i * n;
			var hi = lo + n;
			var j = Std.int(lo / n2);
			while (j * n2 < hi)
			{
				var a = j * n2 > lo ? j * n2 : lo;
				var b = (j + 1) * n2 < hi ? (j + 1) * n2 : hi;
				if (b > a)
				{
					t.push(j);
					t.push(b - a);
				}
				j++;
			}
			out.push(t);
		}
		return out;
	}

	static function resample(src:Bytes, w:Int, h:Int, w2:Int, h2:Int):Bytes
	{
		var dst = Bytes.alloc(w2 * h2 * 4);
		var tx = taps(w, w2);
		var ty = taps(h, h2);
		var scale = 1 / (w * h);
		var acc = new Vector<Float>(4);
		for (y in 0...h2)
		{
			var ry = ty[y];
			for (x in 0...w2)
			{
				var rx = tx[x];
				for (k in 0...4) acc[k] = 0;
				var i = 0;
				while (i < ry.length)
				{
					var row = ry[i] * w;
					var wy = ry[i + 1];
					var j = 0;
					while (j < rx.length)
					{
						var p = (row + rx[j]) * 4;
						var f = wy * rx[j + 1];
						for (k in 0...4) acc[k] += src.get(p + k) * f;
						j += 2;
					}
					i += 2;
				}
				var o = (y * w2 + x) * 4;
				for (k in 0...4) dst.set(o + k, Std.int(acc[k] * scale + 0.5));
			}
		}
		return dst;
	}
}

class BC7Decoder
{
	var rbits:Int = 0;
	var rsrc:Bytes;
	var roff:Int = 0;
	var e = new Vector<Int>(16);
	var ind = new Vector<Int>(16);
	var ind2 = new Vector<Int>(16);
	var p = new Vector<Int>(4);

	public function new() {}

	function take(n:Int):Int
	{
		var v = 0;
		for (i in 0...n)
		{
			var p = rbits + i;
			v |= ((rsrc.get(roff + (p >> 3)) >> (p & 7)) & 1) << i;
		}
		rbits += n;
		return v;
	}

	public function decodeBlock(src:Bytes, off:Int, out:Vector<Int>):Bool
	{
		rsrc = src;
		roff = off;
		rbits = 0;
		var mode = 0;
		while (mode < 8 && take(1) == 0) mode++;
		if (mode == 0 || mode == 2 || mode >= 8) return false;

		var part = 0;
		var rot = 0;
		var isb = 0;
		var ib = 2;
		var ib2 = 0;

		switch (mode)
		{
			case 1 | 3 | 7:
				part = take(6);
				var cb = mode == 1 ? 6 : (mode == 3 ? 7 : 5);
				var ch = mode == 7 ? 4 : 3;
				for (c in 0...ch) for (ep in 0...4) e[ep * 4 + c] = take(cb);
				if (mode == 1)
				{
					var s0 = take(1);
					var s1 = take(1);
					p[0] = s0; p[1] = s0; p[2] = s1; p[3] = s1;
				}
				else for (ep in 0...4) p[ep] = take(1);
				for (ep in 0...4)
				{
					for (c in 0...ch) e[ep * 4 + c] = BC7.expand((e[ep * 4 + c] << 1) | p[ep], cb + 1);
					if (ch == 3) e[ep * 4 + 3] = 255;
				}
				ib = mode == 1 ? 3 : 2;
				var anchor = BC7.ANCHOR2[part];
				for (i in 0...16) ind[i] = take((i == 0 || i == anchor) ? ib - 1 : ib);
			case 4 | 5:
				rot = take(2);
				if (mode == 4) isb = take(1);
				var cb = mode == 4 ? 5 : 7;
				var ab = mode == 4 ? 6 : 8;
				for (c in 0...3) for (ep in 0...2) e[ep * 4 + c] = BC7.expand(take(cb), cb);
				for (ep in 0...2) e[ep * 4 + 3] = BC7.expand(take(ab), ab);
				ib = 2;
				ib2 = mode == 4 ? 3 : 2;
				for (i in 0...16) ind[i] = take(i == 0 ? ib - 1 : ib);
				for (i in 0...16) ind2[i] = take(i == 0 ? ib2 - 1 : ib2);
			case 6:
				for (c in 0...4) for (ep in 0...2) e[ep * 4 + c] = take(7);
				var p0 = take(1);
				var p1 = take(1);
				for (c in 0...4)
				{
					e[c] = (e[c] << 1) | p0;
					e[4 + c] = (e[4 + c] << 1) | p1;
				}
				ib = 4;
				for (i in 0...16) ind[i] = take(i == 0 ? 3 : 4);
		}

		for (i in 0...16)
		{
			var s = (mode == 1 || mode == 3 || mode == 7) ? (BC7.PART2[part] >> i) & 1 : 0;
			var b = s * 8;
			if (mode == 4 || mode == 5)
			{
				var cw = BC7.weights(isb == 1 ? ib2 : ib)[isb == 1 ? ind2[i] : ind[i]];
				var aw = BC7.weights(isb == 1 ? ib : ib2)[isb == 1 ? ind[i] : ind2[i]];
				for (c in 0...3) out[i * 4 + c] = ((64 - cw) * e[c] + cw * e[4 + c] + 32) >> 6;
				out[i * 4 + 3] = ((64 - aw) * e[3] + aw * e[7] + 32) >> 6;
				if (rot > 0)
				{
					var t = out[i * 4 + 3];
					out[i * 4 + 3] = out[i * 4 + rot - 1];
					out[i * 4 + rot - 1] = t;
				}
			}
			else
			{
				var w = BC7.weights(ib)[ind[i]];
				for (c in 0...4) out[i * 4 + c] = ((64 - w) * e[b + c] + w * e[b + 4 + c] + 32) >> 6;
			}
		}
		return true;
	}
}

class BC7Encoder
{
	public static inline var GOOD:Int = 48;
	public static inline var HARD:Int = 160;
	static inline var TOP:Int = 8;

	public var sse:Float = 0;
	public var counted:Float = 0;
	public var maxErr:Int = 0;
	public var badPixels:Int = 0;
	public var modeCount:Vector<Int> = new Vector<Int>(8);
	public var checkDecode:Bool = true;

	var px = new Vector<Int>(64);
	var blk = new Vector<Int>(16);
	var best = new Vector<Int>(16);
	var bestErr:Int = 0;
	var bestMode:Int = 0;
	var bitPos:Int = 0;

	var q = new Vector<Int>(16);
	var pb = new Vector<Int>(4);
	var ind = new Vector<Int>(16);
	var ind2 = new Vector<Int>(16);
	var tq = new Vector<Int>(8);
	var tp = new Vector<Int>(2);
	var tind = new Vector<Int>(16);
	var pal = new Vector<Int>(64);
	var ef = new Vector<Float>(8);
	var dec = new Vector<Int>(64);
	var decoder = new BC7Decoder();
	var top = new Vector<Int>(TOP);
	var topErr = new Vector<Float>(TOP);
	var alpha0:Int = 0;
	var alpha1:Int = 0;

	public function new()
	{
		for (i in 0...8) modeCount[i] = 0;
	}

	public function encodeRows(rgba:Bytes, w:Int, h:Int, out:Bytes, outOff:Int, byStart:Int, byEnd:Int, ?pause:Void->Void):Void
	{
		var bw = (w + 3) >> 2;
		for (by in byStart...byEnd)
		{
			if (pause != null) pause();
			for (bx in 0...bw)
			{
				#if cpp
				if (bx & 31 == 31) cpp.vm.Gc.safePoint();
				#end
				var empty = true;
				for (yy in 0...4)
				{
					var y = by * 4 + yy;
					if (y >= h) y = h - 1;
					for (xx in 0...4)
					{
						var x = bx * 4 + xx;
						if (x >= w) x = w - 1;
						var s = (y * w + x) * 4;
						var d = (yy * 4 + xx) * 4;
						px[d] = rgba.get(s);
						px[d + 1] = rgba.get(s + 1);
						px[d + 2] = rgba.get(s + 2);
						px[d + 3] = rgba.get(s + 3);
						if (px[d + 3] != 0) empty = false;
					}
				}
				var o = outOff + (by * bw + bx) * 16;
				if (empty)
				{
					out.set(o, 0x40);
					for (k in 1...16) out.set(o + k, 0);
					modeCount[6]++;
					continue;
				}
				encodeBlock();
				for (k in 0...16) out.set(o + k, best[k]);
				modeCount[bestMode]++;
				if (checkDecode) measure(out, o);
			}
		}
	}

	function measure(out:Bytes, o:Int):Void
	{
		if (!decoder.decodeBlock(out, o, dec))
		{
			badPixels += 16;
			maxErr = 255;
			return;
		}
		for (i in 0...16)
		{
			var worst = 0;
			for (c in 0...4)
			{
				var d = dec[i * 4 + c] - px[i * 4 + c];
				if (d < 0) d = -d;
				sse += d * d;
				if (d > worst) worst = d;
			}
			if (worst > maxErr) maxErr = worst;
			if (worst > 8) badPixels++;
		}
		counted += 16;
	}

	function encodeBlock():Void
	{
		var opaque = true;
		for (i in 0...16) if (px[i * 4 + 3] != 255) opaque = false;

		bestErr = 0x7FFFFFFF;
		var e6 = fitSubset(0xFFFF, 0, 4, 7, 1, 4);
		packMode6();
		keep(e6, 6);
		if (bestErr <= GOOD) return;

		tryAlphaModes(0);
		if (bestErr <= GOOD) return;

		var chans = opaque ? 3 : 4;
		estimatePartitions(chans);
		var tries = bestErr > HARD ? TOP : 2;
		for (t in 0...tries)
		{
			var p = top[t];
			if (p < 0) continue;
			var m1 = BC7.PART2[p];
			var m0 = (~m1) & 0xFFFF;
			if (opaque)
			{
				var e1 = fitSubset(m0, 0, 3, 6, 2, 3) + fitSubset(m1, 1, 3, 6, 2, 3);
				packMode1(p);
				keep(e1, 1);
				var e3 = fitSubset(m0, 0, 3, 7, 1, 2) + fitSubset(m1, 1, 3, 7, 1, 2);
				packMode3(p);
				keep(e3, 3);
			}
			else
			{
				var e7 = fitSubset(m0, 0, 4, 5, 1, 2) + fitSubset(m1, 1, 4, 5, 1, 2);
				packMode7(p);
				keep(e7, 7);
			}
			if (bestErr <= GOOD) return;
		}
		if (bestErr > HARD) for (rot in 1...4)
		{
			tryAlphaModes(rot);
			if (bestErr <= GOOD) return;
		}
	}

	function tryAlphaModes(rot:Int):Void
	{
		if (rot > 0) swapChannel(rot);
		var e5 = fitSubset(0xFFFF, 0, 3, 7, 0, 2) + fitAlpha(2, 8);
		packMode5(rot);
		keep(e5, 5);
		for (isb in 0...2)
		{
			var e4 = fitSubset(0xFFFF, 0, 3, 5, 0, isb == 1 ? 3 : 2) + fitAlpha(isb == 1 ? 2 : 3, 6);
			packMode4(rot, isb);
			keep(e4, 4);
		}
		if (rot > 0) swapChannel(rot);
	}

	function swapChannel(rot:Int):Void
	{
		for (i in 0...16)
		{
			var t = px[i * 4 + 3];
			px[i * 4 + 3] = px[i * 4 + rot - 1];
			px[i * 4 + rot - 1] = t;
		}
	}

	public function testBlock(pixels:Vector<Int>, mode:Int, part:Int, out:Bytes, off:Int):Void
	{
		for (i in 0...64) px[i] = pixels[i];
		var m1 = BC7.PART2[part];
		var m0 = (~m1) & 0xFFFF;
		switch (mode)
		{
			case 1:
				fitSubset(m0, 0, 3, 6, 2, 3);
				fitSubset(m1, 1, 3, 6, 2, 3);
				packMode1(part);
			case 3:
				fitSubset(m0, 0, 3, 7, 1, 2);
				fitSubset(m1, 1, 3, 7, 1, 2);
				packMode3(part);
			case 7:
				fitSubset(m0, 0, 4, 5, 1, 2);
				fitSubset(m1, 1, 4, 5, 1, 2);
				packMode7(part);
			case 5:
				fitSubset(0xFFFF, 0, 3, 7, 0, 2);
				fitAlpha(2, 8);
				packMode5(part & 3);
			case 4:
				fitSubset(0xFFFF, 0, 3, 5, 0, (part & 4) != 0 ? 3 : 2);
				fitAlpha((part & 4) != 0 ? 2 : 3, 6);
				packMode4(part & 3, (part & 4) != 0 ? 1 : 0);
			default:
				fitSubset(0xFFFF, 0, 4, 7, 1, 4);
				packMode6();
		}
		for (k in 0...16) out.set(off + k, blk[k]);
	}

	inline function keep(err:Int, mode:Int):Void
	{
		if (err < bestErr)
		{
			bestErr = err;
			bestMode = mode;
			for (k in 0...16) best[k] = blk[k];
		}
	}

	function quantChan(x:Float, p:Int, cb:Int, pm:Int):Int
	{
		var maxc = (1 << cb) - 1;
		var g:Int;
		if (pm == 0) g = Math.round(x * maxc / 255);
		else g = (Math.round(x * ((1 << (cb + 1)) - 1) / 255) - p) >> 1;
		var bestC = 0;
		var bestD = 1e30;
		for (k in -1...2)
		{
			var c = g + k;
			if (c < 0 || c > maxc) continue;
			var v = pm == 0 ? BC7.expand(c, cb) : BC7.expand((c << 1) | p, cb + 1);
			var d = v - x;
			if (d < 0) d = -d;
			if (d < bestD)
			{
				bestD = d;
				bestC = c;
			}
		}
		return bestC;
	}

	inline function value(code:Int, p:Int, cb:Int, pm:Int):Int
		return pm == 0 ? BC7.expand(code, cb) : BC7.expand((code << 1) | p, cb + 1);

	function quantize(chans:Int, cb:Int, pm:Int):Void
	{
		if (pm == 0)
		{
			for (c in 0...chans)
			{
				tq[c] = quantChan(ef[c], 0, cb, 0);
				tq[4 + c] = quantChan(ef[4 + c], 0, cb, 0);
			}
			tp[0] = tp[1] = 0;
			return;
		}
		var bestP0 = 0;
		var bestP1 = 0;
		var bestD = 1e30;
		for (p0 in 0...2) for (p1 in 0...2)
		{
			if (pm == 2 && p0 != p1) continue;
			var d = 0.0;
			for (c in 0...chans)
			{
				var a = value(quantChan(ef[c], p0, cb, pm), p0, cb, pm) - ef[c];
				var b = value(quantChan(ef[4 + c], p1, cb, pm), p1, cb, pm) - ef[4 + c];
				d += a * a + b * b;
			}
			if (d < bestD)
			{
				bestD = d;
				bestP0 = p0;
				bestP1 = p1;
			}
		}
		tp[0] = bestP0;
		tp[1] = bestP1;
		for (c in 0...chans)
		{
			tq[c] = quantChan(ef[c], bestP0, cb, pm);
			tq[4 + c] = quantChan(ef[4 + c], bestP1, cb, pm);
		}
	}

	function fitSubset(mask:Int, s:Int, chans:Int, cb:Int, pm:Int, ib:Int):Int
	{
		var n = 0;
		var m0 = 0.0, m1 = 0.0, m2 = 0.0, m3 = 0.0;
		for (i in 0...16) if ((mask >> i) & 1 == 1)
		{
			n++;
			m0 += px[i * 4];
			m1 += px[i * 4 + 1];
			m2 += px[i * 4 + 2];
			m3 += px[i * 4 + 3];
		}
		if (n == 0) return 0;
		m0 /= n; m1 /= n; m2 /= n; m3 /= n;
		if (chans == 3) m3 = 0;

		var c00 = 0.0, c01 = 0.0, c02 = 0.0, c03 = 0.0, c11 = 0.0, c12 = 0.0, c13 = 0.0, c22 = 0.0, c23 = 0.0, c33 = 0.0;
		for (i in 0...16) if ((mask >> i) & 1 == 1)
		{
			var d0 = px[i * 4] - m0;
			var d1 = px[i * 4 + 1] - m1;
			var d2 = px[i * 4 + 2] - m2;
			var d3 = chans == 4 ? px[i * 4 + 3] - m3 : 0.0;
			c00 += d0 * d0; c01 += d0 * d1; c02 += d0 * d2; c03 += d0 * d3;
			c11 += d1 * d1; c12 += d1 * d2; c13 += d1 * d3;
			c22 += d2 * d2; c23 += d2 * d3;
			c33 += d3 * d3;
		}

		var a0 = c00, a1 = c01, a2 = c02, a3 = c03;
		var big = c00;
		if (c11 > big) { big = c11; a0 = c01; a1 = c11; a2 = c12; a3 = c13; }
		if (c22 > big) { big = c22; a0 = c02; a1 = c12; a2 = c22; a3 = c23; }
		if (c33 > big) { big = c33; a0 = c03; a1 = c13; a2 = c23; a3 = c33; }

		var tmin = 0.0, tmax = 0.0;
		if (big > 0)
		{
			for (it in 0...6)
			{
				var b0 = c00 * a0 + c01 * a1 + c02 * a2 + c03 * a3;
				var b1 = c01 * a0 + c11 * a1 + c12 * a2 + c13 * a3;
				var b2 = c02 * a0 + c12 * a1 + c22 * a2 + c23 * a3;
				var b3 = c03 * a0 + c13 * a1 + c23 * a2 + c33 * a3;
				var len = Math.sqrt(b0 * b0 + b1 * b1 + b2 * b2 + b3 * b3);
				if (len <= 0) break;
				a0 = b0 / len; a1 = b1 / len; a2 = b2 / len; a3 = b3 / len;
			}
			var len = Math.sqrt(a0 * a0 + a1 * a1 + a2 * a2 + a3 * a3);
			if (len > 0) { a0 /= len; a1 /= len; a2 /= len; a3 /= len; }
			tmin = 1e30;
			tmax = -1e30;
			for (i in 0...16) if ((mask >> i) & 1 == 1)
			{
				var t = (px[i * 4] - m0) * a0 + (px[i * 4 + 1] - m1) * a1 + (px[i * 4 + 2] - m2) * a2
					+ (chans == 4 ? (px[i * 4 + 3] - m3) * a3 : 0.0);
				if (t < tmin) tmin = t;
				if (t > tmax) tmax = t;
			}
		}
		ef[0] = clamp(m0 + a0 * tmin); ef[1] = clamp(m1 + a1 * tmin); ef[2] = clamp(m2 + a2 * tmin); ef[3] = clamp(m3 + a3 * tmin);
		ef[4] = clamp(m0 + a0 * tmax); ef[5] = clamp(m1 + a1 * tmax); ef[6] = clamp(m2 + a2 * tmax); ef[7] = clamp(m3 + a3 * tmax);
		if (chans == 3) { ef[3] = 255; ef[7] = 255; }

		var wt = BC7.weights(ib);
		var levels = 1 << ib;
		var bestE = 0x7FFFFFFF;
		for (iter in 0...3)
		{
			quantize(chans, cb, pm);
			for (k in 0...levels)
			{
				var w = wt[k];
				for (c in 0...chans)
				{
					var v0 = value(tq[c], tp[0], cb, pm);
					var v1 = value(tq[4 + c], tp[1], cb, pm);
					pal[k * 4 + c] = ((64 - w) * v0 + w * v1 + 32) >> 6;
				}
			}
			var err = 0;
			for (i in 0...16) if ((mask >> i) & 1 == 1)
			{
				var bk = 0;
				var bd = 0x7FFFFFFF;
				for (k in 0...levels)
				{
					var d0 = pal[k * 4] - px[i * 4];
					var d1 = pal[k * 4 + 1] - px[i * 4 + 1];
					var d2 = pal[k * 4 + 2] - px[i * 4 + 2];
					var d = d0 * d0 + d1 * d1 + d2 * d2;
					if (chans == 4)
					{
						var d3 = pal[k * 4 + 3] - px[i * 4 + 3];
						d += d3 * d3;
					}
					if (d < bd)
					{
						bd = d;
						bk = k;
					}
				}
				tind[i] = bk;
				err += bd;
			}
			if (err < bestE)
			{
				bestE = err;
				for (k in 0...8) q[s * 8 + k] = tq[k];
				pb[s * 2] = tp[0];
				pb[s * 2 + 1] = tp[1];
				for (i in 0...16) if ((mask >> i) & 1 == 1) ind[i] = tind[i];
			}
			if (err == 0 || iter == 2) break;

			var sa = 0.0, sb = 0.0, sc = 0.0;
			var x00 = 0.0, x01 = 0.0, x02 = 0.0, x03 = 0.0, x10 = 0.0, x11 = 0.0, x12 = 0.0, x13 = 0.0;
			for (i in 0...16) if ((mask >> i) & 1 == 1)
			{
				var w = wt[tind[i]] / 64;
				var v = 1 - w;
				sa += v * v; sb += v * w; sc += w * w;
				x00 += v * px[i * 4]; x01 += v * px[i * 4 + 1]; x02 += v * px[i * 4 + 2]; x03 += v * px[i * 4 + 3];
				x10 += w * px[i * 4]; x11 += w * px[i * 4 + 1]; x12 += w * px[i * 4 + 2]; x13 += w * px[i * 4 + 3];
			}
			var det = sa * sc - sb * sb;
			if (det < 1e-6 && det > -1e-6) break;
			var inv = 1 / det;
			ef[0] = clamp((sc * x00 - sb * x10) * inv); ef[4] = clamp((sa * x10 - sb * x00) * inv);
			ef[1] = clamp((sc * x01 - sb * x11) * inv); ef[5] = clamp((sa * x11 - sb * x01) * inv);
			ef[2] = clamp((sc * x02 - sb * x12) * inv); ef[6] = clamp((sa * x12 - sb * x02) * inv);
			if (chans == 4)
			{
				ef[3] = clamp((sc * x03 - sb * x13) * inv);
				ef[7] = clamp((sa * x13 - sb * x03) * inv);
			}
		}
		return bestE;
	}

	function fitAlpha(ib:Int, ab:Int):Int
	{
		var lo = 255;
		var hi = 0;
		for (i in 0...16)
		{
			var a = px[i * 4 + 3];
			if (a < lo) lo = a;
			if (a > hi) hi = a;
		}
		var wt = BC7.weights(ib);
		var levels = 1 << ib;
		var bestE = 0x7FFFFFFF;
		var lo0 = quantChan(lo, 0, ab, 0);
		var hi0 = quantChan(hi, 0, ab, 0);
		for (dl in 0...2) for (dh in 0...2)
		{
			var c0 = lo0 + (dl == 1 ? (BC7.expand(lo0, ab) > lo ? -1 : 1) : 0);
			var c1 = hi0 + (dh == 1 ? (BC7.expand(hi0, ab) > hi ? -1 : 1) : 0);
			var maxc = (1 << ab) - 1;
			if (c0 < 0 || c1 < 0 || c0 > maxc || c1 > maxc) continue;
			var v0 = BC7.expand(c0, ab);
			var v1 = BC7.expand(c1, ab);
			var err = 0;
			for (i in 0...16)
			{
				var bk = 0;
				var bd = 0x7FFFFFFF;
				for (k in 0...levels)
				{
					var w = wt[k];
					var d = (((64 - w) * v0 + w * v1 + 32) >> 6) - px[i * 4 + 3];
					d *= d;
					if (d < bd)
					{
						bd = d;
						bk = k;
					}
				}
				tind[i] = bk;
				err += bd;
			}
			if (err < bestE)
			{
				bestE = err;
				alpha0 = c0;
				alpha1 = c1;
				for (i in 0...16) ind2[i] = tind[i];
			}
		}
		return bestE;
	}

	function estimatePartitions(chans:Int):Void
	{
		for (t in 0...TOP)
		{
			top[t] = -1;
			topErr[t] = 1e30;
		}
		var t0 = 0.0, t1 = 0.0, t2 = 0.0, t3 = 0.0;
		var t00 = 0.0, t01 = 0.0, t02 = 0.0, t03 = 0.0, t11 = 0.0, t12 = 0.0, t13 = 0.0, t22 = 0.0, t23 = 0.0, t33 = 0.0;
		for (i in 0...16)
		{
			var r = px[i * 4], g = px[i * 4 + 1], b = px[i * 4 + 2], a = chans == 4 ? px[i * 4 + 3] : 0;
			t0 += r; t1 += g; t2 += b; t3 += a;
			t00 += r * r; t01 += r * g; t02 += r * b; t03 += r * a;
			t11 += g * g; t12 += g * b; t13 += g * a;
			t22 += b * b; t23 += b * a; t33 += a * a;
		}
		for (p in 0...64)
		{
			var m = BC7.PART2[p];
			var n = 0;
			var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0;
			var s00 = 0.0, s01 = 0.0, s02 = 0.0, s03 = 0.0, s11 = 0.0, s12 = 0.0, s13 = 0.0, s22 = 0.0, s23 = 0.0, s33 = 0.0;
			for (i in 0...16) if ((m >> i) & 1 == 1)
			{
				var r = px[i * 4], g = px[i * 4 + 1], b = px[i * 4 + 2], a = chans == 4 ? px[i * 4 + 3] : 0;
				n++;
				s0 += r; s1 += g; s2 += b; s3 += a;
				s00 += r * r; s01 += r * g; s02 += r * b; s03 += r * a;
				s11 += g * g; s12 += g * b; s13 += g * a;
				s22 += b * b; s23 += b * a; s33 += a * a;
			}
			var e = residual(n, s0, s1, s2, s3, s00, s01, s02, s03, s11, s12, s13, s22, s23, s33)
				+ residual(16 - n, t0 - s0, t1 - s1, t2 - s2, t3 - s3, t00 - s00, t01 - s01, t02 - s02, t03 - s03, t11 - s11, t12 - s12, t13 - s13,
					t22 - s22, t23 - s23, t33 - s33);
			if (e < topErr[TOP - 1])
			{
				var k = TOP - 1;
				while (k > 0 && e < topErr[k - 1])
				{
					top[k] = top[k - 1];
					topErr[k] = topErr[k - 1];
					k--;
				}
				top[k] = p;
				topErr[k] = e;
			}
		}
	}

	static function residual(n:Int, s0:Float, s1:Float, s2:Float, s3:Float, s00:Float, s01:Float, s02:Float, s03:Float, s11:Float, s12:Float,
			s13:Float, s22:Float, s23:Float, s33:Float):Float
	{
		if (n <= 1) return 0;
		var inv = 1 / n;
		var c00 = s00 - s0 * s0 * inv, c01 = s01 - s0 * s1 * inv, c02 = s02 - s0 * s2 * inv, c03 = s03 - s0 * s3 * inv;
		var c11 = s11 - s1 * s1 * inv, c12 = s12 - s1 * s2 * inv, c13 = s13 - s1 * s3 * inv;
		var c22 = s22 - s2 * s2 * inv, c23 = s23 - s2 * s3 * inv, c33 = s33 - s3 * s3 * inv;
		var tr = c00 + c11 + c22 + c33;
		if (tr <= 0) return 0;
		var a0 = c00, a1 = c01, a2 = c02, a3 = c03;
		var big = c00;
		if (c11 > big) { big = c11; a0 = c01; a1 = c11; a2 = c12; a3 = c13; }
		if (c22 > big) { big = c22; a0 = c02; a1 = c12; a2 = c22; a3 = c23; }
		if (c33 > big) { big = c33; a0 = c03; a1 = c13; a2 = c23; a3 = c33; }
		for (it in 0...3)
		{
			var b0 = c00 * a0 + c01 * a1 + c02 * a2 + c03 * a3;
			var b1 = c01 * a0 + c11 * a1 + c12 * a2 + c13 * a3;
			var b2 = c02 * a0 + c12 * a1 + c22 * a2 + c23 * a3;
			var b3 = c03 * a0 + c13 * a1 + c23 * a2 + c33 * a3;
			var len = Math.sqrt(b0 * b0 + b1 * b1 + b2 * b2 + b3 * b3);
			if (len <= 0) return tr;
			a0 = b0 / len; a1 = b1 / len; a2 = b2 / len; a3 = b3 / len;
		}
		var l0 = c00 * a0 + c01 * a1 + c02 * a2 + c03 * a3;
		var l1 = c01 * a0 + c11 * a1 + c12 * a2 + c13 * a3;
		var l2 = c02 * a0 + c12 * a1 + c22 * a2 + c23 * a3;
		var l3 = c03 * a0 + c13 * a1 + c23 * a2 + c33 * a3;
		var lambda = a0 * l0 + a1 * l1 + a2 * l2 + a3 * l3;
		var r = tr - lambda;
		return r < 0 ? 0 : r;
	}

	static inline function clamp(v:Float):Float
		return v < 0 ? 0 : (v > 255 ? 255 : v);

	inline function clearBlock():Void
	{
		for (k in 0...16) blk[k] = 0;
		bitPos = 0;
	}

	function put(v:Int, n:Int):Void
	{
		while (n > 0)
		{
			var off = bitPos & 7;
			var room = 8 - off;
			var take = room < n ? room : n;
			blk[bitPos >> 3] |= (v & ((1 << take) - 1)) << off;
			v >>= take;
			n -= take;
			bitPos += take;
		}
	}

	function fixAnchor(s:Int, anchor:Int, mask:Int, ib:Int):Void
	{
		if (ind[anchor] < (1 << (ib - 1))) return;
		for (c in 0...4)
		{
			var t = q[s * 8 + c];
			q[s * 8 + c] = q[s * 8 + 4 + c];
			q[s * 8 + 4 + c] = t;
		}
		var t = pb[s * 2];
		pb[s * 2] = pb[s * 2 + 1];
		pb[s * 2 + 1] = t;
		var mx = (1 << ib) - 1;
		for (i in 0...16) if ((mask >> i) & 1 == 1) ind[i] = mx - ind[i];
	}

	function packMode6():Void
	{
		fixAnchor(0, 0, 0xFFFF, 4);
		clearBlock();
		put(1 << 6, 7);
		for (c in 0...4)
		{
			put(q[c], 7);
			put(q[4 + c], 7);
		}
		put(pb[0], 1);
		put(pb[1], 1);
		put(ind[0], 3);
		for (i in 1...16) put(ind[i], 4);
	}

	function fixAlpha(ib:Int):Void
	{
		if (ind2[0] < (1 << (ib - 1))) return;
		var t = alpha0;
		alpha0 = alpha1;
		alpha1 = t;
		var mx = (1 << ib) - 1;
		for (i in 0...16) ind2[i] = mx - ind2[i];
	}

	function packMode5(rot:Int):Void
	{
		fixAnchor(0, 0, 0xFFFF, 2);
		fixAlpha(2);
		clearBlock();
		put(1 << 5, 6);
		put(rot, 2);
		for (c in 0...3)
		{
			put(q[c], 7);
			put(q[4 + c], 7);
		}
		put(alpha0, 8);
		put(alpha1, 8);
		put(ind[0], 1);
		for (i in 1...16) put(ind[i], 2);
		put(ind2[0], 1);
		for (i in 1...16) put(ind2[i], 2);
	}

	function packMode4(rot:Int, isb:Int):Void
	{
		var cib = isb == 1 ? 3 : 2;
		var aib = isb == 1 ? 2 : 3;
		fixAnchor(0, 0, 0xFFFF, cib);
		fixAlpha(aib);
		clearBlock();
		put(1 << 4, 5);
		put(rot, 2);
		put(isb, 1);
		for (c in 0...3)
		{
			put(q[c], 5);
			put(q[4 + c], 5);
		}
		put(alpha0, 6);
		put(alpha1, 6);
		if (isb == 0)
		{
			put(ind[0], 1);
			for (i in 1...16) put(ind[i], 2);
			put(ind2[0], 2);
			for (i in 1...16) put(ind2[i], 3);
		}
		else
		{
			put(ind2[0], 1);
			for (i in 1...16) put(ind2[i], 2);
			put(ind[0], 2);
			for (i in 1...16) put(ind[i], 3);
		}
	}

	function packTwo(p:Int, ib:Int):Int
	{
		var m1 = BC7.PART2[p];
		var anchor = BC7.ANCHOR2[p];
		fixAnchor(0, 0, (~m1) & 0xFFFF, ib);
		fixAnchor(1, anchor, m1, ib);
		return anchor;
	}

	function putIndices(anchor:Int, ib:Int):Void
		for (i in 0...16) put(ind[i], (i == 0 || i == anchor) ? ib - 1 : ib);

	function packMode1(p:Int):Void
	{
		var anchor = packTwo(p, 3);
		clearBlock();
		put(1 << 1, 2);
		put(p, 6);
		for (c in 0...3)
		{
			put(q[c], 6);
			put(q[4 + c], 6);
			put(q[8 + c], 6);
			put(q[12 + c], 6);
		}
		put(pb[0], 1);
		put(pb[2], 1);
		putIndices(anchor, 3);
	}

	function packMode3(p:Int):Void
	{
		var anchor = packTwo(p, 2);
		clearBlock();
		put(1 << 3, 4);
		put(p, 6);
		for (c in 0...3)
		{
			put(q[c], 7);
			put(q[4 + c], 7);
			put(q[8 + c], 7);
			put(q[12 + c], 7);
		}
		for (k in 0...4) put(pb[k], 1);
		putIndices(anchor, 2);
	}

	function packMode7(p:Int):Void
	{
		var anchor = packTwo(p, 2);
		clearBlock();
		put(1 << 7, 8);
		put(p, 6);
		for (c in 0...4)
		{
			put(q[c], 5);
			put(q[4 + c], 5);
			put(q[8 + c], 5);
			put(q[12 + c], 5);
		}
		for (k in 0...4) put(pb[k], 1);
		putIndices(anchor, 2);
	}
}

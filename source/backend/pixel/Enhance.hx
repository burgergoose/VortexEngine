package backend.pixel;

import haxe.ds.Vector;
import haxe.io.Bytes;

class Enhance
{
	public static inline var ANGLES:Int = 16;
	public static inline var EDGES:Int = 8;
	public static inline var MARGIN:Int = 3;
	public static inline var EDGE_FULL:Float = 4000;

	static var table:Vector<Int>;

	public var sse:Float = 0;
	public var counted:Float = 0;

	var tensor:Vector<Int>;
	var rowSum:Vector<Int>;
	var codes:Vector<Int>;
	var up:Bytes;
	var res:Vector<Int>;
	var zero:Bytes;
	var bandOut:Bytes;

	public function new()
	{
		if (table == null) build();
	}

	static inline function lanczos(x:Float):Float
	{
		var x2 = x * x;
		if (x2 >= 4) return 0;
		var a = 0.4 * x2 - 1;
		var b = 0.25 * x2 - 1;
		return (1.5625 * a * a - 0.5625) * b * b;
	}

	static function build():Void
	{
		var t = new Vector<Int>(ANGLES * EDGES * 4 * 16);
		var w = new Vector<Float>(16);
		for (a in 0...ANGLES)
		{
			var th = a * Math.PI / ANGLES;
			var nx = Math.cos(th);
			var ny = Math.sin(th);
			for (e in 0...EDGES)
			{
				var ef = e / (EDGES - 1);
				var along = 1 / (1 + ef);
				for (c in 0...4)
				{
					var dx = (c & 1) == 1 ? 0.25 : -0.25;
					var dy = (c & 2) == 2 ? 0.25 : -0.25;
					var bx = (c & 1) == 1 ? -1 : -2;
					var by = (c & 2) == 2 ? -1 : -2;
					var sum = 0.0;
					for (i in 0...16)
					{
						var px = bx + (i & 3) - dx;
						var py = by + (i >> 2) - dy;
						var v = 0.0;
						if (e == 0) v = lanczos(px) * lanczos(py);
						else
						{
							var u = px * nx + py * ny;
							var s = py * nx - px * ny;
							v = lanczos(u) * lanczos(s * along);
						}
						w[i] = v;
						sum += v;
					}
					var base = ((a * EDGES + e) * 4 + c) * 16;
					var total = 0;
					var peak = 0;
					for (i in 0...16)
					{
						var q = Math.round(w[i] / sum * 4096);
						t[base + i] = q;
						total += q;
						if (w[i] > w[peak]) peak = i;
					}
					t[base + peak] += 4096 - total;
				}
			}
		}
		table = t;
	}

	public function band(srcBytes:Bytes, w:Int, h:Int, y0:Int, y1:Int):Bytes
	{
		var ry0 = y0 - MARGIN < 0 ? 0 : y0 - MARGIN;
		var ry1 = y1 + MARGIN > h ? h : y1 + MARGIN;
		var rows = ry1 - ry0;
		var w2 = w * 2;
		var need = rows * w2 * 2 * 4;
		if (up == null || up.length < need) up = Bytes.alloc(need);
		var tr0 = ry0 - 1;
		var trows = rows + 2;
		if (tensor == null || tensor.length < trows * w * 3) tensor = new Vector<Int>(trows * w * 3);
		if (rowSum == null || rowSum.length < trows * w * 3) rowSum = new Vector<Int>(trows * w * 3);
		if (codes == null || codes.length < rows * w) codes = new Vector<Int>(rows * w);
		if (res == null || res.length < rows * w * 4) res = new Vector<Int>(rows * w * 4);
		if (zero == null || zero.length < rows * w * 4) zero = Bytes.alloc(rows * w * 4);
		var src = Mem.of(srcBytes);
		var up = Mem.of(this.up);
		var zero = Mem.of(this.zero);
		var tensor = Ptr.of(this.tensor);
		var rowSum = Ptr.of(this.rowSum);
		var codes = Ptr.of(this.codes);
		var res = Ptr.of(this.res);

		inline function feat(x:Int, y:Int):Int
		{
			if (x < 0) x = 0 else if (x >= w) x = w - 1;
			if (y < 0) y = 0 else if (y >= h) y = h - 1;
			var o = (y * w + x) * 4;
			return ((src.get(o) * 77 + src.get(o + 1) * 150 + src.get(o + 2) * 29) >> 8) | (src.get(o + 3) << 8);
		}

		for (r in 0...trows)
		{
			var y = tr0 + r;
			var left = feat(-1, y);
			var mid = feat(0, y);
			for (x in 0...w)
			{
				var right = feat(x + 1, y);
				var upF = feat(x, y - 1);
				var downF = feat(x, y + 1);
				var lx = (right & 255) - (left & 255);
				var ax = (right >> 8) - (left >> 8);
				var ly = (downF & 255) - (upF & 255);
				var ay = (downF >> 8) - (upF >> 8);
				var o = (r * w + x) * 3;
				tensor[o] = lx * lx + ax * ax;
				tensor[o + 1] = lx * ly + ax * ay;
				tensor[o + 2] = ly * ly + ay * ay;
				left = mid;
				mid = right;
			}
		}
		for (r in 0...trows)
		{
			for (x in 0...w)
			{
				var o = (r * w + x) * 3;
				for (k in 0...3)
				{
					var s = tensor[o + k];
					if (x > 0) s += tensor[o - 3 + k];
					if (x < w - 1) s += tensor[o + 3 + k];
					rowSum[o + k] = s;
				}
			}
		}
		for (r in 0...rows)
		{
			for (x in 0...w)
			{
				var o = ((r + 1) * w + x) * 3;
				var a = rowSum[o] + rowSum[o - w * 3] + rowSum[o + w * 3];
				var b = rowSum[o + 1] + rowSum[o + 1 - w * 3] + rowSum[o + 1 + w * 3];
				var c = rowSum[o + 2] + rowSum[o + 2 - w * 3] + rowSum[o + 2 + w * 3];
				var code = 0;
				var tr = a + c;
				if (tr > 0)
				{
					var d = a - c;
					var coh = Math.sqrt(d * d + 4.0 * b * b) / tr;
					var strength = tr / EDGE_FULL;
					if (strength > 1) strength = 1;
					var e = Std.int(coh * strength * (EDGES - 1) + 0.5);
					if (e > 0)
					{
						var th = 0.5 * Math.atan2(2.0 * b, d);
						if (th < 0) th += Math.PI;
						var ai = Std.int(th / Math.PI * ANGLES + 0.5) % ANGLES;
						code = ai * EDGES + e;
					}
				}
				codes[r * w + x] = code;
			}
		}

		var t = Ptr.of(table);
		for (r in 0...rows)
		{
			var y = ry0 + r;
			for (x in 0...w)
			{
				var base0 = codes[r * w + x] * 64;
				for (c in 0...4)
				{
					var cx = (c & 1) == 1 ? 1 : -1;
					var cy = (c & 2) == 2 ? 1 : -1;
					var nx0 = cx < 0 ? x - 1 : x;
					var ny0 = cy < 0 ? y - 1 : y;
					var o = ((r * 2 + ((c >> 1) & 1)) * w2 + x * 2 + (c & 1)) * 4;
					var mnR = 255, mnG = 255, mnB = 255, mnA = 255;
					var mxR = 0, mxG = 0, mxB = 0, mxA = 0;
					for (j in 0...4)
					{
						var sx = nx0 + (j & 1);
						var sy = ny0 + (j >> 1);
						if (sx < 0) sx = 0 else if (sx >= w) sx = w - 1;
						if (sy < 0) sy = 0 else if (sy >= h) sy = h - 1;
						var p = (sy * w + sx) * 4;
						var vr = src.get(p), vg = src.get(p + 1), vb = src.get(p + 2), va = src.get(p + 3);
						if (vr < mnR) mnR = vr;
						if (vr > mxR) mxR = vr;
						if (vg < mnG) mnG = vg;
						if (vg > mxG) mxG = vg;
						if (vb < mnB) mnB = vb;
						if (vb > mxB) mxB = vb;
						if (va < mnA) mnA = va;
						if (va > mxA) mxA = va;
					}
					zero.set((r * w + x) * 4 + c, mxA == 0 ? 1 : 0);
					if (mxA == 0)
					{
						up.set(o, 0);
						up.set(o + 1, 0);
						up.set(o + 2, 0);
						up.set(o + 3, 0);
						continue;
					}
					var bx = cx < 0 ? x - 2 : x - 1;
					var by = cy < 0 ? y - 2 : y - 1;
					var base = base0 + c * 16;
					var sr = 0, sg = 0, sb = 0, sa = 0;
					for (i in 0...16)
					{
						var wt = t[base + i];
						if (wt == 0) continue;
						var sx = bx + (i & 3);
						var sy = by + (i >> 2);
						if (sx < 0) sx = 0 else if (sx >= w) sx = w - 1;
						if (sy < 0) sy = 0 else if (sy >= h) sy = h - 1;
						var p = (sy * w + sx) * 4;
						sr += src.get(p) * wt;
						sg += src.get(p + 1) * wt;
						sb += src.get(p + 2) * wt;
						sa += src.get(p + 3) * wt;
					}
					var va = (sa + 2048) >> 12;
					if (va < mnA) va = mnA else if (va > mxA) va = mxA;
					var vr = (sr + 2048) >> 12;
					if (vr < mnR) vr = mnR else if (vr > mxR) vr = mxR;
					var vg = (sg + 2048) >> 12;
					if (vg < mnG) vg = mnG else if (vg > mxG) vg = mxG;
					var vb = (sb + 2048) >> 12;
					if (vb < mnB) vb = mnB else if (vb > mxB) vb = mxB;
					if (vr > va) vr = va;
					if (vg > va) vg = va;
					if (vb > va) vb = va;
					up.set(o, vr);
					up.set(o + 1, vg);
					up.set(o + 2, vb);
					up.set(o + 3, va);
				}
			}
		}

		for (pass in 0...2)
		{
			for (r in 0...rows)
			{
				var y = ry0 + r;
				for (x in 0...w)
				{
					var s = (y * w + x) * 4;
					var a = ((r * 2) * w2 + x * 2) * 4;
					var b = a + w2 * 4;
					var ro = (r * w + x) * 4;
					for (k in 0...4)
					{
						var m = (up.get(a + k) + up.get(a + 4 + k) + up.get(b + k) + up.get(b + 4 + k) + 2) >> 2;
						res[ro + k] = src.get(s + k) - m;
					}
				}
			}
			for (r in 0...rows)
			{
				for (x in 0...w)
				{
					var ro = (r * w + x) * 4;
					for (c in 0...4)
					{
						var cx = (c & 1) == 1 ? 1 : -1;
						var cy = (c & 2) == 2 ? 1 : -1;
						var xn = x + cx;
						if (xn < 0 || xn >= w) xn = x;
						var rn = r + cy;
						if (rn < 0 || rn >= rows) rn = r;
						var rx = (r * w + xn) * 4;
						var ry = (rn * w + x) * 4;
						var rxy = (rn * w + xn) * 4;
						var o = ((r * 2 + ((c >> 1) & 1)) * w2 + x * 2 + (c & 1)) * 4;
						if (zero.get(ro + c) == 1) continue;
						var va = up.get(o + 3) + ((9 * res[ro + 3] + 3 * res[rx + 3] + 3 * res[ry + 3] + res[rxy + 3] + 8) >> 4);
						if (va < 0) va = 0 else if (va > 255) va = 255;
						for (k in 0...3)
						{
							var v = up.get(o + k) + ((9 * res[ro + k] + 3 * res[rx + k] + 3 * res[ry + k] + res[rxy + k] + 8) >> 4);
							if (v < 0) v = 0 else if (v > va) v = va;
							up.set(o + k, v);
						}
						up.set(o + 3, va);
					}
				}
			}
		}

		for (r in 0...rows)
		{
			var y = ry0 + r;
			for (x in 0...w)
			{
				var s = (y * w + x) * 4;
				var a = ((r * 2) * w2 + x * 2) * 4;
				var b = a + w2 * 4;
				var ro = (r * w + x) * 4;
				var open = 0;
				for (c in 0...4) if (zero.get(ro + c) == 0) open++;
				if (open == 0) continue;
				for (kk in 0...4)
				{
					var k = (kk + 3) & 3;
					var sum = up.get(a + k) + up.get(a + 4 + k) + up.get(b + k) + up.get(b + 4 + k);
					var diff = src.get(s + k) * 4 - sum;
					var c = 0;
					var guard = 0;
					while (diff != 0 && guard++ < 16)
					{
						if (zero.get(ro + c) == 0)
						{
							var kid = (c & 2) == 0 ? a + (c & 1) * 4 : b + (c & 1) * 4;
							var o = kid + k;
							var cap = k == 3 ? 255 : up.get(kid + 3);
							var v = up.get(o);
							var step = diff > 0 ? Std.int((diff + open - 1) / open) : -Std.int((open - 1 - diff) / open);
							var nv = v + step;
							if (nv < 0) nv = 0 else if (nv > cap) nv = cap;
							diff -= nv - v;
							up.set(o, nv);
						}
						c = (c + 1) & 3;
					}
				}
				for (c in 0...4)
				{
					var o = (c & 2) == 0 ? a + (c & 1) * 4 : b + (c & 1) * 4;
					var va = up.get(o + 3);
					for (k in 0...3) if (up.get(o + k) > va) up.set(o + k, va);
				}
			}
		}

		var size = (y1 - y0) * 2 * w2 * 4;
		if (bandOut == null || bandOut.length < size) bandOut = Bytes.alloc(size);
		var out = bandOut;
		out.blit(0, this.up, (y0 - ry0) * 2 * w2 * 4, size);
		for (y in y0...y1)
		{
			var r = y - ry0;
			for (x in 0...w)
			{
				var s = (y * w + x) * 4;
				var a = ((r * 2) * w2 + x * 2) * 4;
				var b = a + w2 * 4;
				for (k in 0...4)
				{
					var m = (up.get(a + k) + up.get(a + 4 + k) + up.get(b + k) + up.get(b + 4 + k) + 2) >> 2;
					var d = m - src.get(s + k);
					sse += d * d;
				}
			}
		}
		counted += (y1 - y0) * w;
		return out;
	}
}

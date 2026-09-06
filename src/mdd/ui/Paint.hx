package mdd.ui;

import haxe.ds.Vector;
import mdd.host.Canvas;
import mdd.host.Draw;
import mdd.host.Sdl;
import mdd.host.Texture;

@:unreflective
final class Paint {
	static inline final FLOATS = 8;
	static inline final DEPTH = 16;

	public var font(default, null):Font;

	var renderer:cpp.Star<Canvas>;
	var bound:cpp.Star<Texture> = null;

	var batch:Vector<Single>;
	var used:Int = 0;

	var offsetX:Float = 0;
	var offsetY:Float = 0;
	var scaleX:Float = 1;
	var scaleY:Float = 1;

	final stackX:Vector<Float> = new Vector<Float>(DEPTH);
	final stackY:Vector<Float> = new Vector<Float>(DEPTH);
	final stackSx:Vector<Float> = new Vector<Float>(DEPTH);
	final stackSy:Vector<Float> = new Vector<Float>(DEPTH);
	var deep:Int = 0;

	var opacity:Float = 1;
	final opacities:Vector<Float> = new Vector<Float>(DEPTH);
	var veiled:Int = 0;

	final clipX:Vector<Float> = new Vector<Float>(DEPTH);
	final clipY:Vector<Float> = new Vector<Float>(DEPTH);
	final clipW:Vector<Float> = new Vector<Float>(DEPTH);
	final clipH:Vector<Float> = new Vector<Float>(DEPTH);
	var clipped:Int = 0;

	var skippedClips:Int = 0;
	var skippedDeep:Int = 0;
	var skippedVeils:Int = 0;

	final corners:Vector<Int> = new Vector<Int>(512);

	function new() {}

	public static function on(renderer:cpp.Star<Canvas>, font:Font):Paint {
		final paint = new Paint();
		paint.renderer = renderer;
		paint.font = font;
		paint.bound = font.texture;
		paint.batch = new Vector<Single>(FLOATS * 6 * 2048);
		return paint;
	}

	public function sheet(width:Int, height:Int):cpp.Star<Texture> {
		return Draw.createTarget(renderer, width, height);
	}

	public function target(texture:cpp.Star<Texture>):Void {
		flush();
		Draw.setTarget(renderer, texture);
	}

	public function clear(red:Float, green:Float, blue:Float, alpha:Float):Void {
		Sdl.renderClear(renderer, red, green, blue, alpha);
	}

	public function blit(texture:cpp.Star<Texture>, x:Float, y:Float, width:Float,
			height:Float):Void {
		flush();
		Draw.texture(renderer, texture, at(x), down(y), width * scaleX, height * scaleY, opacity);
	}

	public function pushOpacity(amount:Float):Void {
		if (veiled >= DEPTH) {
			skippedVeils++;
			return;
		}


		opacities[veiled] = opacity;
		veiled++;
		opacity *= amount < 0 ? 0 : (amount > 1 ? 1 : amount);
	}

	public function popOpacity():Void {
		if (skippedVeils > 0) {
			skippedVeils--;
			return;
		}

		if (veiled <= 0) return;

		veiled--;
		opacity = opacities[veiled];
	}

	public function reface(font:Font):Void {
		flush();
		this.font = font;
		bound = font.texture;
	}

	public function icon(icons:Icons, which:Int, x:Float, y:Float, size:Float, colour:Colour,
			alpha:Float = 1):Void {
		if (icons == null || !icons.has(which) || size <= 0) return;

		binds(icons.texture);
		room(FLOATS * 6);

		final r = colour.red * CHANNEL;
		final g = colour.green * CHANNEL;
		final b = colour.blue * CHANNEL;
		final a = alpha * opacity;

		final left = at(x);
		final top = down(y);
		final right = at(x + size);
		final bottom = down(y + size);

		final u0 = icons.u0(which);
		final v0 = icons.v0(which);
		final u1 = icons.u1(which);
		final v1 = icons.v1(which);

		push(left, top, r, g, b, a, u0, v0);
		push(right, top, r, g, b, a, u1, v0);
		push(right, bottom, r, g, b, a, u1, v1);

		push(left, top, r, g, b, a, u0, v0);
		push(right, bottom, r, g, b, a, u1, v1);
		push(left, bottom, r, g, b, a, u0, v1);
	}

	inline function binds(texture:cpp.Star<Texture>):Void {
		if (texture != bound) {
			flush();
			bound = texture;
		}
	}

	public inline function nesting():Int {
		return clipped + deep + veiled + skippedClips + skippedDeep + skippedVeils;
	}

	public inline function pending():Int {
		return Std.int(used / FLOATS);
	}

	public function flush():Void {
		if (used == 0) return;
		Draw.geometry(renderer, bound == null ? font.texture : bound,
			cpp.Pointer.arrayElem(batch.toData(), 0).constRaw, Std.int(used / FLOATS));
		used = 0;
	}

	function room(floats:Int):Void {
		if (used + floats <= batch.length) return;

		var wide = batch.length;
		while (wide < used + floats) wide = wide << 1;

		final grown = new Vector<Single>(wide);
		Vector.blit(batch, 0, grown, 0, used);
		batch = grown;
	}

	inline function at(x:Float):Float {
		return x * scaleX + offsetX;
	}

	inline function down(y:Float):Float {
		return y * scaleY + offsetY;
	}

	static inline final CHANNEL = 1 / 255.0;

	inline function push(x:Float, y:Float, r:Float, g:Float, b:Float, a:Float, u:Float,
			v:Float):Void {
		final into = batch;
		final at = used;

		into[at] = x;
		into[at + 1] = y;
		into[at + 2] = r;
		into[at + 3] = g;
		into[at + 4] = b;
		into[at + 5] = a;
		into[at + 6] = u;
		into[at + 7] = v;

		used = at + FLOATS;
	}

	function triangle(x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, colour:Colour,
			alpha:Float):Void {
		binds(font.texture);
		room(FLOATS * 3);

		final r = colour.red * CHANNEL;
		final g = colour.green * CHANNEL;
		final b = colour.blue * CHANNEL;
		final a = alpha * opacity;
		final u = font.solidU;
		final v = font.solidV;

		push(at(x0), down(y0), r, g, b, a, u, v);
		push(at(x1), down(y1), r, g, b, a, u, v);
		push(at(x2), down(y2), r, g, b, a, u, v);
	}

	function quad(x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float,
			colour:Colour, alpha:Float):Void {
		binds(font.texture);
		room(FLOATS * 6);

		final r = colour.red * CHANNEL;
		final g = colour.green * CHANNEL;
		final b = colour.blue * CHANNEL;
		final a = alpha * opacity;
		final u = font.solidU;
		final v = font.solidV;

		final ax = at(x0);
		final ay = down(y0);
		final bx = at(x1);
		final by = down(y1);
		final cx = at(x2);
		final cy = down(y2);
		final dx = at(x3);
		final dy = down(y3);

		push(ax, ay, r, g, b, a, u, v);
		push(bx, by, r, g, b, a, u, v);
		push(cx, cy, r, g, b, a, u, v);

		push(ax, ay, r, g, b, a, u, v);
		push(cx, cy, r, g, b, a, u, v);
		push(dx, dy, r, g, b, a, u, v);
	}

	public function rect(x:Float, y:Float, width:Float, height:Float, colour:Colour,
			alpha:Float = 1):Void {
		if (width <= 0 || height <= 0) return;

		final left = Math.round(x);
		final top = Math.round(y);

		var right = Math.round(x + width);
		var bottom = Math.round(y + height);

		if (right <= left) right = left + 1;
		if (bottom <= top) bottom = top + 1;

		quad(left, top, right, top, right, bottom, left, bottom, colour, alpha);
	}

	public function roundedGradient(x:Float, y:Float, width:Float, height:Float,
			radius:Float, top:Colour, bottom:Colour, alpha:Float = 1, share:Float = 1):Void {
		if (width <= 0 || height <= 0) return;

		if (share < 1) {
			if (share <= 0) return;

			pushClip(x, y, width * share, height);
			roundedGradient(x, y, width, height, radius, top, bottom, alpha);
			popClip();
			return;
		}

		final left = Math.round(x);
		final upper = Math.round(y);

		var right = Math.round(x + width);
		var lower = Math.round(y + height);

		if (right <= left) right = left + 1;
		if (lower <= upper) lower = upper + 1;

		final wide = right - left;
		final tall = lower - upper;

		final r = rounding(radius, wide, tall);

		if (r <= 0) {
			gradient(left, upper, wide, tall, top, bottom, alpha);
			return;
		}

		shaded(left + r, upper, wide - r * 2, tall, top, bottom, upper, tall, alpha);
		shaded(left, upper + r, r, tall - r * 2, top, bottom, upper, tall, alpha);
		shaded(right - r, upper + r, r, tall - r * 2, top, bottom, upper, tall, alpha);

		bend(left + r, upper + r, r, 180, 270, top, bottom, upper, tall, alpha);
		bend(right - r, upper + r, r, 270, 360, top, bottom, upper, tall, alpha);
		bend(right - r, lower - r, r, 0, 90, top, bottom, upper, tall, alpha);
		bend(left + r, lower - r, r, 90, 180, top, bottom, upper, tall, alpha);
	}

	public function gradient(x:Float, y:Float, width:Float, height:Float, top:Colour, bottom:Colour,
			alpha:Float = 1):Void {
		if (width <= 0 || height <= 0) return;
		shaded(x, y, width, height, top, bottom, y, height, alpha);
	}

	inline function tone(top:Colour, bottom:Colour, from:Float, span:Float, y:Float):Colour {
		if (span <= 0) return top;

		final t = (y - from) / span;
		return top.mix(bottom, t < 0 ? 0 : (t > 1 ? 1 : t));
	}

	function shaded(x:Float, y:Float, width:Float, height:Float, top:Colour, bottom:Colour,
			from:Float, span:Float, alpha:Float):Void {
		if (width <= 0 || height <= 0) return;

		final left = Math.round(x);
		final upper = Math.round(y);

		var right = Math.round(x + width);
		var lower = Math.round(y + height);

		if (right <= left) right = left + 1;
		if (lower <= upper) lower = upper + 1;

		final above = tone(top, bottom, from, span, upper);
		final below = tone(top, bottom, from, span, lower);

		wedge(left, upper, above, right, upper, above, right, lower, below, alpha);
		wedge(left, upper, above, right, lower, below, left, lower, below, alpha);
	}

	function bend(cx:Float, cy:Float, r:Float, starts:Float, ends:Float, top:Colour,
			bottom:Colour, from:Float, span:Float, alpha:Float):Void {
		var count = Math.ceil(r * 1.2);
		if (count < 3) count = 3;
		if (count > 24) count = 24;

		final step = (ends - starts) * Math.PI / 180 / count;
		var angle = starts * Math.PI / 180;

		final middle = tone(top, bottom, from, span, cy);

		for (index in 0...count) {
			final ax = cx + Math.cos(angle) * r;
			final ay = cy + Math.sin(angle) * r;
			final bx = cx + Math.cos(angle + step) * r;
			final by = cy + Math.sin(angle + step) * r;

			wedge(cx, cy, middle, ax, ay, tone(top, bottom, from, span, ay),
				bx, by, tone(top, bottom, from, span, by), alpha);

			angle += step;
		}
	}

	function faded(x0:Float, y0:Float, a0:Float, x1:Float, y1:Float, a1:Float, x2:Float,
			y2:Float, a2:Float, colour:Colour):Void {
		binds(font.texture);
		room(FLOATS * 3);

		final r = colour.red * CHANNEL;
		final g = colour.green * CHANNEL;
		final b = colour.blue * CHANNEL;
		final held = opacity;
		final u = font.solidU;
		final v = font.solidV;

		push(at(x0), down(y0), r, g, b, a0 * held, u, v);
		push(at(x1), down(y1), r, g, b, a1 * held, u, v);
		push(at(x2), down(y2), r, g, b, a2 * held, u, v);
	}

	function band(cx:Float, cy:Float, inner:Float, outer:Float, from:Float, to:Float,
			count:Int, colour:Colour, alpha:Float):Void {
		final step = (to - from) / count;

		var angle = from;

		for (index in 0...count) {
			final ax = Math.cos(angle);
			final ay = Math.sin(angle);
			final bx = Math.cos(angle + step);
			final by = Math.sin(angle + step);

			faded(cx + ax * inner, cy + ay * inner, alpha, cx + ax * outer, cy + ay * outer, 0,
				cx + bx * outer, cy + by * outer, 0, colour);
			faded(cx + ax * inner, cy + ay * inner, alpha, cx + bx * outer, cy + by * outer, 0,
				cx + bx * inner, cy + by * inner, alpha, colour);

			angle += step;
		}
	}

	static inline final FEATHER = 0.5;

	static inline function rounding(radius:Float, wide:Float, tall:Float):Float {
		final half = Math.ffloor((wide < tall ? wide : tall) * 0.5);
		final want = Math.ffloor(radius);

		return want > half ? half : (want < 1 ? 0 : want);
	}

	function wedge(x0:Float, y0:Float, c0:Colour, x1:Float, y1:Float, c1:Colour, x2:Float,
			y2:Float, c2:Colour, alpha:Float):Void {
		binds(font.texture);
		room(FLOATS * 3);

		final a = alpha * opacity;
		final u = font.solidU;
		final v = font.solidV;

		push(at(x0), down(y0), c0.red * CHANNEL, c0.green * CHANNEL, c0.blue * CHANNEL, a, u, v);
		push(at(x1), down(y1), c1.red * CHANNEL, c1.green * CHANNEL, c1.blue * CHANNEL, a, u, v);
		push(at(x2), down(y2), c2.red * CHANNEL, c2.green * CHANNEL, c2.blue * CHANNEL, a, u, v);
	}

	public function outline(x:Float, y:Float, width:Float, height:Float, colour:Colour,
			weight:Float = 1, alpha:Float = 1, radius:Float = 0):Void {
		if (width <= 0 || height <= 0) return;

		var r = radius;
		final half = (width < height ? width : height) * 0.5;
		if (r > half) r = half;

		if (r <= 0.5) {
			rect(x, y, width, weight, colour, alpha);
			rect(x, y + height - weight, width, weight, colour, alpha);
			rect(x, y + weight, weight, height - weight * 2, colour, alpha);
			rect(x + width - weight, y + weight, weight, height - weight * 2, colour, alpha);

			return;
		}

		rect(x + r, y, width - r * 2, weight, colour, alpha);
		rect(x + r, y + height - weight, width - r * 2, weight, colour, alpha);
		rect(x, y + r, weight, height - r * 2, colour, alpha);
		rect(x + width - weight, y + r, weight, height - r * 2, colour, alpha);

		final half = Math.PI * 0.5;

		arc(x + r, y + r, r, Math.PI, Math.PI + half, weight, colour, alpha);
		arc(x + width - r, y + r, r, Math.PI + half, Math.PI * 2, weight, colour, alpha);
		arc(x + width - r, y + height - r, r, 0, half, weight, colour, alpha);
		arc(x + r, y + height - r, r, half, Math.PI, weight, colour, alpha);
	}

	public function roundedRect(x:Float, y:Float, width:Float, height:Float, radius:Float,
			colour:Colour, alpha:Float = 1, share:Float = 1):Void {
		if (width <= 0 || height <= 0) return;

		if (share < 1) {
			if (share <= 0) return;

			pushClip(x, y, width * share, height);
			roundedRect(x, y, width, height, radius, colour, alpha);
			popClip();
			return;
		}

		final left = Math.round(x);
		final top = Math.round(y);

		var right = Math.round(x + width);
		var bottom = Math.round(y + height);

		if (right <= left) right = left + 1;
		if (bottom <= top) bottom = top + 1;

		final wide = right - left;
		final tall = bottom - top;

		final r = rounding(radius, wide, tall);

		if (r <= 0) {
			rect(left, top, wide, tall, colour, alpha);
			return;
		}

		rect(left + r, top, wide - r * 2, tall, colour, alpha);
		rect(left, top + r, r, tall - r * 2, colour, alpha);
		rect(right - r, top + r, r, tall - r * 2, colour, alpha);

		corner(left + r, top + r, r, 180, 270, colour, alpha);
		corner(right - r, top + r, r, 270, 360, colour, alpha);
		corner(right - r, bottom - r, r, 0, 90, colour, alpha);
		corner(left + r, bottom - r, r, 90, 180, colour, alpha);
	}

	function corner(cx:Float, cy:Float, r:Float, from:Float, to:Float, colour:Colour,
			alpha:Float):Void {
		var count = Math.ceil(r * 2);
		if (count < 4) count = 4;
		if (count > 48) count = 48;

		final solid = r - FEATHER;
		final starts = from * Math.PI / 180;
		final ends = to * Math.PI / 180;
		final step = (ends - starts) / count;

		band(cx, cy, solid, r + FEATHER, starts, ends, count, colour, alpha);

		var angle = starts;

		for (i in 0...count) {
			triangle(cx, cy, cx + Math.cos(angle) * solid, cy + Math.sin(angle) * solid,
				cx + Math.cos(angle + step) * solid, cy + Math.sin(angle + step) * solid,
				colour, alpha);
			angle += step;
		}
	}

	static inline function segments(radius:Float):Int {
		final want = Math.ceil(radius * 3);
		return want < 12 ? 12 : (want > 128 ? 128 : want);
	}

	public function circle(cx:Float, cy:Float, radius:Float, colour:Colour, alpha:Float = 1):Void {
		if (radius <= 0) return;

		final count = segments(radius);
		final step = Math.PI * 2 / count;
		final solid = radius - FEATHER;

		band(cx, cy, solid, radius + FEATHER, 0, Math.PI * 2, count, colour, alpha);

		var angle = 0.0;

		for (i in 0...count) {
			triangle(cx, cy, cx + Math.cos(angle) * solid, cy + Math.sin(angle) * solid,
				cx + Math.cos(angle + step) * solid, cy + Math.sin(angle + step) * solid,
				colour, alpha);
			angle += step;
		}
	}

	public function arc(cx:Float, cy:Float, radius:Float, from:Float, to:Float, weight:Float,
			colour:Colour, alpha:Float = 1):Void {
		if (radius <= 0 || weight <= 0) return;

		final count = segments(radius);
		final step = (to - from) / count;

		final outer = radius - FEATHER;
		var inner = radius - weight + FEATHER;
		if (inner > outer) inner = outer;

		band(cx, cy, outer, radius + FEATHER, from, to, count, colour, alpha);
		band(cx, cy, inner, radius - weight - FEATHER, from, to, count, colour, alpha);

		var angle = from;

		for (i in 0...count) {
			final ax = Math.cos(angle);
			final ay = Math.sin(angle);
			final bx = Math.cos(angle + step);
			final by = Math.sin(angle + step);

			quad(cx + ax * inner, cy + ay * inner, cx + ax * outer, cy + ay * outer,
				cx + bx * outer, cy + by * outer, cx + bx * inner, cy + by * inner, colour,
				alpha);
			angle += step;
		}
	}

	public inline function ring(cx:Float, cy:Float, radius:Float, weight:Float, colour:Colour,
			alpha:Float = 1):Void {
		arc(cx, cy, radius, 0, Math.PI * 2, weight, colour, alpha);
	}

	public function line(x0:Float, y0:Float, x1:Float, y1:Float, weight:Float, colour:Colour,
			alpha:Float = 1):Void {
		final dx = x1 - x0;
		final dy = y1 - y0;
		final run = Math.sqrt(dx * dx + dy * dy);
		if (run < 0.0001) return;

		final half = weight * 0.5;
		final nx = -dy / run * half;
		final ny = dx / run * half;

		quad(x0 + nx, y0 + ny, x1 + nx, y1 + ny, x1 - nx, y1 - ny, x0 - nx, y0 - ny, colour, alpha);
	}

	public static inline final JOIN = 0.35;

	public function polyline(points:Vector<Float>, count:Int, weight:Float, colour:Colour,
			alpha:Float = 1):Void {
		if (count < 2) return;

		for (i in 0...count - 1) {
			line(points[i * 2], points[i * 2 + 1], points[i * 2 + 2], points[i * 2 + 3], weight,
				colour, alpha);
		}

		if (weight <= 1.5) return;

		final half = weight * 0.5;
		final least = JOIN / half;
		final square = least * least;

		for (i in 1...count - 1) {
			final ax = points[i * 2] - points[i * 2 - 2];
			final ay = points[i * 2 + 1] - points[i * 2 - 1];
			final bx = points[i * 2 + 2] - points[i * 2];
			final by = points[i * 2 + 3] - points[i * 2 + 1];

			final dot = ax * bx + ay * by;

			if (dot > 0) {
				final cross = ax * by - ay * bx;
				if (cross * cross <= square * dot * dot) continue;
			}

			circle(points[i * 2], points[i * 2 + 1], half, colour, alpha);
		}
	}

	public function polygon(points:Vector<Float>, count:Int, colour:Colour, alpha:Float = 1):Void {
		if (count < 3) return;

		var left = count;
		for (i in 0...count) corners[i] = i;

		var guard = 0;
		final most = count * count;

		while (left > 3 && guard < most) {
			guard++;
			var clipped = false;

			for (i in 0...left) {
				final a = corners[i];
				final b = corners[(i + 1) % left];
				final c = corners[(i + 2) % left];

				if (!ear(points, a, b, c, left)) continue;

				triangle(points[a * 2], points[a * 2 + 1], points[b * 2], points[b * 2 + 1],
					points[c * 2], points[c * 2 + 1], colour, alpha);

				final drop = (i + 1) % left;
				for (n in drop...left - 1) corners[n] = corners[n + 1];
				left--;
				clipped = true;
				break;
			}

			if (!clipped) break;
		}

		for (i in 0...left - 2) {
			final a = corners[0];
			final b = corners[i + 1];
			final c = corners[i + 2];
			triangle(points[a * 2], points[a * 2 + 1], points[b * 2], points[b * 2 + 1],
				points[c * 2], points[c * 2 + 1], colour, alpha);
		}
	}

	function ear(points:Vector<Float>, a:Int, b:Int, c:Int, left:Int):Bool {
		final ax = points[a * 2];
		final ay = points[a * 2 + 1];
		final bx = points[b * 2];
		final by = points[b * 2 + 1];
		final cx = points[c * 2];
		final cy = points[c * 2 + 1];

		if ((bx - ax) * (cy - ay) - (by - ay) * (cx - ax) <= 0) return false;

		for (n in 0...left) {
			final index = corners[n];
			if (index == a || index == b || index == c) continue;
			if (inside(points[index * 2], points[index * 2 + 1], ax, ay, bx, by, cx, cy)) {
				return false;
			}
		}
		return true;
	}

	static function inside(x:Float, y:Float, ax:Float, ay:Float, bx:Float, by:Float, cx:Float,
			cy:Float):Bool {
		final one = (bx - ax) * (y - ay) - (by - ay) * (x - ax);
		final two = (cx - bx) * (y - by) - (cy - by) * (x - bx);
		final three = (ax - cx) * (y - cy) - (ay - cy) * (x - cx);
		return (one >= 0 && two >= 0 && three >= 0) || (one <= 0 && two <= 0 && three <= 0);
	}

	public function curve(x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float,
			y3:Float, weight:Float, colour:Colour, alpha:Float = 1):Void {
		final rough = Math.abs(x1 - x0) + Math.abs(y1 - y0) + Math.abs(x2 - x1)
			+ Math.abs(y2 - y1) + Math.abs(x3 - x2) + Math.abs(y3 - y2);

		var steps = Std.int(Math.sqrt(rough * 3));
		if (steps < 4) steps = 4;
		if (steps > 128) steps = 128;

		var lastX = x0;
		var lastY = y0;

		for (i in 1...steps + 1) {
			final t = i / steps;
			final k = 1 - t;
			final a = k * k * k;
			final b = 3 * k * k * t;
			final c = 3 * k * t * t;
			final d = t * t * t;

			final x = a * x0 + b * x1 + c * x2 + d * x3;
			final y = a * y0 + b * y1 + c * y2 + d * y3;

			line(lastX, lastY, x, y, weight, colour, alpha);
			lastX = x;
			lastY = y;
		}
	}

	public function waveform(samples:Vector<Float>, from:Int, to:Int, x:Float, y:Float,
			width:Float, height:Float, colour:Colour, alpha:Float = 1):Void {
		final span = to - from;
		if (span <= 0 || width <= 0) return;

		final columns = Std.int(width);
		final middle = y + height * 0.5;
		final reach = height * 0.5;

		for (column in 0...columns) {
			final start = from + Std.int(span * column / columns);
			var stop = from + Std.int(span * (column + 1) / columns);
			if (stop <= start) stop = start + 1;
			if (stop > to) stop = to;

			var least = samples[start];
			var most = samples[start];

			for (i in start...stop) {
				final one = samples[i];
				if (one < least) least = one;
				if (one > most) most = one;
			}

			final top = middle - most * reach;
			final bottom = middle - least * reach;
			final tall = bottom - top;
			rect(x + column, top, 1, tall < 1 ? 1 : tall, colour, alpha);
		}
	}

	public function text(value:String, x:Float, y:Float, colour:Colour, alpha:Float = 1):Float {
		binds(font.texture);
		room(FLOATS * 6 * value.length);

		final r = colour.red * CHANNEL;
		final g = colour.green * CHANNEL;
		final b = colour.blue * CHANNEL;
		final a = alpha * opacity;

		var pen = x;

		for (i in 0...value.length) {
			final code = value.charCodeAt(i);
			if (!font.has(code)) continue;

			final left = at(pen + font.offsetX(code));
			final top = down(y + font.offsetY(code));
			final right = left + font.wide(code) * scaleX;
			final bottom = top + font.tall(code) * scaleY;

			final u0 = font.u0(code);
			final v0 = font.v0(code);
			final u1 = font.u1(code);
			final v1 = font.v1(code);

			push(left, top, r, g, b, a, u0, v0);
			push(right, top, r, g, b, a, u1, v0);
			push(right, bottom, r, g, b, a, u1, v1);

			push(left, top, r, g, b, a, u0, v0);
			push(right, bottom, r, g, b, a, u1, v1);
			push(left, bottom, r, g, b, a, u0, v1);

			pen += font.advance(code);
		}

		return pen;
	}

	public inline function textRight(value:String, right:Float, y:Float, colour:Colour,
			alpha:Float = 1):Void {
		text(value, right - font.measure(value), y, colour, alpha);
	}

	public inline function textCentred(value:String, centre:Float, y:Float, colour:Colour,
			alpha:Float = 1):Void {
		text(value, centre - font.measure(value) * 0.5, y, colour, alpha);
	}

	public inline function measure(value:String):Float {
		return font.measure(value);
	}

	public function pushClip(x:Float, y:Float, width:Float, height:Float):Void {
		if (clipped >= DEPTH) {
			skippedClips++;
			return;
		}

		flush();

		var left = at(x);
		var top = down(y);
		var right = left + width * scaleX;
		var bottom = top + height * scaleY;

		if (clipped > 0) {
			final heldX = clipX[clipped - 1];
			final heldY = clipY[clipped - 1];
			final heldRight = heldX + clipW[clipped - 1];
			final heldBottom = heldY + clipH[clipped - 1];

			if (left < heldX) left = heldX;
			if (top < heldY) top = heldY;
			if (right > heldRight) right = heldRight;
			if (bottom > heldBottom) bottom = heldBottom;
		}

		if (right < left) right = left;
		if (bottom < top) bottom = top;

		clipX[clipped] = left;
		clipY[clipped] = top;
		clipW[clipped] = right - left;
		clipH[clipped] = bottom - top;
		clipped++;

		Sdl.setClip(renderer, Std.int(left), Std.int(top), Std.int(right - left),
			Std.int(bottom - top));
	}

	public function popClip():Void {
		if (skippedClips > 0) {
			skippedClips--;
			return;
		}

		if (clipped == 0) return;

		flush();
		clipped--;

		if (clipped == 0) {
			Sdl.clearClip(renderer);
			return;
		}

		Sdl.setClip(renderer, Std.int(clipX[clipped - 1]), Std.int(clipY[clipped - 1]),
			Std.int(clipW[clipped - 1]), Std.int(clipH[clipped - 1]));
	}

	public function pushTransform(dx:Float, dy:Float, sx:Float = 1, sy:Float = 1):Void {
		if (deep >= DEPTH) {
			skippedDeep++;
			return;
		}


		stackX[deep] = offsetX;
		stackY[deep] = offsetY;
		stackSx[deep] = scaleX;
		stackSy[deep] = scaleY;
		deep++;

		offsetX = offsetX + dx * scaleX;
		offsetY = offsetY + dy * scaleY;
		scaleX *= sx;
		scaleY *= sy;
	}

	public function popTransform():Void {
		if (skippedDeep > 0) {
			skippedDeep--;
			return;
		}

		if (deep == 0) return;

		deep--;
		offsetX = stackX[deep];
		offsetY = stackY[deep];
		scaleX = stackSx[deep];
		scaleY = stackSy[deep];
	}

	public function reset():Void {
		deep = 0;
		veiled = 0;
		opacity = 1;
		offsetX = 0;
		offsetY = 0;
		scaleX = 1;
		scaleY = 1;
		while (clipped > 0) popClip();
	}
}

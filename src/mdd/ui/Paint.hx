package mdd.ui;

import haxe.ds.Vector;
import mdd.host.Canvas;
import mdd.host.Draw;
import mdd.host.Sdl;
import mdd.host.Texture;

@:unreflective

/**
	Every shape the interface draws, batched into as few draw calls as possible.

	Nothing here draws immediately. A shape becomes triangles in a growing buffer, and
	the buffer is handed to the card in one call whenever the texture, the clip or the
	transform has to change. A rectangle samples one opaque pixel in the glyph atlas,
	so a filled shape and a run of text are the same call and never split it.

	Timing a frame here without presenting measures the driver queue rather than the
	frame. Rendering six hundred frames into a texture as fast as they would build
	showed a deterministic forty millisecond spike inside a clip flush, which is where
	the card finally blocked waiting for everything queued behind it. The same six
	hundred with a real present at the end of each ran at 0.34 ms mean.
**/
final class Paint {
	static inline final FLOATS = 8;
	static inline final DEPTH = 16;

	/**
		The face text is drawn in, and the atlas every filled shape samples its opaque
		pixel from.
	**/
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

	/**
		Private: use `on`.
	**/
	function new() {}

	/**
		Builds a painter for a renderer.

		@param renderer The renderer to draw to.
		@param font The face to start with.
		@return The painter.
	**/
	public static function on(renderer:cpp.Star<Canvas>, font:Font):Paint {
		final paint = new Paint();
		paint.renderer = renderer;
		paint.font = font;
		paint.bound = font.texture;
		paint.batch = new Vector<Single>(FLOATS * 6 * 2048);
		return paint;
	}

	/**
		Makes a texture that can be drawn into.

		@param width How wide.
		@param height How tall.
		@return The texture, or null.
	**/
	public function sheet(width:Int, height:Int):cpp.Star<Texture> {
		return Draw.createTarget(renderer, width, height);
	}

	/**
		Draws into a texture from here, or back into the window when given null.

		@param texture The target, or null for the window.
	**/
	public function target(texture:cpp.Star<Texture>):Void {
		flush();
		Draw.setTarget(renderer, texture);
	}

	/**
		Fills the whole target with a colour.

		@param red Red, 0 to 1.
		@param green Green.
		@param blue Blue.
		@param alpha Alpha.
	**/
	public function clear(red:Float, green:Float, blue:Float, alpha:Float):Void {
		Sdl.renderClear(renderer, red, green, blue, alpha);
	}

	/**
		Draws a whole texture into a rectangle. This flushes, because it is not a
		triangle batch.

		@param texture The texture.
		@param x Where it goes, across.
		@param y Where it goes, down.
		@param width How wide.
		@param height How tall.
	**/
	public function blit(texture:cpp.Star<Texture>, x:Float, y:Float, width:Float,
			height:Float):Void {
		flush();
		Draw.texture(renderer, texture, at(x), down(y), width * scaleX, height * scaleY, opacity);
	}

	/**
		Multiplies everything drawn until the matching pop by an opacity.

		@param amount How opaque, 0 to 1.
	**/
	public function pushOpacity(amount:Float):Void {
		if (veiled >= DEPTH) {
			skippedVeils++;
			return;
		}


		opacities[veiled] = opacity;
		veiled++;
		opacity *= amount < 0 ? 0 : (amount > 1 ? 1 : amount);
	}

	/**
		Takes the last opacity back off.
	**/
	public function popOpacity():Void {
		if (skippedVeils > 0) {
			skippedVeils--;
			return;
		}

		if (veiled <= 0) return;

		veiled--;
		opacity = opacities[veiled];
	}

	/**
		Changes the face text is drawn in, flushing first because the atlas changes.

		@param font The face to draw in.
	**/
	public function reface(font:Font):Void {
		flush();
		this.font = font;
		bound = font.texture;
	}

	/**
		Draws one icon, tinted.

		@param icons The atlas.
		@param which Which icon.
		@param x Where it goes, across.
		@param y Where it goes, down.
		@param size How large to draw it.
		@param colour What to tint it.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		@return How deep the clip and transform stacks are, which a check reads to prove they are
			balanced.
	**/
	public inline function nesting():Int {
		return clipped + deep + veiled + skippedClips + skippedDeep + skippedVeils;
	}

	/**
		@return How many floats are waiting to be handed to the card.
	**/
	public inline function pending():Int {
		return Std.int(used / FLOATS);
	}

	/**
		Hands whatever is waiting to the card. Called whenever the texture, the clip or the
		transform has to change, and at the end of a frame.
	**/
	public function flush():Void {
		if (used == 0) return;
		Draw.geometry(renderer, bound == null ? font.texture : bound,
			cpp.Pointer.arrayElem(batch.toData(), 0).constRaw, Std.int(used / FLOATS));
		used = 0;
	}

	/**
		Makes sure there is room for more vertices, growing the buffer where there is
		not. It never flushes to make room: a flush is a draw call, and the whole point
		of the batch is that a frame is as few of those as it can be. The buffer
		doubles, so a frame stops growing it once it has seen its own busiest frame.

		@param floats How many floats are about to be written.
	**/
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

	/**
		Adds one flat triangle.

		@param x0 First corner, across.
		@param y0 First corner, down.
		@param x1 Second corner, across.
		@param y1 Second corner, down.
		@param x2 Third corner, across.
		@param y2 Third corner, down.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		Adds one flat quadrilateral, as two triangles.

		@param x0 First corner, across.
		@param y0 First corner, down.
		@param x1 Second corner, across.
		@param y1 Second corner, down.
		@param x2 Third corner, across.
		@param y2 Third corner, down.
		@param x3 Fourth corner, across.
		@param y3 Fourth corner, down.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		Draws a filled rectangle.

		@param x Where it goes, across.
		@param y Where it goes, down.
		@param width How wide.
		@param height How tall.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		Draws a rounded rectangle filled with a vertical gradient.

		@param x Where it goes, across.
		@param y Where it goes, down.
		@param width How wide.
		@param height How tall.
		@param radius How round the corners are.
		@param top The colour at the top.
		@param bottom The colour at the bottom.
		@param alpha How opaque, 0 to 1.
		@param share How much of the height to fill, 0 to 1, for a meter.
	**/
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

	/**
		Draws a rectangle filled with a vertical gradient.

		@param x Where it goes, across.
		@param y Where it goes, down.
		@param width How wide.
		@param height How tall.
		@param top The colour at the top.
		@param bottom The colour at the bottom.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		Draws a gradient rectangle whose colours come from a span larger than itself, so
		several pieces share one gradient.

		@param x Where it goes, across.
		@param y Where it goes, down.
		@param width How wide.
		@param height How tall.
		@param top The colour at the top of the span.
		@param bottom The colour at the bottom.
		@param from Where the span starts.
		@param span How tall the span is.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		Draws a rounded corner filled from a gradient span.

		@param cx The centre, across.
		@param cy The centre, down.
		@param r The corner radius.
		@param starts The angle it starts at.
		@param ends The angle it ends at.
		@param top The colour at the top of the span.
		@param bottom The colour at the bottom.
		@param from Where the span starts.
		@param span How tall the span is.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		Adds one triangle with a different opacity at each corner.

		@param x0 First corner, across.
		@param y0 First corner, down.
		@param a0 Its opacity.
		@param x1 Second corner, across.
		@param y1 Second corner, down.
		@param a1 Its opacity.
		@param x2 Third corner, across.
		@param y2 Third corner, down.
		@param a2 Its opacity.
		@param colour The colour to draw it in.
	**/
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

	/**
		Draws part of a ring, as a fan of quadrilaterals.

		@param cx The centre, across.
		@param cy The centre, down.
		@param inner The inner radius.
		@param outer The outer radius.
		@param from The angle it starts at.
		@param to The angle it ends at.
		@param count How many segments to use.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		Adds one triangle with a different colour at each corner.

		@param x0 First corner, across.
		@param y0 First corner, down.
		@param c0 Its colour.
		@param x1 Second corner, across.
		@param y1 Second corner, down.
		@param c1 Its colour.
		@param x2 Third corner, across.
		@param y2 Third corner, down.
		@param c2 Its colour.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		Draws the outline of a rectangle, rounded where asked.

		@param x Where it goes, across.
		@param y Where it goes, down.
		@param width How wide.
		@param height How tall.
		@param colour The colour to draw it in.
		@param weight How thick the line is.
		@param alpha How opaque, 0 to 1.
		@param radius How round the corners are, or nought for square.
	**/
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

	/**
		Draws a filled rounded rectangle.

		@param x Where it goes, across.
		@param y Where it goes, down.
		@param width How wide.
		@param height How tall.
		@param radius How round the corners are.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
		@param share How much of the height to fill, 0 to 1, for a meter.
	**/
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

	/**
		Draws one filled rounded corner, as a fan.

		@param cx The centre, across.
		@param cy The centre, down.
		@param r The corner radius.
		@param from The angle it starts at.
		@param to The angle it ends at.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		Draws a filled circle.

		@param cx The centre, across.
		@param cy The centre, down.
		@param radius How large.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		Draws part of a circle as a stroked line, which is what a knob sweep is.

		@param cx The centre, across.
		@param cy The centre, down.
		@param radius How large.
		@param from The angle it starts at.
		@param to The angle it ends at.
		@param weight How thick the line is.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		Draws a whole circle as a stroked line.

		@param cx The centre, across.
		@param cy The centre, down.
		@param radius How large.
		@param weight How thick the line is.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
	public inline function ring(cx:Float, cy:Float, radius:Float, weight:Float, colour:Colour,
			alpha:Float = 1):Void {
		arc(cx, cy, radius, 0, Math.PI * 2, weight, colour, alpha);
	}

	/**
		Draws a straight line.

		@param x0 Where it starts, across.
		@param y0 Where it starts, down.
		@param x1 Where it ends, across.
		@param y1 Where it ends, down.
		@param weight How thick.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
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

	static inline final JOIN = 0.35;

	/**
		Draws a run of joined lines.

		@param points The points, two floats each.
		@param count How many points.
		@param weight How thick.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		Fills a polygon, cutting it into triangles as it goes.

		@param points The points, two floats each, in order round the shape.
		@param count How many points.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		@param points The points of a polygon.
		@param a The first corner of a candidate triangle.
		@param b The second.
		@param c The third.
		@param left How many points are still in the polygon.
		@return Whether that triangle can be cut off without crossing the shape.
	**/
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

	/**
		Draws a cubic curve as a stroked line, with as many segments as its size needs.

		@param x0 Where it starts, across.
		@param y0 Where it starts, down.
		@param x1 First control point, across.
		@param y1 First control point, down.
		@param x2 Second control point, across.
		@param y2 Second control point, down.
		@param x3 Where it ends, across.
		@param y3 Where it ends, down.
		@param weight How thick.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		Draws a waveform, one column per pixel, reduced to the lowest and highest sample
		in each. A column narrower than one sample has no peak to peak and draws a flat
		line, correctly.

		@param samples The audio.
		@param from The first sample to draw.
		@param to One past the last.
		@param x Where it goes, across.
		@param y Where it goes, down.
		@param width How wide.
		@param height How tall.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
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

	/**
		Draws a line in the narrowest face it fits in: the one given where it fits,
		the condensed one where that would, and the short form where neither does.
		The painter is left drawing in the face it was given, whichever it used.

		@param font The face the rest of the row is drawn in.
		@param condensed A narrower face, or null where none was baked.
		@param said The line, spelt out.
		@param short What to draw where neither face fits it. An empty string draws
			the line in the narrowest face there is and lets it run on.
		@param x Where it starts, across.
		@param middle The middle of the row it sits on, down, because the baseline
			moves with the face it lands in.
		@param room How much room it has, across.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
	public function fitted(font:Font, condensed:Null<Font>, said:String, short:String,
			x:Float, middle:Float, room:Float, colour:Colour, alpha:Float = 1):Void {
		if (font.measure(said) <= room) {
			text(said, x, middle - font.height * 0.5 + font.ascent, colour, alpha);
			return;
		}

		if (condensed != null && (short == "" || condensed.measure(said) <= room)) {
			reface(condensed);
			text(said, x, middle - condensed.height * 0.5 + condensed.ascent, colour,
				alpha);
			reface(font);
			return;
		}

		text(short == "" ? said : short, x, middle - font.height * 0.5 + font.ascent,
			colour, alpha);
	}

	/**
		Draws text at a baseline.

		@param value The text.
		@param x Where it starts, across.
		@param y The baseline.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
		@return Where it ended, across.
	**/
	public function text(value:String, x:Float, y:Float, colour:Colour, alpha:Float = 1):Float {
		binds(font.texture);
		room(FLOATS * 6 * value.length);

		final r = colour.red * CHANNEL;
		final g = colour.green * CHANNEL;
		final b = colour.blue * CHANNEL;
		final a = alpha * opacity;

		var pen = x;
		var index = 0;

		while (index < value.length) {
			final code = Font.codeAt(value, index);
			index += Font.step(code);

			final slot = font.slotOf(code);
			if (slot == Font.NONE) continue;

			final left = at(pen + font.offsetX(slot));
			final top = down(y + font.offsetY(slot));
			final right = left + font.wide(slot) * scaleX;
			final bottom = top + font.tall(slot) * scaleY;

			final u0 = font.u0(slot);
			final v0 = font.v0(slot);
			final u1 = font.u1(slot);
			final v1 = font.v1(slot);

			push(left, top, r, g, b, a, u0, v0);
			push(right, top, r, g, b, a, u1, v0);
			push(right, bottom, r, g, b, a, u1, v1);

			push(left, top, r, g, b, a, u0, v0);
			push(right, bottom, r, g, b, a, u1, v1);
			push(left, bottom, r, g, b, a, u0, v1);

			pen += font.advance(slot);
		}

		return pen;
	}

	/**
		Draws text ending at a position.

		@param value The text.
		@param right Where it ends, across.
		@param y The baseline.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
	public inline function textRight(value:String, right:Float, y:Float, colour:Colour,
			alpha:Float = 1):Void {
		text(value, right - font.measure(value), y, colour, alpha);
	}

	/**
		Draws text centred on a position.

		@param value The text.
		@param centre Where its middle goes, across.
		@param y The baseline.
		@param colour The colour to draw it in.
		@param alpha How opaque, 0 to 1.
	**/
	public inline function textCentred(value:String, centre:Float, y:Float, colour:Colour,
			alpha:Float = 1):Void {
		text(value, centre - font.measure(value) * 0.5, y, colour, alpha);
	}

	/**
		@param value Some text.
		@return How wide it draws in the current face.
	**/
	public inline function measure(value:String):Float {
		return font.measure(value);
	}

	/**
		Limits drawing to a rectangle until the matching pop. Clips nest by taking the
		overlap rather than replacing.

		@param x Where it goes, across.
		@param y Where it goes, down.
		@param width How wide.
		@param height How tall.
	**/
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

	/**
		Takes the last clip back off.
	**/
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

	/**
		Moves and scales everything drawn until the matching pop.

		@param dx How far to move, across.
		@param dy How far to move, down.
		@param sx What to scale by, across.
		@param sy What to scale by, down.
	**/
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

	/**
		Takes the last transform back off.
	**/
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

	/**
		Empties the buffer and every stack, which a frame that faulted part way through
		needs before the next one.
	**/
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

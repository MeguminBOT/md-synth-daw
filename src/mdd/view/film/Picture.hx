package mdd.view.film;

import haxe.ds.Vector;
import mdd.host.Draw;
import mdd.host.Image;
import mdd.host.Texture;
import mdd.ui.Font;
import mdd.ui.Paint;
import mdd.view.monitor.Scope;

/**
	Draws a style: the ground, then every layer in order, the lanes, the pictures and the lines of
	text among them.

	It belongs to one renderer, because the pictures it reads and the faces it bakes belong to
	that renderer, and it keeps each picture it has read until `shut`, so a video reads every file
	once rather than once a frame. A file that will not read is remembered as missing and drawn as
	nothing, and a font that will not read is replaced by `face`.

	Lanes and text that are neither turned nor faded are drawn straight into the picture, so the
	plain style draws exactly what a video drew before styles. The rest are drawn into the corner
	of one texture kept for the purpose, which grows to the largest thing drawn there and never
	shrinks, and laid over the picture turned and faded as one, blended as colour already
	multiplied by alpha, which is what drawing into a target cleared to nothing leaves. Fading the
	whole rather than each stroke keeps a border's overlapping rings from building up. A frame
	makes no texture once the first has grown it.

	A layer with effects is drawn the same way with room around it, and its shape is taken from
	its alpha: every effect is made from that shape by laying it over itself, shifted, in blends
	that touch only alpha, and the shadow, the outside border, the layer, the inside border and the
	bevel are put together in a third texture before it is laid over the picture. Three more
	textures are kept for that, and a few smaller ones the shadow is softened through, all grown
	the same way and only once a layer with effects is drawn. The software renderer cannot blend
	that way, and there a layer is drawn without its effects.
**/
@:unreflective
final class Picture {
	/**
		The most pixels the texture turned things are drawn into grows to on either side. Anything
		larger is drawn into it smaller and scaled back up as it is laid down.
	**/
	public static inline final SCRATCH = 4096;

	/**
		How many baked faces are kept at once. A style with more text sizes than this bakes the
		oldest again when it comes round.
	**/
	static inline final FACES = 12;

	/**
		How many points around a circle a shape is laid at, on each pass that grows or shrinks it.
	**/
	static inline final RING = 12;

	/**
		The most passes a shape is grown or shrunk in. Each is twice the last, so this is far more
		than `Layer.WIDEST` at `SCRATCH` needs.
	**/
	static inline final PASSES = 16;

	/**
		The most times a shadow is halved on its way to being softened.
	**/
	static inline final LEVELS = 12;

	/**
		The most steps a bevel is shaded in.
	**/
	static inline final BANDS = 16;

	/**
		The face a line of text is written in where it names none, or where the one it names will
		not read.
	**/
	public var face:String = "";

	final paint:Paint;

	final sources:Array<Source> = [];
	final size:Vector<Int> = new Vector<Int>(2);
	final gathered:Array<Int> = [];

	final fonts:Array<Font> = [];
	final fontPaths:Array<String> = [];
	final fontPixels:Array<Int> = [];

	final scratch:Source = Source.of("");
	final shape:Source = Source.of("");
	final work:Source = Source.of("");
	final whole:Source = Source.of("");
	final levels:Array<Source> = [];
	final steps:Vector<Float> = new Vector<Float>(PASSES);

	var softWide:Float = 0;
	var softTall:Float = 0;

	/**
		Builds a picture that draws with a paint and reads pictures into its renderer.

		@param paint What to draw with.
	**/
	public function new(paint:Paint) {
		this.paint = paint;
	}

	/**
		Draws a style over the whole of the target being drawn into.

		@param style How it looks.
		@param scope The scope, dressed by the style and fed up to the moment drawn.
		@param parts Which parts the lanes show, in order.
		@param words What the placeholders in the text stand for.
		@param wide How wide the picture is, in pixels.
		@param tall How tall.
		@param into The target the picture is being drawn into, which turned things return to.
	**/
	public function draws(style:Style, scope:Scope, parts:Array<Int>, words:Words, wide:Int,
			tall:Int, into:cpp.Star<Texture>):Void {
		grounded(style, wide, tall);
		style.gathered(parts, gathered);

		for (layer in style.layers) {
			switch (layer.kind) {
				case Layer.LANES:
					if (gathered.length > 0) laned(layer, scope, gathered, -1, wide, tall, into);

				case Layer.LANE:
					if (parts.indexOf(layer.part) >= 0) laned(layer, scope, parts, layer.part, wide, tall, into);

				case Layer.TEXT: written(layer, words, wide, tall, into);
				case _: placed(layer, wide, tall, into);
			}
		}
	}

	/**
		Gives back every texture and face it read, baked or made.
	**/
	public function shut():Void {
		for (held in sources) if (held.texture != null) Draw.destroyTexture(held.texture);
		for (held in fonts) held.shut();

		sources.resize(0);
		fonts.resize(0);
		fontPaths.resize(0);
		fontPixels.resize(0);

		for (held in [scratch, shape, work, whole]) emptied(held);
		for (held in levels) emptied(held);

		levels.resize(0);
	}

	/**
		Forgets a picture read from a file, so the next frame reads it again.

		@param path The file.
	**/
	public function forgets(path:String):Void {
		for (index in 0...sources.length) {
			final held = sources[index];
			if (held.path != path) continue;

			if (held.texture != null) Draw.destroyTexture(held.texture);
			sources.splice(index, 1);

			return;
		}
	}

	/**
		@param path A picture's file.
		@return How wide and how tall it is, as width over height, or nought where it will not
			read.
	**/
	public function aspect(path:String):Float {
		final held = read(path);
		return held.texture == null || held.tall == 0 ? 0 : held.wide / held.tall;
	}

	/**
		How wide the last layer `bounds` measured is drawn, in pixels, before it is turned.
	**/
	public var boundWide(default, null):Float = 0;

	/**
		How tall, in pixels.
	**/
	public var boundTall(default, null):Float = 0;

	/**
		Measures the box a layer is drawn in, before it is turned, into `boundWide` and
		`boundTall`: its own size for the lanes and a picture, and the line with its border for
		text. A line that says nothing is measured as an empty line of its height, so it can still
		be found and grabbed. Effects reach outside the box and are not measured.

		@param layer The layer.
		@param words What text placeholders stand for.
		@param wide How wide the picture is, in pixels.
		@param tall How tall.
	**/
	public function bounds(layer:Layer, words:Words, wide:Int, tall:Int):Void {
		if (layer.kind != Layer.TEXT) {
			boundWide = layer.wide * wide;
			boundTall = layer.tall * tall;
			return;
		}

		final said = words.filled(layer.text);
		final pixels = pixelsOf(layer, tall);
		final font = fontOf(layer.font, pixels);
		final border = layer.borderWidth * pixels;

		boundWide = (font == null || said == "" ? pixels : font.measure(said)) + border * 2;
		boundTall = (font == null ? pixels : font.height) + border * 2;
	}

	/**
		Fills the picture with the ground's colour or gradient, and lays its picture over it,
		cropped to fill.
	**/
	function grounded(style:Style, wide:Int, tall:Int):Void {
		if (style.ground == Style.GRADIENT) {
			paint.slope(0, 0, wide, tall, style.groundColour, style.groundTo, style.groundTurn);
		} else {
			paint.rect(0, 0, wide, tall, style.groundColour);
		}

		if (style.groundImage == "" || style.groundAlpha <= 0) return;

		final held = read(style.groundImage);
		if (held.texture == null) return;

		final across = wide / held.wide;
		final down = tall / held.tall;
		final much = across > down ? across : down;

		paint.turned(held.texture, wide * 0.5, tall * 0.5, held.wide * much, held.tall * much, 0,
			style.groundAlpha);
	}

	/**
		Draws lanes into a layer's box, turned and faded where the layer is: the lanes laid out
		together, or one part's lane on its own.

		@param layer The layer.
		@param scope The scope that draws them.
		@param parts The parts laid out together, for the lanes.
		@param single The part a lane on its own shows, or -1 for the lanes laid out together.
		@param wide How wide the picture is, in pixels.
		@param tall How tall.
		@param into The target the picture is being drawn into.
	**/
	function laned(layer:Layer, scope:Scope, parts:Array<Int>, single:Int, wide:Int, tall:Int,
			into:cpp.Star<Texture>):Void {
		final boxWide = layer.wide * wide;
		final boxTall = layer.tall * tall;
		final centreX = layer.x * wide;
		final centreY = layer.y * tall;

		if (layer.alpha <= 0 || boxWide < 1 || boxTall < 1) return;

		final dressed = layer.dressed();

		if (layer.turn % 360 == 0 && layer.alpha >= 1 && !dressed) {
			scope.arrange(centreX - boxWide * 0.5, centreY - boxTall * 0.5, boxWide, boxTall);

			if (single < 0) scope.films(paint, parts);
			else scope.filmsLane(paint, single);

			return;
		}

		final pad = dressed ? padOf(layer, tall) : 0;
		final much = shrink(boxWide + pad * 2, boxTall + pad * 2);
		final spanWide = (boxWide + pad * 2) * much;
		final spanTall = (boxTall + pad * 2) * much;

		if (!opened(spanWide, spanTall)) return;

		scope.arrange(pad * much, pad * much, boxWide * much, boxTall * much);

		if (single < 0) scope.films(paint, parts);
		else scope.filmsLane(paint, single);

		laid(layer, spanWide, spanTall, much, tall, centreX, centreY, into);
	}

	/**
		Draws a line of text centred on its layer's centre, its border first and its fill over it,
		turned where the layer is.
	**/
	function written(layer:Layer, words:Words, wide:Int, tall:Int, into:cpp.Star<Texture>):Void {
		if (layer.alpha <= 0) return;

		final said = words.filled(layer.text);
		if (said == "") return;

		final pixels = pixelsOf(layer, tall);
		final font = fontOf(layer.font, pixels);
		if (font == null) return;

		final border = layer.borderWidth * pixels;
		final lineWide = font.measure(said) + border * 2;
		final lineTall = font.height + border * 2;
		final centreX = layer.x * wide;
		final centreY = layer.y * tall;
		final dressed = layer.dressed();

		if (layer.turn % 360 == 0 && layer.alpha >= 1 && !dressed) {
			lettered(font, said, layer, border, centreX - lineWide * 0.5, centreY - lineTall * 0.5);
			return;
		}

		final pad = dressed ? padOf(layer, tall) : 0;
		final spanWide = lineWide + pad * 2;
		final spanTall = lineTall + pad * 2;

		if (spanWide > SCRATCH || spanTall > SCRATCH) return;
		if (!opened(spanWide, spanTall)) return;

		lettered(font, said, layer, border, pad, pad);
		laid(layer, spanWide, spanTall, 1, tall, centreX, centreY, into);
	}

	/**
		Writes a line with its top left corner at a place: the border as the line drawn at every
		point of a ring around where it sits, a ring for every pixel out to the border's width,
		then the fill over it.

		@param font The face.
		@param said What it says.
		@param layer The line's colours.
		@param border How thick the border is, in pixels.
		@param left Where the line's box starts, across, border included.
		@param top Where it starts, down.
	**/
	function lettered(font:Font, said:String, layer:Layer, border:Float, left:Float,
			top:Float):Void {
		final baseline = top + border + font.ascent;
		final start = left + border;

		paint.reface(font);

		if (border > 0) {
			final rings = Math.ceil(border);

			for (ring in 1...rings + 1) {
				final reach = ring == rings ? border : ring;
				final points = ring * 8 < 64 ? ring * 8 : 64;

				for (point in 0...points) {
					final angle = 2 * Math.PI * point / points;
					paint.text(said, start + Math.cos(angle) * reach, baseline + Math.sin(angle) * reach,
						layer.border);
				}
			}
		}

		paint.text(said, start, baseline, layer.colour);
	}

	/**
		Draws a picture layer, stretched to its box and turned about its centre.
	**/
	function placed(layer:Layer, wide:Int, tall:Int, into:cpp.Star<Texture>):Void {
		if (layer.kind != Layer.IMAGE || layer.path == "" || layer.alpha <= 0) return;

		final held = read(layer.path);
		if (held.texture == null) return;

		final boxWide = layer.wide * wide;
		final boxTall = layer.tall * tall;

		if (!layer.dressed()) {
			paint.turned(held.texture, layer.x * wide, layer.y * tall, boxWide, boxTall, layer.turn,
				layer.alpha);
			return;
		}

		if (boxWide < 1 || boxTall < 1) return;

		final pad = padOf(layer, tall);
		final much = shrink(boxWide + pad * 2, boxTall + pad * 2);
		final spanWide = (boxWide + pad * 2) * much;
		final spanTall = (boxTall + pad * 2) * much;

		if (!opened(spanWide, spanTall)) return;

		paint.turned(held.texture, spanWide * 0.5, spanTall * 0.5, boxWide * much, boxTall * much, 0, 1);
		laid(layer, spanWide, spanTall, much, tall, layer.x * wide, layer.y * tall, into);
	}

	/**
		Makes the scratch texture at least a size, draws into it from here and clears it to
		nothing.

		@param spanWide How wide what is about to be drawn is.
		@param spanTall How tall.
		@return Whether there is one to draw into.
	**/
	function opened(spanWide:Float, spanTall:Float):Bool {
		if (!grown(scratch, Math.ceil(spanWide), Math.ceil(spanTall), true)) return false;

		paint.target(scratch.texture);
		paint.clear(0, 0, 0, 0);

		return true;
	}

	/**
		Lays what was drawn into the scratch texture over the picture, turned and faded as its
		layer is, with the layer's effects around it.

		@param layer The layer.
		@param spanWide How much of the scratch texture was drawn into, across, the room for
			effects included.
		@param spanTall How much, down.
		@param much What it was drawn at, against the picture's own pixels.
		@param tall How tall the picture is, which effects are measured against.
		@param centreX Where the layer's centre is, across the picture.
		@param centreY Where it is, down.
		@param into The target the picture is being drawn into.
	**/
	function laid(layer:Layer, spanWide:Float, spanTall:Float, much:Float, tall:Int, centreX:Float,
			centreY:Float, into:cpp.Star<Texture>):Void {
		final layWide = spanWide / much;
		final layTall = spanTall / much;

		if (layer.dressed() && dressedIn(layer, spanWide, spanTall, tall * much)) {
			paint.target(into);
			paint.turnedPart(whole.texture, spanWide, spanTall, centreX, centreY, layWide, layTall,
				layer.turn, layer.alpha);
			return;
		}

		paint.target(into);
		Draw.premultiplied(scratch.texture, 1);
		paint.turnedPart(scratch.texture, spanWide, spanTall, centreX, centreY, layWide, layTall,
			layer.turn, layer.alpha);
	}

	/**
		Puts a layer and its effects together in `whole`, from what was drawn into the scratch
		texture: the shadow, the outside border, the layer, the inside border, and the bevel's
		light and shade, in that order.

		@param layer The layer.
		@param spanWide How much of the scratch texture was drawn into, across.
		@param spanTall How much, down.
		@param unit How many pixels of the scratch texture the picture's height is, which every
			effect is a fraction of.
		@return Whether it was put together. Where it was not, the scratch texture still holds the
			layer as drawn.
	**/
	function dressedIn(layer:Layer, spanWide:Float, spanTall:Float, unit:Float):Bool {
		final needWide = Math.ceil(spanWide);
		final needTall = Math.ceil(spanTall);

		if (!grown(shape, needWide, needTall, false) || !grown(work, needWide, needTall, false)
				|| !grown(whole, needWide, needTall, true)) {
			return false;
		}

		paint.target(shape.texture);
		paint.clear(1, 1, 1, 0);

		if (!paint.shaped(scratch.texture, spanWide, spanTall, 0, 0, spanWide, spanTall, 1, Paint.SHAPE_OVER)) {
			return false;
		}

		final outsideReach = layer.kind == Layer.TEXT ? 0 : layer.outsideWidth * unit;
		final outside = outsideReach > 0 ? spread(outsideReach, spanWide, spanTall, whole, Paint.SHAPE_OVER) : null;
		final softened = layer.shadowAlpha > 0 ? softenedBy(layer.shadowSoftness * unit, spanWide, spanTall) : null;

		final middleX = spanWide * 0.5;
		final middleY = spanTall * 0.5;
		final fall = (layer.shadowAngle - layer.turn) * Math.PI / 180;
		final alongX = Math.cos(fall);
		final alongY = Math.sin(fall);

		paint.target(whole.texture);
		paint.clear(0, 0, 0, 0);

		if (softened != null) {
			final distance = layer.shadowDistance * unit;

			paint.tintedPart(softened.texture, softWide, softTall, middleX + alongX * distance,
				middleY + alongY * distance, spanWide, spanTall, 0, layer.shadowAlpha, layer.shadow);
		}

		if (outside != null) {
			paint.tintedPart(outside.texture, spanWide, spanTall, middleX, middleY, spanWide, spanTall, 0,
				1, layer.outside);
		}

		Draw.premultiplied(scratch.texture, 1);
		paint.turnedPart(scratch.texture, spanWide, spanTall, middleX, middleY, spanWide, spanTall, 0, 1);

		final insideReach = layer.insideWidth * unit;

		if (insideReach > 0) {
			final edge = spread(insideReach, spanWide, spanTall, scratch, Paint.SHAPE_WITHIN);

			paint.target(edge.texture);
			paint.shaped(shape.texture, spanWide, spanTall, 0, 0, spanWide, spanTall, 1, Paint.SHAPE_OUTSIDE);
			paint.target(whole.texture);
			paint.tintedPart(edge.texture, spanWide, spanTall, middleX, middleY, spanWide, spanTall, 0, 1,
				layer.inside);
		}

		final bevelReach = layer.bevel * unit;

		if (bevelReach > 0 && layer.bevelDepth > 0) {
			lit(bevelReach, alongX, alongY, spanWide, spanTall, 0xFFFFFF, layer.bevelDepth);
			lit(bevelReach, -alongX, -alongY, spanWide, spanTall, 0x000000, layer.bevelDepth);
		}

		return true;
	}

	/**
		Grows or shrinks `shape` by a distance, into `work`: laid over itself at every point of a
		ring, once for each pass, each pass twice as far as the last, so a wide border costs a few
		passes rather than a ring for every pixel. Grown, it is the shape with a border around it;
		shrunk, it is what is left of the shape once its edge is taken away.

		@param reach How far, in pixels of the scratch texture.
		@param spanWide How much of each texture is in use, across.
		@param spanTall How much, down.
		@param other The texture every other pass is drawn into, which is left holding nothing
			anybody reads.
		@param mode `Paint.SHAPE_OVER` to grow it, `Paint.SHAPE_WITHIN` to shrink it.
		@return `work`, holding the result, white with the shape as its alpha.
	**/
	function spread(reach:Float, spanWide:Float, spanTall:Float, other:Source, mode:Int):Source {
		final count = stepped(reach);
		var from = shape;

		for (pass in 0...count) {
			final to = (count - pass) % 2 == 1 ? work : other;
			final radius = steps[pass];

			paint.target(to.texture);
			paint.clear(1, 1, 1, 0);
			paint.shaped(from.texture, spanWide, spanTall, 0, 0, spanWide, spanTall, 1, Paint.SHAPE_OVER);

			for (point in 0...RING) {
				final angle = (point + (pass & 1) * 0.5) * Math.PI * 2 / RING;
				paint.shaped(from.texture, spanWide, spanTall, Math.cos(angle) * radius,
					Math.sin(angle) * radius, spanWide, spanTall, 1, mode);
			}

			from = to;
		}

		return from;
	}

	/**
		Splits a distance into the passes `spread` takes: one pixel, then two, four and so on, the
		last taking whatever is left.

		@param reach The distance, in pixels.
		@return How many passes, written into `steps`.
	**/
	function stepped(reach:Float):Int {
		var count = 0;
		var left = reach;
		var step = 1.0;

		while (left > 0 && count < PASSES) {
			final taken = left < step || count == PASSES - 1 ? left : step;

			steps[count] = taken;
			count++;
			left -= taken;
			step *= 2;
		}

		return count;
	}

	/**
		Softens `shape` for a shadow by halving it until it is as many times smaller as the
		softening is pixels wide, the last step less than a half where that is what is left. Drawn
		back up to its size it is blurred by about that much. The part of the texture it answers
		that holds it is written into `softWide` and `softTall`.

		@param softness How far to soften it, in pixels of the scratch texture.
		@param spanWide How much of `shape` is in use, across.
		@param spanTall How much, down.
		@return The texture it was softened into, or `shape` itself for less than a pixel.
	**/
	function softenedBy(softness:Float, spanWide:Float, spanTall:Float):Source {
		var from = shape;
		var scale = 1.0;
		var index = 0;

		softWide = spanWide;
		softTall = spanTall;

		while (softness - scale > 0.01 && index < LEVELS) {
			final step = softness / scale >= 2 ? 2 : softness / scale;
			final nextWide = softWide / step;
			final nextTall = softTall / step;

			if (nextWide < 1 || nextTall < 1) break;

			while (levels.length <= index) levels.push(Source.of(""));

			final level = levels[index];
			if (!grown(level, Math.ceil(nextWide) + 1, Math.ceil(nextTall) + 1, false)) break;

			paint.target(level.texture);
			paint.clear(1, 1, 1, 0);
			paint.shaped(from.texture, softWide, softTall, 0, 0, nextWide, nextTall, 1, Paint.SHAPE_OVER);

			from = level;
			softWide = nextWide;
			softTall = nextTall;
			scale *= step;
			index++;
		}

		return from;
	}

	/**
		Lays one side of a bevel over `whole`: the part of the shape within a distance of its edge
		on one side, most strongly nearest the edge, in one colour.

		@param reach How wide the bevel is, in pixels of the scratch texture.
		@param towardX Which way the side it lights faces away from, across.
		@param towardY Which way, down.
		@param spanWide How much of each texture is in use, across.
		@param spanTall How much, down.
		@param colour What it is lit in, as `0xRRGGBB`.
		@param depth How opaque, 0 to 1.
	**/
	function lit(reach:Float, towardX:Float, towardY:Float, spanWide:Float, spanTall:Float,
			colour:Int, depth:Float):Void {
		final wanted = Math.ceil(reach / 1.5);
		final bands = wanted < 1 ? 1 : (wanted > BANDS ? BANDS : wanted);
		final weight = 1 / bands + 1 / 510;

		paint.target(work.texture);
		paint.clear(1, 1, 1, 0);

		for (band in 1...bands + 1) {
			final shift = reach * band / bands;
			paint.shaped(shape.texture, spanWide, spanTall, towardX * shift, towardY * shift, spanWide,
				spanTall, weight, Paint.SHAPE_ADD);
		}

		paint.shaped(shape.texture, spanWide, spanTall, 0, 0, spanWide, spanTall, 1, Paint.SHAPE_OUTSIDE);
		paint.target(whole.texture);
		paint.tintedPart(work.texture, spanWide, spanTall, spanWide * 0.5, spanTall * 0.5, spanWide,
			spanTall, 0, depth, colour);
	}

	/**
		@return How many pixels tall a line of text is drawn at, never less than four.
	**/
	static inline function pixelsOf(layer:Layer, tall:Int):Int {
		final held = Math.round(layer.tall * tall);
		return held < 4 ? 4 : held;
	}

	/**
		@param layer A layer with effects.
		@param tall How tall the picture is.
		@return How much room its effects need around what it draws, in whole pixels of the
			picture: out to its outside border and its softened shadow, and at least as far as its
			inside border and bevel reach in, which find the edge by looking past it.
	**/
	static function padOf(layer:Layer, tall:Int):Int {
		var reach = layer.insideWidth > layer.bevel ? layer.insideWidth : layer.bevel;

		if (layer.kind != Layer.TEXT && layer.outsideWidth > reach) reach = layer.outsideWidth;

		if (layer.shadowAlpha > 0) {
			final thrown = layer.shadowDistance + layer.shadowSoftness * 2;
			if (thrown > reach) reach = thrown;
		}

		return Math.ceil(reach * tall) + 2;
	}

	/**
		@param wide How wide something turned is.
		@param tall How tall.
		@return What to scale it by so it fits in `SCRATCH` on both sides, one where it already
			does.
	**/
	static inline function shrink(wide:Float, tall:Float):Float {
		final across = wide > SCRATCH ? SCRATCH / wide : 1;
		final down = tall > SCRATCH ? SCRATCH / tall : 1;
		return across < down ? across : down;
	}

	/**
		Makes sure a texture kept for drawing into is at least a size, making it again larger
		where it has to grow and never smaller.

		@param held The texture and the size it was made at.
		@param needWide How wide it has to be.
		@param needTall How tall.
		@param premultiplied Whether what is drawn into it is laid down as colour already
			multiplied by alpha, rather than as a shape.
		@return Whether there is one.
	**/
	function grown(held:Source, needWide:Int, needTall:Int, premultiplied:Bool):Bool {
		if (held.texture != null && held.wide >= needWide && held.tall >= needTall) return true;

		final makeWide = needWide > held.wide ? needWide : held.wide;
		final makeTall = needTall > held.tall ? needTall : held.tall;

		if (held.texture != null) Draw.destroyTexture(held.texture);

		held.texture = Draw.createTarget(paint.canvas(), makeWide, makeTall);
		held.wide = held.texture == null ? 0 : makeWide;
		held.tall = held.texture == null ? 0 : makeTall;

		if (held.texture != null && premultiplied) Draw.premultiplied(held.texture, 1);

		return held.texture != null;
	}

	/**
		Gives back a texture kept for drawing into.
	**/
	static function emptied(held:Source):Void {
		if (held.texture != null) Draw.destroyTexture(held.texture);

		held.texture = null;
		held.wide = 0;
		held.tall = 0;
	}

	/**
		@param path A picture's file.
		@return What was read from it, reading it the first time it is asked for. Its texture is
			null where the file will not read.
	**/
	function read(path:String):Source {
		for (held in sources) if (held.path == path) return held;

		final out = Source.of(path);

		out.texture = Image.load(paint.canvas(), path, cpp.Pointer.arrayElem(size.toData(), 0).raw);
		out.wide = size[0];
		out.tall = size[1];

		sources.push(out);
		return out;
	}

	/**
		@param path A font file, or an empty string for `face`.
		@param pixels How tall it is drawn.
		@return The face baked at that size, baking it the first time and falling back to `face`
			where the file will not read, or null where neither will.
	**/
	function fontOf(path:String, pixels:Int):Null<Font> {
		final wanted = path == "" ? face : path;

		for (index in 0...fonts.length) {
			if (fontPaths[index] == wanted && fontPixels[index] == pixels) return fonts[index];
		}

		var made = wanted == "" ? null : Font.bake(paint.canvas(), wanted, pixels);
		if (made == null && wanted != face && face != "") made = Font.bake(paint.canvas(), face, pixels);
		if (made == null) return null;

		if (fonts.length >= FACES) {
			paint.flush();
			fonts[0].shut();
			fonts.shift();
			fontPaths.shift();
			fontPixels.shift();
		}

		fonts.push(made);
		fontPaths.push(wanted);
		fontPixels.push(pixels);

		return made;
	}
}

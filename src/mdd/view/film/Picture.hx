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
		The face a line of text is written in where it names none, or where the one it names will
		not read.
	**/
	public var face:String = "";

	final paint:Paint;

	final sources:Array<Source> = [];
	final size:Vector<Int> = new Vector<Int>(2);

	final fonts:Array<Font> = [];
	final fontPaths:Array<String> = [];
	final fontPixels:Array<Int> = [];

	var scratch:cpp.Star<Texture> = null;
	var scratchWide:Int = 0;
	var scratchTall:Int = 0;

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

		for (layer in style.layers) {
			switch (layer.kind) {
				case Layer.LANES: laned(layer, scope, parts, wide, tall, into);
				case Layer.TEXT: written(layer, words, wide, tall, into);
				case _: placed(layer, wide, tall);
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

		if (scratch != null) Draw.destroyTexture(scratch);

		scratch = null;
		scratchWide = 0;
		scratchTall = 0;
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
		be found and grabbed.

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
		Draws the lanes into their box, turned where the layer is.
	**/
	function laned(layer:Layer, scope:Scope, parts:Array<Int>, wide:Int, tall:Int,
			into:cpp.Star<Texture>):Void {
		final boxWide = layer.wide * wide;
		final boxTall = layer.tall * tall;
		final centreX = layer.x * wide;
		final centreY = layer.y * tall;

		if (layer.alpha <= 0 || boxWide < 1 || boxTall < 1) return;

		if (layer.turn % 360 == 0 && layer.alpha >= 1) {
			scope.arrange(centreX - boxWide * 0.5, centreY - boxTall * 0.5, boxWide, boxTall);
			scope.films(paint, parts);

			return;
		}

		final much = shrink(boxWide, boxTall);
		final drawnWide = boxWide * much;
		final drawnTall = boxTall * much;

		if (!grown(Math.ceil(drawnWide), Math.ceil(drawnTall))) return;

		paint.target(scratch);
		paint.clear(0, 0, 0, 0);

		scope.arrange(0, 0, drawnWide, drawnTall);
		scope.films(paint, parts);

		paint.target(into);
		paint.turnedPart(scratch, drawnWide, drawnTall, centreX, centreY, boxWide, boxTall,
			layer.turn, layer.alpha);
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

		if (layer.turn % 360 == 0 && layer.alpha >= 1) {
			lettered(font, said, layer, border, centreX - lineWide * 0.5, centreY - lineTall * 0.5);
			return;
		}

		if (lineWide > SCRATCH || lineTall > SCRATCH) return;
		if (!grown(Math.ceil(lineWide), Math.ceil(lineTall))) return;

		paint.target(scratch);
		paint.clear(0, 0, 0, 0);

		lettered(font, said, layer, border, 0, 0);

		paint.target(into);
		paint.turnedPart(scratch, lineWide, lineTall, centreX, centreY, lineWide, lineTall, layer.turn,
			layer.alpha);
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
		@return How many pixels tall a line of text is drawn at, never less than four.
	**/
	static inline function pixelsOf(layer:Layer, tall:Int):Int {
		final held = Math.round(layer.tall * tall);
		return held < 4 ? 4 : held;
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
		Makes sure the texture turned things are drawn into is at least a size, making it again
		larger where it has to grow and never smaller.

		@param needWide How wide it has to be.
		@param needTall How tall.
		@return Whether there is one.
	**/
	function grown(needWide:Int, needTall:Int):Bool {
		if (scratch != null && scratchWide >= needWide && scratchTall >= needTall) return true;

		final makeWide = needWide > scratchWide ? needWide : scratchWide;
		final makeTall = needTall > scratchTall ? needTall : scratchTall;

		if (scratch != null) Draw.destroyTexture(scratch);

		scratch = Draw.createTarget(paint.canvas(), makeWide, makeTall);
		scratchWide = scratch == null ? 0 : makeWide;
		scratchTall = scratch == null ? 0 : makeTall;

		if (scratch != null) Draw.premultiplied(scratch, 1);

		return scratch != null;
	}

	/**
		Draws a picture layer, stretched to its box and turned about its centre.
	**/
	function placed(layer:Layer, wide:Int, tall:Int):Void {
		if (layer.kind != Layer.IMAGE || layer.path == "" || layer.alpha <= 0) return;

		final held = read(layer.path);
		if (held.texture == null) return;

		paint.turned(held.texture, layer.x * wide, layer.y * tall, layer.wide * wide,
			layer.tall * tall, layer.turn, layer.alpha);
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

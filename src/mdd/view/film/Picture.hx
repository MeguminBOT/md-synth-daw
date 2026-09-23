package mdd.view.film;

import haxe.ds.Vector;
import mdd.host.Draw;
import mdd.host.Image;
import mdd.host.Texture;
import mdd.ui.Paint;
import mdd.view.monitor.Scope;

/**
	Draws a style: the ground, then every layer in order, the lanes among them.

	It belongs to one renderer, because the pictures it reads are textures of that renderer, and
	it keeps each picture it has read until `shut`, so a video reads every file once rather than
	once a frame. A file that will not read is remembered as missing and drawn as nothing.

	Lanes that are not turned are laid out straight into their box, so the plain style draws
	exactly what a video drew before styles. Turned lanes are drawn into a texture of their own
	and laid over the picture turned, blended as colour already multiplied by alpha, which is what
	drawing into a target cleared to nothing leaves.
**/
@:unreflective
final class Picture {
	final paint:Paint;

	final sources:Array<Source> = [];
	final size:Vector<Int> = new Vector<Int>(2);

	var lanesTexture:cpp.Star<Texture> = null;
	var lanesWide:Int = 0;
	var lanesTall:Int = 0;

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
		@param wide How wide the picture is, in pixels.
		@param tall How tall.
		@param into The target the picture is being drawn into, which turned lanes return to.
	**/
	public function draws(style:Style, scope:Scope, parts:Array<Int>, wide:Int, tall:Int,
			into:cpp.Star<Texture>):Void {
		grounded(style, wide, tall);

		for (layer in style.layers) {
			if (layer.kind == Layer.LANES) laned(layer, scope, parts, wide, tall, into);
			else placed(layer, wide, tall);
		}
	}

	/**
		Gives back every texture it read or made.
	**/
	public function shut():Void {
		for (held in sources) if (held.texture != null) Draw.destroyTexture(held.texture);

		sources.resize(0);

		if (lanesTexture != null) Draw.destroyTexture(lanesTexture);

		lanesTexture = null;
		lanesWide = 0;
		lanesTall = 0;
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

		if (layer.turn % 360 == 0) {
			scope.arrange(centreX - boxWide * 0.5, centreY - boxTall * 0.5, boxWide, boxTall);

			paint.pushOpacity(layer.alpha);
			scope.films(paint, parts);
			paint.popOpacity();

			return;
		}

		final needWide = Math.ceil(boxWide);
		final needTall = Math.ceil(boxTall);

		if (!sized(needWide, needTall)) return;

		paint.target(lanesTexture);
		paint.clear(0, 0, 0, 0);

		scope.arrange(0, 0, boxWide, boxTall);
		scope.films(paint, parts);

		paint.target(into);
		paint.turned(lanesTexture, centreX, centreY, lanesWide, lanesTall, layer.turn, layer.alpha);
	}

	/**
		Makes sure the texture turned lanes are drawn into is a size, making it again only where
		the size changed.

		@param needWide How wide it has to be.
		@param needTall How tall.
		@return Whether there is one.
	**/
	function sized(needWide:Int, needTall:Int):Bool {
		if (lanesTexture != null && lanesWide == needWide && lanesTall == needTall) return true;

		if (lanesTexture != null) Draw.destroyTexture(lanesTexture);

		lanesTexture = Draw.createTarget(paint.canvas(), needWide, needTall);
		lanesWide = lanesTexture == null ? 0 : needWide;
		lanesTall = lanesTexture == null ? 0 : needTall;

		if (lanesTexture != null) Draw.premultiplied(lanesTexture, 1);

		return lanesTexture != null;
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
}

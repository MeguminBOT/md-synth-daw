package mdd.ui;

import mdd.host.Draw;
import mdd.host.Texture;

@:unreflective

/**
	A widget that draws itself into a texture and blits that texture on later frames.

	It is what makes a panel of a thousand rows cost one draw call a frame instead of a
	thousand, and it redraws only when something in it says it changed.
**/
class Sheet extends Widget {
	/**
		How many times the contents have actually been drawn.
	**/
	public var baked(default, null):Int = 0;

	/**
		How many frames the texture has been blitted on.
	**/
	public var blitted(default, null):Int = 0;

	var cache:cpp.Star<Texture> = null;
	var cacheWide:Int = 0;
	var cacheTall:Int = 0;
	var fresh:Bool = false;

	/**
		Builds an empty sheet with no texture yet.
	**/
	public function new() {
		super();
		opaque = true;
	}

	/**
		Marks the contents stale, so the next frame draws them again rather than blitting
		what was there.
	**/
	override public function invalidate():Void {
		fresh = false;
		super.invalidate();
	}

	/**
		Gives the texture back.
	**/
	public function shut():Void {
		if (cache != null) Draw.destroyTexture(cache);
		cache = null;
		fresh = false;
	}

	/**
		Draws the contents. Override this rather than `paint`.

		@param paint What to draw with.
	**/
	function draw(paint:Paint):Void {
		for (child in children) {
			if (child.visible) child.paint(paint);
		}
	}

	/**
		Draws the contents into the texture where they are stale, then blits it.

		@param paint What to draw with.
	**/
	override function paint(paint:Paint):Void {
		final wide = Std.int(width);
		final tall = Std.int(height);

		if (wide <= 0 || tall <= 0) return;

		if (cache == null || cacheWide != wide || cacheTall != tall) {
			if (cache != null) Draw.destroyTexture(cache);
			cache = paint.sheet(wide, tall);
			cacheWide = wide;
			cacheTall = tall;
			fresh = false;
		}

		if (cache == null) {
			draw(paint);
			return;
		}

		if (!fresh) {
			paint.target(cache);
			paint.clear(0, 0, 0, 0);
			paint.pushTransform(-x, -y);
			draw(paint);
			paint.popTransform();
			paint.target(null);
			fresh = true;
			baked++;
		}

		paint.blit(cache, x, y, width, height);
		blitted++;
	}
}

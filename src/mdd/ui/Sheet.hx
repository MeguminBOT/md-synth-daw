package mdd.ui;

import mdd.host.Draw;
import mdd.host.Texture;

@:unreflective
class Sheet extends Widget {
	public var baked(default, null):Int = 0;
	public var blitted(default, null):Int = 0;

	var cache:cpp.Star<Texture> = null;
	var cacheWide:Int = 0;
	var cacheTall:Int = 0;
	var fresh:Bool = false;

	public function new() {
		super();
		opaque = true;
	}

	override public function invalidate():Void {
		fresh = false;
		super.invalidate();
	}

	public function shut():Void {
		if (cache != null) Draw.destroyTexture(cache);
		cache = null;
		fresh = false;
	}

	function draw(paint:Paint):Void {
		for (child in children) {
			if (child.visible) child.paint(paint);
		}
	}

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

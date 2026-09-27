package mdd.ui;

import mdd.host.Draw;
import mdd.host.Texture;

@:unreflective

/**
	The texture a widget keeps its drawing in, so a frame where nothing it draws has changed costs
	one textured rectangle rather than every shape again. What changes on its own from frame to
	frame, a playhead or a meter, is drawn over it by the widget's `over` and is never kept.

	The texture is made in steps of `ROOM` and never smaller than it was, because a panel being
	dragged to a new size would otherwise make one for every size it passed through, and
	Direct3D 11 keeps what it is given back. It is given back at the end of any frame its widget
	was not drawn in, so a hidden tab holds no memory.
**/
final class Cache {
	/**
		The steps a texture is made in.
	**/
	public static inline final ROOM = 256;

	/**
		How many times the widget has been drawn into the texture, which a check reads to show
		that a frame where nothing it draws changed drew none of it again.
	**/
	public var baked(default, null):Int = 0;

	/**
		The frame the widget was last drawn in, as `Root.painted` counts them.
	**/
	public var shown(default, null):Int = -1;

	var texture:cpp.Star<Texture> = null;
	var textureWide:Int = 0;
	var textureTall:Int = 0;
	var drawnWide:Int = 0;
	var drawnTall:Int = 0;
	var fresh:Bool = false;
	var face:Null<Font> = null;
	var owner:Null<Root> = null;

	/**
		Builds a cache with no texture yet.
	**/
	public function new() {}

	/**
		Says what the widget draws has changed, so the next frame draws it into the texture again.
	**/
	public inline function stale():Void {
		fresh = false;
	}

	/**
		@return Whether a texture is held.
	**/
	public inline function holds():Bool {
		return texture != null;
	}

	/**
		Gives the texture back, and forgets the root it was counted under.
	**/
	public function shut():Void {
		if (texture != null) Draw.destroyTexture(texture);
		texture = null;
		textureWide = 0;
		textureTall = 0;
		fresh = false;
		face = null;
		owner = null;
	}

	/**
		Lays down what a widget keeps, drawing it into the texture first where `bakes` has not.
		A widget drawn from its texture leaves the face in force as drawing it would have, since
		what is drawn after it may rely on that.

		@param widget The widget.
		@param paint What the window is drawn with.
		@return False where there is no texture to keep it in, or the root has keeping turned off,
			and the widget has to be drawn directly.
	**/
	public function draws(widget:Widget, paint:Paint):Bool {
		final wide = Std.int(widget.width);
		final tall = Std.int(widget.height);

		if (wide <= 0 || tall <= 0) return true;

		final root = widget.root();
		if (root == null || !root.caching || !bakes(widget, paint)) return false;

		shown = root.painted;

		if (face != null) paint.reface(face);
		paint.kept(texture, widget.x, widget.y, wide, tall);
		return true;
	}

	/**
		Draws a widget into the texture where it is stale or changed size, making the texture
		first where there is none or it is too small. `Root.prepares` calls this for every widget
		shown before the window is drawn into at all, so a frame turns to its textures and back
		once rather than part way through, which a backend recording render passes pays for and
		a tiled one pays more for.

		@param widget The widget.
		@param paint What the window is drawn with.
		@return False where there is no texture to keep it in.
	**/
	public function bakes(widget:Widget, paint:Paint):Bool {
		final wide = Std.int(widget.width);
		final tall = Std.int(widget.height);

		final root = widget.root();
		if (wide <= 0 || tall <= 0 || root == null) return false;

		if (texture == null || textureWide < wide || textureTall < tall) {
			final makeWide = roomy(wide > textureWide ? wide : textureWide);
			final makeTall = roomy(tall > textureTall ? tall : textureTall);

			if (texture != null) Draw.destroyTexture(texture);

			texture = paint.keeps(makeWide, makeTall);
			textureWide = texture == null ? 0 : makeWide;
			textureTall = texture == null ? 0 : makeTall;
			fresh = false;

			if (texture == null) return false;
		}

		if (owner != root) {
			owner = root;
			root.keeps(this);
		}

		if (fresh && drawnWide == wide && drawnTall == tall) return true;

		final was = Draw.getTarget(paint.canvas());
		if (!paint.diverts(texture, widget.x, widget.y, wide, tall)) return false;

		fresh = true;
		widget.paint(paint);
		paint.restores(was);

		face = paint.font;
		drawnWide = wide;
		drawnTall = tall;
		baked++;
		return true;
	}

	/**
		@param size A size, in pixels.
		@return It rounded up to the next whole `ROOM`.
	**/
	static inline function roomy(size:Int):Int {
		return Std.int((size + ROOM - 1) / ROOM) * ROOM;
	}
}

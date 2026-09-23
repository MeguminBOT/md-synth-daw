package mdd.view.film;

import haxe.ds.Vector;
import mdd.app.Locale;
import mdd.host.Draw;
import mdd.host.Texture;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Widget;

/**
	The picture a style draws, at the shape the video will have, with the chosen layer's handles
	over it: drag inside a layer to move it, a corner to size it, and the knob above it to turn it.

	It draws the style the way the video will, from the song as it plays, into a texture the size
	of its own box, in sizes made for that height, so what is seen here is the video made smaller
	rather than a sketch of it. Nothing here renders the song: the scope it draws is fed by
	playback.

	A picture keeps its shape as it is sized unless Shift is held, and the lanes are sized freely
	unless it is. A move comes to rest on the picture's middle lines when it passes near them, and
	a turn on a quarter; with Shift held a turn steps by fifteen degrees.
**/
@:unreflective
final class Preview extends Widget {
	static inline final NONE = 0;
	static inline final MOVE = 1;
	static inline final SIZE = 2;
	static inline final TURN = 3;

	/**
		How close to the picture's middle, in the preview's pixels, a move comes to rest on it.
	**/
	static inline final SNAP = 6.0;

	/**
		How close to a quarter, in degrees, a turn comes to rest on it.
	**/
	static inline final SQUARE = 3.0;

	final studio:Studio;

	var picture:Null<Picture> = null;
	var texture:cpp.Star<Texture> = null;
	var textureWide:Int = 0;
	var textureTall:Int = 0;

	var sizes:Null<Metrics> = null;
	var sizesFor:Int = 0;
	var words:Words = Words.none();

	var dragging:Int = NONE;
	var fromX:Float = 0;
	var fromY:Float = 0;
	var startX:Float = 0;
	var startY:Float = 0;
	var startWide:Float = 0;
	var startTall:Float = 0;
	var startHalfWide:Float = 0;
	var startHalfTall:Float = 0;
	var snappedX:Bool = false;
	var snappedY:Bool = false;

	var atX:Float = 0;
	var atY:Float = 0;
	final corners:Vector<Float> = new Vector<Float>(8);
	final cell:Vector<Float> = new Vector<Float>(4);

	/**
		Where the picture sits in the preview, across, in the window's pixels.
	**/
	public var pictureLeft(default, null):Float = 0;

	/**
		Where it sits, down.
	**/
	public var pictureTop(default, null):Float = 0;

	/**
		How wide it is drawn.
	**/
	public var pictureWide(default, null):Int = 0;

	/**
		How tall.
	**/
	public var pictureTall(default, null):Int = 0;

	/**
		Builds the preview of a studio's style.

		@param studio The studio it belongs to.
	**/
	public function new(studio:Studio) {
		super();
		this.studio = studio;
		focusable = true;
		opaque = true;
	}

	/**
		Gives back the texture, the pictures and the faces it drew with.
	**/
	public function shut():Void {
		final held = picture;
		if (held != null) held.shut();

		picture = null;

		if (texture != null) Draw.destroyTexture(texture);

		texture = null;
		textureWide = 0;
		textureTall = 0;
	}

	/**
		Forgets a picture read from a file, so it is read again next time it is drawn.

		@param path The file.
	**/
	public function forgets(path:String):Void {
		final held = picture;
		if (held != null) held.forgets(path);
	}

	/**
		@param path A picture's file.
		@return Its width over its height, or nought where it will not read or nothing has been
			drawn yet to read it with.
	**/
	public function aspect(path:String):Float {
		final held = picture;
		return held == null ? 0 : held.aspect(path);
	}

	override function layout():Void {
		final root = root();
		final pad = root == null ? 16 : root.metrics.whole(16);
		final roomWide = width - pad * 2;
		final roomTall = height - pad * 2;
		final shape = studio.pictureWide / studio.pictureTall;

		var wide = roomWide;
		var tall = wide / shape;

		if (tall > roomTall) {
			tall = roomTall;
			wide = tall * shape;
		}

		pictureWide = wide < 16 ? 16 : Math.floor(wide);
		pictureTall = tall < 9 ? 9 : Math.floor(tall);
		pictureLeft = Math.round(x + (width - pictureWide) * 0.5);
		pictureTop = Math.round(y + (height - pictureTall) * 0.5);
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button != Pointer.Left) return false;

				grabbed(event.x, event.y);
				return true;

			case Kind.PointerMove:
				if (dragging == NONE) {
					described(event.x, event.y);
					return false;
				}

				dragged(event.x, event.y, event.shift());
				return true;

			case Kind.PointerUp:
				if (dragging == NONE) return false;

				dragging = NONE;
				snappedX = false;
				snappedY = false;
				studio.changed(true);

				return true;

			case _:
		}

		return false;
	}

	/**
		Says what the pointer is over.
	**/
	function described(px:Float, py:Float):Void {
		final layer = studio.chosenLayer();
		var said = Locale.FILM_PREVIEW_TIP;

		if (layer != null && measured(layer)) {
			if (onKnob(layer, px, py)) said = Locale.FILM_TURN_TIP;
			else if (cornerAt(layer, px, py) >= 0) said = Locale.FILM_SIZE_TIP;
			else if (inside(layer, px, py)) said = Locale.FILM_MOVE_TIP;
		}

		if (said == Locale.FILM_PREVIEW_TIP) {
			final lanes = studio.style.lanes();
			if (lanes != layer && measured(lanes) && laneAt(lanes, px, py) >= 0) said = Locale.FILM_LANE_MOVE_TIP;
		}

		tip = translate(said);
	}

	/**
		Starts a drag: on the chosen layer's knob or a corner where the pointer is on one, and
		otherwise on whichever layer is uppermost under it, which it chooses. A press on nothing
		chooses nothing.
	**/
	function grabbed(px:Float, py:Float):Void {
		final chosen = studio.chosenLayer();

		if (chosen != null && measured(chosen)) {
			if (onKnob(chosen, px, py)) {
				starts(TURN, chosen, px, py);
				return;
			}

			if (cornerAt(chosen, px, py) >= 0) {
				starts(SIZE, chosen, px, py);
				return;
			}
		}

		var index = studio.style.layers.length - 1;

		while (index >= 0) {
			final layer = studio.style.layers[index];

			if (measured(layer) && inside(layer, px, py)) {
				if (layer.kind == Layer.LANES && index != studio.chosen) {
					final part = laneAt(layer, px, py);
					final lone = part < 0 ? null : studio.detaches(part);

					if (lone != null && measured(lone)) {
						starts(MOVE, lone, px, py);
						return;
					}
				}

				studio.chooses(index);
				starts(MOVE, layer, px, py);
				return;
			}

			index--;
		}

		studio.chooses(-1);
	}

	function starts(mode:Int, layer:Layer, px:Float, py:Float):Void {
		dragging = mode;
		fromX = px;
		fromY = py;
		startX = layer.x;
		startY = layer.y;
		startWide = layer.wide;
		startTall = layer.tall;

		final held = picture;
		startHalfWide = held == null ? 1 : held.boundWide * 0.5;
		startHalfTall = held == null ? 1 : held.boundTall * 0.5;
	}

	function dragged(px:Float, py:Float, shift:Bool):Void {
		final layer = studio.chosenLayer();
		if (layer == null || pictureWide <= 0) return;

		switch (dragging) {
			case MOVE:
				var nextX = startX + (px - fromX) / pictureWide;
				var nextY = startY + (py - fromY) / pictureTall;

				snappedX = Math.abs((nextX - 0.5) * pictureWide) < SNAP;
				snappedY = Math.abs((nextY - 0.5) * pictureTall) < SNAP;

				if (snappedX) nextX = 0.5;
				if (snappedY) nextY = 0.5;

				layer.x = nextX;
				layer.y = nextY;

			case SIZE:
				final centreX = pictureLeft + layer.x * pictureWide;
				final centreY = pictureTop + layer.y * pictureTall;
				final turn = layer.turn * Math.PI / 180;
				final dx = px - centreX;
				final dy = py - centreY;
				final along = Math.abs(dx * Math.cos(turn) + dy * Math.sin(turn));
				final across = Math.abs(-dx * Math.sin(turn) + dy * Math.cos(turn));

				final wider = startHalfWide <= 0 ? 1 : along / startHalfWide;
				final taller = startHalfTall <= 0 ? 1 : across / startHalfTall;
				final kept = layer.kind == Layer.LANES || layer.kind == Layer.LANE ? shift : !shift;
				final even = wider > taller ? wider : taller;

				if (layer.kind == Layer.TEXT) {
					layer.tall = startTall * (wider > taller ? wider : taller);
				} else {
					layer.wide = startWide * (kept ? even : wider);
					layer.tall = startTall * (kept ? even : taller);
				}

				layer.tidied();

			case TURN:
				final centreX = pictureLeft + layer.x * pictureWide;
				final centreY = pictureTop + layer.y * pictureTall;
				var degrees = Math.atan2(py - centreY, px - centreX) * 180 / Math.PI + 90;

				if (shift) {
					degrees = Math.round(degrees / 15) * 15;
				} else {
					final quarter = Math.round(degrees / 90) * 90;
					if (Math.abs(degrees - quarter) < SQUARE) degrees = quarter;
				}

				degrees %= 360;
				layer.turn = degrees < 0 ? degrees + 360 : degrees;

			case _:
		}

		studio.changed(false);
	}

	/**
		Measures a layer into the picture's bounds, at the preview's size.

		@return Whether there is a picture to measure with yet.
	**/
	function measured(layer:Layer):Bool {
		final held = picture;
		if (held == null) return false;

		held.bounds(layer, words, pictureWide, pictureTall);
		return true;
	}

	/**
		@return Whether a point is inside a layer's turned box, as `measured` last measured it.
	**/
	function inside(layer:Layer, px:Float, py:Float):Bool {
		final held = picture;
		if (held == null) return false;

		final turn = layer.turn * Math.PI / 180;
		final dx = px - (pictureLeft + layer.x * pictureWide);
		final dy = py - (pictureTop + layer.y * pictureTall);
		final along = dx * Math.cos(turn) + dy * Math.sin(turn);
		final across = -dx * Math.sin(turn) + dy * Math.cos(turn);

		return Math.abs(along) <= held.boundWide * 0.5 && Math.abs(across) <= held.boundTall * 0.5;
	}

	/**
		@param lanes The lanes laid out together, measured.
		@return Which part's lane a point is on among the lanes laid out together, or -1 for none.
	**/
	function laneAt(lanes:Layer, px:Float, py:Float):Int {
		final held = picture;
		if (held == null || held.boundWide <= 0 || held.boundTall <= 0) return -1;

		final together = studio.gathered();
		if (together.length == 0) return -1;

		final turn = lanes.turn * Math.PI / 180;
		final dx = px - (pictureLeft + lanes.x * pictureWide);
		final dy = py - (pictureTop + lanes.y * pictureTall);
		final along = (dx * Math.cos(turn) + dy * Math.sin(turn)) / held.boundWide + 0.5;
		final across = (-dx * Math.sin(turn) + dy * Math.cos(turn)) / held.boundTall + 0.5;

		for (index in 0...together.length) {
			mdd.view.monitor.Scope.cellOf(together.length, index, cell);

			if (along >= cell[0] && along < cell[0] + cell[2] && across >= cell[1]
					&& across < cell[1] + cell[3]) {
				return together[index];
			}
		}

		return -1;
	}

	/**
		@return Which corner of a layer's turned box a point is on, 0 to 3, or -1 for none.
	**/
	function cornerAt(layer:Layer, px:Float, py:Float):Int {
		final reach = grip();

		for (corner in 0...4) {
			cornered(layer, corner);
			if (Math.abs(px - atX) <= reach && Math.abs(py - atY) <= reach) return corner;
		}

		return -1;
	}

	/**
		@return Whether a point is on the knob a layer is turned by.
	**/
	function onKnob(layer:Layer, px:Float, py:Float):Bool {
		knobbed(layer);

		final dx = px - atX;
		final dy = py - atY;
		final reach = grip() * 1.4;

		return dx * dx + dy * dy <= reach * reach;
	}

	function grip():Float {
		final root = root();
		return root == null ? 6 : root.metrics.whole(6);
	}

	/**
		Works out where a corner of a layer's turned box is, in the window, into `atX` and `atY`.

		@param layer The layer, measured.
		@param corner Which corner, 0 to 3 clockwise from the top left.
	**/
	function cornered(layer:Layer, corner:Int):Void {
		final held = picture;
		final halfWide = held == null ? 0 : held.boundWide * 0.5;
		final halfTall = held == null ? 0 : held.boundTall * 0.5;
		final along = corner == 0 || corner == 3 ? -halfWide : halfWide;
		final across = corner < 2 ? -halfTall : halfTall;

		placed(layer, along, across);
	}

	/**
		Works out where the knob a layer is turned by sits, above its box's top edge, into `atX`
		and `atY`.

		@param layer The layer, measured.
	**/
	function knobbed(layer:Layer):Void {
		final held = picture;
		final root = root();
		final halfTall = held == null ? 0 : held.boundTall * 0.5;
		final stalk = root == null ? 24 : root.metrics.whole(24);

		placed(layer, 0, -halfTall - stalk);
	}

	/**
		Works out where a point given in a layer's own turned frame is, in the window, into `atX`
		and `atY`.

		@param layer The layer.
		@param along How far from its centre along its own width.
		@param across How far along its own height.
	**/
	function placed(layer:Layer, along:Float, across:Float):Void {
		final turn = layer.turn * Math.PI / 180;
		final centreX = pictureLeft + layer.x * pictureWide;
		final centreY = pictureTop + layer.y * pictureTall;

		atX = centreX + along * Math.cos(turn) - across * Math.sin(turn);
		atY = centreY + along * Math.sin(turn) + across * Math.cos(turn);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;

		paint.rect(x, y, width, height, theme.sink);

		if (pictureWide <= 0 || pictureTall <= 0) return;

		if (picture == null) {
			final made = new Picture(paint);
			made.face = studio.face;
			picture = made;
		}

		final held = picture;
		if (held == null || !sized(paint)) return;

		if (sizesFor != pictureTall && studio.onSizes != null) {
			sizes = studio.onSizes(pictureTall);
			sizesFor = pictureTall;
		}

		words = studio.words();

		final back = paint.targeted();
		final worn = sizes == null ? null : root.wears(sizes);

		paint.target(texture);
		paint.clear(0, 0, 0, 1);

		studio.style.dresses(studio.scope);
		held.draws(studio.style, studio.scope, studio.parts(), words, pictureWide, pictureTall, texture);

		paint.target(back);
		if (worn != null) root.wears(worn);

		paint.blit(texture, pictureLeft, pictureTop, pictureWide, pictureTall);
		paint.outline(pictureLeft, pictureTop, pictureWide, pictureTall, theme.frame, metrics.whole(1),
			1, 0);

		guides(paint, metrics);
		handles(paint, metrics);
	}

	/**
		Draws the picture's middle lines while a move rests on them.
	**/
	function guides(paint:Paint, metrics:Metrics):Void {
		final root = root();
		if (root == null || dragging != MOVE) return;

		final hair = metrics.whole(1);

		if (snappedX) {
			paint.rect(pictureLeft + pictureWide * 0.5, pictureTop, hair, pictureTall, root.theme.accent, 0.8);
		}

		if (snappedY) {
			paint.rect(pictureLeft, pictureTop + pictureTall * 0.5, pictureWide, hair, root.theme.accent, 0.8);
		}
	}

	/**
		Draws the chosen layer's turned box, its corners and the knob it turns by.
	**/
	function handles(paint:Paint, metrics:Metrics):Void {
		final root = root();
		final layer = studio.chosenLayer();
		if (root == null || layer == null || !measured(layer)) return;

		final accent = root.theme.accent;
		final weight = metrics.whole(1.5);

		for (corner in 0...4) {
			cornered(layer, corner);
			corners[corner * 2] = atX;
			corners[corner * 2 + 1] = atY;
		}

		for (corner in 0...4) {
			final next = (corner + 1) % 4;
			paint.line(corners[corner * 2], corners[corner * 2 + 1], corners[next * 2],
				corners[next * 2 + 1], weight, accent, 0.95);
		}

		final grip = grip();

		for (corner in 0...4) {
			final left = corners[corner * 2] - grip;
			final top = corners[corner * 2 + 1] - grip;

			paint.rect(left, top, grip * 2, grip * 2, root.theme.ink);
			paint.outline(left, top, grip * 2, grip * 2, accent, weight, 1, 0);
		}

		placed(layer, 0, -(picture == null ? 0 : picture.boundTall * 0.5));

		final topX = atX;
		final topY = atY;

		knobbed(layer);

		paint.line(topX, topY, atX, atY, weight, accent, 0.95);
		paint.circle(atX, atY, grip * 1.2, root.theme.ink);
		paint.arc(atX, atY, grip * 1.2, 0, Math.PI * 2, weight, accent);
	}

	/**
		Makes sure the texture the picture is drawn into is the preview's size.

		@param paint What the window is drawn with, whose renderer the texture belongs to.
		@return Whether there is one.
	**/
	function sized(paint:Paint):Bool {
		if (texture != null && textureWide == pictureWide && textureTall == pictureTall) return true;

		if (texture != null) Draw.destroyTexture(texture);

		texture = Draw.createTarget(paint.canvas(), pictureWide, pictureTall);
		textureWide = texture == null ? 0 : pictureWide;
		textureTall = texture == null ? 0 : pictureTall;

		return texture != null;
	}
}

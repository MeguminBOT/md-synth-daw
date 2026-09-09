package mdd.ui.control;

@:unreflective

/**
	The bar across the top: named menus on the left, and a few labels on the right.

	Once one menu is open, moving across the bar opens the next rather than needing a
	second click.
**/
final class MenuBar extends Widget {
	/**
		What each menu is called.
	**/
	public final labels:Array<String> = [];

	/**
		The menus themselves.
	**/
	public final menus:Array<Menu> = [];

	/**
		The labels on the right.
	**/
	public final trailing:Array<String> = [];

	/**
		Called when one of those is clicked.
	**/
	public var onTrailing:Null<Int -> Void> = null;

	/**
		Which menu is open, or -1 for none.
	**/
	public var openAt(default, null):Int = -1;
	var overTrailing:Int = -1;

	var hoverAt:Int = -1;

	/**
		Builds an empty bar.
	**/
	public function new() {
		super();

		drives = true;
		opaque = true;
	}

	/**
		Adds a menu to the bar.

		@param label What to call it.
		@param menu The menu.
		@return The same menu.
	**/
	public function offer(label:String, menu:Menu):Menu {
		labels.push(label);
		menus.push(menu);
		menu.onClose = function(fade:Motion):Void shed(fade);
		relayout();
		return menu;
	}

	/**
		Forgets which menu is open once its fade has finished. It is called through a
		closure rather than as a method reference, because a method reference on an
		`@:unreflective` class lowers to a wrapper the metadata removes.

		@param fade The fade that finished.
	**/
	function shed(fade:Motion):Void {
		if (openAt < 0) return;
		openAt = -1;
		invalidate();
	}

	/**
		@return How much room a menu name takes beyond its text.
	**/
	public function cell():Float {
		final root = root();
		return root == null ? 22 : root.metrics.whole(22);
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return Which trailing label is there, or -1.
	**/
	function trailingAt(px:Float, py:Float):Int {
		if (trailing.length == 0) return -1;

		final root = root();
		if (root == null) return -1;

		final metrics = root.metrics;
		final size = cell();
		final top = y + (height - size) * 0.5;

		if (py < top || py >= top + size) return -1;

		var pen = x + width - metrics.gap - size;

		for (index in 0...trailing.length) {
			if (px >= pen && px < pen + size) return trailing.length - 1 - index;
			pen -= size + metrics.unit;
		}

		return -1;
	}

	/**
		@param font The face the labels draw in.
		@param metrics The sizes to draw at.
		@param which Which menu.
		@return How wide its name draws.
	**/
	function widthOf(font:Font, metrics:Metrics, which:Int):Float {
		return font.measure(labels[which]) + metrics.gap * 2;
	}

	/**
		@param px A point, across.
		@return Which menu name is there, or -1.
	**/
	public function at(px:Float):Int {
		final root = root();
		if (root == null || root.metrics.body == null) return -1;

		final font = root.metrics.body;
		final metrics = root.metrics;

		var pen = x + metrics.unit;

		for (which in 0...labels.length) {
			final wide = widthOf(font, metrics, which);
			if (px >= pen && px < pen + wide) return which;
			pen += wide;
		}
		return -1;
	}

	/**
		@param which A menu.
		@return Where its name starts, across.
	**/
	public function penOf(which:Int):Float {
		final root = root();
		if (root == null || root.metrics.body == null) return x;

		final font = root.metrics.body;
		final metrics = root.metrics;

		var pen = x + metrics.unit;
		for (before in 0...which) pen += widthOf(font, metrics, before);
		return pen;
	}

	/**
		Opens a menu under its name, closing whichever was open.

		@param which Which menu.
	**/
	public function open(which:Int):Void {
		final root = root();
		if (root == null || which < 0 || which >= menus.length) return;

		if (openAt >= 0) root.dismiss();

		openAt = which;
		root.pop(menus[which], penOf(which), y + height, this);
		invalidate();
	}

	/**
		Closes whichever menu is open.
	**/
	public function close():Void {
		final root = root();
		if (root == null || openAt < 0) return;

		openAt = -1;
		root.dismiss();
		invalidate();
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				final trailed = trailingAt(event.x, event.y);

				if (trailed >= 0) {
					if (onTrailing != null) onTrailing(trailed);
					return true;
				}

				final which = at(event.x);
				if (which < 0) return false;

				if (which == openAt) close();
				else open(which);
				return true;

			case Kind.PointerMove:
				final trailed = trailingAt(event.x, event.y);

				if (trailed != overTrailing) {
					overTrailing = trailed;
					tip = trailed < 0 ? "" : trailing[trailed];
					invalidate();
				}

				final which = at(event.x);

				if (which != hoverAt) {
					hoverAt = which;
					invalidate();
				}

				if (openAt >= 0 && which >= 0 && which != openAt) open(which);
				return true;

			case _:
		}
		return false;
	}

	override function hovered(on:Bool):Void {
		if (!on) {
			hoverAt = -1;
			overTrailing = -1;
		}

		super.hovered(on);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.body;

		paint.rect(x, y, width, height, theme.bar);
		paint.reface(font);

		var pen = x + metrics.unit;

		for (which in 0...labels.length) {
			final wide = widthOf(font, metrics, which);

			if (which == openAt) {
				paint.roundedRect(pen, y + metrics.unit, wide, height - metrics.unit * 2,
					metrics.radiusSmall, theme.accent, Theme.SELECT);
			} else if (which == hoverAt) {
				paint.roundedRect(pen, y + metrics.unit, wide, height - metrics.unit * 2,
					metrics.radiusSmall, theme.accent, Theme.HOVER);
			}

			paint.textCentred(labels[which], pen + wide * 0.5,
				y + (height - font.height) * 0.5 + font.ascent,
				which == openAt ? theme.ink : theme.dim);

			pen += wide;
		}

		if (trailing.length == 0) return;

		final size = cell();
		final top = y + (height - size) * 0.5;

		var right = x + width - metrics.gap - size;

		var index = trailing.length - 1;

		while (index >= 0) {
			if (index == overTrailing) {
				paint.roundedRect(right, top, size, size, metrics.radiusSmall, theme.accent,
					Theme.HOVER);
			}

			mark(paint, theme, metrics, index, right, top, size);
			right -= size + metrics.unit;
			index--;
		}
	}

	/**
		Draws one of the trailing marks on the right, lit where it is hovered.

		@param paint What to draw with.
		@param theme The colours to draw in.
		@param metrics The sizes to draw at.
		@param index Which trailing mark.
		@param at Where it goes, across.
		@param top Where it goes, down.
		@param size How large to draw the mark.
	**/
	function mark(paint:Paint, theme:Theme, metrics:Metrics, index:Int, at:Float,
			top:Float, size:Float):Void {
		final ink = index == overTrailing ? theme.ink : theme.dim;
		final middle = at + size * 0.5;
		final centre = top + size * 0.5;
		final reach = metrics.whole(5);
		final hair = metrics.whole(1);

		switch (index) {
			case 0:
				paint.rect(middle - reach, centre - reach * 0.6, reach * 0.8, hair * 2, ink);
				paint.outline(middle - reach, centre - reach * 0.3, reach * 2, reach * 1.2,
					ink, hair);

			case 1:
				paint.outline(middle - reach, centre - reach, reach * 2, reach * 2, ink, hair);
				paint.rect(middle - reach * 0.5, centre - reach, reach, reach * 0.7, ink);

			case _:
				paint.ring(middle, centre, reach * 0.7, hair * 2, ink);
				paint.rect(middle - hair, centre - reach, hair * 2, reach * 2, ink, 0.6);
		}
	}
}

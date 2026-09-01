package mdd.ui.control;

@:unreflective
final class MenuBar extends Widget {
	public final labels:Array<String> = [];
	public final menus:Array<Menu> = [];

	public var openAt(default, null):Int = -1;

	var hoverAt:Int = -1;

	public function new() {
		super();
		opaque = true;
	}

	public function offer(label:String, menu:Menu):Menu {
		labels.push(label);
		menus.push(menu);
		menu.onClose = function(fade:Motion):Void shed(fade);
		relayout();
		return menu;
	}

	function shed(fade:Motion):Void {
		if (openAt < 0) return;
		openAt = -1;
		invalidate();
	}

	function widthOf(font:Font, metrics:Metrics, which:Int):Float {
		return font.measure(labels[which]) + metrics.gap * 2;
	}

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

	public function penOf(which:Int):Float {
		final root = root();
		if (root == null || root.metrics.body == null) return x;

		final font = root.metrics.body;
		final metrics = root.metrics;

		var pen = x + metrics.unit;
		for (before in 0...which) pen += widthOf(font, metrics, before);
		return pen;
	}

	public function open(which:Int):Void {
		final root = root();
		if (root == null || which < 0 || which >= menus.length) return;

		if (openAt >= 0) root.dismiss();

		openAt = which;
		root.pop(menus[which], penOf(which), y + height, this);
		invalidate();
	}

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
				final which = at(event.x);
				if (which < 0) return false;

				if (which == openAt) close();
				else open(which);
				return true;

			case Kind.PointerMove:
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
		if (!on) hoverAt = -1;
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
	}
}
